#include "lexer.h"

/* Global lexer instance */
Lexer lexer;

/* Initialize lexer */
void lexer_init(char *source) {
    lexer.source = source;
    lexer.source_length = strlen(source);
    lexer.position = 0;
    lexer.line = 1;
    lexer.column = 1;
    lexer.current_token.type = TOKEN_UNKNOWN;
}

/* Get current character */
char lexer_current(void) {
    if (lexer.position >= lexer.source_length) {
        return '\0';
    }
    return lexer.source[lexer.position];
}

/* Get next character */
char lexer_next(void) {
    if (lexer.position >= lexer.source_length) {
        return '\0';
    }

    char c = lexer.source[lexer.position++];

    if (c == '\n') {
        lexer.line++;
        lexer.column = 1;
    } else {
        lexer.column++;
    }

    return c;
}

/* Peek at next character without advancing */
char lexer_peek(void) {
    if (lexer.position >= lexer.source_length) {
        return '\0';
    }
    return lexer.source[lexer.position];
}

/* Skip whitespace */
void lexer_skip_whitespace(void) {
    while (lexer_current() == ' ' || lexer_current() == '\t' ||
           lexer_current() == '\n' || lexer_current() == '\r') {
        lexer_next();
    }
}

/* Read identifier or keyword */
Token lexer_read_identifier(void) {
    int start = lexer.position;

    while (isalnum(lexer_current()) || lexer_current() == '_') {
        lexer_next();
    }

    int length = lexer.position - start;
    char *text = malloc(length + 1);
    strncpy(text, lexer.source + start, length);
    text[length] = '\0';

    Token token;
    token.text = text;
    token.length = length;
    token.line = lexer.line;
    token.column = lexer.column - length;

    /* Check for keywords */
    if (strcmp(text, "int") == 0) {
        token.type = TOKEN_INT;
    } else if (strcmp(text, "return") == 0) {
        token.type = TOKEN_RETURN;
    } else if (strcmp(text, "if") == 0) {
        token.type = TOKEN_IF;
    } else if (strcmp(text, "else") == 0) {
        token.type = TOKEN_ELSE;
    } else if (strcmp(text, "while") == 0) {
        token.type = TOKEN_WHILE;
    } else if (strcmp(text, "for") == 0) {
        token.type = TOKEN_FOR;
    } else if (strcmp(text, "main") == 0) {
        token.type = TOKEN_MAIN;
    } else {
        token.type = TOKEN_IDENTIFIER;
    }

    return token;
}

/* Read number */
Token lexer_read_number(void) {
    int start = lexer.position;
    int value = 0;

    while (isdigit(lexer_current())) {
        value = value * 10 + (lexer_current() - '0');
        lexer_next();
    }

    int length = lexer.position - start;
    char *text = malloc(length + 1);
    strncpy(text, lexer.source + start, length);
    text[length] = '\0';

    Token token;
    token.type = TOKEN_NUMBER;
    token.text = text;
    token.length = length;
    token.value = value;
    token.line = lexer.line;
    token.column = lexer.column - length;

    return token;
}

/* Read string literal */
Token lexer_read_string(void) {
    lexer_next(); /* Skip opening quote */
    int start = lexer.position;

    while (lexer_current() != '"' && lexer_current() != '\0') {
        lexer_next();
    }

    int length = lexer.position - start;
    char *text = malloc(length + 1);
    strncpy(text, lexer.source + start, length);
    text[length] = '\0';

    if (lexer_current() == '"') {
        lexer_next(); /* Skip closing quote */
    }

    Token token;
    token.type = TOKEN_STRING;
    token.text = text;
    token.length = length;
    token.line = lexer.line;
    token.column = lexer.column - length - 1;

    return token;
}

/* Get next token */
Token lexer_next_token(void) {
    lexer_skip_whitespace();

    if (lexer_current() == '\0') {
        Token token;
        token.type = TOKEN_EOF;
        token.text = NULL;
        token.length = 0;
        token.line = lexer.line;
        token.column = lexer.column;
        return token;
    }

    char c = lexer_current();

    /* Identifiers and keywords */
    if (isalpha(c) || c == '_') {
        return lexer_read_identifier();
    }

    /* Numbers */
    if (isdigit(c)) {
        return lexer_read_number();
    }

    /* String literals */
    if (c == '"') {
        return lexer_read_string();
    }

    /* Single character tokens */
    Token token;
    token.line = lexer.line;
    token.column = lexer.column;
    token.text = malloc(3);
    token.text[0] = c;
    token.text[1] = '\0';
    token.length = 1;

    switch (c) {
        case '+': token.type = TOKEN_PLUS; break;
        case '-': token.type = TOKEN_MINUS; break;
        case '*': token.type = TOKEN_MULTIPLY; break;
        case '/': token.type = TOKEN_DIVIDE; break;
        case '=':
            lexer_next();
            if (lexer_current() == '=') {
                lexer_next();
                token.type = TOKEN_EQUAL;
                token.text[1] = '=';
                token.text[2] = '\0';
                token.length = 2;
            } else {
                token.type = TOKEN_ASSIGN;
            }
            break;
        case '!':
            lexer_next();
            if (lexer_current() == '=') {
                lexer_next();
                token.type = TOKEN_NOT_EQUAL;
                token.text[1] = '=';
                token.text[2] = '\0';
                token.length = 2;
            } else {
                token.type = TOKEN_UNKNOWN;
            }
            break;
        case '<':
            lexer_next();
            if (lexer_current() == '=') {
                lexer_next();
                token.type = TOKEN_LESS_EQUAL;
                token.text[1] = '=';
                token.text[2] = '\0';
                token.length = 2;
            } else {
                token.type = TOKEN_LESS;
            }
            break;
        case '>':
            lexer_next();
            if (lexer_current() == '=') {
                lexer_next();
                token.type = TOKEN_GREATER_EQUAL;
                token.text[1] = '=';
                token.text[2] = '\0';
                token.length = 2;
            } else {
                token.type = TOKEN_GREATER;
            }
            break;
        case ';': token.type = TOKEN_SEMICOLON; break;
        case ',': token.type = TOKEN_COMMA; break;
        case '(': token.type = TOKEN_LPAREN; break;
        case ')': token.type = TOKEN_RPAREN; break;
        case '{': token.type = TOKEN_LBRACE; break;
        case '}': token.type = TOKEN_RBRACE; break;
        case '[': token.type = TOKEN_LBRACKET; break;
        case ']': token.type = TOKEN_RBRACKET; break;
        default:
            token.type = TOKEN_UNKNOWN;
            lexer_next();
            return token;
    }

    if (token.type != TOKEN_EQUAL && token.type != TOKEN_NOT_EQUAL &&
        token.type != TOKEN_LESS_EQUAL && token.type != TOKEN_GREATER_EQUAL) {
        lexer_next();
    }

    return token;
}

/* Get token type name for debugging */
const char *token_type_name(TokenType type) {
    switch (type) {
        case TOKEN_EOF: return "EOF";
        case TOKEN_IDENTIFIER: return "IDENTIFIER";
        case TOKEN_NUMBER: return "NUMBER";
        case TOKEN_STRING: return "STRING";
        case TOKEN_CHAR: return "CHAR";
        case TOKEN_INT: return "INT";
        case TOKEN_RETURN: return "RETURN";
        case TOKEN_IF: return "IF";
        case TOKEN_ELSE: return "ELSE";
        case TOKEN_WHILE: return "WHILE";
        case TOKEN_FOR: return "FOR";
        case TOKEN_MAIN: return "MAIN";
        case TOKEN_PLUS: return "PLUS";
        case TOKEN_MINUS: return "MINUS";
        case TOKEN_MULTIPLY: return "MULTIPLY";
        case TOKEN_DIVIDE: return "DIVIDE";
        case TOKEN_ASSIGN: return "ASSIGN";
        case TOKEN_EQUAL: return "EQUAL";
        case TOKEN_NOT_EQUAL: return "NOT_EQUAL";
        case TOKEN_LESS: return "LESS";
        case TOKEN_GREATER: return "GREATER";
        case TOKEN_LESS_EQUAL: return "LESS_EQUAL";
        case TOKEN_GREATER_EQUAL: return "GREATER_EQUAL";
        case TOKEN_SEMICOLON: return "SEMICOLON";
        case TOKEN_COMMA: return "COMMA";
        case TOKEN_LPAREN: return "LPAREN";
        case TOKEN_RPAREN: return "RPAREN";
        case TOKEN_LBRACE: return "LBRACE";
        case TOKEN_RBRACE: return "RBRACE";
        case TOKEN_LBRACKET: return "LBRACKET";
        case TOKEN_RBRACKET: return "RBRACKET";
        case TOKEN_UNKNOWN: return "UNKNOWN";
        default: return "UNKNOWN";
    }
}
