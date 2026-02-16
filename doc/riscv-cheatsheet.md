# RISC-V Comprehensive Cheatsheet

## Instruction Naming Convention

RISC-V instructions follow a pattern:

```
[operation][size][sign]   or   [operation][immediate]

Examples:
  ld   = Load Doubleword (64-bit)
  lw   = Load Word (32-bit)
  lb   = Load Byte (8-bit)
  lbu  = Load Byte Unsigned
  addi = ADD Immediate
```

### Size Suffixes
| Suffix | Size | Bits |
|--------|------|------|
| b | Byte | 8 |
| h | Halfword | 16 |
| w | Word | 32 |
| d | Doubleword | 64 |

### Modifier Suffixes
| Suffix | Meaning |
|--------|---------|
| u | Unsigned |
| i | Immediate (constant value) |
| s | Signed (for shifts: arithmetic) |

---

## Registers

### General Purpose Registers (x0-x31)

```
┌──────────┬──────────┬─────────────────────────────┬────────┐
│ Register │ ABI Name │ Description                 │ Saver  │
├──────────┼──────────┼─────────────────────────────┼────────┤
│ x0       │ zero     │ Always zero (hardwired)     │ —      │
│ x1       │ ra       │ Return Address              │ Caller │
│ x2       │ sp       │ Stack Pointer               │ Callee │
│ x3       │ gp       │ Global Pointer              │ —      │
│ x4       │ tp       │ Thread Pointer              │ —      │
├──────────┼──────────┼─────────────────────────────┼────────┤
│ x5-x7    │ t0-t2    │ Temporaries                 │ Caller │
│ x28-x31  │ t3-t6    │ Temporaries                 │ Caller │
├──────────┼──────────┼─────────────────────────────┼────────┤
│ x8       │ s0 / fp  │ Saved reg / Frame Pointer   │ Callee │
│ x9       │ s1       │ Saved register              │ Callee │
│ x18-x27  │ s2-s11   │ Saved registers             │ Callee │
├──────────┼──────────┼─────────────────────────────┼────────┤
│ x10-x11  │ a0-a1    │ Arguments / Return values   │ Caller │
│ x12-x17  │ a2-a7    │ Arguments                   │ Caller │
└──────────┴──────────┴─────────────────────────────┴────────┘
```

### What "Caller/Callee Saved" Means

```
caller_function:
    li      t0, 100         # t0 = 100
    jal     other_function  # call another function
    # t0 might be DESTROYED here! (caller-saved)
    # s0 is PRESERVED here (callee-saved)
    
other_function:
    # If I want to use s0, I must save/restore it
    addi    sp, sp, -8
    sd      s0, 0(sp)       # save s0
    # ... use s0 ...
    ld      s0, 0(sp)       # restore s0
    addi    sp, sp, 8
    ret
```

---

## Load Instructions

**"Load" = Memory → Register**

### Instruction Breakdown

```
ld   rd, offset(rs1)
│    │   │      │
│    │   │      └── Base register (address)
│    │   └────────── Offset in bytes
│    └────────────── Destination register
└─────────────────── Load Doubleword (64-bit)
```

### All Load Instructions

| Instruction | Name | Bits | Sign Extension |
|-------------|------|------|----------------|
| `lb rd, off(rs1)` | Load Byte | 8 | Sign-extend to 64 |
| `lbu rd, off(rs1)` | Load Byte Unsigned | 8 | Zero-extend to 64 |
| `lh rd, off(rs1)` | Load Halfword | 16 | Sign-extend to 64 |
| `lhu rd, off(rs1)` | Load Halfword Unsigned | 16 | Zero-extend to 64 |
| `lw rd, off(rs1)` | Load Word | 32 | Sign-extend to 64 |
| `lwu rd, off(rs1)` | Load Word Unsigned | 32 | Zero-extend to 64 |
| `ld rd, off(rs1)` | Load Doubleword | 64 | — |

### Sign Extension Example

```
Memory contains: 0xFF (255 unsigned, -1 signed)

lb   a0, 0(t0)    # a0 = 0xFFFFFFFFFFFFFFFF (-1)
                  #      Sign bit (1) extended

lbu  a0, 0(t0)    # a0 = 0x00000000000000FF (255)
                  #      Zero extended
```

### Common Usage

```asm
# Load a 64-bit pointer
ld      a0, 0(sp)           # a0 = *(long *)sp

# Load a character (byte)
lbu     t0, 0(s0)           # t0 = *s0 (as unsigned char)

# Load from array: arr[i]
slli    t1, t0, 3           # t1 = i * 8 (for 64-bit elements)
add     t1, s0, t1          # t1 = &arr[i]
ld      a0, 0(t1)           # a0 = arr[i]
```

---

## Store Instructions

**"Store" = Register → Memory**

### Instruction Breakdown

```
sd   rs2, offset(rs1)
│    │    │      │
│    │    │      └── Base register (address)
│    │    └────────── Offset in bytes
│    └─────────────── Source register (value to store)
└──────────────────── Store Doubleword (64-bit)
```

### All Store Instructions

| Instruction | Name | Bits Stored |
|-------------|------|-------------|
| `sb rs2, off(rs1)` | Store Byte | 8 |
| `sh rs2, off(rs1)` | Store Halfword | 16 |
| `sw rs2, off(rs1)` | Store Word | 32 |
| `sd rs2, off(rs1)` | Store Doubleword | 64 |

### Common Usage

```asm
# Save return address to stack
sd      ra, 0(sp)           # *(long *)sp = ra

# Store a character
li      t0, 'A'
sb      t0, 0(s0)           # *s0 = 'A'

# Store to array: arr[i] = value
slli    t1, t0, 3           # t1 = i * 8
add     t1, s0, t1          # t1 = &arr[i]
sd      a0, 0(t1)           # arr[i] = a0
```

---

## Arithmetic Instructions

### Register-Register (R-type)

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `add rd, rs1, rs2` | Add | rd = rs1 + rs2 |
| `sub rd, rs1, rs2` | Subtract | rd = rs1 - rs2 |
| `mul rd, rs1, rs2` | Multiply | rd = (rs1 * rs2)[63:0] |
| `div rd, rs1, rs2` | Divide (signed) | rd = rs1 / rs2 |
| `divu rd, rs1, rs2` | Divide (unsigned) | rd = rs1 / rs2 |
| `rem rd, rs1, rs2` | Remainder (signed) | rd = rs1 % rs2 |
| `remu rd, rs1, rs2` | Remainder (unsigned) | rd = rs1 % rs2 |

### Register-Immediate (I-type)

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `addi rd, rs1, imm` | Add Immediate | rd = rs1 + imm |
| `li rd, imm` | Load Immediate | rd = imm (pseudo) |
| `mv rd, rs` | Move | rd = rs (pseudo: addi rd, rs, 0) |
| `neg rd, rs` | Negate | rd = -rs (pseudo: sub rd, zero, rs) |

### Examples

```asm
# Simple math
addi    a0, a0, 1           # a0++
addi    a0, a0, -1          # a0--
add     a0, a1, a2          # a0 = a1 + a2

# Multiply by constant (no muli instruction!)
li      t0, 10
mul     a0, a0, t0          # a0 = a0 * 10

# Division and remainder
li      t0, 10
div     a1, a0, t0          # a1 = a0 / 10
rem     a2, a0, t0          # a2 = a0 % 10
```

---

## Logical Instructions

### Bitwise Operations

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `and rd, rs1, rs2` | AND | rd = rs1 & rs2 |
| `or rd, rs1, rs2` | OR | rd = rs1 \| rs2 |
| `xor rd, rs1, rs2` | XOR | rd = rs1 ^ rs2 |
| `andi rd, rs1, imm` | AND Immediate | rd = rs1 & imm |
| `ori rd, rs1, imm` | OR Immediate | rd = rs1 \| imm |
| `xori rd, rs1, imm` | XOR Immediate | rd = rs1 ^ imm |
| `not rd, rs` | NOT | rd = ~rs (pseudo: xori rd, rs, -1) |

### Shift Operations

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `sll rd, rs1, rs2` | Shift Left Logical | rd = rs1 << rs2 |
| `srl rd, rs1, rs2` | Shift Right Logical | rd = rs1 >> rs2 (zero fill) |
| `sra rd, rs1, rs2` | Shift Right Arithmetic | rd = rs1 >> rs2 (sign fill) |
| `slli rd, rs1, imm` | Shift Left Immediate | rd = rs1 << imm |
| `srli rd, rs1, imm` | Shift Right Logical Imm | rd = rs1 >> imm |
| `srai rd, rs1, imm` | Shift Right Arith Imm | rd = rs1 >> imm |

### Logical vs Arithmetic Shift

```
Value: 0x80 = 0b10000000 (128 unsigned, -128 signed as byte)

srli:  10000000 >> 2 = 00100000  (fills with 0)
srai:  10000000 >> 2 = 11100000  (fills with sign bit)
```

### Examples

```asm
# Extract low byte
andi    a0, a0, 0xFF        # a0 = a0 & 0xFF

# Multiply by 8 (shift left 3)
slli    a0, a0, 3           # a0 = a0 * 8

# Divide by 4 (shift right 2)
srli    a0, a0, 2           # a0 = a0 / 4 (unsigned)
srai    a0, a0, 2           # a0 = a0 / 4 (signed)

# Check if bit 5 is set
andi    t0, a0, 0x20        # t0 = a0 & (1 << 5)
bnez    t0, bit_is_set
```

---

## Comparison Instructions

### Set Less Than

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `slt rd, rs1, rs2` | Set Less Than | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| `sltu rd, rs1, rs2` | Set Less Than Unsigned | rd = (rs1 < rs2) ? 1 : 0 |
| `slti rd, rs1, imm` | Set Less Than Immediate | rd = (rs1 < imm) ? 1 : 0 |
| `sltiu rd, rs1, imm` | Set Less Than Imm Unsigned | rd = (rs1 < imm) ? 1 : 0 |

### Pseudo-instructions

| Instruction | Meaning | Expansion |
|-------------|---------|-----------|
| `seqz rd, rs` | Set if Equal Zero | sltiu rd, rs, 1 |
| `snez rd, rs` | Set if Not Equal Zero | sltu rd, zero, rs |
| `sltz rd, rs` | Set if Less Than Zero | slt rd, rs, zero |
| `sgtz rd, rs` | Set if Greater Than Zero | slt rd, zero, rs |

### Examples

```asm
# Check if a0 < 10
slti    t0, a0, 10          # t0 = (a0 < 10) ? 1 : 0
bnez    t0, less_than_10

# Check if a0 == 0
seqz    t0, a0              # t0 = (a0 == 0) ? 1 : 0
```

---

## Branch Instructions

**"Branch" = Conditional jump (short range)**

### Instruction Breakdown

```
beq  rs1, rs2, label
│    │    │    │
│    │    │    └── Target label
│    │    └─────── Second register to compare
│    └──────────── First register to compare
└───────────────── Branch if Equal
```

### All Branch Instructions

| Instruction | Meaning | Condition |
|-------------|---------|-----------|
| `beq rs1, rs2, label` | Branch if Equal | rs1 == rs2 |
| `bne rs1, rs2, label` | Branch if Not Equal | rs1 != rs2 |
| `blt rs1, rs2, label` | Branch if Less Than | rs1 < rs2 (signed) |
| `bge rs1, rs2, label` | Branch if Greater or Equal | rs1 >= rs2 (signed) |
| `bltu rs1, rs2, label` | Branch if Less Than Unsigned | rs1 < rs2 |
| `bgeu rs1, rs2, label` | Branch if Greater or Equal Unsigned | rs1 >= rs2 |

### Pseudo-instructions

| Instruction | Meaning | Expansion |
|-------------|---------|-----------|
| `beqz rs, label` | Branch if Zero | beq rs, zero, label |
| `bnez rs, label` | Branch if Not Zero | bne rs, zero, label |
| `blez rs, label` | Branch if ≤ Zero | bge zero, rs, label |
| `bgez rs, label` | Branch if ≥ Zero | bge rs, zero, label |
| `bltz rs, label` | Branch if < Zero | blt rs, zero, label |
| `bgtz rs, label` | Branch if > Zero | blt zero, rs, label |
| `bgt rs1, rs2, label` | Branch if Greater | blt rs2, rs1, label |
| `ble rs1, rs2, label` | Branch if Less or Equal | bge rs2, rs1, label |

### Examples

```asm
# if (a0 == 0) goto done
beqz    a0, done

# if (a0 < a1) goto less
blt     a0, a1, less

# while (a0 != 0) { ... }
loop:
    beqz    a0, end_loop
    # ... loop body ...
    j       loop
end_loop:

# if (a0 >= 10) goto big
li      t0, 10
bge     a0, t0, big
```

---

## Jump Instructions

**"Jump" = Unconditional jump (any distance)**

### Instructions

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `jal rd, label` | Jump And Link | rd = PC+4; goto label |
| `jalr rd, rs1, imm` | Jump And Link Register | rd = PC+4; goto rs1+imm |
| `j label` | Jump | goto label (pseudo: jal zero, label) |
| `jr rs` | Jump Register | goto rs (pseudo: jalr zero, rs, 0) |
| `ret` | Return | goto ra (pseudo: jalr zero, ra, 0) |
| `call label` | Call function | (pseudo: auipc+jalr) |

### How Function Calls Work

```asm
# Calling a function
main:
    # ...
    jal     ra, my_function     # ra = return address, jump to function
    # execution continues here after return
    
my_function:
    # ... do work ...
    ret                         # jump back to ra (return address)
```

### jal vs jalr

```asm
# jal - Jump to label (PC-relative, ±1MB range)
jal     ra, printf              # call printf

# jalr - Jump to address in register (any address)
ld      t0, 0(s0)               # load function pointer
jalr    ra, t0, 0               # call through pointer
```

---

## Address/Data Loading

### Upper Immediate Instructions

| Instruction | Meaning | Operation |
|-------------|---------|-----------|
| `lui rd, imm` | Load Upper Immediate | rd = imm << 12 |
| `auipc rd, imm` | Add Upper Imm to PC | rd = PC + (imm << 12) |

### Why Do We Need These?

RISC-V immediates are only 12 bits. To load a 32/64-bit value:

```asm
# Load 0x12345678 into a0

lui     a0, 0x12345         # a0 = 0x12345000
addi    a0, a0, 0x678       # a0 = 0x12345678

# Or use the pseudo-instruction:
li      a0, 0x12345678      # assembler generates lui+addi
```

### Loading Addresses

```asm
# Load address of a label
la      a0, my_data         # pseudo: auipc + addi

# What it expands to:
auipc   a0, %pcrel_hi(my_data)
addi    a0, a0, %pcrel_lo(my_data)
```

---

## Pseudo-instructions Summary

These don't exist in hardware — the assembler expands them:

| Pseudo | Expansion | Meaning |
|--------|-----------|---------|
| `li rd, imm` | lui+addi | Load immediate |
| `la rd, sym` | auipc+addi | Load address |
| `mv rd, rs` | addi rd, rs, 0 | Copy register |
| `not rd, rs` | xori rd, rs, -1 | Bitwise NOT |
| `neg rd, rs` | sub rd, zero, rs | Negate |
| `nop` | addi zero, zero, 0 | No operation |
| `j label` | jal zero, label | Jump |
| `jr rs` | jalr zero, rs, 0 | Jump register |
| `ret` | jalr zero, ra, 0 | Return |
| `call label` | auipc+jalr | Call function |
| `beqz rs, label` | beq rs, zero, label | Branch if zero |
| `bnez rs, label` | bne rs, zero, label | Branch if not zero |

---

## System Instructions

### Environment Call

```asm
ecall                       # System call / trap to kernel
```

The kernel reads:
- `a7` = syscall number
- `a0-a5` = arguments
- Returns result in `a0`

### Linux Syscall Numbers (RISC-V)

| Number | Name | Arguments |
|--------|------|-----------|
| 93 | exit | a0=status |
| 63 | read | a0=fd, a1=buf, a2=count |
| 64 | write | a0=fd, a1=buf, a2=count |
| 56 | openat | a0=dirfd, a1=path, a2=flags, a3=mode |
| 57 | close | a0=fd |

### Example: Exit Program

```asm
li      a0, 0               # exit code 0
li      a7, 93              # syscall number for exit
ecall                       # call kernel
```

### Example: Write to stdout

```asm
li      a0, 1               # fd = stdout
la      a1, message         # buffer
li      a2, 13              # length
li      a7, 64              # syscall number for write
ecall
```

---

## Memory Layout & Stack

### Stack Operations

```
        High addresses
              │
    ┌─────────┴─────────┐
    │   Previous frame  │
    ├───────────────────┤
    │   Return address  │  ← sp + 24
    ├───────────────────┤
    │   Saved s0        │  ← sp + 16
    ├───────────────────┤
    │   Saved s1        │  ← sp + 8
    ├───────────────────┤
    │   Local var       │  ← sp + 0
    └─────────┬─────────┘
              │
        Low addresses (stack grows down)
```

### Function Prologue/Epilogue

```asm
my_function:
    # Prologue - save registers, allocate stack
    addi    sp, sp, -32         # allocate 32 bytes
    sd      ra, 24(sp)          # save return address
    sd      s0, 16(sp)          # save s0
    sd      s1, 8(sp)           # save s1
    
    # ... function body ...
    
    # Epilogue - restore registers, deallocate stack
    ld      s1, 8(sp)           # restore s1
    ld      s0, 16(sp)          # restore s0
    ld      ra, 24(sp)          # restore return address
    addi    sp, sp, 32          # deallocate
    ret
```

---

## Common Patterns

### Loop: for (i = 0; i < n; i++)

```asm
    li      t0, 0               # i = 0
loop:
    bge     t0, a0, done        # if (i >= n) break
    
    # ... loop body ...
    
    addi    t0, t0, 1           # i++
    j       loop
done:
```

### If-Else

```asm
    # if (a0 == 0) { ... } else { ... }
    bnez    a0, else_branch
    # then branch
    j       end_if
else_branch:
    # else branch
end_if:
```

### String Length (strlen)

```asm
# a0 = pointer to string
# returns length in a0
strlen:
    mv      t0, a0              # save start
.loop:
    lbu     t1, 0(a0)           # load char
    beqz    t1, .done           # if null, done
    addi    a0, a0, 1           # next char
    j       .loop
.done:
    sub     a0, a0, t0          # length = end - start
    ret
```

### Integer to ASCII (itoa)

```asm
# a0 = number, a1 = buffer
# Simple version for positive numbers
itoa:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    mv      t0, a1              # save buffer start
    li      t1, 0               # digit count
    
.digits:
    li      t2, 10
    rem     t3, a0, t2          # t3 = a0 % 10
    div     a0, a0, t2          # a0 = a0 / 10
    addi    t3, t3, '0'         # convert to ASCII
    sb      t3, 0(a1)           # store digit
    addi    a1, a1, 1
    addi    t1, t1, 1
    bnez    a0, .digits
    
    # Reverse the string (digits are backwards)
    # ... (left as exercise)
    
    ld      ra, 0(sp)
    addi    sp, sp, 16
    ret
```

---

## Quick Reference Card

```
┌────────────────────────────────────────────────────────────┐
│                    LOAD / STORE                            │
├────────────────────────────────────────────────────────────┤
│ ld/sd   = 64-bit     lw/sw   = 32-bit                     │
│ lh/sh   = 16-bit     lb/sb   = 8-bit                      │
│ lbu/lhu/lwu = unsigned (zero-extend)                      │
├────────────────────────────────────────────────────────────┤
│                    ARITHMETIC                              │
├────────────────────────────────────────────────────────────┤
│ add sub mul div rem   (register-register)                 │
│ addi li              (immediate)                          │
│ neg mv               (pseudo)                             │
├────────────────────────────────────────────────────────────┤
│                    LOGICAL                                 │
├────────────────────────────────────────────────────────────┤
│ and or xor andi ori xori not                              │
│ sll srl sra slli srli srai                                │
├────────────────────────────────────────────────────────────┤
│                    COMPARE                                 │
├────────────────────────────────────────────────────────────┤
│ slt sltu slti sltiu                                       │
│ seqz snez sltz sgtz  (pseudo)                             │
├────────────────────────────────────────────────────────────┤
│                    BRANCH                                  │
├────────────────────────────────────────────────────────────┤
│ beq bne blt bge bltu bgeu                                 │
│ beqz bnez blez bgez bltz bgtz bgt ble  (pseudo)          │
├────────────────────────────────────────────────────────────┤
│                    JUMP                                    │
├────────────────────────────────────────────────────────────┤
│ jal jalr j jr ret call  (last 4 are pseudo)               │
├────────────────────────────────────────────────────────────┤
│                    UPPER IMMEDIATE                         │
├────────────────────────────────────────────────────────────┤
│ lui auipc la         (la is pseudo)                       │
├────────────────────────────────────────────────────────────┤
│                    SYSTEM                                  │
├────────────────────────────────────────────────────────────┤
│ ecall                                                      │
└────────────────────────────────────────────────────────────┘
```
