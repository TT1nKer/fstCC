#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TABLE_SIZE 11  // Small size to force collisions
#define MAX_STRING 50

// Hash table entry
typedef struct HashEntry {
    char key[MAX_STRING];
    int value;
    struct HashEntry* next;  // For chaining
} HashEntry;

// Hash table structure
typedef struct {
    HashEntry* table[TABLE_SIZE];
    int size;
} HashTable;

// Simple hash function (will cause collisions)
unsigned int hash_function(const char* key) {
    unsigned int hash = 0;
    for (int i = 0; key[i]; i++) {
        hash = hash * 31 + key[i];
    }
    return hash % TABLE_SIZE;
}

// Method 1: Separate Chaining (Linked Lists)
void init_hash_table(HashTable* ht) {
    for (int i = 0; i < TABLE_SIZE; i++) {
        ht->table[i] = NULL;
    }
    ht->size = 0;
}

void insert_chaining(HashTable* ht, const char* key, int value) {
    unsigned int index = hash_function(key);
    
    // Create new entry
    HashEntry* new_entry = malloc(sizeof(HashEntry));
    strcpy(new_entry->key, key);
    new_entry->value = value;
    new_entry->next = NULL;
    
    // Insert at head of chain
    new_entry->next = ht->table[index];
    ht->table[index] = new_entry;
    ht->size++;
}

HashEntry* lookup_chaining(HashTable* ht, const char* key) {
    unsigned int index = hash_function(key);
    HashEntry* current = ht->table[index];
    
    // Search through the chain
    while (current != NULL) {
        if (strcmp(current->key, key) == 0) {
            return current;
        }
        current = current->next;
    }
    return NULL;
}

// Method 2: Linear Probing (Open Addressing)
typedef struct {
    char key[MAX_STRING];
    int value;
    int occupied;  // 0 = empty, 1 = occupied, 2 = deleted
} LinearEntry;

typedef struct {
    LinearEntry table[TABLE_SIZE];
    int size;
} LinearHashTable;

void init_linear_table(LinearHashTable* ht) {
    for (int i = 0; i < TABLE_SIZE; i++) {
        ht->table[i].occupied = 0;
    }
    ht->size = 0;
}

void insert_linear_probing(LinearHashTable* ht, const char* key, int value) {
    unsigned int index = hash_function(key);
    int original_index = index;
    
    // Find empty slot
    while (ht->table[index].occupied == 1) {
        index = (index + 1) % TABLE_SIZE;
        if (index == original_index) {
            printf("Hash table is full!\n");
            return;
        }
    }
    
    // Insert at found slot
    strcpy(ht->table[index].key, key);
    ht->table[index].value = value;
    ht->table[index].occupied = 1;
    ht->size++;
}

LinearEntry* lookup_linear_probing(LinearHashTable* ht, const char* key) {
    unsigned int index = hash_function(key);
    int original_index = index;
    
    // Search until we find the key or an empty slot
    while (ht->table[index].occupied != 0) {
        if (ht->table[index].occupied == 1 && 
            strcmp(ht->table[index].key, key) == 0) {
            return &ht->table[index];
        }
        index = (index + 1) % TABLE_SIZE;
        if (index == original_index) {
            break;  // Wrapped around, key not found
        }
    }
    return NULL;
}

// Method 3: Quadratic Probing
void insert_quadratic_probing(LinearHashTable* ht, const char* key, int value) {
    unsigned int index = hash_function(key);
    int original_index = index;
    int i = 0;
    
    // Find empty slot using quadratic probing
    while (ht->table[index].occupied == 1) {
        i++;
        index = (original_index + i * i) % TABLE_SIZE;
        if (i >= TABLE_SIZE) {
            printf("Hash table is full!\n");
            return;
        }
    }
    
    // Insert at found slot
    strcpy(ht->table[index].key, key);
    ht->table[index].value = value;
    ht->table[index].occupied = 1;
    ht->size++;
}

// Method 4: Double Hashing
unsigned int hash_function2(const char* key) {
    unsigned int hash = 0;
    for (int i = 0; key[i]; i++) {
        hash = hash * 17 + key[i];
    }
    return hash % (TABLE_SIZE - 1) + 1;  // Must be coprime with TABLE_SIZE
}

void insert_double_hashing(LinearHashTable* ht, const char* key, int value) {
    unsigned int index = hash_function(key);
    unsigned int step = hash_function2(key);
    int original_index = index;
    
    // Find empty slot using double hashing
    while (ht->table[index].occupied == 1) {
        index = (index + step) % TABLE_SIZE;
        if (index == original_index) {
            printf("Hash table is full!\n");
            return;
        }
    }
    
    // Insert at found slot
    strcpy(ht->table[index].key, key);
    ht->table[index].value = value;
    ht->table[index].occupied = 1;
    ht->size++;
}

// Method 5: Cuckoo Hashing
#define CUCKOO_SIZE 11
#define CUCKOO_HASHES 2

typedef struct {
    char key[MAX_STRING];
    int value;
    int occupied;
} CuckooEntry;

typedef struct {
    CuckooEntry table[CUCKOO_SIZE];
    int size;
} CuckooHashTable;

unsigned int cuckoo_hash1(const char* key) {
    unsigned int hash = 0;
    for (int i = 0; key[i]; i++) {
        hash = hash * 31 + key[i];
    }
    return hash % CUCKOO_SIZE;
}

unsigned int cuckoo_hash2(const char* key) {
    unsigned int hash = 0;
    for (int i = 0; key[i]; i++) {
        hash = hash * 17 + key[i] + i;
    }
    return hash % CUCKOO_SIZE;
}

void init_cuckoo_table(CuckooHashTable* ht) {
    for (int i = 0; i < CUCKOO_SIZE; i++) {
        ht->table[i].occupied = 0;
    }
    ht->size = 0;
}

int insert_cuckoo(CuckooHashTable* ht, const char* key, int value) {
    char current_key[MAX_STRING];
    int current_value = value;
    strcpy(current_key, key);
    
    // Try to insert, evicting if necessary
    for (int attempts = 0; attempts < CUCKOO_SIZE * 2; attempts++) {
        unsigned int h1 = cuckoo_hash1(current_key);
        unsigned int h2 = cuckoo_hash2(current_key);
        
        // Try first hash
        if (!ht->table[h1].occupied) {
            strcpy(ht->table[h1].key, current_key);
            ht->table[h1].value = current_value;
            ht->table[h1].occupied = 1;
            ht->size++;
            return 1;  // Success
        }
        
        // Try second hash
        if (!ht->table[h2].occupied) {
            strcpy(ht->table[h2].key, current_key);
            ht->table[h2].value = current_value;
            ht->table[h2].occupied = 1;
            ht->size++;
            return 1;  // Success
        }
        
        // Both occupied, evict from first hash
        char evicted_key[MAX_STRING];
        int evicted_value;
        strcpy(evicted_key, ht->table[h1].key);
        evicted_value = ht->table[h1].value;
        
        strcpy(ht->table[h1].key, current_key);
        ht->table[h1].value = current_value;
        
        strcpy(current_key, evicted_key);
        current_value = evicted_value;
    }
    
    printf("Cuckoo hashing failed - too many evictions\n");
    return 0;  // Failed
}

// Test functions
void test_chaining() {
    printf("1. Separate Chaining (Linked Lists):\n");
    printf("====================================\n");
    
    HashTable ht;
    init_hash_table(&ht);
    
    const char* test_keys[] = {
        "int", "char", "float", "double", "void", "if", "else", "while",
        "for", "return", "break", "continue", "switch", "case", "default"
    };
    
    // Insert keys
    for (int i = 0; i < 15; i++) {
        insert_chaining(&ht, test_keys[i], i + 1);
        printf("Inserted: %s -> %d (hash: %u)\n", 
               test_keys[i], i + 1, hash_function(test_keys[i]));
    }
    
    printf("\nHash Table State:\n");
    for (int i = 0; i < TABLE_SIZE; i++) {
        printf("Bucket %d: ", i);
        HashEntry* current = ht.table[i];
        while (current != NULL) {
            printf("%s ", current->key);
            current = current->next;
        }
        printf("\n");
    }
    
    printf("\nLookup Test:\n");
    HashEntry* result = lookup_chaining(&ht, "int");
    if (result) {
        printf("Found: %s -> %d\n", result->key, result->value);
    }
    
    printf("\n");
}

void test_linear_probing() {
    printf("2. Linear Probing (Open Addressing):\n");
    printf("====================================\n");
    
    LinearHashTable ht;
    init_linear_table(&ht);
    
    const char* test_keys[] = {
        "int", "char", "float", "double", "void", "if", "else", "while"
    };
    
    // Insert keys
    for (int i = 0; i < 8; i++) {
        insert_linear_probing(&ht, test_keys[i], i + 1);
        printf("Inserted: %s -> %d (hash: %u)\n", 
               test_keys[i], i + 1, hash_function(test_keys[i]));
    }
    
    printf("\nHash Table State:\n");
    for (int i = 0; i < TABLE_SIZE; i++) {
        if (ht.table[i].occupied == 1) {
            printf("Slot %d: %s -> %d\n", i, ht.table[i].key, ht.table[i].value);
        } else {
            printf("Slot %d: [empty]\n", i);
        }
    }
    
    printf("\nLookup Test:\n");
    LinearEntry* result = lookup_linear_probing(&ht, "int");
    if (result) {
        printf("Found: %s -> %d\n", result->key, result->value);
    }
    
    printf("\n");
}

void test_quadratic_probing() {
    printf("3. Quadratic Probing:\n");
    printf("====================\n");
    
    LinearHashTable ht;
    init_linear_table(&ht);
    
    const char* test_keys[] = {
        "int", "char", "float", "double", "void", "if", "else", "while"
    };
    
    // Insert keys
    for (int i = 0; i < 8; i++) {
        insert_quadratic_probing(&ht, test_keys[i], i + 1);
        printf("Inserted: %s -> %d (hash: %u)\n", 
               test_keys[i], i + 1, hash_function(test_keys[i]));
    }
    
    printf("\nHash Table State:\n");
    for (int i = 0; i < TABLE_SIZE; i++) {
        if (ht.table[i].occupied == 1) {
            printf("Slot %d: %s -> %d\n", i, ht.table[i].key, ht.table[i].value);
        } else {
            printf("Slot %d: [empty]\n", i);
        }
    }
    
    printf("\n");
}

void test_double_hashing() {
    printf("4. Double Hashing:\n");
    printf("==================\n");
    
    LinearHashTable ht;
    init_linear_table(&ht);
    
    const char* test_keys[] = {
        "int", "char", "float", "double", "void", "if", "else", "while"
    };
    
    // Insert keys
    for (int i = 0; i < 8; i++) {
        insert_double_hashing(&ht, test_keys[i], i + 1);
        printf("Inserted: %s -> %d (hash1: %u, hash2: %u)\n", 
               test_keys[i], i + 1, hash_function(test_keys[i]), hash_function2(test_keys[i]));
    }
    
    printf("\nHash Table State:\n");
    for (int i = 0; i < TABLE_SIZE; i++) {
        if (ht.table[i].occupied == 1) {
            printf("Slot %d: %s -> %d\n", i, ht.table[i].key, ht.table[i].value);
        } else {
            printf("Slot %d: [empty]\n", i);
        }
    }
    
    printf("\n");
}

void test_cuckoo_hashing() {
    printf("5. Cuckoo Hashing:\n");
    printf("==================\n");
    
    CuckooHashTable ht;
    init_cuckoo_table(&ht);
    
    const char* test_keys[] = {
        "int", "char", "float", "double", "void", "if", "else", "while"
    };
    
    // Insert keys
    for (int i = 0; i < 8; i++) {
        int success = insert_cuckoo(&ht, test_keys[i], i + 1);
        printf("Inserted: %s -> %d (hash1: %u, hash2: %u) %s\n", 
               test_keys[i], i + 1, cuckoo_hash1(test_keys[i]), cuckoo_hash2(test_keys[i]),
               success ? "SUCCESS" : "FAILED");
    }
    
    printf("\nHash Table State:\n");
    for (int i = 0; i < CUCKOO_SIZE; i++) {
        if (ht.table[i].occupied == 1) {
            printf("Slot %d: %s -> %d\n", i, ht.table[i].key, ht.table[i].value);
        } else {
            printf("Slot %d: [empty]\n", i);
        }
    }
    
    printf("\n");
}

int main() {
    printf("Hash Table Collision Resolution Methods:\n");
    printf("=======================================\n\n");
    
    test_chaining();
    test_linear_probing();
    test_quadratic_probing();
    test_double_hashing();
    test_cuckoo_hashing();
    
    printf("Collision Resolution Comparison:\n");
    printf("===============================\n");
    printf("1. Separate Chaining:\n");
    printf("   ✓ Simple to implement\n");
    printf("   ✓ No clustering\n");
    printf("   ✓ Can store more than table size\n");
    printf("   ✗ Extra memory for pointers\n");
    printf("   ✗ Cache unfriendly\n\n");
    
    printf("2. Linear Probing:\n");
    printf("   ✓ Cache friendly\n");
    printf("   ✓ No extra memory\n");
    printf("   ✗ Primary clustering\n");
    printf("   ✗ Performance degrades with load factor\n\n");
    
    printf("3. Quadratic Probing:\n");
    printf("   ✓ Reduces primary clustering\n");
    printf("   ✓ Cache friendly\n");
    printf("   ✗ Secondary clustering\n");
    printf("   ✗ May not find empty slot even if one exists\n\n");
    
    printf("4. Double Hashing:\n");
    printf("   ✓ Best probing method\n");
    printf("   ✓ Reduces clustering\n");
    printf("   ✓ Good distribution\n");
    printf("   ✗ More complex hash function\n\n");
    
    printf("5. Cuckoo Hashing:\n");
    printf("   ✓ O(1) worst-case lookup\n");
    printf("   ✓ No clustering\n");
    printf("   ✗ Complex insertion\n");
    printf("   ✗ May fail to insert\n");
    printf("   ✗ Requires rehashing on failure\n\n");
    
    printf("Real-World Usage:\n");
    printf("================\n");
    printf("- Java HashMap: Separate chaining + tree for long chains\n");
    printf("- Python dict: Open addressing with random probing\n");
    printf("- C++ unordered_map: Separate chaining\n");
    printf("- Go map: Bucket-based with overflow buckets\n");
    printf("- Rust HashMap: Robin Hood hashing (linear probing variant)\n");
    
    return 0;
}
