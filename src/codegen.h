#ifndef FSTCC_CODEGEN_H
#define FSTCC_CODEGEN_H

#include "common.h"
#include "parser.h"
#include "symtab.h"

/* Code output buffer */
typedef struct {
    char *output;
    int size;
    int capacity;
} CodeBuffer;

/* Global code buffer */
extern CodeBuffer code_buffer;

/* Code buffer functions */
void code_buffer_init(void);
void code_emit(char *format, ...);

/* Code generation functions */
void generate_program(ASTNode *node);
void generate_function(ASTNode *node);
void generate_compound_stmt(ASTNode *node);
void generate_statement(ASTNode *node);
void generate_variable_decl(ASTNode *node);
void generate_return_stmt(ASTNode *node);
void generate_expression_stmt(ASTNode *node);
void generate_expression(ASTNode *node);
void generate_binary_op(ASTNode *node);
void generate_identifier(ASTNode *node);
void generate_number(ASTNode *node);

#endif /* FSTCC_CODEGEN_H */
