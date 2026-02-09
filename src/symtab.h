#ifndef FSTCC_SYMTAB_H
#define FSTCC_SYMTAB_H

#include "common.h"

/* Symbol entry */
typedef struct {
    char *name;
    int offset;    /* Stack offset from %rbp */
} Symbol;

/* Symbol table */
typedef struct {
    Symbol *symbols;
    int count;
    int capacity;
    int current_offset;
} SymbolTable;

/* Global symbol table */
extern SymbolTable symbol_table;

/* Symbol table functions */
void symbol_table_init(void);
void symbol_table_add(char *name);
int symbol_table_lookup(char *name);

#endif /* FSTCC_SYMTAB_H */
