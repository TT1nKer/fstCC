# fstCC Roadmap — From Assembly to Self-Hosting
## Target: RISC-V 64-bit (RV64IMAC, LP64 ABI)

## The Bootstrap Ladder

```
Stage 0 (Assembly)         Stage 1 (C)                Self-Hosting
┌────────────────┐         ┌─────────────────┐        ┌─────────────────┐
│ fstcc0.s       │ builds  │ src/*.c          │ builds │ src/*.c compiles│
│ hand-written   │-------->│ written in L0 C  │------->│ itself          │
│ RV64 assembly  │         │ Understands L1   │        │                 │
│ Understands L0 │         │ Emits RV64 asm   │        │                 │
└────────────────┘         └─────────────────┘        └─────────────────┘
```

## RISC-V Quick Reference

```
Registers:
  x0 (zero)     - hardwired zero
  x1 (ra)       - return address
  x2 (sp)       - stack pointer
  x5-x7 (t0-t2) - temporaries
  x8 (s0/fp)    - frame pointer / saved
  x9 (s1)       - saved
  x10-x17 (a0-a7) - function args / return values
  x18-x27 (s2-s11) - saved registers
  x28-x31 (t3-t6)  - temporaries

Linux syscalls: ecall with a7=syscall#, args in a0-a5
  exit=93, read=63, write=64, openat=56, close=57
```

## Language Levels

### L0 — Minimal C (Stage 0 can compile this)
- `int` type, integer literals
- Variables: `int x = expr;`
- Arithmetic: `+ - * /`
- Comparisons: `== != < > <= >=`
- Control flow: `if/else`, `while`
- Functions: definition, parameters, calls, return
- Single-file only, no #include

### L1 — Extended C (Stage 1 can compile this = self-hosting target)
- Everything in L0 plus:
- `char` type, character literals (`'a'`), string literals (`"hello"`)
- Pointers: `*ptr`, `&var`, pointer arithmetic
- Arrays: `int arr[N]`, `arr[i]`
- `for` loops
- `#include "file"` (simple file paste)
- `#define NAME value` (simple substitution)

## Milestones

### M0: Return Constant
**Goal**: Stage 0 compiles `int main() { return 42; }` → working executable

- [ ] Entry point: parse argv, open/read/write files via Linux RV64 syscalls
- [ ] Lexer: tokenize identifiers, numbers, keywords, punctuation
- [ ] Parser: parse `int name() { return NUMBER; }`
- [ ] Codegen: emit `_start`, function prologue/epilogue using `sp`/`ra`

**Test**: `echo $?` after running compiled program outputs `42`

### M1: Arithmetic Expressions
**Goal**: Stage 0 handles expressions with `+ - * /` and parentheses

- [ ] Parse binary expressions with operator precedence
- [ ] Codegen: use temporaries (`t0-t6`) and stack for nested expressions

**Test**: `return 2 + 3 * 4;` → exit code 14

### M2: Variables
**Goal**: Stage 0 handles variable declarations and references

- [ ] Symbol table: name → stack offset mapping
- [ ] `int x = expr;` → `sw`/`sd` to stack frame
- [ ] Variable reference in expressions → `lw`/`ld` from stack

**Test**: `int a = 5; int b = 3; int c = a * b + 2; return c;` → exit code 17

### M3: Comparisons + If/Else
**Goal**: Stage 0 handles comparison operators and conditional branching

- [ ] Comparison operators → `slt`, `seqz`, etc.
- [ ] `if (expr) { ... }` → `beqz`/`bnez` conditional branch
- [ ] `if (expr) { ... } else { ... }` → full branching with `j`
- [ ] Label generation with unique counters

**Test**: `if (5 > 3) { return 1; } else { return 0; }` → exit code 1

### M4: While Loops + Functions
**Goal**: Stage 0 handles while loops and function definitions with parameters

- [ ] `while (expr) { ... }` → loop with back-edge (`j` to loop top)
- [ ] Function parameters (RISC-V ABI: a0-a7)
- [ ] Function calls in expressions: `name(arg1, arg2, ...)`
- [ ] Callee-saved registers (`s0-s11`, `ra`) saved/restored in prologue/epilogue
- [ ] L0 complete — Stage 0 can now compile Stage 1

**Test**: Recursive fibonacci → correct result

---

### M5: Stage 1 in C *(current milestone)*
**Goal**: Write src/ as a complete L1 compiler, compiled by gcc

- [ ] char type and character literals
- [ ] String literals (stored in .rodata)
- [ ] Pointer types, `*deref`, `&address`
- [ ] Array declarations and indexing
- [ ] `for` loops
- [ ] `#include "file"` preprocessor
- [ ] `#define` simple macros

### M6: Bootstrap Verification
**Goal**: Stage 0 compiles src/ into a working Stage 1 compiler

- [ ] Stage 0 compiles each src/*.c file individually
- [ ] Link Stage 1 object files into fstcc_stage1
- [ ] fstcc_stage1 passes all test cases
- [ ] Output matches gcc-compiled version

### M7: Self-Hosting
**Goal**: Stage 1 compiles itself — the compiler is self-hosting

- [ ] fstcc_stage1 compiles src/ → fstcc_stage2
- [ ] fstcc_stage2 compiles src/ → fstcc_stage3
- [ ] fstcc_stage2 binary == fstcc_stage3 binary (fixed point reached)
