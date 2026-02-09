#ifndef FSTCC_LEXER_H
#define FSTCC_LEXER_H

#include "common.h"

/* Lexer state */
typedef struct {
    char *source;
    int source_length;
    int position;
    int line;
    int column;
    Token current_token;
} Lexer;

/* Global lexer instance */
extern Lexer lexer;

/* Lexer functions */
void lexer_init(char *source);
char lexer_current(void);
char lexer_next(void);
char lexer_peek(void);
void lexer_skip_whitespace(void);
Token lexer_read_identifier(void);
Token lexer_read_number(void);
Token lexer_read_string(void);
Token lexer_next_token(void);
const char *token_type_name(TokenType type);

#endif /* FSTCC_LEXER_H */
