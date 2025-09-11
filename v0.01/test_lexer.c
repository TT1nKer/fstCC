/* Test program to verify lexer output
 * This shows what tokens should be generated for "int main() { return 42; }"
 */

#include <stdio.h>

typedef enum {
    TOKEN_INT = 1,
    TOKEN_MAIN = 2,
    TOKEN_LPAREN = 3,
    TOKEN_RPAREN = 4,
    TOKEN_LBRACE = 5,
    TOKEN_RBRACE = 6,
    TOKEN_RETURN = 7,
    TOKEN_NUMBER = 8,
    TOKEN_SEMICOLON = 9,
    TOKEN_EOF = 10
} TokenType;

typedef struct {
    TokenType type;
    char* text;
    int value;
} Token;

int main() {
    printf("Expected lexer output for: \"int main() { return 42; }\"\n\n");
    
    Token expected_tokens[] = {
        {TOKEN_INT, "int", 0},
        {TOKEN_MAIN, "main", 0},
        {TOKEN_LPAREN, "(", 0},
        {TOKEN_RPAREN, ")", 0},
        {TOKEN_LBRACE, "{", 0},
        {TOKEN_RETURN, "return", 0},
        {TOKEN_NUMBER, "number", 42},
        {TOKEN_SEMICOLON, ";", 0},
        {TOKEN_RBRACE, "}", 0},
        {TOKEN_EOF, "EOF", 0}
    };
    
    int token_count = sizeof(expected_tokens) / sizeof(Token);
    
    for (int i = 0; i < token_count; i++) {
        printf("Token %d: Type=%d, Text=\"%s\", Value=%d\n", 
               i, expected_tokens[i].type, expected_tokens[i].text, expected_tokens[i].value);
    }
    
    printf("\nTotal tokens: %d\n", token_count);
    
    return 0;
}
