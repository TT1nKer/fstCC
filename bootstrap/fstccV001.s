# fstCC - Minimal Bootstrap C Compiler (AT&T Syntax)
# Target: x86-64 Linux

.section .data
    # Token type constants
    TOKEN_INT:         .quad 1
    TOKEN_MAIN:        .quad 2
    TOKEN_LPAREN:      .quad 3
    TOKEN_RPAREN:      .quad 4
    TOKEN_LBRACE:      .quad 5
    TOKEN_RBRACE:      .quad 6
    TOKEN_RETURN:      .quad 7
    TOKEN_NUMBER:      .quad 8
    TOKEN_SEMICOLON:   .quad 9
    TOKEN_EOF:         .quad 10
    
    # Source code buffer (smaller - 4KB is enough)
    source_buffer:     .space 4096     # 4KB source buffer
    source_size:       .quad 0
    
    # Token storage (enough for complex programs)
    token_stream:      .space 1600     # 50 tokens * 32 bytes each
    token_count:       .quad 0
    current_pos:       .quad 0         # Current position in source
    
    # Assembly output (smaller - 8KB is enough)
    asm_buffer:        .space 8192     # 8KB assembly output
    asm_size:          .quad 0

.section .text
.global _start

# Main entry point
_start:
    # Load test input
    call load_test_input
    
    # Lex source code (convert to tokens)
    call lex_source
    
    # Parse tokens (build syntax tree)
    call parse_tokens
    
    # Generate assembly (convert tree to assembly)
    call generate_assembly
    
    # Exit
    movq $60, %rax         # sys_exit
    movq $0, %rdi          # exit code 0
    syscall

# Load test input into buffer
load_test_input:
    # Copy test input to source buffer
    movq $source_buffer, %rdi
    movq $test_input, %rsi
    movq test_input_len(%rip), %rcx
    rep movsb
    
    movq test_input_len(%rip), %rax
    movq %rax, source_size(%rip)
    movq $0, current_pos(%rip)
    ret

# Lexical analysis - convert source to tokens
lex_source:
    pushq %rbp
    movq %rsp, %rbp
    
    # Initialize
    
    movq $0, %rsi                    # rsi = source position
    movq $0, %rdi                    # rdi = token index
    
lex_loop:
    # Check if we've reached end of source
    cmpq source_size(%rip), %rsi
    jge lex_done
    
    # Get current character
    movb source_buffer(%rsi), %al
    
    # Skip whitespace
    cmpb $' ', %al
    je lex_skip_whitespace
    cmpb $'\t', %al
    je lex_skip_whitespace
    cmpb $'\n', %al
    je lex_skip_whitespace
    cmpb $'\r', %al
    je lex_skip_whitespace
    jmp lex_check_tokens
    
lex_skip_whitespace:
    incq %rsi
    jmp lex_loop
    
lex_check_tokens:
    # Check for single character tokens
    cmpb $'(', %al
    je lex_lparen
    cmpb $')', %al
    je lex_rparen
    cmpb $'{', %al
    je lex_lbrace
    cmpb $'}', %al
    je lex_rbrace
    cmpb $';', %al
    je lex_semicolon
    
    # Check for numbers
    cmpb $'0', %al
    jl lex_check_keywords
    cmpb $'9', %al
    jg lex_check_keywords
    jmp lex_number
    
    # Check for keywords/identifiers
lex_check_keywords:
    cmpb $'a', %al
    jl lex_unknown
    cmpb $'z', %al
    jg lex_unknown
    jmp lex_keyword
    
lex_unknown:
    incq %rsi
    jmp lex_loop
    
# Token handlers
lex_lparen:
    call add_token
    movq TOKEN_LPAREN(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_lparen, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_rparen:
    call add_token
    movq TOKEN_RPAREN(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_rparen, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_lbrace:
    call add_token
    movq TOKEN_LBRACE(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_lbrace, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_rbrace:
    call add_token
    movq TOKEN_RBRACE(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_rbrace, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_semicolon:
    call add_token
    movq TOKEN_SEMICOLON(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_semicolon, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_number:
    call add_token
    movq TOKEN_NUMBER(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_number, token_stream+8(,%rdi,8)
    
    # Parse number value
    movq $0, %rcx                    # rcx = number value
lex_number_loop:
    cmpq source_size(%rip), %rsi
    jge lex_number_done
    movb source_buffer(%rsi), %al
    cmpb $'0', %al
    jl lex_number_done
    cmpb $'9', %al
    jg lex_number_done
    
    # Convert digit to number
    subb $'0', %al
    movzbl %al, %eax
    imulq $10, %rcx
    addq %rax, %rcx
    incq %rsi
    jmp lex_number_loop
    
lex_number_done:
    movq %rcx, token_stream+16(,%rdi,8)  # Store number value
    incq %rdi
    jmp lex_loop
    
lex_keyword:
    # Check for "int"
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'i', %al
    jne lex_check_main
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'n', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'t', %al
    jne lex_unknown
    
    call add_token
    movq TOKEN_INT(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_int, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_check_main:
    # Check for "main"
    cmpb $'m', %al
    jne lex_check_return
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'a', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'i', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'n', %al
    jne lex_unknown
    
    call add_token
    movq TOKEN_MAIN(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_main, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
lex_check_return:
    # Check for "return"
    cmpb $'r', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'e', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'t', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'u', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'r', %al
    jne lex_unknown
    incq %rsi
    cmpq source_size(%rip), %rsi
    jge lex_unknown
    movb source_buffer(%rsi), %al
    cmpb $'n', %al
    jne lex_unknown
    
    call add_token
    movq TOKEN_RETURN(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_return, token_stream+8(,%rdi,8)
    incq %rsi
    incq %rdi
    jmp lex_loop
    
add_token:
    # Check if we have space for more tokens
    cmpq $50, %rdi
    jge lex_done
    ret
    
lex_done:
    # Add EOF token
    call add_token
    movq TOKEN_EOF(%rip), %rax
    movq %rax, token_stream(,%rdi,8)
    movq $lexeme_eof, token_stream+8(,%rdi,8)
    incq %rdi
    movq %rdi, token_count(%rip)
    
    popq %rbp
    ret

# Syntax analysis - parse tokens into syntax tree
parse_tokens:
    # TODO: Implement simple parser
    # For now, just return
    ret

# Code generation - convert syntax tree to assembly
generate_assembly:
    # TODO: Implement simple code generator
    # For now, just set assembly size to 0
    movq $0, asm_size(%rip)
    ret

# Test data and lexeme strings
.section .rodata
    test_input:        .asciz "int main() { return 42; }"
    test_input_len:    .quad 25
    
    # Lexeme strings for tokens
    lexeme_int:        .asciz "int"
    lexeme_main:       .asciz "main"
    lexeme_lparen:     .asciz "("
    lexeme_rparen:     .asciz ")"
    lexeme_lbrace:     .asciz "{"
    lexeme_rbrace:     .asciz "}"
    lexeme_return:     .asciz "return"
    lexeme_number:     .asciz "number"
    lexeme_semicolon:  .asciz ";"
    lexeme_eof:        .asciz "EOF"
