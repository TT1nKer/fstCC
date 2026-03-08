# fstCC — A Self-Hosting C Compiler, Built From Scratch

A C compiler bootstrapped from a single hand-written RISC-V assembly file — no libc, no LLVM, no external frameworks. The compiler understands real C code and produces working RISC-V binaries.

**Stage 0 is complete: 39/39 tests pass**, including recursion, arithmetic, and multi-function programs.

---

## What This Is

Most compilers are written in a high-level language and rely on existing compilers to build themselves. This project starts with nothing — just raw assembly — and builds upward:

```
Stage 0: fstcc0                Stage 1: fstcc1 (next)         Stage 2
┌──────────────────────┐       ┌──────────────────────┐       ┌─────────────────┐
│  src/fstcc0.s        │  →    │  fstcc1.c             │  →   │  fstcc1 compiles│
│  ~2500 lines         │       │  written in L0 C      │       │  itself         │
│  hand-written RV64   │       │  compiled by fstcc0   │       │  self-hosting ✓ │
│  emits .s text       │       │  understands L1 C     │       │                 │
└──────────────────────┘       └──────────────────────┘       └─────────────────┘
```

**The pipeline:**
```
your_program.c  →  fstcc0  →  out.s  →  riscv64-linux-gnu-as  →  out.o  →  riscv64-linux-gnu-ld  →  binary
```

---

## Technical Highlights

- **Single-file compiler** — `bootstrap/src/fstcc0.s` (~2500 lines of RISC-V assembly)
- **No dependencies** — uses only Linux syscalls (`mmap`, `write`, `exit`)
- **Recursive-descent parser** — full expression precedence without a parser generator
- **Text-mode codegen** — emits readable `.s` assembly; GNU tools handle symbol resolution
- **Zero backpatching** — `if/else` and `while` use symbolic labels (`.L0`, `.L1`, ...), making the code simple and auditable
- **Frame pointer discipline** — proper RISC-V ABI: `s0` as frame pointer, `ra` saved/restored, 16-byte aligned frames
- **Recursion works** — `fact(5)` = 120, `fib(10)` = 55

---

## Supported Language (L0 C)

```c
// Variables and assignment
int x = 10;
x = x * 2 + 1;

// All arithmetic and comparisons
int r = (a + b) * c / 2 % 10;
if (x >= 0 && y != 3) { ... }

// Control flow
while (i < n) { i = i + 1; }
if (cond) { ... } else { ... }

// Functions with up to 8 parameters, recursion
int fact(int n) {
    if (n <= 1) return 1;
    return n * fact(n - 1);
}
int main() { return fact(5); }  // exit code: 120
```

---

## Test Results

```
M0 — Return constant         3/3   ✓
M1 — Local variables         4/4   ✓
M2 — Arithmetic              7/7   ✓
M3 — Comparisons & logical  16/16  ✓
M4 — if/else, while, calls   9/9   ✓
─────────────────────────────────────
Total                       39/39  ✓
```

See [bootstrap/test/proof/stage0_proof.md](bootstrap/test/proof/stage0_proof.md) for generated assembly and verified outputs.

---

## Quick Start

**Requirements** (Ubuntu/Debian/WSL2):
```bash
sudo apt install gcc-riscv64-linux-gnu qemu-user
```

**Build and test:**
```bash
cd bootstrap
make              # assemble fstcc0 from src/fstcc0.s
make test-suite   # run all 39 tests
make run N=42     # compile and run 'return 42'
```

**Compile your own program:**
```bash
# Step 1: C → assembly text
qemu-riscv64 build/fstcc0 your_program.c out.s

# Step 2: assemble + link
riscv64-linux-gnu-as out.s -o out.o
riscv64-linux-gnu-ld out.o -o out

# Step 3: run
qemu-riscv64 out; echo $?
```

Or in one step:
```bash
make test FILE=your_program.c   # compiles, prints .s, runs
```

---

## Project Structure

```
fstCC/
├── README.md                        ← you are here
├── ROADMAP.md                       ← full plan M0 → self-hosting
├── Makefile                         ← root (delegates to bootstrap/)
├── bootstrap/                       ← Stage 0: fstcc0 (COMPLETE)
│   ├── README.md                    ← Stage 0 usage
│   ├── Makefile
│   ├── src/
│   │   └── fstcc0.s                 ← the compiler (~2500 lines)
│   └── test/
│       ├── run_tests.sh             ← 39-test suite
│       └── proof/
│           └── stage0_proof.md      ← test results + generated assembly
└── doc/
    └── riscv-cheatsheet.md          ← RISC-V reference
```

---

## How fstcc0 Works Internally

```
open input.c via mmap
         │
         ▼
    ┌─────────┐
    │  Lexer  │  character stream → token stream
    │         │  (identifiers, numbers, keywords, operators)
    └────┬────┘
         │
         ▼
    ┌─────────────────────────────────────┐
    │  Recursive-Descent Parser           │
    │                                     │
    │  program → funcdef*                 │
    │  funcdef → int name(params) block   │
    │  block   → { stmt* }               │
    │  stmt    → return | if | while |    │
    │            vardecl | expr;          │
    │  expr    → or → and → eq → rel →   │
    │            add → mul → unary →      │
    │            primary                  │
    └────┬────────────────────────────────┘
         │
         ▼ (body buffered in g_out_buf)
    ┌────────────────────────┐
    │  Text-mode Codegen     │
    │                        │
    │  emit_li_a0(n)         │  →  "\tli\ta0, N\n"
    │  emit_push_a0()        │  →  "\taddi sp, sp, -8\n\tsd a0, 0(sp)\n"
    │  emit_label_def(N)     │  →  ".LN:\n"
    │  emit_beqz_label(N)    │  →  "\tbeqz a0, .LN\n"
    │  flush_func()          │  →  write prologue + body to out_fd
    └────┬───────────────────┘
         │
         ▼
     out.s (readable RISC-V assembly)
         │
    riscv64-linux-gnu-as → riscv64-linux-gnu-ld → binary
```

Key design decisions:
- **Body buffer first** — function body is emitted to `g_out_buf`, then `flush_func` writes the prologue with the correct frame size in front. No two-pass layout needed.
- **Symbolic labels** — `alloc_label()` returns a counter; `if/else/while` emit `.LN:` labels. The GNU assembler resolves them. No backpatching.
- **Stack-based expression evaluation** — binary ops push left operand, evaluate right, pop into `a1`, operate. Simple and correct.

---

## Roadmap

| Stage | Status | Description |
|-------|--------|-------------|
| M0–M4 | **Done** | fstcc0: hand-written assembly compiler, L0 C subset |
| M5 | Next | fstcc1: write a fuller compiler in L0 C, compiled by fstcc0 |
| M6 | Future | Verify fstcc1 built by fstcc0 passes all tests |
| M7 | Future | fstcc1 compiles itself — self-hosting achieved |

Full details in [ROADMAP.md](ROADMAP.md).
