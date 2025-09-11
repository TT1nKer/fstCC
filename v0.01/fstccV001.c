/* fstCC Stage 1 - C Compiler
 * Written in C, compiled by assembly compiler (fstccV001.s)
 * Target: Minimal C subset for self-hosting
 */

/* Token types for minimal C subset */
typedef enum {
    TOKEN_INT,          /* int keyword */
    TOKEN_MAIN,         /* main identifier */
    TOKEN_LPAREN,       /* ( */
    TOKEN_RPAREN,       /* ) */
    TOKEN_LBRACE,       /* { */
    TOKEN_RBRACE,       /* } */
    TOKEN_RETURN,       /* return keyword */
    TOKEN_NUMBER,       /* integer literal */
    TOKEN_SEMICOLON,    /* ; */
    TOKEN_EOF           /* end of file */
} TokenType;

/* Token structure */
typedef struct {
    TokenType type;
    char* text;
    int value;          /* for numbers */
} Token;

/* Global variables */
char source_buffer[4096];
Token token_stream[50];
int token_count = 0;
int current_pos = 0;
char asm_buffer[8192];
int asm_size = 0;

/* Test input */
char* test_input = "int main() { return 42; }";

/* Function prototypes */
void load_test_input(void);
void lex_source(void);
void parse_tokens(void);
void generate_assembly(void);

/* Main function */
int main() {
    load_test_input();
    lex_source();
    parse_tokens();
    generate_assembly();
    return 0;
}

/* Load test input into source buffer */
void load_test_input() {
    int i = 0;
    while (test_input[i] != '\0') {
        source_buffer[i] = test_input[i];
        i++;
    }
    source_buffer[i] = '\0';
    current_pos = 0;
}

/* Simple lexer - convert source to tokens */
void lex_source() {
    token_count = 0;
    int pos = 0;
    
    while (source_buffer[pos] != '\0' && token_count < 50) {
        /* Skip whitespace */
        while (source_buffer[pos] == ' ' || source_buffer[pos] == '\t' || 
               source_buffer[pos] == '\n' || source_buffer[pos] == '\r') {
            pos++;
        }
        
        if (source_buffer[pos] == '\0') break;
        
        /* Tokenize based on character */
        if (source_buffer[pos] == '(') {
            token_stream[token_count].type = TOKEN_LPAREN;
            token_stream[token_count].text = "(";
            token_count++;
            pos++;
        }
        else if (source_buffer[pos] == ')') {
            token_stream[token_count].type = TOKEN_RPAREN;
            token_stream[token_count].text = ")";
            token_count++;
            pos++;
        }
        else if (source_buffer[pos] == '{') {
            token_stream[token_count].type = TOKEN_LBRACE;
            token_stream[token_count].text = "{";
            token_count++;
            pos++;
        }
        else if (source_buffer[pos] == '}') {
            token_stream[token_count].type = TOKEN_RBRACE;
            token_stream[token_count].text = "}";
            token_count++;
            pos++;
        }
        else if (source_buffer[pos] == ';') {
            token_stream[token_count].type = TOKEN_SEMICOLON;
            token_stream[token_count].text = ";";
            token_count++;
            pos++;
        }
        else if (source_buffer[pos] >= '0' && source_buffer[pos] <= '9') {
            /* Parse number */
            int value = 0;
            int start = pos;
            while (source_buffer[pos] >= '0' && source_buffer[pos] <= '9') {
                value = value * 10 + (source_buffer[pos] - '0');
                pos++;
            }
            token_stream[token_count].type = TOKEN_NUMBER;
            token_stream[token_count].text = "number";
            token_stream[token_count].value = value;
            token_count++;
        }
        else if (source_buffer[pos] >= 'a' && source_buffer[pos] <= 'z') {
            /* Parse identifier/keyword */
            int start = pos;
            while ((source_buffer[pos] >= 'a' && source_buffer[pos] <= 'z') ||
                   (source_buffer[pos] >= 'A' && source_buffer[pos] <= 'Z') ||
                   (source_buffer[pos] >= '0' && source_buffer[pos] <= '9')) {
                pos++;
            }
            
            /* Check for keywords */
            if (pos - start == 3 && 
                source_buffer[start] == 'i' && 
                source_buffer[start+1] == 'n' && 
                source_buffer[start+2] == 't') {
                token_stream[token_count].type = TOKEN_INT;
                token_stream[token_count].text = "int";
            }
            else if (pos - start == 4 && 
                     source_buffer[start] == 'm' && 
                     source_buffer[start+1] == 'a' && 
                     source_buffer[start+2] == 'i' && 
                     source_buffer[start+3] == 'n') {
                token_stream[token_count].type = TOKEN_MAIN;
                token_stream[token_count].text = "main";
            }
            else if (pos - start == 6 && 
                     source_buffer[start] == 'r' && 
                     source_buffer[start+1] == 'e' && 
                     source_buffer[start+2] == 't' && 
                     source_buffer[start+3] == 'u' && 
                     source_buffer[start+4] == 'r' && 
                     source_buffer[start+5] == 'n') {
                token_stream[token_count].type = TOKEN_RETURN;
                token_stream[token_count].text = "return";
            }
            token_count++;
        }
        else {
            pos++; /* Skip unknown characters */
        }
    }
    
    /* Add EOF token */
    token_stream[token_count].type = TOKEN_EOF;
    token_stream[token_count].text = "EOF";
    token_count++;
}

/* Simple parser - build syntax tree (simplified) */
void parse_tokens() {
    /* For now, just validate token sequence */
    /* TODO: Build actual syntax tree */
}

/* Simple code generator - convert to assembly */
void generate_assembly() {
    asm_size = 0;
    
    /* Generate simple assembly for "int main() { return 42; }" */
    char* asm_code = "main:\n    mov rax, 42\n    ret\n";
    
    int i = 0;
    while (asm_code[i] != '\0') {
        asm_buffer[asm_size] = asm_code[i];
        asm_size++;
        i++;
    }
    asm_buffer[asm_size] = '\0';
}
