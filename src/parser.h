#ifndef FSTCC_PARSER_H
#define FSTCC_PARSER_H

#include "common.h"
#include "lexer.h"

/* AST Node Types */
typedef enum {
    AST_PROGRAM,
    AST_FUNCTION_DEF,
    AST_VARIABLE_DECL,
    AST_STATEMENT_LIST,
    AST_RETURN_STMT,
    AST_IF_STMT,
    AST_WHILE_STMT,
    AST_EXPRESSION_STMT,
    AST_COMPOUND_STMT,
    AST_BINARY_OP,
    AST_IDENTIFIER,
    AST_NUMBER
} ASTNodeType;

/* Forward declaration */
struct ASTNode;

/* AST Node structure */
typedef struct ASTNode {
    ASTNodeType type;
    Token token;

    union {
        struct {
            struct ASTNode **functions;
            int function_count;
        } program;

        struct {
            char *name;
            TokenType return_type;
            struct ASTNode *body;
        } function_def;

        struct {
            char *name;
            TokenType var_type;
            struct ASTNode *initializer;
        } var_decl;

        struct {
            struct ASTNode **statements;
            int statement_count;
        } stmt_list;

        struct {
            struct ASTNode *expression;
        } return_stmt;

        struct {
            struct ASTNode *condition;
            struct ASTNode *then_stmt;
            struct ASTNode *else_stmt;
        } if_stmt;

        struct {
            struct ASTNode *condition;
            struct ASTNode *body;
        } while_stmt;

        struct {
            TokenType operator;
            struct ASTNode *left;
            struct ASTNode *right;
        } binary_op;

        struct {
            char *name;
        } identifier;

        struct {
            int value;
        } number;
    } data;
} ASTNode;

/* Parser state */
typedef struct {
    Token current_token;
    int has_token;
} Parser;

/* Global parser instance */
extern Parser parser;

/* Parser functions */
void parser_init(void);
Token parser_current_token(void);
void parser_consume_token(void);
int parser_match(TokenType expected);
Token parser_expect(TokenType expected);

/* AST creation */
ASTNode *create_ast_node(ASTNodeType type);
ASTNode *create_number_node(int value);
ASTNode *create_identifier_node(char *name);
ASTNode *create_binary_op_node(TokenType operator, ASTNode *left, ASTNode *right);

/* Parsing functions */
ASTNode *parse_program(void);
ASTNode *parse_function_definition(void);
ASTNode *parse_compound_statement(void);
ASTNode *parse_statement(void);
ASTNode *parse_variable_declaration(void);
ASTNode *parse_return_statement(void);
ASTNode *parse_expression_statement(void);
ASTNode *parse_expression(void);
ASTNode *parse_additive_expression(void);
ASTNode *parse_multiplicative_expression(void);
ASTNode *parse_primary_expression(void);

/* Debug */
void print_ast(ASTNode *node, int indent);

#endif /* FSTCC_PARSER_H */
