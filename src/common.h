#ifndef FSTCC_COMMON_H
#define FSTCC_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

/* Token types */
typedef enum {
    TOKEN_EOF = 0,
    TOKEN_IDENTIFIER,
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_CHAR,

    /* Keywords */
    TOKEN_INT,
    TOKEN_RETURN,
    TOKEN_IF,
    TOKEN_ELSE,
    TOKEN_WHILE,
    TOKEN_FOR,
    TOKEN_MAIN,

    /* Operators */
    TOKEN_PLUS,          /* + */
    TOKEN_MINUS,         /* - */
    TOKEN_MULTIPLY,      /* * */
    TOKEN_DIVIDE,        /* / */
    TOKEN_ASSIGN,        /* = */
    TOKEN_EQUAL,         /* == */
    TOKEN_NOT_EQUAL,     /* != */
    TOKEN_LESS,          /* < */
    TOKEN_GREATER,       /* > */
    TOKEN_LESS_EQUAL,    /* <= */
    TOKEN_GREATER_EQUAL, /* >= */

    /* Punctuation */
    TOKEN_SEMICOLON,     /* ; */
    TOKEN_COMMA,         /* , */
    TOKEN_LPAREN,        /* ( */
    TOKEN_RPAREN,        /* ) */
    TOKEN_LBRACE,        /* { */
    TOKEN_RBRACE,        /* } */
    TOKEN_LBRACKET,      /* [ */
    TOKEN_RBRACKET,      /* ] */

    /* Special */
    TOKEN_UNKNOWN
} TokenType;

/* Token structure */
typedef struct {
    TokenType type;
    char *text;
    int length;
    int value;      /* For numbers */
    int line;
    int column;
} Token;

#endif /* FSTCC_COMMON_H */
