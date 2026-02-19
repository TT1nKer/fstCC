# fstcc0.s - fstCC Stage 0 Bootstrap Compiler (RISC-V, Linux riscv64)

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

#----------------------token list----------------------
    #------------------------------------I_keyword-------------------------------
.equ    TK_INT, 1
.equ    TK_RETURN, 2
.equ    TK_IF, 3
.equ    TK_ELSE, 4
.equ    TK_WHILE, 5
#keywords must be lowercase to distinguish from identifiers
    #------------------------------------II_identifier----------------------------
#regex for identifiers: [a-zA-Z_][a-zA-Z0-9_]*
.equ    TK_IDENT, 6
    #------------------------------------III_integer literals----------------------
#regex for integer literals: [0-9]+
.equ    TK_NUM, 7
    #------------------------------------IV_operators-----------------------------
.equ    TK_ASSIGN, 8   # =

.equ    TK_PLUS, 9     # +
.equ    TK_MINUS, 10   # -
.equ    TK_MUL, 11     # *
.equ    TK_DIV, 12     # /
.equ    TK_MOD, 13     # %

.equ    TK_EQ, 14      # ==
.equ    TK_NEQ, 15     # !=
.equ    TK_LT, 16      # <
.equ    TK_GT, 17      # >
.equ    TK_LE, 18      # <=
.equ    TK_GE, 19      # >=

.equ    TK_AND, 20     # &&
.equ    TK_OR, 21      # ||
.equ    TK_NOT, 22     # !
    #------------------------------------V_delimiters-----------------------------
.equ    TK_LPAREN, 23  # (
.equ    TK_RPAREN, 24  # )
.equ    TK_LBRACE, 25  # {
.equ    TK_RBRACE, 26  # }
.equ    TK_COMMA, 27   # ,
.equ    TK_SEMI, 28    # ;
    #------------------------------------VI_EOF-----------------------------------
.equ    TK_EOF, 0
# use 0 here so that uninitialized tokens default to EOF which is safe

# priority levels(L-H):
#1.=
#2.||
#3.&&
#4.== !=
#5.< > <= >=
#6.+ -
#7.* / %
#8unary: ! - (note: unary minus has higher precedence than binary minus)

#longer

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

#====================== macros ======================
# exit (Linux)
.macro EXIT code
    li a0, \code       # exit code
    li a7, 93          # SYS_exit
    ecall
.endm

.macro DIE msg
    # write(fd=2, buf=msg, len=msg_len)
    # syscall: write = 64
    li a0, 2                  # fd = stderr
    la a1, \msg               # buffer pointer
    li a2, \msg\()_len        # length
    li a7, 64                 # SYS_write
    ecall
    EXIT 1
.endm

#====================== entry ======================
_start:

#---------------------- file open (input) ----------------------
    # Linux entry stack (riscv64):
    # 0(sp)=argc, 8(sp)=argv[0], 16(sp)=argv[1], 24(sp)=argv[2], ...
    ld      t0, 0(sp)                 # t0 = argc
    bne     t0, 3, .arg_error         # expect: prog + 2 args => argc == 3

    ld      a1, 16(sp)                # a1 = input filename pointer (argv[1])

    # openat(AT_FDCWD, pathname, O_RDONLY, 0)
    li      a0, AT_FDCWD              # dirfd
    li      a2, O_RDONLY              # flags
    li      a3, 0                     # mode (unused for O_RDONLY)
    li      a7, 56                    # SYS_openat
    ecall

    # if (ret < 0) DIE
    bltz    a0, .open_in_error

    mv      s0, a0                    # s0 = in_fd   (TODO(TOUNDERSTAND): choose a register convention)

    # persist for later stages (optional)
    la      t1, g_in_fd
    sd      s0, 0(t1)

#---------------------- input size (lseek) ----------------------
    # TODO(TOUNDERSTAND): using lseek avoids struct stat layout; confirm it works for your input sources
    # size = lseek(in_fd, 0, SEEK_END)
    mv      a0, s0                    # fd
    li      a1, 0                     # offset
    li      a2, SEEK_END              # whence
    li      a7, 62                    # SYS_lseek
    ecall
    bltz    a0, .seek_end_error

    mv      s2, a0                    # s2 = in_size (bytes)
    la      t1, g_in_size
    sd      s2, 0(t1)

    # rewind: lseek(in_fd, 0, SEEK_SET)
    mv      a0, s0
    li      a1, 0
    li      a2, SEEK_SET
    li      a7, 62                    # SYS_lseek
    ecall
    bltz    a0, .seek_set_error

#---------------------- mmap input ----------------------
    # mmap(NULL, in_size, PROT_READ, MAP_PRIVATE, in_fd, 0)
    li      a0, 0                     # addr = NULL
    mv      a1, s2                    # length
    li      a2, PROT_READ             # prot
    li      a3, MAP_PRIVATE           # flags
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
    li      a0, AT_FDCWD              # dirfd
    li      a2, (O_WRONLY | O_CREAT | O_TRUNC)
    li      a3, 0644                  # mode rw-r--r--
    li      a7, 56                    # SYS_openat
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

#---------------------- lexer -----------------------
    # TODO: implement lexer using (s3, s2)
    
#input a0 = cursor (char*)
#input a1 = tok_ptr
next_token:

#---------------------- parser ----------------------
    # TODO: implement parser

#---------------------- codegen ---------------------
    # TODO: emit bytes to output fd (s1) via SYS_write (64)
    # TODO(TOUNDERSTAND): buffering strategy vs direct writes

#---------------------- exit ------------------------
    EXIT 0

#====================== errors ======================
.arg_error:
    DIE arg_error_msg

.open_in_error:
    DIE open_in_error_msg

.seek_end_error:
    DIE seek_end_error_msg

.seek_set_error:    
    DIE seek_set_error_msg

.mmap_error:
    DIE mmap_error_msg

.open_out_error:
    DIE open_out_error_msg


#====================== globals ======================
.section .bss
    .balign 8
g_in_fd:    .quad 0
g_out_fd:   .quad 0
g_in_size:  .quad 0
g_in_ptr:   .quad 0

.section .data
    # TODO: any mutable tables/buffers you want initialized at load time
