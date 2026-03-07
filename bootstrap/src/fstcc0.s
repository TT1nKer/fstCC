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

undeclared_var_msg:
    .asciz "undeclared variable"
undeclared_var_msg_len = . - undeclared_var_msg

str_main:
    .ascii "main"              # NOT null-terminated (we use length=4)

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
    li      a3, 420                   # mode 0644 octal = rw-r--r--
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

    # -------- init reloc state --------
    la      t0, g_reloc_count
    sd      x0, 0(t0)
    la      t0, g_func_count
    sd      x0, 0(t0)

    # -------- emit _start stub --------
    # The generated binary's _start will:
    #   jal ra, main   (patched by fixup_calls via a reloc entry)
    #   mv a0, a0      (result already in a0)
    #   li a7, 93      (SYS_exit)
    #   ecall

    # Record _start's jal as a relocation to "main"
    la      t0, g_emit_ptr
    ld      s4, 0(t0)          # s4 = addr of jal instruction (callee-saved)

    # emit: jal ra, 0  (placeholder, will be patched to jump to main)
    li      a0, 0x000000EF     # jal ra, 0
    call    emit_u32

    # record reloc for "main"
    la      t0, g_reloc_count
    ld      t2, 0(t0)
    li      t3, 24
    mul     t3, t2, t3
    la      t4, g_reloc_table
    add     t4, t4, t3
    sd      s4, 0(t4)          # call site addr (saved in s4)

    # We need a pointer to the string "main" in our rodata
    la      t5, str_main
    sd      t5, 8(t4)          # func_name_ptr
    li      t5, 4
    sd      t5, 16(t4)         # func_name_len = 4
    addi    t2, t2, 1
    sd      t2, 0(t0)

    # emit: li a7, 93  = addi a7, x0, 93
    # I-type: imm=93=0x5D, rs1=x0, funct3=000, rd=a7=x17, op=0010011
    # 0x05D00893
    li      a0, 0x05D00893
    call    emit_u32

    # emit: ecall = 0x00000073
    li      a0, 0x00000073
    call    emit_u32

    # -------- parse all function definitions --------
    call    parse_program

#---------------------- write output ---------------------
    # write [g_out_buf .. g_emit_ptr) to g_out_fd via SYS_write
    la      t0, g_out_buf
    la      t1, g_emit_ptr
    ld      t1, 0(t1)
    sub     t2, t1, t0          # t2 = byte count

    la      t3, g_out_fd
    ld      a0, 0(t3)          # fd
    mv      a1, t0             # buf
    mv      a2, t2             # count
    li      a7, 64             # SYS_write
    ecall

    # close output fd
    la      t0, g_out_fd
    ld      a0, 0(t0)
    li      a7, 57             # SYS_close
    ecall

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

#-------------------------------- emit_li_a0 --------------------------------
# a0 = immediate value to load into a0 in the *generated* code.
# If value fits in signed 12 bits [-2048, 2047]: emit addi a0, x0, val
# Otherwise: emit lui a0, upper20 ; addi a0, a0, lower12
.globl emit_li_a0
emit_li_a0:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0              # s1 = value

    # check if fits in signed 12 bits
    li   t0, -2048
    blt  s1, t0, .li_large
    li   t0, 2047
    bgt  s1, t0, .li_large

    # small: addi a0, x0, val
    # I-type: imm[11:0] at bits [31:20]
    # Extract low 12 bits via shift pair (avoids andi with 0xFFF)
    slli t1, s1, 52
    srli t1, t1, 32           # low 12 bits of s1 now in bits [31:20]
    li   t2, 0x00000513       # addi a0, x0, 0
    or   a0, t1, t2
    call emit_u32
    j    .li_done

.li_large:
    # lui a0, upper20 ; addi a0, a0, lower12
    # Extract low 12 bits
    slli t1, s1, 52
    srli t1, t1, 52           # t1 = zero-extended low 12 bits
    # upper = value >> 12 (arithmetic)
    srai t2, s1, 12

    # if bit 11 of lower is set, addi will sign-extend and subtract from upper
    # so we compensate: upper += 1
    srli t3, t1, 11           # bit 11 → bit 0
    andi t3, t3, 1
    add  t2, t2, t3           # upper += (bit11 ? 1 : 0)

    # lui a0, upper20
    # U-type: imm at bits [31:12]
    slli t2, t2, 12           # shift upper to bits [31:12]
    li   t3, 0x00000537       # lui a0, 0
    or   a0, t2, t3
    call emit_u32

    # addi a0, a0, lower12
    slli t1, t1, 20           # low 12 bits → bits [31:20]
    li   t2, 0x00050513       # addi a0, a0, 0
    or   a0, t1, t2
    call emit_u32

.li_done:
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_ld_a0_off_s0 --------------------------------
# a0 = signed offset (e.g. -24)
# Emits: ld a0, offset(s0)
# I-type: imm[11:0] at bits [31:20]
.globl emit_ld_a0_off_s0
emit_ld_a0_off_s0:
    addi sp, sp, -16
    sd   ra, 8(sp)

    slli t1, a0, 52
    srli t1, t1, 32           # low 12 bits → bits [31:20]
    li   t2, 0x00043503       # ld a0, 0(s0)
    or   a0, t1, t2
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_sd_a0_off_s0 --------------------------------
# a0 = signed offset (e.g. -24)
# Emits: sd a0, offset(s0)
# S-type: imm[11:5] at bits [31:25], imm[4:0] at bits [11:7]
.globl emit_sd_a0_off_s0
emit_sd_a0_off_s0:
    addi sp, sp, -16
    sd   ra, 8(sp)

    # extract low 12 bits of offset
    slli t0, a0, 52
    srli t0, t0, 52           # t0 = zero-extended 12-bit offset

    # imm[4:0] → instruction bits [11:7]
    andi t1, t0, 0x1F         # 0x1F fits in 12-bit signed
    slli t1, t1, 7

    # imm[11:5] → instruction bits [31:25]
    srli t2, t0, 5            # shift bits [11:5] down to [6:0]
    andi t2, t2, 0x7F         # keep 7 bits (0x7F fits in 12-bit signed)
    slli t2, t2, 25           # shift to bits [31:25]

    or   t1, t1, t2
    li   t3, 0x00A43023       # sd a0, 0(s0) base (rs2=a0, rs1=s0)
    or   a0, t1, t3
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_sd_aX_off_s0 --------------------------------
# a0 = register index X (0-7 for a0-a7, i.e. x10-x17)
# a1 = signed offset
# Emits: sd aX, offset(s0)
.globl emit_sd_aX_off_s0
emit_sd_aX_off_s0:
    addi sp, sp, -16
    sd   ra, 8(sp)

    # rs2 field = x(10+a0), goes into bits [24:20]
    addi t4, a0, 10
    slli t4, t4, 20

    # extract low 12 bits of offset
    slli t0, a1, 52
    srli t0, t0, 52

    # imm[4:0] → bits [11:7]
    andi t1, t0, 0x1F
    slli t1, t1, 7

    # imm[11:5] → bits [31:25]
    srli t2, t0, 5
    andi t2, t2, 0x7F
    slli t2, t2, 25

    or   t1, t1, t2
    or   t1, t1, t4           # add rs2

    # base: sd x0, 0(s0) (rs2 cleared, we provide it above)
    li   t3, 0x00043023
    or   a0, t1, t3
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_push_a0 --------------------------------
# Emits: addi sp, sp, -8 ; sd a0, 0(sp)
# Used to push left operand in binary expressions.
.globl emit_push_a0
emit_push_a0:
    addi sp, sp, -16
    sd   ra, 8(sp)

    li   a0, 0xFF810113       # addi sp, sp, -8
    call emit_u32
    li   a0, 0x00A13023       # sd a0, 0(sp)
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_pop_a1 --------------------------------
# Emits: ld a1, 0(sp) ; addi sp, sp, 8
# Used to pop left operand into a1 after right operand is computed in a0.
.globl emit_pop_a1
emit_pop_a1:
    addi sp, sp, -16
    sd   ra, 8(sp)

    li   a0, 0x00013583       # ld a1, 0(sp)
    call emit_u32
    li   a0, 0x00810113       # addi sp, sp, 8
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_beqz_a0_hole --------------------------------
# Emits: beqz a0, 0  (B-type placeholder with offset=0)
# Returns a0 = address of the emitted word in g_out_buf (for patching).
.globl emit_beqz_a0_hole
emit_beqz_a0_hole:
    addi sp, sp, -16
    sd   ra, 8(sp)

    la   t0, g_emit_ptr
    ld   s1, 0(t0)            # save current emit address (use s1 temporarily - but we need to save it)

    # Actually, let's save it properly
    sd   s1, 0(sp)
    la   t0, g_emit_ptr
    ld   s1, 0(t0)            # s1 = address of hole

    # beq a0, x0, 0  →  B-type: imm=0, rs1=a0(x10), rs2=x0, funct3=000
    # opcode=1100011, funct3=000, rs1=01010, rs2=00000, imm=0
    li   a0, 0x00050063       # beq a0, x0, 0
    call emit_u32

    mv   a0, s1               # return hole address
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_j_hole --------------------------------
# Emits: jal x0, 0 (J-type placeholder with offset=0)
# Returns a0 = address of the emitted word in g_out_buf (for patching).
.globl emit_j_hole
emit_j_hole:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    la   t0, g_emit_ptr
    ld   s1, 0(t0)            # s1 = address of hole

    # jal x0, 0 → J-type: imm=0, rd=x0
    # opcode=1101111, rd=00000, imm=0
    li   a0, 0x0000006F       # jal x0, 0
    call emit_u32

    mv   a0, s1
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- patch_branch --------------------------------
# a0 = address of B-type instruction in g_out_buf
# a1 = target address in g_out_buf
# Computes offset = target - hole_addr, encodes B-type imm, patches.
# B-type imm layout (13-bit signed, bit 0 always 0):
#   offset bit 12   → instr bit 31
#   offset bits 10:5 → instr bits 30:25
#   offset bits 4:1  → instr bits 11:8
#   offset bit 11   → instr bit 7
.globl patch_branch
patch_branch:
    sub  t0, a1, a0           # t0 = offset (signed, in bytes)

    # bit 12 → instr bit 31
    srli t1, t0, 12
    andi t1, t1, 1            # isolate bit 12 (now in bit 0)
    slli t1, t1, 31           # → bit 31

    # bits 10:5 → instr bits 30:25
    srli t2, t0, 5
    andi t2, t2, 0x3F         # 6 bits (0x3F fits in 12-bit signed)
    slli t2, t2, 25           # → bits 30:25

    # bits 4:1 → instr bits 11:8
    srli t3, t0, 1
    andi t3, t3, 0xF          # 4 bits
    slli t3, t3, 8            # → bits 11:8

    # bit 11 → instr bit 7
    srli t4, t0, 11
    andi t4, t4, 1
    slli t4, t4, 7            # → bit 7

    or   t1, t1, t2
    or   t1, t1, t3
    or   t1, t1, t4           # combined imm fields

    # load existing instruction, clear imm fields, OR in new imm
    # keep: opcode[6:0], funct3[14:12], rs1[19:15], rs2[24:20]
    # mask = 0x01FFF07F
    lw   t5, 0(a0)
    li   t6, 0x01FFF07F
    and  t5, t5, t6
    or   t5, t5, t1
    sw   t5, 0(a0)
    ret

#-------------------------------- patch_jump --------------------------------
# a0 = address of J-type instruction in g_out_buf
# a1 = target address in g_out_buf
# Computes offset = target - hole_addr, encodes J-type imm, patches.
# J-type imm layout (21-bit signed, bit 0 always 0):
#   offset bit 20   → instr bit 31
#   offset bits 10:1 → instr bits 30:21
#   offset bit 11   → instr bit 20
#   offset bits 19:12 → instr bits 19:12
.globl patch_jump
patch_jump:
    sub  t0, a1, a0           # t0 = offset (signed)

    # bit 20 → instr bit 31
    srli t1, t0, 20
    andi t1, t1, 1
    slli t1, t1, 31

    # bits 10:1 → instr bits 30:21
    srli t2, t0, 1
    li   t6, 0x3FF            # 10 bits mask (fits in 12-bit signed)
    and  t2, t2, t6
    slli t2, t2, 21

    # bit 11 → instr bit 20
    srli t3, t0, 11
    andi t3, t3, 1
    slli t3, t3, 20

    # bits 19:12 → instr bits 19:12 (same position)
    srli t4, t0, 12
    andi t4, t4, 0xFF         # 8 bits
    slli t4, t4, 12

    or   t1, t1, t2
    or   t1, t1, t3
    or   t1, t1, t4           # combined imm

    # keep opcode + rd (bits 11:0): zero out bits [31:12]
    lwu  t5, 0(a0)            # lwu: zero-extend 32-bit load
    slli t5, t5, 52           # clear bits above 11
    srli t5, t5, 52           # t5 = bits [11:0] only
    or   t5, t5, t1
    sw   t5, 0(a0)
    ret

#-------------------------------- emit_epilogue --------------------------------
# Emits the 4-instruction epilogue sequence for the *generated* function.
.globl emit_epilogue
emit_epilogue:
    addi sp, sp, -16
    sd   ra, 8(sp)

    li   a0, EMIT_MV_SP_S0
    call emit_u32
    li   a0, EMIT_LD_RA_M8_S0
    call emit_u32
    li   a0, EMIT_LD_S0_M16_S0
    call emit_u32
    li   a0, EMIT_RET
    call emit_u32

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- sym_lookup --------------------------------
# a0 = name_ptr (into mmap), a1 = name_len
# Scans g_sym_table for matching entry.
# Returns: a0 = fp_offset if found, a1 = 1
#          a0 = 0, a1 = 0 if not found
.globl sym_lookup
sym_lookup:
    # a0 = name_ptr, a1 = name_len
    # Uses: t0-t6, a2 (as temp — caller-saved, fine for a leaf-ish function)
    # Returns: a0 = fp_offset, a1 = 1 if found; a0=0, a1=0 if not
    la   t0, g_sym_count
    ld   t1, 0(t0)            # t1 = count
    la   t2, g_sym_table      # t2 = table cursor
    li   t3, 0                # t3 = index
.sym_loop:
    bge  t3, t1, .sym_notfound

    ld   t4, 8(t2)            # entry.name_len
    bne  t4, a1, .sym_next    # lengths differ → skip

    # lengths match: compare bytes
    ld   t4, 0(t2)            # t4 = entry.name_ptr
    mv   t5, a0               # t5 = needle ptr (copy, will advance)
    mv   t6, a1               # t6 = remaining count
.sym_cmp:
    beqz t6, .sym_found
    lbu  a2, 0(t4)            # byte from entry
    lbu  a3, 0(t5)            # byte from needle (a3 is caller-saved)
    bne  a2, a3, .sym_next
    addi t4, t4, 1
    addi t5, t5, 1
    addi t6, t6, -1
    j    .sym_cmp

.sym_found:
    ld   a0, 16(t2)           # fp_offset
    li   a1, 1
    ret

.sym_next:
    addi t2, t2, 24
    addi t3, t3, 1
    j    .sym_loop

.sym_notfound:
    li   a0, 0
    li   a1, 0
    ret

#-------------------------------- sym_add --------------------------------
# a0 = name_ptr, a1 = name_len, a2 = fp_offset
# Adds entry to g_sym_table[g_sym_count], increments g_sym_count.
.globl sym_add
sym_add:
    la   t0, g_sym_count
    ld   t1, 0(t0)            # t1 = current count

    # address = g_sym_table + count * 24
    li   t2, 24
    mul  t2, t1, t2
    la   t3, g_sym_table
    add  t3, t3, t2           # t3 = &table[count]

    sd   a0, 0(t3)            # name_ptr
    sd   a1, 8(t3)            # name_len
    sd   a2, 16(t3)           # fp_offset

    addi t1, t1, 1
    sd   t1, 0(t0)            # g_sym_count++
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
    # --- fixup pass: resolve all call relocations ---
    call fixup_calls

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- fixup_calls --------------------------------
# Iterates g_reloc_table. For each entry, finds the function in g_func_table
# and patches the jal instruction at the call site.
.globl fixup_calls
fixup_calls:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)
    sd   s2,  8(sp)
    sd   s3,  0(sp)

    la   t0, g_reloc_count
    ld   s1, 0(t0)           # s1 = reloc count
    la   s2, g_reloc_table   # s2 = reloc cursor
    li   s3, 0               # s3 = index

.fix_loop:
    bge  s3, s1, .fix_done
    ld   t0, 0(s2)           # call_site_addr
    ld   t1, 8(s2)           # func_name_ptr
    ld   t2, 16(s2)          # func_name_len

    # save call_site on stack (t-regs clobbered by lookup)
    addi sp, sp, -8
    sd   t0, 0(sp)

    # look up function in g_func_table
    mv   a0, t1
    mv   a1, t2
    call func_lookup          # a0 = func_addr, a1 = found?

    ld   t0, 0(sp)           # restore call_site_addr
    addi sp, sp, 8

    beqz a1, .fix_next       # not found = skip (error in real compiler)

    # patch jal: offset = func_addr - call_site_addr
    mv   a1, a0              # a1 = target (func_addr)
    mv   a0, t0              # a0 = call_site_addr
    call patch_jump

.fix_next:
    addi s2, s2, 24
    addi s3, s3, 1
    j    .fix_loop

.fix_done:
    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

#-------------------------------- func_lookup --------------------------------
# a0 = name_ptr, a1 = name_len
# Returns: a0 = func output addr, a1 = 1 if found; a0=0, a1=0 if not found.
.globl func_lookup
func_lookup:
    la   t0, g_func_count
    ld   t1, 0(t0)
    la   t2, g_func_table
    li   t3, 0
.fl_loop:
    bge  t3, t1, .fl_notfound
    ld   t4, 8(t2)           # entry.name_len
    bne  t4, a1, .fl_next

    # lengths match: compare bytes
    ld   t4, 0(t2)           # t4 = entry.name_ptr
    mv   t5, a0              # t5 = needle ptr
    mv   t6, a1              # t6 = remaining count
.fl_cmp:
    beqz t6, .fl_found
    lbu  a2, 0(t4)
    lbu  a3, 0(t5)
    bne  a2, a3, .fl_next
    addi t4, t4, 1
    addi t5, t5, 1
    addi t6, t6, -1
    j    .fl_cmp

.fl_found:
    ld   a0, 16(t2)          # func output addr
    li   a1, 1
    ret

.fl_next:
    addi t2, t2, 24
    addi t3, t3, 1
    j    .fl_loop

.fl_notfound:
    li   a0, 0
    li   a1, 0
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

    # --- record function address in g_func_table ---
    la   t0, g_emit_ptr
    ld   t1, 0(t0)          # t1 = function start address in g_out_buf
    la   t0, g_func_count
    ld   t2, 0(t0)
    li   t3, 24
    mul  t3, t2, t3
    la   t4, g_func_table
    add  t4, t4, t3
    sd   s1, 0(t4)          # func_name_ptr
    sd   s2, 8(t4)          # func_name_len
    sd   t1, 16(t4)         # func output addr
    addi t2, t2, 1
    sd   t2, 0(t0)

    # --- emit prologue words [0..2] BEFORE parse_params ---
    # (params emit sd aX,offset(s0) which requires s0 to be set)
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

    # --- parse parameter list ---
    # parse_params: for each 'int ident', increments g_frame_size by 8,
    # adds entry to g_sym_table, emits sd aX, -offset(s0).
    call parse_params

    li   a0, TK_RPAREN
    call expect

    # --- parse function body ---
    # parse_block emits statements; parse_stmt emits the epilogue at 'return'.
    call parse_block

    # --- backpatch frame HOLE with actual frame size ---
    # Align frame_size up to multiple of 16 (RISC-V ABI)
    la   t0, g_frame_size
    ld   t1, 0(t0)          # t1 = frame_size  (positive, e.g. 24)
    addi t1, t1, 15         # round up
    andi t1, t1, -16        # align to 16 (-16 = 0xFFFF...FFF0, andi sign-extends -16 OK)
    sd   t1, 0(t0)          # store aligned size

    # Target instruction: addi sp, sp, -frame_size
    # I-type encoding: extract low 12 bits of -frame_size, place at bits [31:20]
    neg  t1, t1             # t1 = -frame_size (negative)
    slli t1, t1, 52         # clear upper bits, keep low 12
    srli t1, t1, 32         # move 12-bit imm to bits [31:20]
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
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)         # s1 = param_index
    sd   s2,  8(sp)         # s2 = name_ptr
    sd   s3,  0(sp)         # s3 = name_len
    li   s1, 0              # param_index = 0

.pp_param_loop:
    call peek
    li   t0, TK_RPAREN
    beq  a0, t0, .pp_params_done   # no more params

    # expect 'int'
    li   a0, TK_INT
    call expect

    # capture ident name (peek fills g_tok, then expect consumes)
    call peek
    la   t0, g_tok
    ld   s2, 16(t0)         # name_ptr = tok.start
    ld   s3, 24(t0)         # name_len = tok.len
    li   a0, TK_IDENT
    call expect

    # bump g_frame_size by 8, get offset = -new_frame_size
    la   t0, g_frame_size
    ld   t1, 0(t0)
    addi t1, t1, 8
    sd   t1, 0(t0)
    neg  t2, t1             # t2 = -frame_size = offset

    # sym_add(name_ptr, name_len, offset)
    mv   a0, s2
    mv   a1, s3
    mv   a2, t2
    call sym_add

    # emit: sd aX, offset(s0)
    # reload offset (t2 was clobbered by sym_add)
    la   t0, g_frame_size
    ld   t1, 0(t0)
    neg  t2, t1
    mv   a0, s1             # param_index (0=a0, 1=a1, ...)
    mv   a1, t2             # offset
    call emit_sd_aX_off_s0

    addi s1, s1, 1          # param_index++

    # if next is comma, consume and continue; else done
    li   a0, TK_COMMA
    call consume
    bnez a0, .pp_param_loop  # consumed comma -> next param
    j    .pp_params_done     # no comma -> done

.pp_params_done:
    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

#-------------------------------- parse_block --------------------------------
# Parses: '{' stmt* '}'
.globl parse_block
parse_block:
    addi sp, sp, -16
    sd   ra, 8(sp)

    li   a0, TK_LBRACE
    call expect

.pb_loop:
    call peek
    li   t0, TK_RBRACE
    beq  a0, t0, .pb_done
    li   t0, TK_EOF
    beq  a0, t0, .pb_done     # safety: don't loop forever on missing '}'
    call parse_stmt
    j    .pb_loop
.pb_done:

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
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)         # s1 = scratch (hole addr, etc.)
    sd   s2,  8(sp)         # s2 = scratch
    sd   s3,  0(sp)         # s3 = scratch

    call peek

    li   t0, TK_RETURN
    beq  a0, t0, .ps_return
    li   t0, TK_IF
    beq  a0, t0, .ps_if
    li   t0, TK_WHILE
    beq  a0, t0, .ps_while
    li   t0, TK_LBRACE
    beq  a0, t0, .ps_block
    li   t0, TK_INT
    beq  a0, t0, .ps_vardecl
    j    .ps_exprstmt

# ---- return expr ; ----
.ps_return:
    li   a0, TK_RETURN
    call consume

    call parse_expr
    call emit_epilogue

    li   a0, TK_SEMI
    call expect
    j    .ps_done

# ---- if ( expr ) stmt [else stmt] ----
.ps_if:
    li   a0, TK_IF
    call consume

    li   a0, TK_LPAREN
    call expect
    call parse_expr
    li   a0, TK_RPAREN
    call expect

    # emit beqz a0, ? (hole for else/endif)
    call emit_beqz_a0_hole
    mv   s1, a0             # s1 = beqz hole addr

    call parse_stmt          # then-branch

    # check for 'else'
    call peek
    li   t0, TK_ELSE
    bne  a0, t0, .ps_if_no_else

    # has else: emit j ? (hole for endif), patch beqz to here
    li   a0, TK_ELSE
    call consume

    call emit_j_hole
    mv   s2, a0             # s2 = j hole addr (skip else)

    # patch beqz to current emit position (start of else body)
    mv   a0, s1
    la   t0, g_emit_ptr
    ld   a1, 0(t0)
    call patch_branch

    call parse_stmt          # else-branch

    # patch j to current emit position (end of else)
    mv   a0, s2
    la   t0, g_emit_ptr
    ld   a1, 0(t0)
    call patch_jump
    j    .ps_done

.ps_if_no_else:
    # patch beqz to current emit position
    mv   a0, s1
    la   t0, g_emit_ptr
    ld   a1, 0(t0)
    call patch_branch
    j    .ps_done

# ---- while ( expr ) stmt ----
.ps_while:
    li   a0, TK_WHILE
    call consume

    # record loop top
    la   t0, g_emit_ptr
    ld   s1, 0(t0)          # s1 = loop_top addr

    li   a0, TK_LPAREN
    call expect
    call parse_expr
    li   a0, TK_RPAREN
    call expect

    # emit beqz a0, ? (hole for loop exit)
    call emit_beqz_a0_hole
    mv   s2, a0             # s2 = beqz hole addr

    call parse_stmt

    # emit j loop_top (unconditional back-edge)
    # We need to emit jal x0, offset where offset = loop_top - current_emit_ptr
    call emit_j_hole
    mv   s3, a0             # s3 = j hole addr
    mv   a0, s3
    mv   a1, s1             # target = loop_top
    call patch_jump

    # patch beqz to current emit position (loop exit)
    mv   a0, s2
    la   t0, g_emit_ptr
    ld   a1, 0(t0)
    call patch_branch
    j    .ps_done

# ---- { stmt* } ----
.ps_block:
    call parse_block
    j    .ps_done

# ---- int ident [= expr] ; ----
.ps_vardecl:
    li   a0, TK_INT
    call consume

    # capture ident name
    call peek
    la   t0, g_tok
    ld   s1, 16(t0)         # name_ptr
    ld   s2, 24(t0)         # name_len
    li   a0, TK_IDENT
    call expect

    # bump g_frame_size, get offset
    la   t0, g_frame_size
    ld   t1, 0(t0)
    addi t1, t1, 8
    sd   t1, 0(t0)
    neg  s3, t1             # s3 = offset = -frame_size

    # sym_add(name_ptr, name_len, offset)
    mv   a0, s1
    mv   a1, s2
    mv   a2, s3
    call sym_add

    # optional initializer: = expr
    li   a0, TK_ASSIGN
    call consume
    beqz a0, .ps_vardecl_no_init

    call parse_expr

    # emit: sd a0, offset(s0)
    mv   a0, s3
    call emit_sd_a0_off_s0

.ps_vardecl_no_init:
    li   a0, TK_SEMI
    call expect
    j    .ps_done

# ---- expression statement: expr ; ----
.ps_exprstmt:
    call parse_expr
    li   a0, TK_SEMI
    call expect

.ps_done:
    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

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
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    call parse_or            # a0 = result (value in generated a0)

    # check if last primary was an lvalue and next token is '='
    la   t0, g_last_was_lval
    ld   t1, 0(t0)
    beqz t1, .pa_done        # not an lvalue

    # save the lval offset before consume might clobber things
    la   t0, g_last_lval_offset
    ld   s1, 0(t0)           # s1 = lval fp offset

    li   a0, TK_ASSIGN
    call consume
    beqz a0, .pa_done        # no '=' follows

    # parse RHS (right-associative: call parse_assign recursively)
    call parse_assign

    # emit: sd a0, offset(s0)  (store result into the variable)
    mv   a0, s1
    call emit_sd_a0_off_s0

.pa_done:
    # clear lval flag
    la   t0, g_last_was_lval
    sd   x0, 0(t0)

    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_or --------------------------------
# logical_or → logical_and ('||' logical_and)*
# Short-circuit: emit beqz / bnez holes, patch at end.
.globl parse_or
parse_or:
    addi sp, sp, -16
    sd   ra, 8(sp)

    call parse_and

.por_loop:
    li   a0, TK_OR
    call consume
    beqz a0, .por_done

    # push left operand
    call emit_push_a0
    call parse_and
    call emit_pop_a1

    # emit: snez a1, a1  (a1 = left != 0)
    li   a0, 0x00B03533      # sltu a0(x10), x0, a1(x11) — but we want rd=a1
    # Actually: snez a1,a1 = sltu a1,x0,a1 → funct7=0,rs2=x11,rs1=x0,funct3=011,rd=x11,op=0110011
    # = 0000000 01011 00000 011 01011 0110011 = 0x00B035B3
    li   a0, 0x00B035B3      # snez a1, a1
    call emit_u32
    # emit: snez a0, a0  = sltu a0,x0,a0
    # = 0000000 01010 00000 011 01010 0110011 = 0x00A03533
    li   a0, 0x00A03533      # snez a0, a0
    call emit_u32
    # emit: or a0, a0, a1
    # = 0000000 01011 01010 110 01010 0110011 = 0x00B56533
    li   a0, 0x00B56533      # or a0, a0, a1
    call emit_u32

    j    .por_loop
.por_done:
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_and --------------------------------
.globl parse_and
parse_and:
    addi sp, sp, -16
    sd   ra, 8(sp)

    call parse_equ

.pand_loop:
    li   a0, TK_AND
    call consume
    beqz a0, .pand_done

    call emit_push_a0
    call parse_equ
    call emit_pop_a1

    # emit: snez a1, a1
    li   a0, 0x00B035B3
    call emit_u32
    # emit: snez a0, a0
    li   a0, 0x00A03533
    call emit_u32
    # emit: and a0, a0, a1
    # = 0000000 01011 01010 111 01010 0110011 = 0x00B57533
    li   a0, 0x00B57533
    call emit_u32

    j    .pand_loop
.pand_done:
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_equ --------------------------------
# equality → relational (('=='|'!=') relational)*
.globl parse_equ
parse_equ:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    call parse_relate

.peq_loop:
    # check for == or !=
    li   a0, TK_EQ
    call consume
    bnez a0, .peq_eq
    li   a0, TK_NEQ
    call consume
    bnez a0, .peq_neq
    j    .peq_done

.peq_eq:
    li   s1, 1              # 1 = eq
    j    .peq_binop
.peq_neq:
    li   s1, 2              # 2 = neq

.peq_binop:
    call emit_push_a0
    call parse_relate
    call emit_pop_a1

    # emit: sub a0, a1, a0  (a1=left, a0=right)
    # = 0100000 01010 01011 000 01010 0110011 = 0x40A58533
    li   a0, 0x40A58533
    call emit_u32

    li   t0, 1
    beq  s1, t0, .peq_emit_seqz
    # neq: snez a0, a0  = sltu a0, x0, a0
    li   a0, 0x00A03533
    call emit_u32
    j    .peq_loop

.peq_emit_seqz:
    # eq: seqz a0, a0  = sltiu a0, a0, 1
    li   a0, 0x00153513
    call emit_u32
    j    .peq_loop

.peq_done:
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_relate --------------------------------
# relational → additive (('<'|'>'|'<='|'>=') additive)*
.globl parse_relate
parse_relate:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    call parse_addsub

.prel_loop:
    li   a0, TK_LT
    call consume
    bnez a0, .prel_lt
    li   a0, TK_GT
    call consume
    bnez a0, .prel_gt
    li   a0, TK_LE
    call consume
    bnez a0, .prel_le
    li   a0, TK_GE
    call consume
    bnez a0, .prel_ge
    j    .prel_done

.prel_lt:  li s1, 1; j .prel_binop
.prel_gt:  li s1, 2; j .prel_binop
.prel_le:  li s1, 3; j .prel_binop
.prel_ge:  li s1, 4; j .prel_binop

.prel_binop:
    call emit_push_a0
    call parse_addsub
    call emit_pop_a1         # a1 = left, a0 = right

    li   t0, 1
    beq  s1, t0, .prel_emit_lt
    li   t0, 2
    beq  s1, t0, .prel_emit_gt
    li   t0, 3
    beq  s1, t0, .prel_emit_le
    j    .prel_emit_ge

.prel_emit_lt:
    # slt a0, a1, a0  (left < right)
    # = 0000000 01010 01011 010 01010 0110011 = 0x00A5A533
    li   a0, 0x00A5A533
    call emit_u32
    j    .prel_loop

.prel_emit_gt:
    # slt a0, a0, a1  (right < left = left > right)
    # = 0000000 01011 01010 010 01010 0110011 = 0x00B52533
    li   a0, 0x00B52533
    call emit_u32
    j    .prel_loop

.prel_emit_le:
    # slt a0, a0, a1 then xori a0,a0,1  (!(left > right) = left <= right)
    li   a0, 0x00B52533      # slt a0, a0, a1
    call emit_u32
    li   a0, 0x00154513      # xori a0, a0, 1
    call emit_u32
    j    .prel_loop

.prel_emit_ge:
    # slt a0, a1, a0 then xori a0,a0,1  (!(left < right) = left >= right)
    li   a0, 0x00A5A533      # slt a0, a1, a0
    call emit_u32
    li   a0, 0x00154513      # xori a0, a0, 1
    call emit_u32
    j    .prel_loop

.prel_done:
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

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
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    call parse_muldiv

.pas_loop:
    li   a0, TK_PLUS
    call consume
    bnez a0, .pas_add
    li   a0, TK_MINUS
    call consume
    bnez a0, .pas_sub
    j    .pas_done

.pas_add: li s1, 1; j .pas_binop
.pas_sub: li s1, 2

.pas_binop:
    call emit_push_a0
    call parse_muldiv
    call emit_pop_a1         # a1=left, a0=right

    li   t0, 1
    beq  s1, t0, .pas_emit_add
    # sub a0, a1, a0
    li   a0, 0x40A58533
    call emit_u32
    j    .pas_loop

.pas_emit_add:
    # add a0, a1, a0
    li   a0, 0x00A58533
    call emit_u32
    j    .pas_loop

.pas_done:
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_muldiv --------------------------------
.globl parse_muldiv
parse_muldiv:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)

    call parse_unary

.pmd_loop:
    li   a0, TK_MUL
    call consume
    bnez a0, .pmd_mul
    li   a0, TK_DIV
    call consume
    bnez a0, .pmd_div
    li   a0, TK_MOD
    call consume
    bnez a0, .pmd_mod
    j    .pmd_done

.pmd_mul: li s1, 1; j .pmd_binop
.pmd_div: li s1, 2; j .pmd_binop
.pmd_mod: li s1, 3

.pmd_binop:
    call emit_push_a0
    call parse_unary
    call emit_pop_a1         # a1=left, a0=right

    li   t0, 1
    beq  s1, t0, .pmd_emit_mul
    li   t0, 2
    beq  s1, t0, .pmd_emit_div
    # rem a0, a1, a0
    li   a0, 0x02A5E533
    call emit_u32
    j    .pmd_loop

.pmd_emit_mul:
    # mul a0, a1, a0
    li   a0, 0x02A58533
    call emit_u32
    j    .pmd_loop

.pmd_emit_div:
    # div a0, a1, a0
    li   a0, 0x02A5C533
    call emit_u32
    j    .pmd_loop

.pmd_done:
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_unary --------------------------------
# unary → ('!' | '-') unary  |  parse_primary
.globl parse_unary
parse_unary:
    addi sp, sp, -16
    sd   ra, 8(sp)

    # check for unary minus
    li   a0, TK_MINUS
    call consume
    bnez a0, .pu_neg

    # check for unary not
    li   a0, TK_NOT
    call consume
    bnez a0, .pu_not

    # otherwise: primary
    call parse_primary
    j    .pu_done

.pu_neg:
    call parse_unary
    # emit: sub a0, x0, a0  (neg a0, a0)
    # = 0100000 01010 00000 000 01010 0110011 = 0x40A00533
    li   a0, 0x40A00533
    call emit_u32
    j    .pu_done

.pu_not:
    call parse_unary
    # emit: seqz a0, a0  = sltiu a0, a0, 1
    li   a0, 0x00153513
    call emit_u32

.pu_done:
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

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
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)
    sd   s2,  8(sp)
    sd   s3,  0(sp)

    # clear lval flag
    la   t0, g_last_was_lval
    sd   x0, 0(t0)

    call peek

    li   t0, TK_NUM
    beq  a0, t0, .pp_num
    li   t0, TK_IDENT
    beq  a0, t0, .pp_ident
    li   t0, TK_LPAREN
    beq  a0, t0, .pp_paren

    # unexpected token
    la   t0, g_tok
    ld   a0, 16(t0)
    la   a1, expected_token_msg
    li   a2, expected_token_msg_len
    call error_at

# ---- number literal ----
.pp_num:
    # save tok.val before consuming
    la   t0, g_tok
    ld   s1, 8(t0)           # s1 = value
    li   a0, TK_NUM
    call consume

    # emit li a0, value
    mv   a0, s1
    call emit_li_a0
    j    .pp_done

# ---- identifier (variable ref or function call) ----
.pp_ident:
    # capture name before consuming
    la   t0, g_tok
    ld   s1, 16(t0)          # s1 = name_ptr
    ld   s2, 24(t0)          # s2 = name_len
    li   a0, TK_IDENT
    call consume

    # check for function call: ident '('
    call peek
    li   t0, TK_LPAREN
    beq  a0, t0, .pp_funcall

    # variable reference: look up in sym table
    mv   a0, s1
    mv   a1, s2
    call sym_lookup           # a0 = offset, a1 = found?

    beqz a1, .pp_undeclared

    mv   s3, a0              # s3 = fp offset

    # emit: ld a0, offset(s0)
    mv   a0, s3
    call emit_ld_a0_off_s0

    # set lval info for parse_assign
    la   t0, g_last_was_lval
    li   t1, 1
    sd   t1, 0(t0)
    la   t0, g_last_lval_offset
    sd   s3, 0(t0)
    j    .pp_done

.pp_undeclared:
    mv   a0, s1              # point at the identifier
    la   a1, undeclared_var_msg
    li   a2, undeclared_var_msg_len
    call error_at

# ---- function call: ident '(' args ')' ----
.pp_funcall:
    li   a0, TK_LPAREN
    call consume

    # For now, support up to 8 args pushed onto compiler stack,
    # then moved into a0-a7 before the call.
    # Strategy: emit each arg expr, push result. After all args,
    # pop into a7..a0 (reverse order). Then emit call.
    # We use s3 as arg count.
    li   s3, 0               # arg count

    # check for empty arg list
    call peek
    li   t0, TK_RPAREN
    beq  a0, t0, .pp_fc_noargs

.pp_fc_argloop:
    call parse_expr
    call emit_push_a0        # push arg value
    addi s3, s3, 1

    li   a0, TK_COMMA
    call consume
    bnez a0, .pp_fc_argloop

.pp_fc_noargs:
    li   a0, TK_RPAREN
    call expect

    # pop args into a0-a7 (pop in reverse: last pushed = highest arg reg)
    # We pop s3 values. First pop goes into a(s3-1), last into a0.
    mv   t0, s3
.pp_fc_pop:
    beqz t0, .pp_fc_call
    addi t0, t0, -1

    # emit: ld a(t0), 0(sp); addi sp,sp,8
    # ld aX, 0(sp): I-type imm=0, rs1=sp(x2), funct3=011, rd=x(10+t0), op=0000011
    # base for ld x10,0(sp) = 0x00013503
    # each +1 to rd shifts by 7 bits: rd field is bits [11:7]
    # So: 0x00013503 + (t0 << 7) ... but we can't do this at the compiler level
    # since we're emitting machine code. We need to construct the encoding.

    # rd = 10 + t0 (a0=x10, a1=x11, ..., a7=x17)
    addi t1, t0, 10          # t1 = register number
    slli t1, t1, 7           # shift to rd field [11:7]
    li   t2, 0x00013003      # ld x0, 0(sp) base (rd=0, rs1=sp=x2, funct3=011, op=0000011)
    or   a0, t1, t2
    call emit_u32

    # addi sp, sp, 8
    li   a0, 0x00810113
    call emit_u32

    j    .pp_fc_pop

.pp_fc_call:
    # Now we need to emit a call to the function.
    # For a simple compiler, we assume functions are at known offsets
    # in the output buffer. For now, since we don't have a function
    # address table yet, we'll emit a placeholder approach:
    # We need a function relocation table. For simplicity in Stage 0,
    # we'll use a simple forward-reference scheme:
    # Store function addresses in a table (name -> output offset).
    # For now, emit auipc t1, 0 + jalr ra, t1, 0 as placeholders
    # that will need a fixup pass.
    #
    # SIMPLIFIED APPROACH for M4: emit an indirect call sequence.
    # Since all functions are in the same output buffer, we can compute
    # the offset at link time. For now, store the call site for fixup.
    #
    # Actually, the simplest approach: maintain a function address table.
    # At parse_funcdef, record (name, output_offset).
    # At call sites, look up the target and compute the relative offset.
    # But targets may not be defined yet (forward references).
    #
    # For now, emit a call hole (auipc+jalr with imm=0) and record it
    # for a fixup pass. This is complex. Since M0 only needs main()
    # which returns a constant and is called from _start, and M4 adds
    # function calls, let's just emit a placeholder and mark it TODO.
    # We'll emit: jal ra, 0 (placeholder) and record for fixup.

    # For simplicity, use the func reloc table approach:
    # Record (call_site_addr, func_name_ptr, func_name_len) in g_reloc_table
    # and do a fixup pass after parse_program.

    # emit jal ra, 0 (J-type: rd=ra=x1, imm=0)
    # opcode=1101111, rd=00001 → 0x000000EF
    la   t0, g_emit_ptr
    ld   s3, 0(t0)          # s3 = call site addr (callee-saved, already on stack)

    li   a0, 0x000000EF      # jal ra, 0
    call emit_u32

    # record relocation: (call_site, name_ptr, name_len)
    la   t0, g_reloc_count
    ld   t2, 0(t0)
    li   t3, 24
    mul  t3, t2, t3
    la   t4, g_reloc_table
    add  t4, t4, t3
    sd   s3, 0(t4)          # call_site_addr
    sd   s1, 8(t4)          # func_name_ptr
    sd   s2, 16(t4)         # func_name_len
    addi t2, t2, 1
    sd   t2, 0(t0)

    j    .pp_done

# ---- parenthesized expression ----
.pp_paren:
    li   a0, TK_LPAREN
    call consume
    call parse_expr
    li   a0, TK_RPAREN
    call expect

.pp_done:
    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret


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

# function address table: 64 entries × 24 bytes (name_ptr, name_len, output_addr)
g_func_count:       .quad 0
g_func_table:       .zero (64 * 24)

# call relocation table: 128 entries × 24 bytes (call_site_addr, name_ptr, name_len)
g_reloc_count:      .quad 0
g_reloc_table:      .zero (128 * 24)

# output code buffer: 512 KiB (enough for a Stage 1 compiler)
    .balign 4096
g_out_buf:          .zero (512 * 1024)
