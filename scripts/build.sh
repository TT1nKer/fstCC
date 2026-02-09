#!/bin/bash
# fstCC Bootstrap Build Script
# Run from build/ subfolder

echo "=== fstCC Bootstrap Build Process ==="

echo "Stage 0: Building Assembly Compiler..."
# Assemble the assembly compiler (from parent directory)
nasm -f elf64 ../fstccV001.s -o fstccV001.o
ld fstccV001.o -o fstcc_asm

echo "Stage 1: Building C Compiler with Assembly Compiler..."
# Use assembly compiler to compile C compiler
./fstcc_asm ../fstccV001.c fstccV001_asm.s

echo "Stage 2: Assembling C Compiler..."
# Assemble the C compiler
nasm -f elf64 fstccV001_asm.s -o fstccV001_c.o
ld fstccV001_c.o -o fstcc_c

echo "Stage 3: Self-Hosting Test..."
# Use C compiler to compile itself
./fstcc_c ../fstccV001.c fstccV001_self.s

echo "Bootstrap Complete!"
echo "Files created in build/ directory:"
echo "  fstcc_asm    - Assembly compiler"
echo "  fstcc_c      - C compiler"
echo "  fstccV001_asm.s  - Assembly output from C compiler"
echo "  fstccV001_self.s - Self-compiled output"
