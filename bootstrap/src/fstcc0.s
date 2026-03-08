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

# ---- assembly text templates written to output .s file ----
asm_preamble:
    .ascii "\t.text\n\t.globl _start\n_start:\n\tcall\tmain\n\tli\ta7, 93\n\tecall\n"
asm_preamble_len = . - asm_preamble

asm_globl:
    .ascii "\t.globl\t"
asm_globl_len = . - asm_globl

asm_colon_nl:
    .ascii ":\n"
asm_colon_nl_len = . - asm_colon_nl

# fixed prologue prefix (sd ra; sd s0; mv s0,sp; addi sp,sp,-)
asm_prologue_pfx:
    .ascii "\tsd\tra, -8(sp)\n\tsd\ts0, -16(sp)\n\tmv\ts0, sp\n\taddi\tsp, sp, -"
asm_prologue_pfx_len = . - asm_prologue_pfx

# epilogue lines (emitted at each return)
asm_epilogue:
    .ascii "\tmv\tsp, s0\n\tld\tra, -8(s0)\n\tld\ts0, -16(s0)\n\tret\n"
asm_epilogue_len = . - asm_epilogue

# li a0, N
asm_li_a0:
    .ascii "\tli\ta0, "
asm_li_a0_len = . - asm_li_a0

# push/pop for binary expression temporaries
asm_push_a0:
    .ascii "\taddi\tsp, sp, -8\n\tsd\ta0, 0(sp)\n"
asm_push_a0_len = . - asm_push_a0

asm_pop_a1:
    .ascii "\tld\ta1, 0(sp)\n\taddi\tsp, sp, 8\n"
asm_pop_a1_len = . - asm_pop_a1

# ld/sd with variable s0-relative offset
asm_ld_a0_pfx:
    .ascii "\tld\ta0, "
asm_ld_a0_pfx_len = . - asm_ld_a0_pfx

asm_sd_a0_pfx:
    .ascii "\tsd\ta0, "
asm_sd_a0_pfx_len = . - asm_sd_a0_pfx

asm_s0_sfx:
    .ascii "(s0)\n"
asm_s0_sfx_len = . - asm_s0_sfx

# branch/jump labels
asm_beqz_a0_pfx:
    .ascii "\tbeqz\ta0, .L"
asm_beqz_a0_pfx_len = . - asm_beqz_a0_pfx

asm_j_pfx:
    .ascii "\tj\t.L"
asm_j_pfx_len = . - asm_j_pfx

asm_label_pfx:
    .ascii ".L"
asm_label_pfx_len = . - asm_label_pfx

# newline
asm_nl:
    .ascii "\n"

# call instruction prefix
asm_call_pfx:
    .ascii "\tcall\t"
asm_call_pfx_len = . - asm_call_pfx

# binary ops (a1=left, a0=right → result in a0)
asm_add:
    .ascii "\tadd\ta0, a1, a0\n"
asm_add_len = . - asm_add

asm_sub_a1_a0:
    .ascii "\tsub\ta0, a1, a0\n"
asm_sub_a1_a0_len = . - asm_sub_a1_a0

asm_mul:
    .ascii "\tmul\ta0, a1, a0\n"
asm_mul_len = . - asm_mul

asm_div:
    .ascii "\tdiv\ta0, a1, a0\n"
asm_div_len = . - asm_div

asm_rem:
    .ascii "\trem\ta0, a1, a0\n"
asm_rem_len = . - asm_rem

asm_slt_a1_a0:
    .ascii "\tslt\ta0, a1, a0\n"     # a1 < a0
asm_slt_a1_a0_len = . - asm_slt_a1_a0

asm_slt_a0_a1:
    .ascii "\tslt\ta0, a0, a1\n"     # a0 < a1  (→ a1 > a0)
asm_slt_a0_a1_len = . - asm_slt_a0_a1

asm_xori1:
    .ascii "\txori\ta0, a0, 1\n"
asm_xori1_len = . - asm_xori1

asm_snez_a0:
    .ascii "\tsltu\ta0, x0, a0\n"
asm_snez_a0_len = . - asm_snez_a0

asm_snez_a1:
    .ascii "\tsltu\ta1, x0, a1\n"
asm_snez_a1_len = . - asm_snez_a1

asm_seqz_a0:
    .ascii "\tsltiu\ta0, a0, 1\n"
asm_seqz_a0_len = . - asm_seqz_a0

asm_or_a0_a1:
    .ascii "\tor\ta0, a0, a1\n"
asm_or_a0_a1_len = . - asm_or_a0_a1

asm_and_a0_a1:
    .ascii "\tand\ta0, a0, a1\n"
asm_and_a0_a1_len = . - asm_and_a0_a1

asm_neg_a0:
    .ascii "\tsub\ta0, x0, a0\n"
asm_neg_a0_len = . - asm_neg_a0

asm_sub_a0_a1_a0:
    .ascii "\tsub\ta0, a1, a0\n"     # a0 = a1 - a0  (for == and !=)
asm_sub_a0_a1_a0_len = . - asm_sub_a0_a1_a0

# sd aX, off(s0) prefix parts
asm_sd_a_pfx:
    .ascii "\tsd\ta"
asm_sd_a_pfx_len = . - asm_sd_a_pfx

asm_comma_sp:
    .ascii ", "
asm_comma_sp_len = . - asm_comma_sp

# ld aX, 0(sp) + addi sp, sp, 8  (arg pop from stack)
asm_ld_a_pfx:
    .ascii "\tld\ta"
asm_ld_a_pfx_len = . - asm_ld_a_pfx

asm_0sp_pop:
    .ascii ", 0(sp)\n\taddi\tsp, sp, 8\n"
asm_0sp_pop_len = . - asm_0sp_pop

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
.section .text
_start:
    # Linux entry stack (riscv64):
    # 0(sp)=argc, 8(sp)=argv[0], 16(sp)=argv[1], 24(sp)=argv[2], ...

#---------------------- file open (input) ----------------------
    ld      t0, 0(sp)                 # t0 = argc
    li      t1, 3
    bne     t0, t1, .arg_error        # expect: prog + 2 args => argc == 3

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
    # -------- init emit buffer (g_out_buf is now a per-function text buffer) --------
    la      t0, g_emit_ptr
    la      t1, g_out_buf
    sd      t1, 0(t0)

    # -------- write assembly preamble to output file --------
    # The preamble defines _start which calls main and exits.
    la      a0, asm_preamble
    li      a1, asm_preamble_len
    call    write_fd

    # -------- parse all function definitions --------
    call    parse_program

    # -------- close output fd ----
    la      t0, g_out_fd
    ld      a0, 0(t0)
    li      a7, 57                  # SYS_close
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
# LOAD_U16_LE dst, base_reg, scratch_reg
.macro LOAD_U16_LE dst, base, scratch
    lbu  \dst,     0(\base)
    lbu  \scratch, 1(\base)
    slli \scratch, \scratch, 8
    or   \dst, \dst, \scratch
.endm

# LOAD_U32_LE dst, base_reg, scratch_reg
.macro LOAD_U32_LE dst, base, scratch
    lbu  \dst,     0(\base)
    lbu  \scratch, 1(\base)
    slli \scratch, \scratch, 8
    or   \dst, \dst, \scratch
    lbu  \scratch, 2(\base)
    slli \scratch, \scratch, 16
    or   \dst, \dst, \scratch
    lbu  \scratch, 3(\base)
    slli \scratch, \scratch, 24
    or   \dst, \dst, \scratch
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
    la  a2, g_end
    ld  a2, 0(a2)       # a2 = end  (t7 doesn't exist in RV64; a2 is free here)
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
    bgeu t0, a2, .emit_eof

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
    bgeu t3, a2, .ws_done
    lbu t4, 0(t3)
    li  t2, '/'
    bne t4, t2, .ws_done

    # consume until '\n' or end
    addi t0, t0, 2
.comment_loop:
    bgeu t0, a2, .skip_ws
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
    bgeu t0, a2, .num_done
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
    bgeu t0, a2, .ident_done
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
    LOAD_U16_LE t2, t4, t3       # "if" little-endian = 0x6669
    li  t3, 0x6669
    bne t2, t3, .emit_identlike
    li  t1, TK_IF
    j .emit_identlike

.kw_len3:
    # if (len==3 && "int")
    li  t2, 3
    bne t5, t2, .kw_len4
    LOAD_U16_LE t2, t4, t3       # "in" = 0x6e69
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
    LOAD_U32_LE t2, t4, t3       # "else" = 0x65736c65
    li  t3, 0x65736c65
    bne t2, t3, .emit_identlike
    li  t1, TK_ELSE
    j .emit_identlike

.kw_len5:
    # if (len==5 && "while")
    li  t2, 5
    bne t5, t2, .kw_len6
    LOAD_U32_LE t2, t4, t3       # "whil" = 0x6c696877
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
    LOAD_U32_LE t2, t4, t3       # "retu" = 0x75746572
    li  t3, 0x75746572
    bne t2, t3, .emit_identlike
    addi a3, t4, 4
    LOAD_U16_LE t2, a3, t3      # "rn" = 0x6e72
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
    bgeu t0, a2, .emit_eof
    lbu t1, 0(t0)               # c0

    # c1 if exists
    addi t3, t0, 1
    li  t2, 0
    bgeu t3, a2, .no_c1
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
# Emitter — Text Mode
# emit_* append assembly text to g_out_buf (per-function body buffer).
# write_fd writes directly to out_fd (preamble / function headers).
# flush_func writes complete function (label+prologue+body) to out_fd.
#==============================================================================

#-------------------------------- write_fd --------------------------------
# a0 = buf ptr, a1 = byte count  →  writes to g_out_fd.
.globl write_fd
write_fd:
    mv   a2, a1
    mv   a1, a0
    la   t0, g_out_fd
    ld   a0, 0(t0)
    li   a7, 64              # SYS_write
    ecall
    ret

#-------------------------------- emit_text --------------------------------
# a0 = ptr, a1 = len  →  appends to g_out_buf. Leaf.
.globl emit_text
emit_text:
    beqz a1, .et_done
    la   t0, g_emit_ptr
    ld   t1, 0(t0)
.et_loop:
    lbu  t2, 0(a0)
    sb   t2, 0(t1)
    addi a0, a0, 1
    addi t1, t1, 1
    addi a1, a1, -1
    bnez a1, .et_loop
    la   t0, g_emit_ptr
    sd   t1, 0(t0)
.et_done:
    ret

#-------------------------------- int_to_str --------------------------------
# a0 = signed integer, a1 = output buffer (>=22 bytes)
# Returns: a0 = start ptr, a1 = length.  Leaf.
.globl int_to_str
int_to_str:
    addi t0, a1, 21
    mv   t4, t0              # t4 = end ptr (saved for length calc)
    mv   t1, a0
    bgez t1, .its_pos
    neg  t1, t1
.its_pos:
    li   t2, 10
.its_loop:
    addi t0, t0, -1
    remu t3, t1, t2
    divu t1, t1, t2
    addi t3, t3, '0'
    sb   t3, 0(t0)
    bnez t1, .its_loop
    bgez a0, .its_sign_done
    addi t0, t0, -1
    li   t3, '-'
    sb   t3, 0(t0)
.its_sign_done:
    mv   a0, t0
    sub  a1, t4, t0
    ret

#-------------------------------- emit_int --------------------------------
# a0 = signed integer  →  appends decimal text to g_out_buf.
.globl emit_int
emit_int:
    addi sp, sp, -64
    sd   ra, 56(sp)
    addi a1, sp, 0
    call int_to_str
    call emit_text
    ld   ra, 56(sp)
    addi sp, sp, 64
    ret

#-------------------------------- write_int_fd --------------------------------
# a0 = signed integer  →  writes decimal text directly to out_fd.
.globl write_int_fd
write_int_fd:
    addi sp, sp, -64
    sd   ra, 56(sp)
    addi a1, sp, 0
    call int_to_str
    call write_fd
    ld   ra, 56(sp)
    addi sp, sp, 64
    ret

#-------------------------------- emit_li_a0 --------------------------------
# a0 = immediate  →  emits "\tli\ta0, N\n" to g_out_buf.
.globl emit_li_a0
emit_li_a0:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_li_a0
    li   a1, asm_li_a0_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_nl
    li   a1, 1
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_epilogue --------------------------------
# Emits epilogue (mv sp,s0 / ld ra / ld s0 / ret) to g_out_buf.
.globl emit_epilogue
emit_epilogue:
    addi sp, sp, -16
    sd   ra, 8(sp)
    la   a0, asm_epilogue
    li   a1, asm_epilogue_len
    call emit_text
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_push_a0 --------------------------------
.globl emit_push_a0
emit_push_a0:
    addi sp, sp, -16
    sd   ra, 8(sp)
    la   a0, asm_push_a0
    li   a1, asm_push_a0_len
    call emit_text
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_pop_a1 --------------------------------
.globl emit_pop_a1
emit_pop_a1:
    addi sp, sp, -16
    sd   ra, 8(sp)
    la   a0, asm_pop_a1
    li   a1, asm_pop_a1_len
    call emit_text
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_ld_a0_off_s0 --------------------------------
# a0 = signed offset  →  emits "\tld\ta0, N(s0)\n"
.globl emit_ld_a0_off_s0
emit_ld_a0_off_s0:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_ld_a0_pfx
    li   a1, asm_ld_a0_pfx_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_s0_sfx
    li   a1, asm_s0_sfx_len
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_sd_a0_off_s0 --------------------------------
# a0 = signed offset  →  emits "\tsd\ta0, N(s0)\n"
.globl emit_sd_a0_off_s0
emit_sd_a0_off_s0:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_sd_a0_pfx
    li   a1, asm_sd_a0_pfx_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_s0_sfx
    li   a1, asm_s0_sfx_len
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_sd_aX_off_s0 --------------------------------
# a0 = param index 0-7, a1 = signed offset  →  emits "\tsd\taX, N(s0)\n"
.globl emit_sd_aX_off_s0
emit_sd_aX_off_s0:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)
    sd   s2,  8(sp)
    mv   s1, a0
    mv   s2, a1
    la   a0, asm_sd_a_pfx
    li   a1, asm_sd_a_pfx_len
    call emit_text
    addi t0, s1, '0'        # single digit
    sb   t0, 0(sp)
    mv   a0, sp
    li   a1, 1
    call emit_text
    la   a0, asm_comma_sp
    li   a1, asm_comma_sp_len
    call emit_text
    mv   a0, s2
    call emit_int
    la   a0, asm_s0_sfx
    li   a1, asm_s0_sfx_len
    call emit_text
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

#-------------------------------- emit_label_def --------------------------------
# a0 = label number N  →  emits ".LN:\n"
.globl emit_label_def
emit_label_def:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_label_pfx
    li   a1, asm_label_pfx_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_colon_nl
    li   a1, asm_colon_nl_len
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_beqz_label --------------------------------
# a0 = label number N  →  emits "\tbeqz\ta0, .LN\n"
.globl emit_beqz_label
emit_beqz_label:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_beqz_a0_pfx
    li   a1, asm_beqz_a0_pfx_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_nl
    li   a1, 1
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- emit_j_label --------------------------------
# a0 = label number N  →  emits "\tj\t.LN\n"
.globl emit_j_label
emit_j_label:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s1, 0(sp)
    mv   s1, a0
    la   a0, asm_j_pfx
    li   a1, asm_j_pfx_len
    call emit_text
    mv   a0, s1
    call emit_int
    la   a0, asm_nl
    li   a1, 1
    call emit_text
    ld   s1, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- alloc_label --------------------------------
# Returns: a0 = unique label number, increments g_label_cnt.
.globl alloc_label
alloc_label:
    la   t0, g_label_cnt
    ld   a0, 0(t0)
    addi t1, a0, 1
    sd   t1, 0(t0)
    ret

#-------------------------------- flush_func --------------------------------
# a0 = name_ptr, a1 = name_len
# Writes .globl NAME, NAME:, prologue, body to out_fd; resets emit ptr.
.globl flush_func
flush_func:
    addi sp, sp, -48
    sd   ra, 40(sp)
    sd   s1, 32(sp)
    sd   s2, 24(sp)
    mv   s1, a0
    mv   s2, a1
    la   a0, asm_globl
    li   a1, asm_globl_len
    call write_fd
    mv   a0, s1
    mv   a1, s2
    call write_fd
    la   a0, asm_nl
    li   a1, 1
    call write_fd
    mv   a0, s1
    mv   a1, s2
    call write_fd
    la   a0, asm_colon_nl
    li   a1, asm_colon_nl_len
    call write_fd
    la   a0, asm_prologue_pfx
    li   a1, asm_prologue_pfx_len
    call write_fd
    la   t0, g_frame_size
    ld   a0, 0(t0)
    call write_int_fd
    la   a0, asm_nl
    li   a1, 1
    call write_fd
    la   a0, g_out_buf
    la   t0, g_emit_ptr
    ld   t1, 0(t0)
    sub  a1, t1, a0
    call write_fd
    la   t0, g_emit_ptr
    la   t1, g_out_buf
    sd   t1, 0(t0)
    ld   s2, 24(sp)
    ld   s1, 32(sp)
    ld   ra, 40(sp)
    addi sp, sp, 48
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
    beq  a0, t0, .pgm_done
    call parse_funcdef
    j    .pp_loop

.pgm_done:
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

#-------------------------------- parse_funcdef --------------------------------
# Parses: int ident ( params ) block
# Body text is buffered in g_out_buf, then flush_func writes
# the complete function (label + prologue + body) to out_fd.
#   s1 = func name ptr (into mmap)
#   s2 = func name len
.globl parse_funcdef
parse_funcdef:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s1, 16(sp)
    sd   s2,  8(sp)
    sd   s3,  0(sp)

    li   a0, TK_INT
    call expect

    call peek
    la   t0, g_tok
    ld   s1, 16(t0)         # s1 = func_name_ptr
    ld   s2, 24(t0)         # s2 = func_name_len
    li   a0, TK_IDENT
    call expect

    li   a0, TK_LPAREN
    call expect

    # reset per-function state
    la   t0, g_frame_size
    li   t1, 16
    sd   t1, 0(t0)

    la   t0, g_sym_count
    sd   x0, 0(t0)

    # reset body buffer
    la   t0, g_emit_ptr
    la   t1, g_out_buf
    sd   t1, 0(t0)

    # parse params → body buffer gets param stores
    call parse_params

    li   a0, TK_RPAREN
    call expect

    # parse body → body buffer gets all statements
    call parse_block

    # align frame_size to 16
    la   t0, g_frame_size
    ld   t1, 0(t0)
    addi t1, t1, 15
    andi t1, t1, -16
    sd   t1, 0(t0)

    # flush: write label+prologue+body to out_fd
    mv   a0, s1
    mv   a1, s2
    call flush_func

    ld   s3,  0(sp)
    ld   s2,  8(sp)
    ld   s1, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

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

    # alloc label N for else/endif target
    call alloc_label
    mv   s1, a0              # s1 = N (else/endif label)

    # emit: beqz a0, .LN
    call emit_beqz_label

    call parse_stmt          # then-branch

    # check for 'else'
    call peek
    li   t0, TK_ELSE
    bne  a0, t0, .ps_if_no_else

    # has else: alloc end label M, emit j .LM, emit .LN:, parse else, emit .LM:
    li   a0, TK_ELSE
    call consume

    call alloc_label
    mv   s2, a0              # s2 = M (end label)

    # emit: j .LM
    mv   a0, s2
    call emit_j_label

    # emit: .LN:  (start of else body)
    mv   a0, s1
    call emit_label_def

    call parse_stmt          # else-branch

    # emit: .LM:  (end of if/else)
    mv   a0, s2
    call emit_label_def
    j    .ps_done

.ps_if_no_else:
    # emit: .LN:  (end of if, no else)
    mv   a0, s1
    call emit_label_def
    j    .ps_done

# ---- while ( expr ) stmt ----
.ps_while:
    li   a0, TK_WHILE
    call consume

    # alloc loop-top label N and exit label M
    call alloc_label
    mv   s1, a0              # s1 = N (loop top)
    call alloc_label
    mv   s2, a0              # s2 = M (loop exit)

    # emit: .LN:  (loop top)
    mv   a0, s1
    call emit_label_def

    li   a0, TK_LPAREN
    call expect
    call parse_expr
    li   a0, TK_RPAREN
    call expect

    # emit: beqz a0, .LM  (exit if cond false)
    mv   a0, s2
    call emit_beqz_label

    call parse_stmt

    # emit: j .LN  (back to loop top)
    mv   a0, s1
    call emit_j_label

    # emit: .LM:  (loop exit)
    mv   a0, s2
    call emit_label_def
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

    la   a0, asm_snez_a1
    li   a1, asm_snez_a1_len
    call emit_text
    la   a0, asm_snez_a0
    li   a1, asm_snez_a0_len
    call emit_text
    la   a0, asm_or_a0_a1
    li   a1, asm_or_a0_a1_len
    call emit_text

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

    la   a0, asm_snez_a1
    li   a1, asm_snez_a1_len
    call emit_text
    la   a0, asm_snez_a0
    li   a1, asm_snez_a0_len
    call emit_text
    la   a0, asm_and_a0_a1
    li   a1, asm_and_a0_a1_len
    call emit_text

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

    la   a0, asm_sub_a0_a1_a0
    li   a1, asm_sub_a0_a1_a0_len
    call emit_text

    li   t0, 1
    beq  s1, t0, .peq_emit_seqz
    # neq: snez a0, a0
    la   a0, asm_snez_a0
    li   a1, asm_snez_a0_len
    call emit_text
    j    .peq_loop

.peq_emit_seqz:
    # eq: seqz a0, a0
    la   a0, asm_seqz_a0
    li   a1, asm_seqz_a0_len
    call emit_text
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
    la   a0, asm_slt_a1_a0
    li   a1, asm_slt_a1_a0_len
    call emit_text
    j    .prel_loop

.prel_emit_gt:
    # slt a0, a0, a1  (left > right)
    la   a0, asm_slt_a0_a1
    li   a1, asm_slt_a0_a1_len
    call emit_text
    j    .prel_loop

.prel_emit_le:
    # !(left > right): slt a0, a0, a1 + xori a0, a0, 1
    la   a0, asm_slt_a0_a1
    li   a1, asm_slt_a0_a1_len
    call emit_text
    la   a0, asm_xori1
    li   a1, asm_xori1_len
    call emit_text
    j    .prel_loop

.prel_emit_ge:
    # !(left < right): slt a0, a1, a0 + xori a0, a0, 1
    la   a0, asm_slt_a1_a0
    li   a1, asm_slt_a1_a0_len
    call emit_text
    la   a0, asm_xori1
    li   a1, asm_xori1_len
    call emit_text
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
    la   a0, asm_sub_a1_a0
    li   a1, asm_sub_a1_a0_len
    call emit_text
    j    .pas_loop

.pas_emit_add:
    la   a0, asm_add
    li   a1, asm_add_len
    call emit_text
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
    la   a0, asm_rem
    li   a1, asm_rem_len
    call emit_text
    j    .pmd_loop

.pmd_emit_mul:
    la   a0, asm_mul
    li   a1, asm_mul_len
    call emit_text
    j    .pmd_loop

.pmd_emit_div:
    la   a0, asm_div
    li   a1, asm_div_len
    call emit_text
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
    la   a0, asm_neg_a0
    li   a1, asm_neg_a0_len
    call emit_text
    j    .pu_done

.pu_not:
    call parse_unary
    la   a0, asm_seqz_a0
    li   a1, asm_seqz_a0_len
    call emit_text

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

    # pop args into a0-a7 in reverse order (last pushed = highest-numbered reg)
    # s3 = arg count; emit "\tld\taX, 0(sp)\n\taddi\tsp, sp, 8\n" for X = s3-1..0
.pp_fc_pop:
    beqz s3, .pp_fc_call
    addi s3, s3, -1

    # emit: \tld\taX, 0(sp)\n\taddi\tsp, sp, 8\n  where X = s3
    la   a0, asm_ld_a_pfx
    li   a1, asm_ld_a_pfx_len
    call emit_text

    # emit single digit for register number (s3 is 0-7)
    addi sp, sp, -8
    addi t0, s3, '0'
    sb   t0, 0(sp)
    mv   a0, sp
    li   a1, 1
    call emit_text
    addi sp, sp, 8

    la   a0, asm_0sp_pop
    li   a1, asm_0sp_pop_len
    call emit_text

    j    .pp_fc_pop

.pp_fc_call:
    # emit: \tcall\tNAME\n
    la   a0, asm_call_pfx
    li   a1, asm_call_pfx_len
    call emit_text
    mv   a0, s1              # name_ptr
    mv   a1, s2              # name_len
    call emit_text
    la   a0, asm_nl
    li   a1, 1
    call emit_text

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

# unique label counter for if/while text-mode labels
g_label_cnt:        .quad 0

# output code buffer: 512 KiB (enough for a Stage 1 compiler)
    .balign 4096
g_out_buf:          .zero (512 * 1024)
