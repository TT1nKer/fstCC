#include <stdio.h>
#include <string.h>

// Include the generated perfect hash
#include "keywords_hash.c"

// Test the perfect hash function
void test_perfect_hash() {
    printf("Testing GPERF Generated Perfect Hash:\n");
    printf("====================================\n\n");
    
    // Test all keywords
    const char* test_keywords[] = {
        "int", "char", "float", "double", "void", "if", "else", "while", 
        "for", "return", "break", "continue", "switch", "case", "default",
        "struct", "union", "enum", "typedef", "const", "static", "extern"
    };
    
    int keyword_count = sizeof(test_keywords) / sizeof(test_keywords[0]);
    
    printf("Keyword Lookup Results:\n");
    printf("======================\n");
    
    for (int i = 0; i < keyword_count; i++) {
        const char* keyword = test_keywords[i];
        int len = strlen(keyword);
        
        // Use the generated perfect hash function
        const char* result = in_word_set(keyword, len);
        
        if (result && strcmp(result, keyword) == 0) {
            printf("✓ %s -> FOUND (hash: %u)\n", keyword, hash(keyword, len));
        } else {
            printf("✗ %s -> NOT FOUND\n", keyword);
        }
    }
    
    printf("\nTesting Non-Keywords:\n");
    printf("====================\n");
    
    const char* non_keywords[] = {
        "main", "printf", "scanf", "malloc", "free", "hello", "world"
    };
    
    for (int i = 0; i < sizeof(non_keywords)/sizeof(non_keywords[0]); i++) {
        const char* word = non_keywords[i];
        int len = strlen(word);
        
        const char* result = in_word_set(word, len);
        
        if (result == NULL) {
            printf("✓ %s -> NOT FOUND (correct)\n", word);
        } else {
            printf("✗ %s -> FOUND (incorrect)\n", word);
        }
    }
    
    printf("\nHash Function Analysis:\n");
    printf("======================\n");
    
    // Analyze hash distribution
    int hash_counts[32] = {0};  // Hash range is 2-31
    int collisions = 0;
    
    for (int i = 0; i < keyword_count; i++) {
        const char* keyword = test_keywords[i];
        int len = strlen(keyword);
        unsigned int h = hash(keyword, len);
        
        if (hash_counts[h] > 0) {
            collisions++;
            printf("COLLISION: %s -> %u\n", keyword, h);
        } else {
            hash_counts[h] = 1;
            printf("%s -> %u\n", keyword, h);
        }
    }
    
    printf("\nCollision Analysis:\n");
    printf("==================\n");
    printf("Total keywords: %d\n", keyword_count);
    printf("Hash range: %d to %d\n", MIN_HASH_VALUE, MAX_HASH_VALUE);
    printf("Collisions: %d\n", collisions);
    printf("Perfect hash: %s\n", collisions == 0 ? "YES" : "NO");
    
    // Show hash table utilization
    int used_slots = 0;
    for (int i = MIN_HASH_VALUE; i <= MAX_HASH_VALUE; i++) {
        if (hash_counts[i] > 0) used_slots++;
    }
    
    printf("Table utilization: %d/%d slots (%.1f%%)\n", 
           used_slots, MAX_HASH_VALUE - MIN_HASH_VALUE + 1,
           100.0 * used_slots / (MAX_HASH_VALUE - MIN_HASH_VALUE + 1));
}

// Demonstrate how to use in a lexer
TokenType lookup_keyword(const char* str, int len) {
    const char* result = in_word_set(str, len);
    
    if (result == NULL) {
        return 0;  // Not a keyword
    }
    
    // Map string to token type
    if (strcmp(result, "int") == 0) return TOKEN_INT;
    if (strcmp(result, "char") == 0) return TOKEN_CHAR;
    if (strcmp(result, "float") == 0) return TOKEN_FLOAT;
    if (strcmp(result, "double") == 0) return TOKEN_DOUBLE;
    if (strcmp(result, "void") == 0) return TOKEN_VOID;
    if (strcmp(result, "if") == 0) return TOKEN_IF;
    if (strcmp(result, "else") == 0) return TOKEN_ELSE;
    if (strcmp(result, "while") == 0) return TOKEN_WHILE;
    if (strcmp(result, "for") == 0) return TOKEN_FOR;
    if (strcmp(result, "return") == 0) return TOKEN_RETURN;
    if (strcmp(result, "break") == 0) return TOKEN_BREAK;
    if (strcmp(result, "continue") == 0) return TOKEN_CONTINUE;
    if (strcmp(result, "switch") == 0) return TOKEN_SWITCH;
    if (strcmp(result, "case") == 0) return TOKEN_CASE;
    if (strcmp(result, "default") == 0) return TOKEN_DEFAULT;
    if (strcmp(result, "struct") == 0) return TOKEN_STRUCT;
    if (strcmp(result, "union") == 0) return TOKEN_UNION;
    if (strcmp(result, "enum") == 0) return TOKEN_ENUM;
    if (strcmp(result, "typedef") == 0) return TOKEN_TYPEDEF;
    if (strcmp(result, "const") == 0) return TOKEN_CONST;
    if (strcmp(result, "static") == 0) return TOKEN_STATIC;
    if (strcmp(result, "extern") == 0) return TOKEN_EXTERN;
    
    return 0;  // Should not reach here
}

int main() {
    test_perfect_hash();
    
    printf("\nPerfect Hash in Real Compilers:\n");
    printf("===============================\n");
    printf("1. GCC: Uses GPERF for C/C++ keywords\n");
    printf("2. Clang: Uses perfect hash for reserved words\n");
    printf("3. Python: Uses perfect hash for built-in functions\n");
    printf("4. Java: Uses perfect hash for keywords and operators\n");
    printf("5. Go: Uses perfect hash for language keywords\n");
    
    printf("\nAdvantages of Perfect Hash:\n");
    printf("===========================\n");
    printf("✓ Zero collisions for known set\n");
    printf("✓ O(1) lookup time\n");
    printf("✓ No chaining or probing needed\n");
    printf("✓ Memory efficient\n");
    printf("✓ Fast compilation\n");
    
    printf("\nDisadvantages:\n");
    printf("==============\n");
    printf("✗ Only works for fixed, known set\n");
    printf("✗ Cannot add new elements at runtime\n");
    printf("✗ Generation can be slow for large sets\n");
    printf("✗ May require large lookup tables\n");
    
    return 0;
}
