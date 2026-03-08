# fstCC Roadmap — From Assembly to Self-Hosting

## The Bootstrap Ladder

```
Stage 0 (done)          Stage 1 (next)          Stage 2 (future)
┌────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ fstcc0         │ →    │ fstcc1           │ →    │ fstcc1 compiles │
│ hand-written   │      │ written in L0 C  │      │ itself          │
│ RV64 assembly  │      │ compiled by fstcc0│     │ self-hosting ✓  │
│ emits .s text  │      │ understands L1 C │      │                 │
└────────────────┘      └─────────────────┘      └─────────────────┘
```

---

## Language Levels

### L0 — What fstcc0 can compile (DONE)
- `int` type, integer literals
- Local variables: `int x = expr;`
- Arithmetic: `+ - * / %`
- Comparisons: `== != < > <= >=`
- Logical: `&& || !`
- Unary: `-expr`
- Control flow: `if/else`, `while`
- Functions: definition, parameters (up to 8), calls, `return`
- Assignment: `x = expr`
- Single-file, no preprocessor

### L1 — What fstcc1 needs to understand (Stage 1 target)
Everything in L0 plus:
- `char` type, character literals `'a'`
- String literals `"hello"` (pointer to .rodata)
- Pointers: `*ptr`, `&var`, pointer arithmetic
- Arrays: `int arr[N]`, `arr[i]`
- `for` loops
- `#include "file"` (simple file paste)
- `#define NAME value` (simple substitution)
- `sizeof`

---

## Milestones

### ✅ M0: Return Constant
fstcc0 compiles `int main() { return 42; }` → working RISC-V binary.
- [x] Syscall-based I/O (mmap input, write output)
- [x] Lexer: keywords, identifiers, integers, operators
- [x] Parser: function definition, return statement
- [x] Codegen: emit `.s` text → assembled + linked by GNU tools

### ✅ M1: Local Variables
- [x] Symbol table: name → frame-pointer offset
- [x] `int x = expr;` and `int x;` declarations
- [x] Variable load and store (`ld`/`sd` relative to `s0`)
- [x] Assignment expression `x = expr`

### ✅ M2: Arithmetic
- [x] Binary: `+ - * / %`
- [x] Unary: `-expr`
- [x] Correct operator precedence (mul > add > compare > logical)
- [x] Push/pop stack for nested expression temporaries

### ✅ M3: Comparisons and Logical Operators
- [x] `== != < > <= >=` → `slt`/`seqz`/`snez` sequences
- [x] `&&` `||` → snez + and/or
- [x] `!` → seqz

### ✅ M4: Control Flow and Functions
- [x] `if/else` → symbolic labels `.LN`, no backpatching
- [x] `while` → loop-top + exit labels
- [x] Function calls: emit `call NAME` (GNU assembler resolves)
- [x] Up to 8 arguments via `a0-a7`
- [x] Recursion works (tested: `fact(5) = 120`)

**39/39 tests pass. fstcc0 is complete.**

---

### 🔲 M5: Write fstcc1 in L0 C
Goal: a fuller compiler, written in the subset fstcc0 already handles.

- [ ] Pointer types and dereferencing
- [ ] `char` and string literals → `.rodata` section
- [ ] Array declarations and indexing
- [ ] `for` loops
- [ ] `#include "file"` (read and paste file)
- [ ] `#define NAME value`
- [ ] Write output via `write()` syscall wrappers (no libc)
- [ ] Emit proper RISC-V assembly for all L1 features

Compiled with:
```bash
qemu-riscv64 build/fstcc0 src/fstcc1.c build/fstcc1.s
riscv64-linux-gnu-as build/fstcc1.s -o build/fstcc1.o
riscv64-linux-gnu-ld build/fstcc1.o -o build/fstcc1
```

### 🔲 M6: Bootstrap Verification
Goal: fstcc1 compiled by fstcc0 passes all tests.

- [ ] fstcc0 compiles all fstcc1 source files
- [ ] Linked fstcc1 binary runs correctly
- [ ] fstcc1 passes the same test suite as fstcc0

### 🔲 M7: Self-Hosting
Goal: fstcc1 compiles itself.

- [ ] `fstcc1` compiles `fstcc1.c` → `fstcc2`
- [ ] `fstcc2` compiles `fstcc1.c` → `fstcc3`
- [ ] `fstcc2` binary == `fstcc3` binary (fixed point)

Bootstrap complete. ✓
