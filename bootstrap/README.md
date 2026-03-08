# fstCC Stage 0 — fstcc0

Hand-written RISC-V assembly compiler. Takes a C subset and emits RISC-V assembly text.

## Build

```bash
make          # produces build/fstcc0
```

## Usage

```bash
# Compile a C file to assembly, then assemble and link:
qemu-riscv64 build/fstcc0 input.c output.s
riscv64-linux-gnu-as output.s -o output.o
riscv64-linux-gnu-ld output.o -o output
qemu-riscv64 output

# Makefile shortcuts:
make run N=42            # compile 'return 42;' inline, print result
make test FILE=foo.c     # compile foo.c, show assembly, run it
make test-suite          # run all 39 tests
```

## Test Results

```
m0_return_0              PASS    m3_lt_true               PASS
m0_return_1              PASS    m3_lt_false              PASS
m0_return_42             PASS    m3_gt_true               PASS
m1_var_decl              PASS    m3_le_true               PASS
m1_var_init              PASS    m3_ge_true               PASS
m1_var_assign            PASS    m3_not_true              PASS
m1_two_vars              PASS    m3_not_false             PASS
m2_add                   PASS    m3_and_tt                PASS
m2_sub                   PASS    m3_and_tf                PASS
m2_mul                   PASS    m3_or_ff                 PASS
m2_div                   PASS    m3_or_tf                 PASS
m2_mod                   PASS    m4_if_taken              PASS
m2_neg                   PASS    m4_if_not_taken          PASS
m2_compound              PASS    m4_if_else_true          PASS
m3_eq_true               PASS    m4_if_else_false         PASS
m3_eq_false              PASS    m4_while_0               PASS
m3_neq_true              PASS    m4_while_sum             PASS
m3_neq_false             PASS    m4_funcall               PASS
                                 m4_funcall_arg           PASS
                                 m4_funcall_args2         PASS
                                 m4_recursive             PASS
39/39 passed
```

## What fstcc0 Emits

For `int main() { return 42; }`:

```asm
	.text
	.globl _start
_start:
	call	main
	li	a7, 93
	ecall
	.globl	main
main:
	sd	ra, -8(sp)
	sd	s0, -16(sp)
	mv	s0, sp
	addi	sp, sp, -16
	li	a0, 42
	mv	sp, s0
	ld	ra, -8(s0)
	ld	s0, -16(s0)
	ret
```

## Requirements

```bash
sudo apt install gcc-riscv64-linux-gnu qemu-user
```
