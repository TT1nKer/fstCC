# fstCC Stage 0.3 — Bootstrap compiler with local variables
# Targets: Linux RV64 (LP64 ABI)
#
# COMPLETED:
#   int main() { return NUMBER; }
#   int main() { return NUMBER + NUMBER; }
#   int main() { return NUMBER - NUMBER; }
#   int main() { return NUMBER * NUMBER; }
#   int main() { return NUMBER / NUMBER; }
#
# NEW (YOUR TASK):
#   int main() { int x; x = 5; return x; }
#   int main() { int x; int y; x = 10; y = 32; return x + y; }
#
# Test with:
#   make
#   echo 'int main() { int x; x = 42; return x; }' > test/var.c
#   make test FILE=test/var.c

.equ SYS_EXIT,   93
.equ SYS_READ,   63
.equ SYS_WRITE,  64
.equ SYS_OPENAT, 56
.equ SYS_CLOSE,  57
.equ AT_FDCWD,   -100
.equ O_RDONLY,    0
.equ O_WRONLY_CREAT_TRUNC, 0x241
.equ STDOUT,     1
.equ STDERR,     2
.equ BUF_SIZE,   8192
.equ MAX_VARS,   16

# Token types
.equ TOK_EOF,      0
.equ TOK_INT,      1
.equ TOK_RETURN,   2
.equ TOK_IF,       3
.equ TOK_ELSE,     4
.equ TOK_WHILE,    5
.equ TOK_IDENT,    6
.equ TOK_NUM,      7
.equ TOK_LPAREN,   8
.equ TOK_RPAREN,   9
.equ TOK_LBRACE,  10
.equ TOK_RBRACE,  11
.equ TOK_SEMI,    12
.equ TOK_COMMA,   13
.equ TOK_ASSIGN,  14
.equ TOK_PLUS,    15
.equ TOK_MINUS,   16
.equ TOK_STAR,    17
.equ TOK_SLASH,   18
.equ TOK_PERCENT, 19
.equ TOK_LT,      20
.equ TOK_GT,      21
.equ TOK_LE,      22
.equ TOK_GE,      23
.equ TOK_EQ,      24
.equ TOK_NE,      25
.equ TOK_AND,     26
.equ TOK_OR,      27
.equ TOK_NOT,     28
.equ TOK_AMP,     29
.equ TOK_ERROR,   255

# ============================================================
.section .bss
# ============================================================
input_buf:   .skip BUF_SIZE
output_buf:  .skip BUF_SIZE
out_pos:     .skip 8
input_pos:   .skip 8
input_len:   .skip 8
tok_type:    .skip 8
tok_start:   .skip 8
tok_len:     .skip 8
tok_val:     .skip 8

# Symbol table for local variables
# Each entry: 16 bytes (8 for name pointer, 8 for stack offset)
var_names:   .skip 8 * MAX_VARS      # pointers to variable names in input_buf
var_offsets: .skip 8 * MAX_VARS      # stack offsets (-8, -16, -24, ...)
var_count:   .skip 8                 # number of variables declared
stack_size:  .skip 8                 # total stack space needed

# ============================================================
.section .rodata
# ============================================================
err_usage:   .asciz "Usage: fstcc0 <input.c> <output.s>\n"
err_open:    .asciz "Error: cannot open input file\n"
err_create:  .asciz "Error: cannot create output file\n"
err_syntax:  .asciz "Error: syntax error\n"
err_undecl:  .asciz "Error: undeclared variable\n"

kw_int:      .asciz "int"
kw_return:   .asciz "return"
kw_if:       .asciz "if"
kw_else:     .asciz "else"
kw_while:    .asciz "while"

# Assembly templates
asm_header:  .asciz ".globl _start\n_start:\n"
asm_li_a0:   .asciz "    li a0, "
asm_li_a1:   .asciz "    li a1, "
asm_li_a7:   .asciz "    li a7, 93\n"
asm_ecall:   .asciz "    ecall\n"
asm_newline: .asciz "\n"
asm_add:     .asciz "    add a0, a0, a1\n"
asm_sub:     .asciz "    sub a0, a0, a1\n"
asm_mul:     .asciz "    mul a0, a0, a1\n"
asm_div:     .asciz "    div a0, a0, a1\n"

# Stack frame templates
asm_push_ra: .asciz "    addi sp, sp, -8\n    sd ra, 0(sp)\n"
asm_pop_ra:  .asciz "    ld ra, 0(sp)\n    addi sp, sp, 8\n"
asm_sd_a0:   .asciz "    sd a0, "
asm_ld_a0:   .asciz "    ld a0, "
asm_ld_a1:   .asciz "    ld a1, "
asm_sp:      .asciz "(sp)\n"


# ============================================================
.section .text
# ============================================================
.globl _start

_start:
    ld      a0, 0(sp)
    li      t0, 3
    bne     a0, t0, .usage_error

    ld      s1, 16(sp)
    ld      s2, 24(sp)

    li      a0, AT_FDCWD
    mv      a1, s1
    li      a2, O_RDONLY
    li      a3, 0
    li      a7, SYS_OPENAT
    ecall
    bltz    a0, .open_error
    mv      s3, a0

    mv      a0, s3
    la      a1, input_buf
    li      a2, BUF_SIZE
    li      a7, SYS_READ
    ecall
    bltz    a0, .open_error
    la      t0, input_len
    sd      a0, 0(t0)

    mv      a0, s3
    li      a7, SYS_CLOSE
    ecall

    li      a0, AT_FDCWD
    mv      a1, s2
    li      a2, O_WRONLY_CREAT_TRUNC
    li      a3, 420
    li      a7, SYS_OPENAT
    ecall
    bltz    a0, .create_error
    mv      s5, a0

    la      t0, input_pos
    sd      zero, 0(t0)
    la      t0, out_pos
    sd      zero, 0(t0)
    la      t0, var_count
    sd      zero, 0(t0)
    la      t0, stack_size
    sd      zero, 0(t0)

    jal     compile_program

    jal     flush_output
    mv      a0, s5
    li      a7, SYS_CLOSE
    ecall
    li      a0, 0
    li      a7, SYS_EXIT
    ecall

.usage_error:
    la      a1, err_usage
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall

.open_error:
    la      a1, err_open
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall

.create_error:
    la      a1, err_create
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall


# ############################################################
#                   PARSER / CODEGEN
# ############################################################

# ============================================================
# void expect(int expected_tok)
# ============================================================
expect:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    mv      s0, a0

    la      t0, tok_type
    ld      t0, 0(t0)
    bne     t0, s0, .expect_error

    jal     next_token

    ld      ra, 0(sp)
    ld      s0, 8(sp)
    addi    sp, sp, 16
    ret

.expect_error:
    la      a1, err_syntax
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall


# ============================================================
# void compile_expr(void)
#
# Parses: NUMBER | IDENT | (NUMBER|IDENT) OP (NUMBER|IDENT)
# Emits code that leaves result in a0
# ============================================================
compile_expr:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    la      t0, tok_type
    ld      t0, 0(t0)

    # Is it a number?
    li      t1, TOK_NUM
    beq     t0, t1, .expr_number

    # Is it an identifier (variable)?
    li      t1, TOK_IDENT
    beq     t0, t1, .expr_ident

    j       .expr_error

.expr_number:
    # Emit "    li a0, NUMBER\n"
    la      a0, asm_li_a0
    jal     emit_str
    la      t0, tok_val
    ld      a0, 0(t0)
    jal     emit_num
    la      a0, asm_newline
    jal     emit_str
    jal     next_token
    j       .expr_check_op

.expr_ident:
    #context of this subroutine: we have an identifier token, and we want to emit code to load its value into a0.
    #  Look up variable and emit load      
    # Steps:
    addi    sp, sp, -8
    sd      s0, 0(sp)

    jal     find_var
    li      t1, -1
    beq     a0, t1, .expr_undeclared

    la      a0, asm_ld_a0
    jal     emit_str 

    mv      a0, s0         
    jal     emit_num 

    la      a0, asm_sp
    jal     emit_str

    jal     next_token
                    #answer:
    #   1. Call find_var to get stack offset (returns offset in a0, or -1 if not found)
    #   2. If a0 == -1, jump to .expr_undeclared
    #   3. Emit "    ld a0, OFFSET(sp)\n"
    #      Hint: la a0, asm_ld_a0     # "    ld a0, "
    #            jal emit_str
    #            (emit the offset number)
    #            la a0, asm_sp         # "(sp)\n"
    #            jal emit_str
    #   4. Call next_token to advance
    #
    # Hint for calling find_var:
    #   - find_var uses tok_start and tok_len (already set by lexer)
    #   - just call: jal find_var
    #   - result is in a0

    ld      s0, 0(sp)
    addi    sp, sp, 8

    j       .expr_check_op



.expr_check_op:
    # Check what operator (if any)
    la      t0, tok_type
    ld      t0, 0(t0)

    li      t1, TOK_PLUS
    beq     t0, t1, .expr_add
    li      t1, TOK_MINUS
    beq     t0, t1, .expr_sub
    li      t1, TOK_STAR
    beq     t0, t1, .expr_mul
    li      t1, TOK_SLASH
    beq     t0, t1, .expr_div

    # No operator - done
    j       .expr_done

.expr_add:
    jal     next_token
    jal     .expr_second_operand
    la      a0, asm_add
    jal     emit_str
    jal     next_token
    j       .expr_done

.expr_sub:
    jal     next_token
    jal     .expr_second_operand
    la      a0, asm_sub
    jal     emit_str
    jal     next_token
    j       .expr_done

.expr_mul:
    jal     next_token
    jal     .expr_second_operand
    la      a0, asm_mul
    jal     emit_str
    jal     next_token
    j       .expr_done

.expr_div:
    jal     next_token
    jal     .expr_second_operand
    la      a0, asm_div
    jal     emit_str
    jal     next_token
    j       .expr_done

# Helper: emit second operand into a1
.expr_second_operand:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    la      t0, tok_type
    ld      t0, 0(t0)

    li      t1, TOK_NUM
    beq     t0, t1, .expr_second_num

    li      t1, TOK_IDENT
    beq     t0, t1, .expr_second_ident

    j       .expr_error

.expr_second_num:
    # Emit "    li a1, NUMBER\n"
    la      a0, asm_li_a1
    jal     emit_str
    la      t0, tok_val
    ld      a0, 0(t0)
    jal     emit_num
    la      a0, asm_newline
    jal     emit_str
    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.expr_second_ident:
    # TODO 2: Look up variable and emit load into a1
    #
    # Same as TODO 1, but use asm_ld_a1 instead of asm_ld_a0
    # Emit "    ld a1, OFFSET(sp)\n"
    addi    sp, sp, -16
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    
    jal     find_var
    li      t1, -1
    beq     a0, t1, .expr_undeclared

    mv      s0, a0 #     s0  a01

    la      a0, asm_ld_a1
    jal     emit_str 

    mv      a0, s0
    jal     emit_num

    la      a0, asm_sp
    jal     emit_str

    jal     next_token

    ld      ra, 0(sp)
    ld      s0, 8(sp)
    addi    sp, sp, 16
    ret

.expr_done:
    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.expr_error:
    la      a1, err_syntax
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall

.expr_undeclared:
    la      a1, err_undecl
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall


# ============================================================
# void compile_statement(void)
#
# Parses one statement:
#   - "int" IDENT ";"           → variable declaration
#   - IDENT "=" expr ";"        → assignment
#   - "return" expr ";"         → return statement
# ============================================================
compile_statement:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    la      t0, tok_type
    ld      t0, 0(t0)

    # "int" → variable declaration
    li      t1, TOK_INT
    beq     t0, t1, .stmt_decl

    # "return" → return statement
    li      t1, TOK_RETURN
    beq     t0, t1, .stmt_return

    # IDENT → assignment
    li      t1, TOK_IDENT
    beq     t0, t1, .stmt_assign

    j       .stmt_error

.stmt_decl:
    # TODO 3: Parse variable declaration: int IDENT ;
    #
    jal     next_token           # skip 'int' means
    la      t0, tok_type
    ld      t0, 0(t0)
    li      t1, TOK_IDENT
    bne     t0, t1, .stmt_error
    jal     add_var              # adds variable to symbol table 
    li      a0, TOK_SEMI
    jal     expect               # expect and skip ';'  
    

        # Steps:
    #   1. jal next_token           (advance past 'int')
    #   2. Check tok_type == TOK_IDENT, else error
    #   3. jal add_var              (adds variable to symbol table)
    #   4. li a0, TOK_SEMI
    #      jal expect               (expect and skip ';')


    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.stmt_assign:
    # TODO 4: Parse assignment: IDENT = expr ;
    jal     find_var             # look up variable, offset returned in a0
    li      t1, -1
    beq     a0, t1, .stmt_undeclared
    addi    sp, sp, -8
    sd      s0, 0(sp)          # save ramember that find_var returns offset in a0
    mv      s0, a0                  # save offset to s0

    #
    # Steps:
    #   1. jal find_var             (look up variable, offset returned in a0)
    #   2. If a0 == -1, jump to .stmt_undeclared
    #   3. Save offset to s0 (you'll need to adjust stack frame to save s0, which means the code: addi sp, sp, -8; sd s0, 0(sp) at the start, and ld s0, 0(sp); addi sp, sp, 8 before each ret)
    #   4. li a0, TOK_ASSIGN
    #      jal expect               (expect and skip '=')
    #   5. jal compile_expr         (compile the expression, result in a0)
    #   6. Emit "    sd a0, OFFSET(sp)\n"
    #      Hint: la a0, asm_sd_a0   # "    sd a0, "
    #            jal emit_str
    #            mv a0, s0          # the offset
    #            jal emit_num
    #            la a0, asm_sp      # "(sp)\n"
    #            jal emit_str
    #   7. li a0, TOK_SEMI
    #      jal expect               (expect and skip ';')


    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.stmt_return:
    jal     next_token              # skip 'return'
    jal     compile_expr            # compile expression

    li      a0, TOK_SEMI
    jal     expect

    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.stmt_error:
    la      a1, err_syntax
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall

.stmt_undeclared:
    la      a1, err_undecl
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall


# ============================================================
# void compile_program(void)
#
# Parses:  int main() { statement* return expr; }
# ============================================================
compile_program:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    jal     next_token

    li      a0, TOK_INT
    jal     expect

    li      a0, TOK_IDENT
    jal     expect

    li      a0, TOK_LPAREN
    jal     expect

    li      a0, TOK_RPAREN
    jal     expect

    li      a0, TOK_LBRACE
    jal     expect

    # ---- First pass: count variables ----
    # For now, we emit header after parsing all statements
    # This is simplified: we assume max 16 vars, allocate 128 bytes

    # Emit header
    la      a0, asm_header
    jal     emit_str

    # TODO 5: Emit stack frame setup
    #
    # We need to allocate space for local variables.
    # For simplicity, always allocate 128 bytes (16 variables * 8 bytes).
    #
    # Emit:
    #   addi sp, sp, -128
    #
    # You'll need to add this string to .rodata:
    #   asm_frame_setup: .asciz "    addi sp, sp, -128\n"
    #
    # Then: la a0, asm_frame_setup
    #       jal emit_str


    # ---- Compile statements until we see 'return' or '}' ----
.prog_loop:
    la      t0, tok_type
    ld      t0, 0(t0)

    # If '}', we're done (error: no return)
    li      t1, TOK_RBRACE
    beq     t0, t1, .prog_error_noreturn

    # Compile one statement
    jal     compile_statement

    # If it was a return, we're done
    # (compile_statement already compiled the return expression)
    # Check if next token is '}'
    la      t0, tok_type
    ld      t0, 0(t0)
    li      t1, TOK_RBRACE
    beq     t0, t1, .prog_epilogue

    j       .prog_loop

.prog_epilogue:
    # TODO 6: Emit stack frame cleanup and exit
    #
    # Emit:
    #   addi sp, sp, 128
    #   li a7, 93
    #   ecall
    #
    # You'll need: asm_frame_cleanup: .asciz "    addi sp, sp, 128\n"


    la      a0, asm_li_a7
    jal     emit_str
    la      a0, asm_ecall
    jal     emit_str

    li      a0, TOK_RBRACE
    jal     expect

    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

.prog_error_noreturn:
    la      a1, err_syntax
    jal     print_err
    li      a0, 1
    li      a7, SYS_EXIT
    ecall


# ============================================================
# void add_var(void)
#
# Adds current token (must be IDENT) to symbol table.
# Assigns next available stack offset.
#
# Uses tok_start and tok_len for the variable name.
# ============================================================
add_var:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    # TODO 7: Add variable to symbol table
    #
    # Steps:
    #   1. Load var_count into t0
    #   2. Calculate offset: offset = -(var_count + 1) * 8
    #      (First var at -8, second at -16, etc.)
    #   3. Store tok_start into var_names[var_count]
    #      Hint: la t1, var_names
    #            slli t2, t0, 3      # t2 = var_count * 8
    #            add t1, t1, t2
    #            la t3, tok_start
    #            ld t3, 0(t3)
    #            sd t3, 0(t1)
    #   4. Store offset into var_offsets[var_count]
    #   5. Increment var_count
    #   6. Call next_token to advance past the identifier


    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret


# ============================================================
# int find_var(void)
#
# Looks up current token (must be IDENT) in symbol table.
# Returns stack offset in a0, or -1 if not found.
#
# Uses tok_start and tok_len for the variable name.
# ============================================================
find_var:
    addi    sp, sp, -24
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)

    # TODO 8: Look up variable in symbol table
    #
    # Steps:
    #   1. Load var_count into s0 (loop counter)
    #   2. li s1, 0 (current index)
    #   3. Loop:
    #      a. If s1 >= s0, not found, return -1
    #      b. Load var_names[s1] into a0 (pointer to stored name)
    #      c. Load tok_start into a2 (pointer to current name)
    #      d. Compare lengths... actually, we need to store lengths too!
    #
    # SIMPLIFICATION: For now, just compare pointers.
    # Variables are identified by their position in input_buf.
    # This works because we use tok_start directly.
    #
    # Simpler approach:
    #   Loop through var_names[], compare each with tok_start.
    #   If match, return var_offsets[index].
    #   If no match, return -1.


    # Placeholder: return -1 (not found)
    li      a0, -1

    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    addi    sp, sp, 24
    ret


# ############################################################
#                         LEXER
# ############################################################

next_token:
    addi    sp, sp, -32
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)

    la      t0, input_pos
    ld      s0, 0(t0)
    la      t1, input_buf
    add     s0, t1, s0

    la      t0, input_len
    ld      t1, 0(t0)
    la      t2, input_buf
    add     s1, t2, t1

.nt_skip:
    bgeu    s0, s1, .nt_eof
    lbu     t0, 0(s0)
    li      t1, ' '
    beq     t0, t1, .nt_skip_one
    li      t1, '\t'
    beq     t0, t1, .nt_skip_one
    li      t1, '\n'
    beq     t0, t1, .nt_skip_one
    li      t1, '\r'
    beq     t0, t1, .nt_skip_one
    li      t1, '/'
    bne     t0, t1, .nt_dispatch
    addi    t2, s0, 1
    bgeu    t2, s1, .nt_dispatch
    lbu     t3, 0(t2)
    li      t1, '/'
    bne     t3, t1, .nt_check_block
.nt_line_comment:
    addi    s0, s0, 1
    bgeu    s0, s1, .nt_eof
    lbu     t0, 0(s0)
    li      t1, '\n'
    bne     t0, t1, .nt_line_comment
    addi    s0, s0, 1
    j       .nt_skip
.nt_check_block:
    li      t1, '*'
    bne     t3, t1, .nt_dispatch
    addi    s0, s0, 2
.nt_block_comment:
    bgeu    s0, s1, .nt_eof
    lbu     t0, 0(s0)
    li      t1, '*'
    bne     t0, t1, .nt_block_next
    addi    t2, s0, 1
    bgeu    t2, s1, .nt_block_next
    lbu     t3, 0(t2)
    li      t1, '/'
    bne     t3, t1, .nt_block_next
    addi    s0, s0, 2
    j       .nt_skip
.nt_block_next:
    addi    s0, s0, 1
    j       .nt_block_comment
.nt_skip_one:
    addi    s0, s0, 1
    j       .nt_skip

.nt_dispatch:
    lbu     t0, 0(s0)
    la      t1, tok_start
    sd      s0, 0(t1)
    li      t1, '('
    beq     t0, t1, .nt_lparen
    li      t1, ')'
    beq     t0, t1, .nt_rparen
    li      t1, '{'
    beq     t0, t1, .nt_lbrace
    li      t1, '}'
    beq     t0, t1, .nt_rbrace
    li      t1, ';'
    beq     t0, t1, .nt_semi
    li      t1, ','
    beq     t0, t1, .nt_comma
    li      t1, '+'
    beq     t0, t1, .nt_plus
    li      t1, '-'
    beq     t0, t1, .nt_minus
    li      t1, '*'
    beq     t0, t1, .nt_star
    li      t1, '/'
    beq     t0, t1, .nt_slash
    li      t1, '%'
    beq     t0, t1, .nt_percent
    li      t1, '='
    beq     t0, t1, .nt_eq_or_assign
    li      t1, '!'
    beq     t0, t1, .nt_not_or_ne
    li      t1, '<'
    beq     t0, t1, .nt_lt_or_le
    li      t1, '>'
    beq     t0, t1, .nt_gt_or_ge
    li      t1, '&'
    beq     t0, t1, .nt_amp_or_and
    li      t1, '|'
    beq     t0, t1, .nt_or
    li      t1, '0'
    blt     t0, t1, .nt_try_ident
    li      t1, '9'
    ble     t0, t1, .nt_number
.nt_try_ident:
    mv      a0, t0
    jal     is_ident_start
    bnez    a0, .nt_identifier
    j       .nt_error

.nt_lparen:
    li      t0, TOK_LPAREN
    j       .nt_single
.nt_rparen:
    li      t0, TOK_RPAREN
    j       .nt_single
.nt_lbrace:
    li      t0, TOK_LBRACE
    j       .nt_single
.nt_rbrace:
    li      t0, TOK_RBRACE
    j       .nt_single
.nt_semi:
    li      t0, TOK_SEMI
    j       .nt_single
.nt_comma:
    li      t0, TOK_COMMA
    j       .nt_single
.nt_plus:
    li      t0, TOK_PLUS
    j       .nt_single
.nt_minus:
    li      t0, TOK_MINUS
    j       .nt_single
.nt_star:
    li      t0, TOK_STAR
    j       .nt_single
.nt_slash:
    li      t0, TOK_SLASH
    j       .nt_single
.nt_percent:
    li      t0, TOK_PERCENT
    j       .nt_single

.nt_single:
    la      t1, tok_type
    sd      t0, 0(t1)
    la      t1, tok_len
    li      t2, 1
    sd      t2, 0(t1)
    addi    s0, s0, 1
    j       .nt_done

.nt_eq_or_assign:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_assign
    lbu     t2, 0(t1)
    li      t3, '='
    bne     t2, t3, .nt_assign
    li      t0, TOK_EQ
    li      t1, 2
    j       .nt_double
.nt_assign:
    li      t0, TOK_ASSIGN
    j       .nt_single

.nt_not_or_ne:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_not
    lbu     t2, 0(t1)
    li      t3, '='
    bne     t2, t3, .nt_not
    li      t0, TOK_NE
    li      t1, 2
    j       .nt_double
.nt_not:
    li      t0, TOK_NOT
    j       .nt_single

.nt_lt_or_le:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_lt
    lbu     t2, 0(t1)
    li      t3, '='
    bne     t2, t3, .nt_lt
    li      t0, TOK_LE
    li      t1, 2
    j       .nt_double
.nt_lt:
    li      t0, TOK_LT
    j       .nt_single

.nt_gt_or_ge:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_gt
    lbu     t2, 0(t1)
    li      t3, '='
    bne     t2, t3, .nt_gt
    li      t0, TOK_GE
    li      t1, 2
    j       .nt_double
.nt_gt:
    li      t0, TOK_GT
    j       .nt_single

.nt_amp_or_and:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_amp
    lbu     t2, 0(t1)
    li      t3, '&'
    bne     t2, t3, .nt_amp
    li      t0, TOK_AND
    li      t1, 2
    j       .nt_double
.nt_amp:
    li      t0, TOK_AMP
    j       .nt_single

.nt_or:
    addi    t1, s0, 1
    bgeu    t1, s1, .nt_error
    lbu     t2, 0(t1)
    li      t3, '|'
    bne     t2, t3, .nt_error
    li      t0, TOK_OR
    li      t1, 2
    j       .nt_double

.nt_double:
    la      t2, tok_type
    sd      t0, 0(t2)
    la      t2, tok_len
    sd      t1, 0(t2)
    add     s0, s0, t1
    j       .nt_done

.nt_number:
    li      s2, 0
.nt_num_loop:
    bgeu    s0, s1, .nt_num_done
    lbu     t0, 0(s0)
    li      t1, '0'
    blt     t0, t1, .nt_num_done
    li      t1, '9'
    bgt     t0, t1, .nt_num_done
    li      t1, 10
    mul     s2, s2, t1
    li      t1, '0'
    sub     t0, t0, t1
    add     s2, s2, t0
    addi    s0, s0, 1
    j       .nt_num_loop
.nt_num_done:
    li      t0, TOK_NUM
    la      t1, tok_type
    sd      t0, 0(t1)
    la      t1, tok_val
    sd      s2, 0(t1)
    la      t1, tok_start
    ld      t2, 0(t1)
    sub     t3, s0, t2
    la      t1, tok_len
    sd      t3, 0(t1)
    j       .nt_done

.nt_identifier:
    mv      s2, s0
.nt_ident_loop:
    addi    s0, s0, 1
    bgeu    s0, s1, .nt_ident_done
    lbu     a0, 0(s0)
    addi    sp, sp, -8
    sd      s0, 0(sp)
    jal     is_ident_char
    ld      s0, 0(sp)
    addi    sp, sp, 8
    bnez    a0, .nt_ident_loop
.nt_ident_done:
    sub     s2, s0, s2
    la      t0, tok_len
    sd      s2, 0(t0)

    la      t0, tok_start
    ld      a0, 0(t0)
    mv      a1, s2
    la      a2, kw_int
    li      a3, 3
    jal     str_eq
    bnez    a0, .nt_kw_int

    la      t0, tok_start
    ld      a0, 0(t0)
    la      t0, tok_len
    ld      a1, 0(t0)
    la      a2, kw_return
    li      a3, 6
    jal     str_eq
    bnez    a0, .nt_kw_return

    la      t0, tok_start
    ld      a0, 0(t0)
    la      t0, tok_len
    ld      a1, 0(t0)
    la      a2, kw_if
    li      a3, 2
    jal     str_eq
    bnez    a0, .nt_kw_if

    la      t0, tok_start
    ld      a0, 0(t0)
    la      t0, tok_len
    ld      a1, 0(t0)
    la      a2, kw_else
    li      a3, 4
    jal     str_eq
    bnez    a0, .nt_kw_else

    la      t0, tok_start
    ld      a0, 0(t0)
    la      t0, tok_len
    ld      a1, 0(t0)
    la      a2, kw_while
    li      a3, 5
    jal     str_eq
    bnez    a0, .nt_kw_while

    li      t0, TOK_IDENT
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done

.nt_kw_int:
    li      t0, TOK_INT
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done
.nt_kw_return:
    li      t0, TOK_RETURN
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done
.nt_kw_if:
    li      t0, TOK_IF
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done
.nt_kw_else:
    li      t0, TOK_ELSE
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done
.nt_kw_while:
    li      t0, TOK_WHILE
    la      t1, tok_type
    sd      t0, 0(t1)
    j       .nt_done

.nt_eof:
    li      t0, TOK_EOF
    la      t1, tok_type
    sd      t0, 0(t1)
    la      t1, tok_len
    sd      zero, 0(t1)
    j       .nt_done

.nt_error:
    li      t0, TOK_ERROR
    la      t1, tok_type
    sd      t0, 0(t1)
    la      t1, tok_len
    li      t2, 1
    sd      t2, 0(t1)
    addi    s0, s0, 1

.nt_done:
    la      t0, input_buf
    sub     t1, s0, t0
    la      t2, input_pos
    sd      t1, 0(t2)
    la      t0, tok_type
    ld      a0, 0(t0)
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    addi    sp, sp, 32
    ret


# ############################################################
#                    HELPER FUNCTIONS
# ############################################################

is_ident_start:
    li      t0, 'a'
    blt     a0, t0, .iis_upper
    li      t0, 'z'
    ble     a0, t0, .iis_yes
.iis_upper:
    li      t0, 'A'
    blt     a0, t0, .iis_under
    li      t0, 'Z'
    ble     a0, t0, .iis_yes
.iis_under:
    li      t0, '_'
    beq     a0, t0, .iis_yes
    li      a0, 0
    ret
.iis_yes:
    li      a0, 1
    ret

is_ident_char:
    addi    sp, sp, -8
    sd      ra, 0(sp)
    mv      t0, a0
    jal     is_ident_start
    bnez    a0, .iic_done
    li      t1, '0'
    blt     t0, t1, .iic_no
    li      t1, '9'
    ble     t0, t1, .iic_yes
.iic_no:
    li      a0, 0
    j       .iic_done
.iic_yes:
    li      a0, 1
.iic_done:
    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret

str_eq:
    bne     a1, a3, .se_no
.se_loop:
    beqz    a1, .se_yes
    lbu     t0, 0(a0)
    lbu     t1, 0(a2)
    bne     t0, t1, .se_no
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    j       .se_loop
.se_no:
    li      a0, 0
    ret
.se_yes:
    li      a0, 1
    ret


# ############################################################
#                    OUTPUT UTILITIES
# ############################################################

print_err:
    mv      t0, a1
.pe_len:
    lbu     t1, 0(t0)
    beqz    t1, .pe_write
    addi    t0, t0, 1
    j       .pe_len
.pe_write:
    sub     a2, t0, a1
    li      a0, STDERR
    li      a7, SYS_WRITE
    ecall
    ret

emit_byte:
    la      t0, out_pos
    ld      t1, 0(t0)
    la      t2, output_buf
    add     t2, t2, t1
    sb      a0, 0(t2)
    addi    t1, t1, 1
    sd      t1, 0(t0)
    li      t3, BUF_SIZE
    blt     t1, t3, .eb_done
    addi    sp, sp, -8
    sd      ra, 0(sp)
    jal     flush_output
    ld      ra, 0(sp)
    addi    sp, sp, 8
.eb_done:
    ret

emit_str:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    mv      s0, a0
.es_loop:
    lbu     a0, 0(s0)
    beqz    a0, .es_done
    jal     emit_byte
    addi    s0, s0, 1
    j       .es_loop
.es_done:
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    addi    sp, sp, 16
    ret

emit_num:
    addi    sp, sp, -48
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    bgez    a0, .en_pos
    addi    sp, sp, -8
    sd      a0, 0(sp)
    li      a0, '-'
    jal     emit_byte
    ld      a0, 0(sp)
    addi    sp, sp, 8
    neg     a0, a0
.en_pos:
    mv      s0, a0
    addi    t0, sp, 16
    li      t1, 0
.en_digits:
    li      t2, 10
    rem     t3, s0, t2
    div     s0, s0, t2
    addi    t3, t3, '0'
    add     t4, t0, t1
    sb      t3, 0(t4)
    addi    t1, t1, 1
    bnez    s0, .en_digits
.en_emit:
    addi    t1, t1, -1
    add     t4, t0, t1
    lbu     a0, 0(t4)
    sd      t0, 24(sp)
    sd      t1, 32(sp)
    jal     emit_byte
    ld      t0, 24(sp)
    ld      t1, 32(sp)
    bnez    t1, .en_emit
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    addi    sp, sp, 48
    ret

flush_output:
    la      t0, out_pos
    ld      a2, 0(t0)
    beqz    a2, .fo_done
    mv      a0, s5
    la      a1, output_buf
    li      a7, SYS_WRITE
    ecall
    la      t0, out_pos
    sd      zero, 0(t0)
.fo_done:
    ret
