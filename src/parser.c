#include "parser.h"

/* Global parser instance */
Parser parser;

/* Parser helper functions */
void parser_init(void) {
    parser.has_token = 0;
}

Token parser_current_token(void) {
    if (!parser.has_token) {
        parser.current_token = lexer_next_token();
        parser.has_token = 1;
    }
    return parser.current_token;
}

void parser_consume_token(void) {
    if (parser.has_token && parser.current_token.text) {
        free(parser.current_token.text);
    }
    parser.has_token = 0;
}

int parser_match(TokenType expected) {
    Token token = parser_current_token();
    return token.type == expected;
}

Token parser_expect(TokenType expected) {
    Token token = parser_current_token();
    if (token.type != expected) {
        printf("Parser error: Expected %s, got %s at line %d\n",
               token_type_name(expected), token_type_name(token.type), token.line);
        exit(1);
    }

    /* Make a copy of the token before consuming it */
    Token result_token;
    result_token.type = token.type;
    result_token.value = token.value;
    result_token.line = token.line;
    result_token.column = token.column;
    result_token.length = token.length;
    if (token.text) {
        result_token.text = malloc(strlen(token.text) + 1);
        strcpy(result_token.text, token.text);
    } else {
        result_token.text = NULL;
    }

    parser_consume_token();
    return result_token;
}

/* AST creation functions */
ASTNode *create_ast_node(ASTNodeType type) {
    ASTNode *node = malloc(sizeof(ASTNode));
    node->type = type;
    node->token = parser_current_token();
    return node;
}

ASTNode *create_number_node(int value) {
    ASTNode *node = create_ast_node(AST_NUMBER);
    node->data.number.value = value;
    return node;
}

ASTNode *create_identifier_node(char *name) {
    ASTNode *node = create_ast_node(AST_IDENTIFIER);
    node->data.identifier.name = malloc(strlen(name) + 1);
    strcpy(node->data.identifier.name, name);
    return node;
}

ASTNode *create_binary_op_node(TokenType operator, ASTNode *left, ASTNode *right) {
    ASTNode *node = create_ast_node(AST_BINARY_OP);
    node->data.binary_op.operator = operator;
    node->data.binary_op.left = left;
    node->data.binary_op.right = right;
    return node;
}

/* Parse program (top level) */
ASTNode *parse_program(void) {
    ASTNode *program = create_ast_node(AST_PROGRAM);
    program->data.program.functions = malloc(sizeof(ASTNode *) * 10);
    program->data.program.function_count = 0;

    while (parser_current_token().type != TOKEN_EOF) {
        ASTNode *func = parse_function_definition();
        program->data.program.functions[program->data.program.function_count++] = func;
    }

    return program;
}

/* Parse function definition */
ASTNode *parse_function_definition(void) {
    Token return_type_token = parser_expect(TOKEN_INT);

    Token name_token;
    if (parser_match(TOKEN_MAIN)) {
        name_token = parser_expect(TOKEN_MAIN);
    } else {
        name_token = parser_expect(TOKEN_IDENTIFIER);
    }

    Token lparen = parser_expect(TOKEN_LPAREN);
    Token rparen = parser_expect(TOKEN_RPAREN);

    ASTNode *body = parse_compound_statement();

    ASTNode *func_def = create_ast_node(AST_FUNCTION_DEF);
    func_def->data.function_def.name = malloc(strlen(name_token.text) + 1);
    strcpy(func_def->data.function_def.name, name_token.text);
    func_def->data.function_def.return_type = return_type_token.type;
    func_def->data.function_def.body = body;

    if (return_type_token.text) free(return_type_token.text);
    if (name_token.text) free(name_token.text);
    if (lparen.text) free(lparen.text);
    if (rparen.text) free(rparen.text);

    return func_def;
}

/* Parse compound statement */
ASTNode *parse_compound_statement(void) {
    parser_expect(TOKEN_LBRACE);

    ASTNode *compound = create_ast_node(AST_COMPOUND_STMT);
    compound->data.stmt_list.statements = malloc(sizeof(ASTNode *) * 20);
    compound->data.stmt_list.statement_count = 0;

    while (!parser_match(TOKEN_RBRACE) && parser_current_token().type != TOKEN_EOF) {
        ASTNode *stmt = parse_statement();
        compound->data.stmt_list.statements[compound->data.stmt_list.statement_count++] = stmt;
    }

    parser_expect(TOKEN_RBRACE);
    return compound;
}

/* Parse statement */
ASTNode *parse_statement(void) {
    Token token = parser_current_token();

    switch (token.type) {
        case TOKEN_INT:
            return parse_variable_declaration();
        case TOKEN_RETURN:
            return parse_return_statement();
        case TOKEN_LBRACE:
            return parse_compound_statement();
        default:
            return parse_expression_statement();
    }
}

/* Parse variable declaration */
ASTNode *parse_variable_declaration(void) {
    Token type_token = parser_expect(TOKEN_INT);
    Token name_token = parser_expect(TOKEN_IDENTIFIER);

    ASTNode *var_decl = create_ast_node(AST_VARIABLE_DECL);
    var_decl->data.var_decl.name = malloc(strlen(name_token.text) + 1);
    strcpy(var_decl->data.var_decl.name, name_token.text);
    var_decl->data.var_decl.var_type = type_token.type;
    var_decl->data.var_decl.initializer = NULL;

    if (parser_match(TOKEN_ASSIGN)) {
        parser_consume_token();
        var_decl->data.var_decl.initializer = parse_expression();
    }

    Token semicolon = parser_expect(TOKEN_SEMICOLON);

    if (type_token.text) free(type_token.text);
    if (name_token.text) free(name_token.text);
    if (semicolon.text) free(semicolon.text);

    return var_decl;
}

/* Parse return statement */
ASTNode *parse_return_statement(void) {
    parser_expect(TOKEN_RETURN);

    ASTNode *return_stmt = create_ast_node(AST_RETURN_STMT);

    if (!parser_match(TOKEN_SEMICOLON)) {
        return_stmt->data.return_stmt.expression = parse_expression();
    } else {
        return_stmt->data.return_stmt.expression = NULL;
    }

    parser_expect(TOKEN_SEMICOLON);
    return return_stmt;
}

/* Parse expression statement */
ASTNode *parse_expression_statement(void) {
    ASTNode *expr_stmt = create_ast_node(AST_EXPRESSION_STMT);

    if (!parser_match(TOKEN_SEMICOLON)) {
        expr_stmt->data.return_stmt.expression = parse_expression();
    } else {
        expr_stmt->data.return_stmt.expression = NULL;
    }

    parser_expect(TOKEN_SEMICOLON);
    return expr_stmt;
}

/* Parse expression */
ASTNode *parse_expression(void) {
    return parse_additive_expression();
}

/* Parse additive expression */
ASTNode *parse_additive_expression(void) {
    ASTNode *expr = parse_multiplicative_expression();

    while (parser_match(TOKEN_PLUS) || parser_match(TOKEN_MINUS)) {
        TokenType op_type = parser_current_token().type;
        parser_consume_token();
        ASTNode *right = parse_multiplicative_expression();
        expr = create_binary_op_node(op_type, expr, right);
    }

    return expr;
}

/* Parse multiplicative expression */
ASTNode *parse_multiplicative_expression(void) {
    ASTNode *expr = parse_primary_expression();

    while (parser_match(TOKEN_MULTIPLY) || parser_match(TOKEN_DIVIDE)) {
        TokenType op_type = parser_current_token().type;
        parser_consume_token();
        ASTNode *right = parse_primary_expression();
        expr = create_binary_op_node(op_type, expr, right);
    }

    return expr;
}

/* Parse primary expression */
ASTNode *parse_primary_expression(void) {
    Token token = parser_current_token();

    switch (token.type) {
        case TOKEN_NUMBER: {
            Token num_token = parser_expect(TOKEN_NUMBER);
            ASTNode *node = create_number_node(num_token.value);
            if (num_token.text) free(num_token.text);
            return node;
        }

        case TOKEN_IDENTIFIER: {
            Token id_token = parser_expect(TOKEN_IDENTIFIER);
            ASTNode *node = create_identifier_node(id_token.text);
            if (id_token.text) free(id_token.text);
            return node;
        }

        case TOKEN_LPAREN: {
            parser_consume_token();
            ASTNode *expr = parse_expression();
            Token rparen = parser_expect(TOKEN_RPAREN);
            if (rparen.text) free(rparen.text);
            return expr;
        }

        default:
            printf("Parser error: Unexpected token %s in expression at line %d\n",
                   token_type_name(token.type), token.line);
            exit(1);
    }
}

/* AST printing for debugging */
void print_ast(ASTNode *node, int indent) {
    if (!node) return;

    for (int i = 0; i < indent; i++) printf("  ");

    switch (node->type) {
        case AST_PROGRAM:
            printf("PROGRAM\n");
            for (int i = 0; i < node->data.program.function_count; i++) {
                print_ast(node->data.program.functions[i], indent + 1);
            }
            break;

        case AST_FUNCTION_DEF:
            printf("FUNCTION_DEF: %s\n", node->data.function_def.name);
            print_ast(node->data.function_def.body, indent + 1);
            break;

        case AST_VARIABLE_DECL:
            printf("VAR_DECL: %s\n", node->data.var_decl.name);
            if (node->data.var_decl.initializer) {
                print_ast(node->data.var_decl.initializer, indent + 1);
            }
            break;

        case AST_COMPOUND_STMT:
            printf("COMPOUND_STMT\n");
            for (int i = 0; i < node->data.stmt_list.statement_count; i++) {
                print_ast(node->data.stmt_list.statements[i], indent + 1);
            }
            break;

        case AST_RETURN_STMT:
            printf("RETURN_STMT\n");
            if (node->data.return_stmt.expression) {
                print_ast(node->data.return_stmt.expression, indent + 1);
            }
            break;

        case AST_EXPRESSION_STMT:
            printf("EXPRESSION_STMT\n");
            if (node->data.return_stmt.expression) {
                print_ast(node->data.return_stmt.expression, indent + 1);
            }
            break;

        case AST_BINARY_OP:
            printf("BINARY_OP: %s\n", token_type_name(node->data.binary_op.operator));
            print_ast(node->data.binary_op.left, indent + 1);
            print_ast(node->data.binary_op.right, indent + 1);
            break;

        case AST_IDENTIFIER:
            printf("IDENTIFIER: %s\n", node->data.identifier.name);
            break;

        case AST_NUMBER:
            printf("NUMBER: %d\n", node->data.number.value);
            break;

        default:
            printf("UNKNOWN_NODE\n");
            break;
    }
}
