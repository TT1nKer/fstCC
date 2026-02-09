#include "lexer.h"
#include "parser.h"
#include "codegen.h"

/* Read entire file into a string */
static char *read_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        printf("Error: Cannot open file '%s'\n", path);
        exit(1);
    }

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(len + 1);
    fread(buf, 1, len, f);
    buf[len] = '\0';
    fclose(f);

    return buf;
}

/* Write string to file */
static void write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) {
        printf("Error: Cannot open output file '%s'\n", path);
        exit(1);
    }
    fprintf(f, "%s", content);
    fclose(f);
}

static void print_usage(const char *prog) {
    printf("fstCC - First Self-hosting Tiny C Compiler\n");
    printf("Usage: %s <input.c> [output.s]\n", prog);
    printf("       %s --test         Run built-in test\n", prog);
}

/* Built-in test (matches original compiler.c behavior) */
static void run_test(void) {
    char *test_code =
        "int main() {\n"
        "    int a = 5;\n"
        "    int b = 3;\n"
        "    int c = a * b + 2;\n"
        "    int d = c - a;\n"
        "    return d;\n"
        "}";

    printf("Testing compiler pipeline with code:\n%s\n", test_code);
    printf("Expected result: 5*3+2-5 = 17-5 = 12\n\n");

    /* Lexer test */
    printf("=== LEXER OUTPUT ===\n");
    lexer_init(test_code);

    Token token;
    do {
        token = lexer_next_token();
        printf("Token: %-15s Text: %-10s Line: %d, Column: %d",
               token_type_name(token.type),
               token.text ? token.text : "NULL",
               token.line, token.column);
        if (token.type == TOKEN_NUMBER) {
            printf(" Value: %d", token.value);
        }
        printf("\n");
        if (token.text) free(token.text);
    } while (token.type != TOKEN_EOF);

    /* Parser test */
    printf("\n=== PARSER OUTPUT ===\n");
    lexer_init(test_code);
    parser_init();
    ASTNode *ast = parse_program();
    printf("Abstract Syntax Tree:\n");
    print_ast(ast, 0);

    /* Code generation test */
    printf("\n=== CODE GENERATOR OUTPUT ===\n");
    code_buffer_init();
    generate_program(ast);
    printf("Generated Assembly:\n");
    printf("%s\n", code_buffer.output);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "--test") == 0) {
        run_test();
        return 0;
    }

    /* Read input file */
    char *source = read_file(argv[1]);

    /* Compile */
    lexer_init(source);
    parser_init();
    ASTNode *ast = parse_program();

    code_buffer_init();
    generate_program(ast);

    /* Write output */
    const char *output_path = (argc >= 3) ? argv[2] : "output.s";
    write_file(output_path, code_buffer.output);
    printf("Compiled '%s' -> '%s'\n", argv[1], output_path);

    free(source);
    free(code_buffer.output);

    return 0;
}
