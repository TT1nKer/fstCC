#!/usr/bin/env bash
# fstCC Stage 0 test suite
# Usage (from WSL): bash /mnt/d/fstCC/bootstrap/test/run_tests.sh
# Or (from Windows): make test-suite  (in bootstrap/)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build"
COMPILER="$BUILD_DIR/fstcc0"
TMP_SRC="/tmp/fstcc_test.c"
TMP_ASM="/tmp/fstcc_test.s"
TMP_OBJ="/tmp/fstcc_test.o"
TMP_OUT="/tmp/fstcc_test_out"

PASS=0
FAIL=0

if [ ! -f "$COMPILER" ]; then
    echo "ERROR: Compiler not found at $COMPILER"
    echo "Run 'make all' in bootstrap/ first."
    exit 1
fi

run_test() {
    local name="$1"
    local src="$2"
    local expected="$3"

    printf "%-30s " "$name"
    printf '%s' "$src" > "$TMP_SRC"

    # compile: fstcc0 → .s → .o → binary
    if ! qemu-riscv64 "$COMPILER" "$TMP_SRC" "$TMP_ASM" 2>/dev/null; then
        echo "FAIL (fstcc0 error)"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! riscv64-linux-gnu-as -o "$TMP_OBJ" "$TMP_ASM" 2>/dev/null; then
        echo "FAIL (assembler error)"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! riscv64-linux-gnu-ld -o "$TMP_OUT" "$TMP_OBJ" 2>/dev/null; then
        echo "FAIL (linker error)"
        FAIL=$((FAIL + 1))
        return
    fi

    # run and capture exit code (|| prevents set -e from firing on non-zero exit)
    actual=0
    qemu-riscv64 "$TMP_OUT" > /dev/null 2>&1 || actual=$?

    if [ "$actual" -eq "$expected" ]; then
        echo "PASS (exit=$actual)"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ===========================================================================
# M0: Return constant
# ===========================================================================
run_test "m0_return_0"       'int main() { return 0; }'    0
run_test "m0_return_1"       'int main() { return 1; }'    1
run_test "m0_return_42"      'int main() { return 42; }'   42

# ===========================================================================
# M1: Local variables and assignment
# ===========================================================================
run_test "m1_var_decl"       'int main() { int x; x = 7; return x; }'   7
run_test "m1_var_init"       'int main() { int x = 13; return x; }'     13
run_test "m1_var_assign"     'int main() { int x = 1; x = 55; return x; }'  55
run_test "m1_two_vars"       'int main() { int a = 10; int b = 20; return a; }'  10

# ===========================================================================
# M2: Arithmetic
# ===========================================================================
run_test "m2_add"            'int main() { return 3 + 4; }'     7
run_test "m2_sub"            'int main() { return 10 - 3; }'    7
run_test "m2_mul"            'int main() { return 3 * 4; }'     12
run_test "m2_div"            'int main() { return 20 / 4; }'    5
run_test "m2_mod"            'int main() { return 17 % 10; }'   7
run_test "m2_neg"            'int main() { int x = 5; return -x + 10; }'  5
run_test "m2_compound"       'int main() { int x = 2; int y = 3; return x * y + 1; }'  7

# ===========================================================================
# M3: Comparisons and logical operators
# ===========================================================================
run_test "m3_eq_true"        'int main() { return 1 == 1; }'    1
run_test "m3_eq_false"       'int main() { return 1 == 2; }'    0
run_test "m3_neq_true"       'int main() { return 1 != 2; }'    1
run_test "m3_neq_false"      'int main() { return 1 != 1; }'    0
run_test "m3_lt_true"        'int main() { return 3 < 5; }'     1
run_test "m3_lt_false"       'int main() { return 5 < 3; }'     0
run_test "m3_gt_true"        'int main() { return 5 > 3; }'     1
run_test "m3_le_true"        'int main() { return 3 <= 3; }'    1
run_test "m3_ge_true"        'int main() { return 5 >= 5; }'    1
run_test "m3_not_true"       'int main() { return !0; }'        1
run_test "m3_not_false"      'int main() { return !1; }'        0
run_test "m3_and_tt"         'int main() { return 1 && 1; }'    1
run_test "m3_and_tf"         'int main() { return 1 && 0; }'    0
run_test "m3_or_ff"          'int main() { return 0 || 0; }'    0
run_test "m3_or_tf"          'int main() { return 0 || 1; }'    1

# ===========================================================================
# M4: if/else, while, function calls
# ===========================================================================
run_test "m4_if_taken"       'int main() { int x = 0; if (1) x = 7; return x; }'   7
run_test "m4_if_not_taken"   'int main() { int x = 3; if (0) x = 7; return x; }'   3
run_test "m4_if_else_true"   'int main() { if (1) return 10; else return 20; }'     10
run_test "m4_if_else_false"  'int main() { if (0) return 10; else return 20; }'     20
run_test "m4_while_0"        'int main() { int i = 0; while (i < 5) i = i + 1; return i; }'  5
run_test "m4_while_sum"      'int main() { int s = 0; int i = 1; while (i <= 4) { s = s + i; i = i + 1; } return s; }'  10
run_test "m4_funcall"        'int seven() { return 7; } int main() { return seven(); }'  7
run_test "m4_funcall_arg"    'int inc(int x) { return x + 1; } int main() { return inc(6); }'  7
run_test "m4_funcall_args2"  'int add(int a, int b) { return a + b; } int main() { return add(3, 4); }'  7
run_test "m4_recursive"      'int fact(int n) { if (n <= 1) return 1; return n * fact(n - 1); } int main() { return fact(5); }'  120

# ===========================================================================
# Summary
# ===========================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
