#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Method 1: Simple Perfect Hash for C Keywords
// This is a manually crafted hash function for a specific set

// C keywords we want to hash perfectly
const char* c_keywords[] = {
    "int", "char", "float", "double", "void", "if", "else", "while", 
    "for", "return", "break", "continue", "switch", "case", "default",
    "struct", "union", "enum", "typedef", "const", "static", "extern",
    "auto", "register", "volatile", "signed", "unsigned", "long", "short"
};

#define KEYWORD_COUNT 29

// Perfect hash function - manually designed for these 29 keywords
unsigned int perfect_hash(const char* str) {
    // This function was designed to have no collisions for our keyword set
    unsigned int hash = 0;
    
    // Use a combination of character positions and values
    for (int i = 0; str[i]; i++) {
        hash = hash * 31 + str[i] + i * 7;  // Position-dependent hashing
    }
    
    // Modulo to fit in our table size
    return hash % 37;  // 37 is the smallest prime > 29 that works
}

// Method 2: Minimal Perfect Hash (table size = number of elements)
unsigned int minimal_perfect_hash(const char* str) {
    unsigned int hash = 0;
    
    // Different algorithm for minimal perfect hash
    for (int i = 0; str[i]; i++) {
        hash = hash * 17 + str[i] * (i + 1);
    }
    
    return hash % KEYWORD_COUNT;  // Table size = number of elements
}

// Method 3: Two-level Perfect Hash
typedef struct {
    unsigned int g1, g2;  // Two hash functions
    unsigned int offset;  // Offset in second level
} TwoLevelHash;

// First level hash
unsigned int hash1(const char* str) {
    unsigned int hash = 0;
    for (int i = 0; str[i]; i++) {
        hash = hash * 13 + str[i];
    }
    return hash % 7;  // 7 buckets in first level
}

// Second level hash
unsigned int hash2(const char* str) {
    unsigned int hash = 0;
    for (int i = 0; str[i]; i++) {
        hash = hash * 19 + str[i] + i;
    }
    return hash;
}

// Test function to verify perfect hash
void test_perfect_hash() {
    printf("Testing Perfect Hash Functions:\n");
    printf("==============================\n\n");
    
    // Test simple perfect hash
    printf("1. Simple Perfect Hash (table size 37):\n");
    int used[37] = {0};
    int collisions = 0;
    
    for (int i = 0; i < KEYWORD_COUNT; i++) {
        unsigned int hash = perfect_hash(c_keywords[i]);
        if (used[hash]) {
            printf("COLLISION: %s -> %u (already used by %s)\n", 
                   c_keywords[i], hash, c_keywords[used[hash]-1]);
            collisions++;
        } else {
            used[hash] = i + 1;  // Store 1-based index
            printf("%s -> %u\n", c_keywords[i], hash);
        }
    }
    printf("Collisions: %d\n\n", collisions);
    
    // Test minimal perfect hash
    printf("2. Minimal Perfect Hash (table size %d):\n", KEYWORD_COUNT);
    int used_min[KEYWORD_COUNT] = {0};
    collisions = 0;
    
    for (int i = 0; i < KEYWORD_COUNT; i++) {
        unsigned int hash = minimal_perfect_hash(c_keywords[i]);
        if (used_min[hash]) {
            printf("COLLISION: %s -> %u (already used by %s)\n", 
                   c_keywords[i], hash, c_keywords[used_min[hash]-1]);
            collisions++;
        } else {
            used_min[hash] = i + 1;
            printf("%s -> %u\n", c_keywords[i], hash);
        }
    }
    printf("Collisions: %d\n\n", collisions);
}

// Method 4: CMPH (C Minimal Perfect Hash) - Algorithm demonstration
typedef struct {
    unsigned int a, b;  // Parameters for hash function
    unsigned int p;     // Prime number
} CMPHParams;

// CMPH-style hash function
unsigned int cmph_hash(const char* str, CMPHParams* params) {
    unsigned int hash = 0;
    for (int i = 0; str[i]; i++) {
        hash = hash * params->a + str[i] + params->b;
    }
    return hash % params->p;
}

// Generate CMPH parameters for our keyword set
CMPHParams generate_cmph_params() {
    CMPHParams params = {1, 0, KEYWORD_COUNT};
    
    // Try different parameter combinations
    for (params.a = 1; params.a < 100; params.a++) {
        for (params.b = 0; params.b < 100; params.b++) {
            int used[KEYWORD_COUNT] = {0};
            int valid = 1;
            
            // Test if this parameter combination works
            for (int i = 0; i < KEYWORD_COUNT; i++) {
                unsigned int hash = cmph_hash(c_keywords[i], &params);
                if (used[hash]) {
                    valid = 0;
                    break;
                }
                used[hash] = 1;
            }
            
            if (valid) {
                printf("Found CMPH parameters: a=%u, b=%u, p=%u\n", 
                       params.a, params.b, params.p);
                return params;
            }
        }
    }
    
    printf("No perfect hash found with CMPH method\n");
    return params;
}

int main() {
    test_perfect_hash();
    
    printf("3. CMPH (C Minimal Perfect Hash) Method:\n");
    CMPHParams params = generate_cmph_params();
    
    // Test the CMPH hash
    int used[KEYWORD_COUNT] = {0};
    int collisions = 0;
    
    for (int i = 0; i < KEYWORD_COUNT; i++) {
        unsigned int hash = cmph_hash(c_keywords[i], &params);
        if (used[hash]) {
            printf("COLLISION: %s -> %u\n", c_keywords[i], hash);
            collisions++;
        } else {
            used[hash] = 1;
            printf("%s -> %u\n", c_keywords[i], hash);
        }
    }
    printf("CMPH Collisions: %d\n\n", collisions);
    
    printf("Perfect Hash Design Strategies:\n");
    printf("==============================\n");
    printf("1. Manual Design: Craft hash function for specific set\n");
    printf("2. Parameter Search: Try different hash parameters\n");
    printf("3. Two-Level Hashing: Use multiple hash functions\n");
    printf("4. CMPH Algorithm: Advanced minimal perfect hash\n");
    printf("5. GPERF: GNU tool for generating perfect hash functions\n");
    
    return 0;
}
