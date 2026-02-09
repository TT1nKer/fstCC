#include "symtab.h"

/* Global symbol table */
SymbolTable symbol_table;

/* Initialize symbol table */
void symbol_table_init(void) {
    symbol_table.symbols = malloc(sizeof(Symbol) * 100);
    symbol_table.count = 0;
    symbol_table.capacity = 100;
    symbol_table.current_offset = -8;  /* Start at -8(%rbp) for first variable */
}

/* Add a variable to symbol table */
void symbol_table_add(char *name) {
    if (symbol_table.count >= symbol_table.capacity) {
        printf("Error: Symbol table overflow\n");
        exit(1);
    }

    Symbol *sym = &symbol_table.symbols[symbol_table.count];
    sym->name = malloc(strlen(name) + 1);
    strcpy(sym->name, name);
    sym->offset = symbol_table.current_offset;
    symbol_table.current_offset -= 8;  /* Each variable takes 8 bytes */
    symbol_table.count++;
}

/* Look up a variable in symbol table, returns stack offset */
int symbol_table_lookup(char *name) {
    for (int i = 0; i < symbol_table.count; i++) {
        if (strcmp(symbol_table.symbols[i].name, name) == 0) {
            return symbol_table.symbols[i].offset;
        }
    }
    printf("Error: Undefined variable '%s'\n", name);
    exit(1);
}
