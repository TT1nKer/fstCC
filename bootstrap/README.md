# fstCC - Bootstrap C Compiler

A self-hosting C compiler written from scratch, starting with RISC-V assembly.

## Requirements

- `riscv64-linux-gnu-as` (assembler)
- `riscv64-linux-gnu-ld` (linker)
- `qemu-riscv64` (emulator)

Ubuntu/Debian:
```bash
sudo apt install gcc-riscv64-linux-gnu qemu-user
```

## Build

```bash
make          # build the compiler
```

## Usage

```bash
# Quick test with a number
make run N=42

# Compile a file
make test FILE=test/test.c

# Or manually:
qemu-riscv64 build/fstcc0 test/test.c build/out.s
```

## Bootstrap Stages

| Stage | Source | Compiles |
|-------|--------|----------|
| 0 | `src/fstcc0.s` (assembly) | `return N;` |
| 0.2 | (coming) | `return N + N;` |
| 1 | (future) | variables, if/else |
| 2 | (future) | while, functions |
| N | (future) | full C, self-hosting |

## Project Structure

```
fstCC/
├── src/           # compiler source code
├── build/         # generated files (gitignored)
├── test/          # test C files
├── Makefile
└── README.md
```
