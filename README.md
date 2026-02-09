# fstCC - First Self-hosting Tiny C Compiler

A bootstrap C compiler that compiles a minimal subset of C to x86-64 assembly, with the ultimate goal of self-hosting.

## Project Structure

```
fstCC/
├── src/                    # Compiler source (modular)
│   ├── main.c              # CLI entry point & file I/O
│   ├── common.h            # Shared types (TokenType, Token)
│   ├── lexer.h / lexer.c   # Lexical analysis
│   ├── parser.h / parser.c # AST & recursive descent parser
│   ├── codegen.h / codegen.c # x86-64 code generation
│   └── symtab.h / symtab.c # Symbol table
│
├── bootstrap/              # Assembly bootstrap compiler (Stage 0)
│   └── fstccV001.s
│
├── lib/hashtable/          # Hash table research for keyword lookup
│   ├── perfect_hash.c      # Perfect hash implementations
│   ├── collision_resolution.c
│   └── analysis/           # Mathematical analysis & visualization
│
├── examples/               # Demo programs & test cases
├── tests/                  # Test suite (WIP)
├── scripts/                # Build scripts (Windows/Linux/WSL)
└── docs/                   # Reference papers
```

## Compiler Pipeline

```
Source Code (.c) → Lexer → Parser (AST) → Code Generator → x86-64 Assembly (.s)
```

## Building

```bash
# Build the compiler
make

# Run built-in test
make test

# Compile a C file
./build/fstcc input.c output.s
```

## Supported C Subset

- Data types: `int`
- Variables and assignments
- Arithmetic: `+`, `-`, `*`, `/`
- Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Control flow: `if/else`, `while`, `for`
- Functions: definition and calls
- Return statements

## Current Status

### Implemented
- Lexical analysis (tokenizer with keyword recognition)
- Recursive descent parser (expressions, statements, functions)
- AST construction and pretty-printing
- x86-64 AT&T syntax code generation
- Symbol table with stack-based variable allocation
- CLI interface with file I/O

### TODO
- [ ] `if/else` and `while` code generation
- [ ] Function calls and parameters
- [ ] `char` type and string literals
- [ ] Pointer operations
- [ ] Preprocessor (`#include`, `#define`)
- [ ] Self-hosting capability

## Bootstrap Strategy

1. **Stage 0**: Assembly compiler (`bootstrap/fstccV001.s`) - hand-written in x86-64 assembly
2. **Stage 1**: C compiler (`src/`) - compiled by Stage 0, extends language support
3. **Stage 2**: Self-hosting - the C compiler compiles itself

## License

Educational project demonstrating bootstrap compiler construction.
