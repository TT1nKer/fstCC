/* Test our compiler with a more complex program */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Include our compiler functions (simplified version)
extern void lexer_init(char *source);
extern void parser_init();
extern void code_buffer_init();
extern void generate_program(void *ast);
extern void *parse_program();
extern char *code_buffer_output;

int main() {
    // Read the complex example
    FILE *file = fopen("complex_example.c", "r");
    if (!file) {
        printf("Error: Could not open complex_example.c\n");
        return 1;
    }
    
    // Get file size
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    // Read file content
    char *source = malloc(size + 1);
    fread(source, 1, size, file);
    source[size] = '\0';
    fclose(file);
    
    printf("Compiling complex program:\n%s\n", source);
    printf("Expected result: 5*3+2-5 = 17-5 = 12\n\n");
    
    free(source);
    return 0;
}

