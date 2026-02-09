/* Code Generation Demonstration
 * 
 * C Source: int x = 42; int y = x + 10; return y;
 * 
 * AST Structure:
 *   VAR_DECL: x
 *     NUMBER: 42
 *   VAR_DECL: y  
 *     BINARY_OP: PLUS
 *       IDENTIFIER: x
 *       NUMBER: 10
 *   RETURN_STMT
 *     IDENTIFIER: y
 * 
 * Generated Assembly Walkthrough:
 */

#include <stdio.h>

void demonstrate_codegen() {
    printf("Code Generation for: int x = 42; int y = x + 10; return y;\n\n");
    
    printf("Step 1: Variable Declaration 'int x = 42'\n");
    printf("  - Add 'x' to symbol table at offset -8(%%rbp)\n");
    printf("  - Generate: movq $42, %%rax      # load constant 42\n");
    printf("  - Generate: movq %%rax, -8(%%rbp) # store in x\n\n");
    
    printf("Step 2: Variable Declaration 'int y = x + 10'\n");
    printf("  - Add 'y' to symbol table at offset -16(%%rbp)\n");
    printf("  - Generate code for 'x + 10':\n");
    printf("    a) Generate left operand (x):\n");
    printf("       movq -8(%%rbp), %%rax    # load x\n");
    printf("    b) Save left operand:\n");
    printf("       pushq %%rax             # save x on stack\n");
    printf("    c) Generate right operand (10):\n");
    printf("       movq $10, %%rax         # load constant 10\n");
    printf("    d) Perform addition:\n");
    printf("       movq %%rax, %%rbx       # right operand in rbx\n");
    printf("       popq %%rax              # restore left operand\n");
    printf("       addq %%rbx, %%rax       # x + 10\n");
    printf("    e) Store result in y:\n");
    printf("       movq %%rax, -16(%%rbp)  # store in y\n\n");
    
    printf("Step 3: Return Statement 'return y'\n");
    printf("  - Generate: movq -16(%%rbp), %%rax  # load y\n");
    printf("  - Generate function epilogue:\n");
    printf("    movq %%rbp, %%rsp\n");
    printf("    popq %%rbp\n");
    printf("    ret\n\n");
    
    printf("Result: Function returns 52 (42 + 10) in %%rax\n");
    printf("Exit code: 52 (passed to sys_exit)\n");
}

void demonstrate_stack_layout() {
    printf("Stack Layout During Execution:\n\n");
    printf("High Memory\n");
    printf("  ┌─────────────────┐\n");
    printf("  │  Return Address │ <- Pushed by 'call main'\n");
    printf("  ├─────────────────┤\n");
    printf("  │   Old %%rbp      │ <- Saved by 'pushq %%rbp'\n");
    printf("  ├─────────────────┤ <- %%rbp (Frame Pointer)\n");
    printf("  │   x = 42        │ <- -8(%%rbp)\n");
    printf("  ├─────────────────┤\n");
    printf("  │   y = 52        │ <- -16(%%rbp)\n");
    printf("  ├─────────────────┤\n");
    printf("  │   (unused)      │ <- %%rsp (Stack Pointer)\n");
    printf("  └─────────────────┘\n");
    printf("Low Memory\n\n");
    
    printf("Register Usage:\n");
    printf("  %%rax - Accumulator (expression results, return value)\n");
    printf("  %%rbx - Temporary (right operand in binary ops)\n");
    printf("  %%rbp - Frame Pointer (base for local variables)\n");
    printf("  %%rsp - Stack Pointer (top of stack)\n");
    printf("  %%rdi - System call argument (exit code)\n");
}

int main() {
    demonstrate_codegen();
    printf("\n" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "=" "\n\n");
    demonstrate_stack_layout();
    return 0;
}

