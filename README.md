# fstCC - First Self-hosting Tiny C Compiler

A bootstrap C compiler written in assembly language, following the traditional bootstrap approach.

## Project Structure

- `fstccV001.s` - Main assembly source code for the bootstrap compiler
- `11-ghuloum.pdf` - Reference paper on incremental compiler construction

## Current Status

**Version 0.01** - Basic assembly structure implemented

### Implemented Features
- ✅ Basic assembly structure and memory layout
- ✅ Compiler pipeline framework
- ✅ Buffer management for source code, tokens, and assembly output
- ✅ Function stubs for all compiler phases

### TODO
- [ ] Command line argument parsing
- [ ] File I/O operations
- [ ] Lexical analysis (tokenizer)
- [ ] Syntax analysis (parser)
- [ ] Code generation
- [ ] Self-hosting capability

## Compiler Pipeline

```
Source Code → Lexer → Parser → Code Generator → Assembly Output
```

## Target Architecture

- **Platform**: x86-64 Linux
- **Language**: Assembly (NASM syntax)
- **Output**: Assembly code

## Minimal C Subset

The compiler will support a minimal subset of C:

- Basic data types: `int`, `char`, pointers
- Variables and assignments
- Basic arithmetic: `+`, `-`, `*`, `/`
- Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Control flow: `if/else`, `while`
- Functions: definition and calls
- Arrays and basic pointers
- Simple preprocessor: `#include`, `#define`

## Bootstrap Goal

The ultimate goal is to create a compiler that can compile its own source code, achieving self-hosting capability.

## Building

```bash
# Assemble the compiler
nasm -f elf64 fstccV001.s -o fstccV001.o
ld fstccV001.o -o fstcc

# Run the compiler
./fstcc input.c output.s
```

## License

This project is for educational purposes, demonstrating the bootstrap compiler construction process.
