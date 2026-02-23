# fstcc0.s - fstCC Stage 0 Bootstrap Compiler (RISC-V, Linux riscv64)
# Includes:
#   - lexer_init / next_token (optimized ident + keyword checks)
#   - error_at(err_ptr, msg_ptr, msg_len) with line + caret
#   - peek / consume / expect (lookahead layer for parser)
#
# NOTES:
#   - Input is mmap'd (NOT NUL-terminated): bounds [g_in_ptr, g_end)
#   - Token layout (32 bytes):
#       0  kind (u64)
#       8  val  (u64)  (TK_NUM only)
#      16  start(u64)  (pointer into mmap)
#      24  len  (u64)

.section .text
.globl _start

#====================== constants ======================
# TODO(TOUNDERSTAND): confirm these flags/values against your target ABI + libc headers
.equ AT_FDCWD,     -100

.equ O_RDONLY,      0
.equ O_WRONLY,      1
.equ O_CREAT,       64
.equ O_TRUNC,       512

.equ SEEK_SET,      0
.equ SEEK_END,      2

.equ PROT_READ,     1
.equ MAP_PRIVATE,   2

#---------------------- token list ----------------------
    #------------------------------------I_keyword-------------------------------
.equ    TK_INT,     1
.equ    TK_RETURN,  2
.equ    TK_IF,      3
.equ    TK_ELSE,    4
.equ    TK_WHILE,   5
# keywords must be lowercase to distinguish from identifiers
    #------------------------------------II_identifier----------------------------
# regex for identifiers: [a-zA-Z_][a-zA-Z0-9_]*
.equ    TK_IDENT,   6
    #------------------------------------III_integer literals----------------------
# regex for integer literals: [0-9]+
.equ    TK_NUM,     7
    #------------------------------------IV_operators-----------------------------
.equ    TK_ASSIGN,  8   # =

.equ    TK_PLUS,    9   # +
.equ    TK_MINUS,  10   # -
.equ    TK_MUL,    11   # *
.equ    TK_DIV,    12   # /
.equ    TK_MOD,    13   # %

.equ    TK_EQ,     14   # ==
.equ    TK_NEQ,    15   # !=
.equ    TK_LT,     16   # <
.equ    TK_GT,     17   # >
.equ    TK_LE,     18   # <=
.equ    TK_GE,     19   # >=

.equ    TK_AND,    20   # &&
.equ    TK_OR,     21   # ||
.equ    TK_NOT,    22   # !
    #------------------------------------V_delimiters-----------------------------
.equ    TK_LPAREN, 23   # (
.equ    TK_RPAREN, 24   # )
.equ    TK_LBRACE, 25   # {
.equ    TK_RBRACE, 26   # }
.equ    TK_COMMA,  27   # ,
.equ    TK_SEMI,   28   # ;
    #------------------------------------VI_EOF-----------------------------------
.equ    TK_EOF,     0
# use 0 here so that uninitialized tokens default to EOF which is safe

# priority levels (L -> H):
#  1. =
#  2. ||
#  3. &&
#  4. == !=
#  5. < > <= >=
#  6. + -
#  7. * / %
#  8. unary: ! -  (unary minus has higher precedence than binary minus)

# -------- RISC-V instruction words emitted into the output binary --------
# These are the 32-bit little-endian machine words we write into g_out_buf.
# Using s0 as the frame pointer (fp = old sp).
#
# Prologue (emitted at function entry):
.equ EMIT_SD_RA_M8_SP,  0xFE113C23   # sd  ra,  -8(sp)   save return addr
.equ EMIT_SD_S0_M16_SP, 0xFE813823   # sd  s0, -16(sp)   save caller fp
.equ EMIT_MV_S0_SP,     0x00010413   # mv  s0,  sp        s0 = old sp (frame base)
.equ EMIT_ADDI_SP_SP_0, 0x00010113   # addi sp, sp, 0    <- HOLE: patch to -frame_size
#
# Epilogue (emitted at each 'return' statement):
.equ EMIT_MV_SP_S0,     0x00040113   # mv  sp,  s0        restore sp
.equ EMIT_LD_RA_M8_S0,  0xFF843083   # ld  ra,  -8(s0)   restore return addr
.equ EMIT_LD_S0_M16_S0, 0xFF043403   # ld  s0, -16(s0)   restore caller fp
.equ EMIT_RET,          0x00008067   # ret                jalr x0, ra, 0

#====================== rodata ======================
.section .rodata
arg_error_msg:
    .asciz "Argument error: expected 2 arguments (file name and output name)\n"
arg_error_msg_len = . - arg_error_msg

open_in_error_msg:
    .asciz "Input open error: openat failed\n"
open_in_error_msg_len = . - open_in_error_msg

seek_end_error_msg:
    .asciz "Input size error: lseek(SEEK_END) failed\n"
seek_end_error_msg_len = . - seek_end_error_msg

seek_set_error_msg:
    .asciz "Input rewind error: lseek(SEEK_SET) failed\n"
seek_set_error_msg_len = . - seek_set_error_msg

mmap_error_msg:
    .asciz "Input map error: mmap failed\n"
mmap_error_msg_len = . - mmap_error_msg

open_out_error_msg:
    .asciz "Output open error: openat failed\n"
open_out_error_msg_len = . - open_out_error_msg

# error_at helpers
err_prefix:
    .asciz "error: "
err_prefix_len = . - err_prefix

newline:
    .asciz "\n"
newline_len = . - newline

caret1:
    .asciz "^\n"

spaces64:
    .ascii "                                                                "  # 64 spaces

# lexer diagnostics
unknown_char_msg:
    .asciz "unexpected character"
unknown_char_msg_len = . - unknown_char_msg

single_amp_msg:
    .asciz "single '&' is not supported (use &&)"
single_amp_msg_len = . - single_amp_msg

single_bar_msg:
    .asciz "single '|' is not supported (use ||)"
single_bar_msg_len = . - single_bar_msg

expected_token_msg:
    .asciz "unexpected token"
expected_token_msg_len = . - expected_token_msg

#====================== macros ======================
.macro EXIT code
    li a0, \code
    li a7, 93          # SYS_exit
    ecall
.endm

.macro DIE msg
    li a0, 2
    la a1, \msg
    li a2, \msg\()_len
    li a7, 64          # SYS_write
    ecall
    EXIT 1
.endm

# write(fd=2, buf=reg, len=reg)
.macro WRITE_STDERR bufreg, lenreg
    li a0, 2
    mv a1, \bufreg
    mv a2, \lenreg
    li a7, 64
    ecall
.endm

#====================== entry ======================
_start:
    # Linux entry stack (riscv64):
    # 0(sp)=argc, 8(sp)=argv[0], 16(sp)=argv[1], 24(sp)=argv[2], ...

#---------------------- file open (input) ----------------------
    ld      t0, 0(sp)                 # t0 = argc
    bne     t0, 3, .arg_error         # expect: prog + 2 args => argc == 3

    ld      a1, 16(sp)                # a1 = input filename pointer (argv[1])

    # openat(AT_FDCWD, pathname, O_RDONLY, 0)
    li      a0, AT_FDCWD
    li      a2, O_RDONLY
    li      a3, 0                     # mode (unused for O_RDONLY)
    li      a7, 56                    # SYS_openat
    ecall
    bltz    a0, .open_in_error

    mv      s0, a0                    # s0 = in_fd   (TODO(TOUNDERSTAND): choose a register convention)
    la      t1, g_in_fd
    sd      s0, 0(t1)

#---------------------- input size (lseek) ----------------------
    # TODO(TOUNDERSTAND): using lseek avoids struct stat layout; confirm it works for your input sources
    # size = lseek(in_fd, 0, SEEK_END)
    mv      a0, s0
    li      a1, 0
    li      a2, SEEK_END
    li      a7, 62                    # SYS_lseek
    ecall
    bltz    a0, .seek_end_error

    mv      s2, a0                    # s2 = in_size
    la      t1, g_in_size
    sd      s2, 0(t1)

    # rewind: lseek(in_fd, 0, SEEK_SET)
    mv      a0, s0
    li      a1, 0
    li      a2, SEEK_SET
    li      a7, 62
    ecall
    bltz    a0, .seek_set_error

#---------------------- mmap input ----------------------
    # mmap(NULL, in_size, PROT_READ, MAP_PRIVATE, in_fd, 0)
    li      a0, 0                     # addr = NULL
    mv      a1, s2                    # length
    li      a2, PROT_READ
    li      a3, MAP_PRIVATE
    mv      a4, s0                    # fd
    li      a5, 0                     # offset
    li      a7, 222                   # SYS_mmap
    ecall
    bltz    a0, .mmap_error

    mv      s3, a0                    # s3 = in_ptr
    la      t1, g_in_ptr
    sd      s3, 0(t1)

    # TODO(TOUNDERSTAND): decide whether to close input fd now or later.
    # Keeping it open is fine; if you close now, mapping remains valid on Linux.

#---------------------- file open (output) ----------------------
    ld      a1, 24(sp)                # a1 = output filename pointer (argv[2])

    # openat(AT_FDCWD, pathname, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    li      a0, AT_FDCWD
    li      a2, (O_WRONLY | O_CREAT | O_TRUNC)
    li      a3, 0644                  # mode rw-r--r--
    li      a7, 56
    ecall
    bltz    a0, .open_out_error

    mv      s1, a0                    # s1 = out_fd
    la      t1, g_out_fd
    sd      s1, 0(t1)

    # TODO(NEXTSTEP): at this point you have:
    #   s3 = pointer to input bytes
    #   s2 = input size
    #   s1 = output fd
    # Wire these into your lexer/parser/codegen pipeline.

    # -------- init lexer state --------
    mv      a0, s3                    # in_ptr
    mv      a1, s2                    # in_size
    call    lexer_init

#---------------------- parser ----------------------
    # -------- init emit buffer --------
    la      t0, g_emit_ptr
    la      t1, g_out_buf
    sd      t1, 0(t0)

    call    parse_program

#---------------------- codegen ---------------------
    # TODO: write [g_out_buf .. g_emit_ptr) to g_out_fd via SYS_write
    # TODO(TOUNDERSTAND): buffering strategy vs direct writes

    EXIT 0

#====================== errors ======================
.arg_error:       DIE arg_error_msg
.open_in_error:   DIE open_in_error_msg
.seek_end_error:  DIE seek_end_error_msg
.seek_set_error:  DIE seek_set_error_msg
.mmap_error:      DIE mmap_error_msg
.open_out_error:  DIE open_out_error_msg


#==============================================================================
# Lexer + Lookahead + error_at
#==============================================================================

# -------- safe unaligned little-endian loads (via lbu) --------
# LOAD_U16_LE dst, base_reg
.macro LOAD_U16_LE dst, base
    lbu  t8, 0(\base)
    lbu  t9, 1(\base)
    slli t9, t9, 8
    or   \dst, t8, t9
.endm

# LOAD_U32_LE dst, base_reg
.macro LOAD_U32_LE dst, base
    lbu  t8, 0(\base)
    lbu  t9, 1(\base)
    slli t9, t9, 8
    or   \dst, t8, t9
    lbu  t9, 2(\base)
    slli t9, t9, 16
    or   \dst, \dst, t9
    lbu  t9, 3(\base)
    slli t9, t9, 24
    or   \dst, \dst, t9
.endm

#-------------------------------- lexer_init --------------------------------
# a0 = in_ptr (char*)
# a1 = in_size (u64)
# sets g_cur=in_ptr, g_end=in_ptr+in_size, g_has_tok=0
.globl lexer_init
lexer_init:
    la  t0, g_cur
    sd  a0, 0(t0)

    add t1, a0, a1
    la  t0, g_end
    sd  t1, 0(t0)

    la  t0, g_has_tok
    sd  x0, 0(t0)
    ret

#-------------------------------- next_token --------------------------------
# input:
#   a0 = cursor (char*)
#   a1 = tok_ptr (Token*)
# output:
#   a0 = new_cursor
#   a1 = token kind
#
# Supports:
#   whitespace: ' ', '\t', '\n', '\r'
#   // line comments
#   NUM: [0-9]+ (decimal)
#   IDENT/keywords: [A-Za-z_][A-Za-z0-9_]*
#   ops: == != <= >= && ||  and singles: = + - * / % < > ! ( ) { } , ;
.globl next_token
next_token:
    mv  t6, a1          # t6 = tok_ptr
    mv  t0, a0          # t0 = p (cursor)
    la  t7, g_end
    ld  t7, 0(t7)       # t7 = end
    j   .skip_ws

#---------------- emit EOF ----------------
.emit_eof:
    li  t1, TK_EOF
    sd  t1, 0(t6)
    sd  x0, 8(t6)
    sd  x0, 16(t6)
    sd  x0, 24(t6)
    mv  a0, t0
    mv  a1, t1
    ret

#---------------- skip whitespace and // comments ----------------
.skip_ws:
    bgeu t0, t7, .emit_eof

    lbu t1, 0(t0)
    li  t2, 32                  # ' '
    beq t1, t2, .ws_advance
    li  t2, 9                   # '\t'
    beq t1, t2, .ws_advance
    li  t2, 10                  # '\n'
    beq t1, t2, .ws_advance
    li  t2, 13                  # '\r'
    beq t1, t2, .ws_advance

    # handle // comment
    li  t2, '/'
    bne t1, t2, .ws_done
    addi t3, t0, 1
    bgeu t3, t7, .ws_done
    lbu t4, 0(t3)
    li  t2, '/'
    bne t4, t2, .ws_done

    # consume until '\n' or end
    addi t0, t0, 2
.comment_loop:
    bgeu t0, t7, .skip_ws
    lbu t1, 0(t0)
    li  t2, 10
    beq t1, t2, .ws_advance
    addi t0, t0, 1
    j .comment_loop

.ws_advance:
    addi t0, t0, 1
    j .skip_ws

.ws_done:

#---------------- number: [0-9]+ ----------------
    lbu t1, 0(t0)
    li  t2, '0'
    blt t1, t2, .not_num
    li  t2, '9'
    bgt t1, t2, .not_num

    li  t3, 0                   # val
    mv  t4, t0                  # start
.num_loop:
    bgeu t0, t7, .num_done
    lbu t1, 0(t0)
    li  t2, '0'
    blt t1, t2, .num_done
    li  t2, '9'
    bgt t1, t2, .num_done

    addi t1, t1, -'0'
    li  t2, 10
    mul t3, t3, t2
    add t3, t3, t1
    addi t0, t0, 1
    j .num_loop

.num_done:
    sub t5, t0, t4              # len
    li  t1, TK_NUM
    sd  t1, 0(t6)
    sd  t3, 8(t6)               # val
    sd  t4, 16(t6)              # start
    sd  t5, 24(t6)              # len
    mv  a0, t0
    mv  a1, t1
    ret

.not_num:

#---------------- ident/keyword ----------------
    lbu t1, 0(t0)

    # ident start: '_' or letter (A-Z/a-z), optimized via case-fold
    li   t2, '_'
    beq  t1, t2, .ident_start
    ori  t2, t1, 0x20            # fold case
    addi t2, t2, -'a'
    li   t3, 'z'-'a'             # 25
    bleu t2, t3, .ident_start
    j .not_ident

.ident_start:
    mv  t4, t0                   # start
.ident_loop:
    bgeu t0, t7, .ident_done
    lbu  t1, 0(t0)

    # ident continue: digit | '_' | letter
    addi t2, t1, -'0'
    li   t3, 9
    bleu t2, t3, .adv_ident

    li   t2, '_'
    beq  t1, t2, .adv_ident

    ori  t2, t1, 0x20
    addi t2, t2, -'a'
    li   t3, 'z'-'a'
    bleu t2, t3, .adv_ident

    j .ident_done

.adv_ident:
    addi t0, t0, 1
    j .ident_loop

.ident_done:
    sub t5, t0, t4               # len
    li  t1, TK_IDENT             # default kind

    # ---- keyword checks (safe unaligned loads) ----
    # if (len==2 && "if")
    li  t2, 2
    bne t5, t2, .kw_len3
    LOAD_U16_LE t2, t4           # "if" little-endian = 0x6669
    li  t3, 0x6669
    bne t2, t3, .emit_identlike
    li  t1, TK_IF
    j .emit_identlike

.kw_len3:
    # if (len==3 && "int")
    li  t2, 3
    bne t5, t2, .kw_len4
    LOAD_U16_LE t2, t4           # "in" = 0x6e69
    li  t3, 0x6e69
    bne t2, t3, .emit_identlike
    lbu t2, 2(t4)
    li  t3, 't'
    bne t2, t3, .emit_identlike
    li  t1, TK_INT
    j .emit_identlike

.kw_len4:
    # if (len==4 && "else")
    li  t2, 4
    bne t5, t2, .kw_len5
    LOAD_U32_LE t2, t4           # "else" = 0x65736c65
    li  t3, 0x65736c65
    bne t2, t3, .emit_identlike
    li  t1, TK_ELSE
    j .emit_identlike

.kw_len5:
    # if (len==5 && "while")
    li  t2, 5
    bne t5, t2, .kw_len6
    LOAD_U32_LE t2, t4           # "whil" = 0x6c696877
    li  t3, 0x6c696877
    bne t2, t3, .emit_identlike
    lbu t2, 4(t4)
    li  t3, 'e'
    bne t2, t3, .emit_identlike
    li  t1, TK_WHILE
    j .emit_identlike

.kw_len6:
    # if (len==6 && "return")
    li  t2, 6
    bne t5, t2, .emit_identlike
    LOAD_U32_LE t2, t4           # "retu" = 0x75746572
    li  t3, 0x75746572
    bne t2, t3, .emit_identlike
    addi t8, t4, 4
    LOAD_U16_LE t2, t8           # "rn" = 0x6e72
    li  t3, 0x6e72
    bne t2, t3, .emit_identlike
    li  t1, TK_RETURN

.emit_identlike:
    sd  t1, 0(t6)               # kind
    sd  x0, 8(t6)               # val=0
    sd  t4, 16(t6)              # start
    sd  t5, 24(t6)              # len
    mv  a0, t0
    mv  a1, t1
    ret

.not_ident:

#---------------- operators / delimiters ----------------
    bgeu t0, t7, .emit_eof
    lbu t1, 0(t0)               # c0

    # c1 if exists
    addi t3, t0, 1
    li  t2, 0
    bgeu t3, t7, .no_c1
    lbu t2, 0(t3)               # c1
.no_c1:

    # 2-char ops first: == != <= >= && ||
    li  t4, '='
    beq t1, t4, .op_eq_or_assign
    li  t4, '!'
    beq t1, t4, .op_neq_or_not
    li  t4, '<'
    beq t1, t4, .op_le_or_lt
    li  t4, '>'
    beq t1, t4, .op_ge_or_gt
    li  t4, '&'
    beq t1, t4, .op_and
    li  t4, '|'
    beq t1, t4, .op_or

    # single-char tokens
    li  t4, '+'
    beq t1, t4, .emit1_plus
    li  t4, '-'
    beq t1, t4, .emit1_minus
    li  t4, '*'
    beq t1, t4, .emit1_mul
    li  t4, '/'
    beq t1, t4, .emit1_div
    li  t4, '%'
    beq t1, t4, .emit1_mod

    li  t4, '('
    beq t1, t4, .emit1_lparen
    li  t4, ')'
    beq t1, t4, .emit1_rparen
    li  t4, '{'
    beq t1, t4, .emit1_lbrace
    li  t4, '}'
    beq t1, t4, .emit1_rbrace
    li  t4, ','
    beq t1, t4, .emit1_comma
    li  t4, ';'
    beq t1, t4, .emit1_semi

    # unknown char -> error_at(t0, "unexpected character")
    mv  a0, t0
    la  a1, unknown_char_msg
    li  a2, unknown_char_msg_len
    call error_at
    # never returns

.op_eq_or_assign:
    li  t4, '='
    beq t2, t4, .emit2_eq
    li  t1, TK_ASSIGN
    j .emit1

.op_neq_or_not:
    li  t4, '='
    beq t2, t4, .emit2_neq
    li  t1, TK_NOT
    j .emit1

.op_le_or_lt:
    li  t4, '='
    beq t2, t4, .emit2_le
    li  t1, TK_LT
    j .emit1

.op_ge_or_gt:
    li  t4, '='
    beq t2, t4, .emit2_ge
    li  t1, TK_GT
    j .emit1

.op_and:
    li  t4, '&'
    beq t2, t4, .emit2_and
    # single '&' -> error
    mv  a0, t0
    la  a1, single_amp_msg
    li  a2, single_amp_msg_len
    call error_at
.emit2_and:
    li  t1, TK_AND
    j .emit2

.op_or:
    li  t4, '|'
    beq t2, t4, .emit2_or
    # single '|' -> error
    mv  a0, t0
    la  a1, single_bar_msg
    li  a2, single_bar_msg_len
    call error_at
.emit2_or:
    li  t1, TK_OR
    j .emit2

.emit2_eq:   li t1, TK_EQ;  j .emit2
.emit2_neq:  li t1, TK_NEQ; j .emit2
.emit2_le:   li t1, TK_LE;  j .emit2
.emit2_ge:   li t1, TK_GE;  j .emit2

.emit1_plus:   li t1, TK_PLUS;   j .emit1
.emit1_minus:  li t1, TK_MINUS;  j .emit1
.emit1_mul:    li t1, TK_MUL;    j .emit1
.emit1_div:    li t1, TK_DIV;    j .emit1
.emit1_mod:    li t1, TK_MOD;    j .emit1
.emit1_lparen: li t1, TK_LPAREN; j .emit1
.emit1_rparen: li t1, TK_RPAREN; j .emit1
.emit1_lbrace: li t1, TK_LBRACE; j .emit1
.emit1_rbrace: li t1, TK_RBRACE; j .emit1
.emit1_comma:  li t1, TK_COMMA;  j .emit1
.emit1_semi:   li t1, TK_SEMI;   j .emit1

.emit1:
    li  t5, 1
    sd  t1, 0(t6)
    sd  x0, 8(t6)
    sd  t0, 16(t6)
    sd  t5, 24(t6)
    addi t0, t0, 1
    mv  a0, t0
    mv  a1, t1
    ret

.emit2:
    li  t5, 2
    sd  t1, 0(t6)
    sd  x0, 8(t6)
    sd  t0, 16(t6)
    sd  t5, 24(t6)
    addi t0, t0, 2
    mv  a0, t0
    mv  a1, t1
    ret


#-------------------------------- peek --------------------------------
# returns a0 = kind of current lookahead token; fills g_tok
# NOTE: peek calls next_token (non-leaf), so we must save/restore ra.
.globl peek
peek:
    la  t0, g_has_tok
    ld  t1, 0(t0)
    bnez t1, .peek_done

    addi sp, sp, -16
    sd   ra, 8(sp)

    la  t2, g_cur
    ld  a0, 0(t2)          # a0 = cursor
    la  a1, g_tok          # tok_ptr
    call next_token        # -> a0=new_cursor, a1=kind

    # reload pointers: t0/t2 are caller-saved and were clobbered by next_token
    la  t2, g_cur
    sd  a0, 0(t2)          # store new cursor

    la  t0, g_has_tok
    li  t1, 1
    sd  t1, 0(t0)          # mark has_tok=1

    ld   ra, 8(sp)
    addi sp, sp, 16

.peek_done:
    la  t2, g_tok
    ld  a0, 0(t2)          # kind
    ret

#-------------------------------- consume --------------------------------
# a0 = expected kind
# returns a0 = 1 if consumed, 0 otherwise
# NOTE: consume calls peek (non-leaf); expected must survive the call.
.globl consume
consume:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   a0, 0(sp)         # save expected kind (t-regs clobbered by peek)

    call peek              # a0 = current kind

    ld   t5, 0(sp)         # restore expected
    ld   ra, 8(sp)
    addi sp, sp, 16

    bne a0, t5, .cons_no
    # match: invalidate lookahead
    la  t0, g_has_tok
    sd  x0, 0(t0)
    li  a0, 1
    ret
.cons_no:
    li  a0, 0
    ret

#-------------------------------- expect --------------------------------
# a0 = expected kind
# if mismatch -> error_at(g_tok.start, "unexpected token")
# NOTE: expect calls consume (non-leaf), so we save/restore ra.
.globl expect
expect:
    addi sp, sp, -16
    sd   ra, 8(sp)

    call consume           # a0 = 1 if consumed, 0 if not

    ld   ra, 8(sp)
    addi sp, sp, 16

    bnez a0, .exp_ok

    # mismatch: point at current token start
    la  t0, g_tok
    ld  a0, 16(t0)         # err_ptr = tok.start
    la  a1, expected_token_msg
    li  a2, expected_token_msg_len
    call error_at
.exp_ok:
    ret


#-------------------------------- error_at --------------------------------
# a0 = err_ptr (char*)
# a1 = msg_ptr
# a2 = msg_len
# prints:
#   error: <msg>\n
#   <the source line>\n
#   <spaces>^\n
# then exits(1)
# NOTE: only uses WRITE_STDERR/EXIT macros (ecall), not call -> no ra issue.
.globl error_at
error_at:
    mv s10, a0     # err_ptr
    mv s11, a1     # msg_ptr
    mv s9,  a2     # msg_len

    # bounds
    la  t0, g_in_ptr
    ld  s0, 0(t0)  # in_ptr
    la  t0, g_end
    ld  s1, 0(t0)  # end

    # print "error: "
    la  t0, err_prefix
    li  t1, err_prefix_len
    WRITE_STDERR t0, t1

    # print msg
    mv  t0, s11
    mv  t1, s9
    WRITE_STDERR t0, t1

    # print "\n"
    la  t0, newline
    li  t1, newline_len
    WRITE_STDERR t0, t1

    # find line_start: scan backward from err_ptr to beginning of line
    mv  t2, s10
.find_ls:
    beq  t2, s0, .ls_found
    addi t3, t2, -1
    lbu  t4, 0(t3)
    li   t5, 10
    beq  t4, t5, .ls_found_nl
    mv   t2, t3
    j .find_ls
.ls_found_nl:
    addi t2, t3, 1
.ls_found:
    mv  s2, t2      # line_start

    # find line_end: scan forward from err_ptr to '\n' or end
    mv  t2, s10
.find_le:
    bgeu t2, s1, .le_found
    lbu  t4, 0(t2)
    li   t5, 10
    beq  t4, t5, .le_found
    addi t2, t2, 1
    j .find_le
.le_found:
    mv  s3, t2      # line_end

    # print the line
    mv  t0, s2
    sub t1, s3, s2
    WRITE_STDERR t0, t1

    # newline
    la  t0, newline
    li  t1, newline_len
    WRITE_STDERR t0, t1

    # col = err_ptr - line_start
    sub s4, s10, s2

    # print spaces (col bytes) in 64-byte chunks
    la  t0, spaces64
    li  t6, 64
.sp_loop:
    beqz s4, .caret
    mv  t1, s4
    bleu t1, t6, .sp_small
    # print 64 spaces
    mv  t2, t0
    mv  t3, t6
    WRITE_STDERR t2, t3
    addi s4, s4, -64
    j .sp_loop
.sp_small:
    mv  t2, t0
    mv  t3, s4
    WRITE_STDERR t2, t3

.caret:
    la  t0, caret1
    li  t1, 2
    WRITE_STDERR t0, t1

    EXIT 1


#-------------------------------- lexer_dump_kinds --------------------------------
# Debug hook: lex all tokens and print kinds until EOF. Placeholder for now.
.globl lexer_dump_kinds
lexer_dump_kinds:
    ret


#==============================================================================
# Emitter
#==============================================================================

#-------------------------------- emit_u32 --------------------------------
# a0 = 32-bit instruction word
# Appends 4 bytes to g_out_buf at g_emit_ptr and advances the pointer.
# (RISC-V is little-endian; sw stores the low 32 bits in LE order.)
.globl emit_u32
emit_u32:
    la   t0, g_emit_ptr
    ld   t1, 0(t0)          # t1 = current write pointer
    sw   a0, 0(t1)          # write 32-bit word
    addi t1, t1, 4
    sd   t1, 0(t0)          # advance pointer
    ret

#-------------------------------- patch_u32 --------------------------------
# a0 = address inside g_out_buf to overwrite
# a1 = new 32-bit instruction word
.globl patch_u32
patch_u32:
    sw   a1, 0(a0)
    ret


#==============================================================================
# Parser  (recursive descent, single-pass codegen into g_out_buf)
#
# Frame pointer convention in the *generated* code:
#   s0 = fp = old sp at function entry
#   -8(s0)  = saved ra
#   -16(s0) = saved s0 (caller fp)
#   -24(s0), -32(s0), ... = params then locals (assigned by parse_params/parse_stmt)
#==============================================================================

#-------------------------------- parse_program --------------------------------
# Top-level loop: parse function definitions until TK_EOF.
.globl parse_program
parse_program:
    addi sp, sp, -16
    sd   ra, 8(sp)

.pp_loop:
    call peek               # a0 = current token kind
    li   t0, TK_EOF
    beq  a0, t0, .pp_done
    call parse_funcdef
    j    .pp_loop

.pp_done:
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_funcdef --------------------------------
# Parses:  int ident ( params ) block
#
# Emits the following prologue into g_out_buf for the *generated* function:
#   [0] sd  ra,  -8(sp)        save return address
#   [1] sd  s0, -16(sp)        save caller fp
#   [2] mv  s0,  sp            s0 = old sp  (frame base)
#   [3] addi sp, sp, 0         <- HOLE: patched to -g_frame_size after body
#
# The epilogue (mv sp,s0 / ld ra / ld s0 / ret) is emitted by parse_stmt
# each time it sees a 'return'.
#
# Saved regs used here (callee-saved, survive across calls):
#   s1 = func name pointer into input mmap
#   s2 = func name length
#   s3 = address of the frame HOLE in g_out_buf (for backpatch)
.globl parse_funcdef
parse_funcdef:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)
    sd   s2,  8(sp)
    sd   s3,  0(sp)

    # --- expect 'int' ---
    li   a0, TK_INT
    call expect

    # --- capture function name BEFORE consuming ---
    # peek() fills g_tok; we read start/len then consume TK_IDENT.
    call peek
    la   t0, g_tok
    ld   s1, 16(t0)         # s1 = func_name_ptr  (tok.start)
    ld   s2, 24(t0)         # s2 = func_name_len  (tok.len)
    li   a0, TK_IDENT
    call expect             # consumes TK_IDENT (g_tok data still valid)

    li   a0, TK_LPAREN
    call expect

    # --- reset per-function state ---
    la   t0, g_frame_size
    li   t1, 16             # 16 = ra slot (8) + old-s0 slot (8)
    sd   t1, 0(t0)

    la   t0, g_sym_count
    sd   x0, 0(t0)          # clear symbol table

    # --- parse parameter list ---
    # parse_params: for each 'int ident', increments g_frame_size by 8,
    # adds entry to g_sym_table, emits sd aX, -offset(s0).
    call parse_params

    li   a0, TK_RPAREN
    call expect

    # --- emit prologue words [0..2] ---
    li   a0, EMIT_SD_RA_M8_SP
    call emit_u32
    li   a0, EMIT_SD_S0_M16_SP
    call emit_u32
    li   a0, EMIT_MV_S0_SP
    call emit_u32

    # --- emit frame HOLE [3]; record its output address for backpatch ---
    la   t0, g_emit_ptr
    ld   s3, 0(t0)          # s3 = address of HOLE in g_out_buf
    li   a0, EMIT_ADDI_SP_SP_0
    call emit_u32           # placeholder: addi sp, sp, 0

    # --- parse function body ---
    # parse_block emits statements; parse_stmt emits the epilogue at 'return'.
    call parse_block

    # --- backpatch frame HOLE with actual frame size ---
    # Target instruction: addi sp, sp, -frame_size
    # I-type encoding: (sign12(-N) << 20) | EMIT_ADDI_SP_SP_0
    la   t0, g_frame_size
    ld   t1, 0(t0)          # t1 = frame_size  (positive, e.g. 32)
    neg  t1, t1             # t1 = -frame_size
    andi t1, t1, 0xFFF      # keep 12 bits (two's complement)
    slli t1, t1, 20         # shift into imm[31:20]
    li   t2, EMIT_ADDI_SP_SP_0
    or   t1, t1, t2         # combine with base instruction

    mv   a0, s3             # address of the HOLE
    mv   a1, t1             # patched instruction word
    call patch_u32

    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

# ---- stubs below: implement these yourself following the same patterns ----

#-------------------------------- parse_params --------------------------------
# Called with '(' already consumed, ')' not yet consumed.
# For each 'int ident':
#   - call peek; if TK_RPAREN, done (no params or no more params)
#   - expect TK_INT, capture ident name (peek → save start/len → expect TK_IDENT)
#   - compute slot offset = -g_frame_size (then increment g_frame_size by 8)
#   - add (name_ptr, name_len, offset) to g_sym_table[g_sym_count++]
#   - emit: sd aX, offset(s0)  where X = param index (a0 for first, a1 for second, ...)
#     sd aX, offset(s0) encoding: S-type, rs1=x8(s0), rs2=aX, imm=offset
#   - if peek == TK_COMMA: consume and loop; else done
.globl parse_params
parse_params:
    ret                     # TODO

#-------------------------------- parse_block --------------------------------
# Parses: '{' stmt* '}'
.globl parse_block
parse_block:
    addi sp, sp, -16
    sd   ra, 8(sp)

    li   a0, TK_LBRACE
    call expect

    # TODO: loop calling parse_stmt until peek() == TK_RBRACE

    li   a0, TK_RBRACE
    call expect

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_stmt --------------------------------
# Dispatcher on current token:
#   TK_RETURN → parse_expr → emit epilogue → TK_SEMI
#   TK_IF     → parse_expr → backpatch branch → parse_stmt ['else' parse_stmt]
#   TK_WHILE  → backpatch loop → parse_stmt
#   TK_LBRACE → parse_block
#   TK_INT    → local var decl: addi sp,sp,-8 + sym_table entry
#   default   → parse_expr + TK_SEMI  (expression statement)
# Epilogue emitted here on 'return':
#   EMIT_MV_SP_S0 / EMIT_LD_RA_M8_S0 / EMIT_LD_S0_M16_S0 / EMIT_RET
.globl parse_stmt
parse_stmt:
    ret                     # TODO

#-------------------------------- parse_expr --------------------------------
.globl parse_expr
parse_expr:
    addi sp, sp, -16
    sd   ra, 8(sp)
    call parse_assign
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_assign --------------------------------
# assign → logical_or ('=' assign)?   (right-associative)
# Lvalue hint: g_last_was_lval / g_last_lval_offset (set by parse_primary)
# If lvalue and next token is '=': emit sd a0, offset(s0) after rhs.
.globl parse_assign
parse_assign:
    ret                     # TODO

#-------------------------------- parse_or --------------------------------
# logical_or → logical_and ('||' logical_and)*
# Short-circuit: emit beqz / bnez holes, patch at end.
.globl parse_or
parse_or:
    ret                     # TODO

#-------------------------------- parse_and --------------------------------
.globl parse_and
parse_and:
    ret                     # TODO

#-------------------------------- parse_equ --------------------------------
# equality → relational (('=='|'!=') relational)*
.globl parse_equ
parse_equ:
    ret                     # TODO

#-------------------------------- parse_relate --------------------------------
# relational → additive (('<'|'>'|'<='|'>=') additive)*
.globl parse_relate
parse_relate:
    ret                     # TODO

#-------------------------------- parse_addsub --------------------------------
# additive → multiplicative (('+' | '-') multiplicative)*
# Pattern (push/pop for left operand):
#   call parse_muldiv        → a0 = left
#   while peek is + or -:
#     addi sp, sp, -8; sd a0, 0(sp)   [push left]
#     consume; call parse_muldiv       → a0 = right
#     ld a1, 0(sp); addi sp, sp, 8    [pop left into a1]
#     emit: add a0,a1,a0  or  sub a0,a1,a0
.globl parse_addsub
parse_addsub:
    ret                     # TODO

#-------------------------------- parse_muldiv --------------------------------
.globl parse_muldiv
parse_muldiv:
    ret                     # TODO

#-------------------------------- parse_unary --------------------------------
# unary → ('!' | '-') unary  |  parse_primary
.globl parse_unary
parse_unary:
    ret                     # TODO

#-------------------------------- parse_primary --------------------------------
# primary → NUM | ident ['(' args ')'] | '(' expr ')'
# On ident (variable load):
#   - scan g_sym_table for matching name_ptr/name_len
#   - emit: ld a0, offset(s0)
#   - set g_last_was_lval=1, g_last_lval_offset=offset  (for parse_assign)
# On NUM: emit: li a0, value  (lui+addi if > 11 bits)
# On '(' expr ')': consume, call parse_expr, expect ')'
.globl parse_primary
parse_primary:
    ret                     # TODO


#====================== globals ======================
.section .bss
    .balign 8
g_in_fd:    .quad 0
g_out_fd:   .quad 0
g_in_size:  .quad 0
g_in_ptr:   .quad 0

# lexer/parser shared state
g_cur:      .quad 0
g_end:      .quad 0
g_has_tok:  .quad 0
g_tok:      .zero 32    # 0: kind, 8: val (NUM only), 16: start, 24: len

# parser / codegen state
g_emit_ptr:         .quad 0     # current write position in g_out_buf
g_frame_size:       .quad 0     # current function's frame size (bytes)
g_sym_count:        .quad 0     # number of active symbol table entries
g_last_was_lval:    .quad 0     # 1 if last parse_primary result was an lvalue
g_last_lval_offset: .quad 0     # fp-relative offset of that lvalue

# symbol table: 64 entries × 24 bytes (name_ptr, name_len, fp_offset)
g_sym_table:        .zero (64 * 24)

# output code buffer: 512 KiB (enough for a Stage 1 compiler)
    .balign 4096
g_out_buf:          .zero (512 * 1024)

.section .data
    # TODO: any mutable tables/buffers you want initialized at load time
