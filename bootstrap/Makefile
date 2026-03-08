# fstCC Bootstrap Compiler Makefile

AS = riscv64-linux-gnu-as
LD = riscv64-linux-gnu-ld
QEMU = qemu-riscv64

SRC_DIR = src
BUILD_DIR = build
TEST_DIR = test

COMPILER = $(BUILD_DIR)/fstcc0

.PHONY: all clean test run test-suite

# Build the compiler
all: $(COMPILER)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/fstcc0.o: $(SRC_DIR)/fstcc0.s | $(BUILD_DIR)
	$(AS) -o $@ $<

$(COMPILER): $(BUILD_DIR)/fstcc0.o
	$(LD) -o $@ $<
	@echo "✓ Compiler built: $(COMPILER)"

# Compile a test file and run it
# Usage: make test FILE=test/test.c
FILE ?= $(TEST_DIR)/test.c
test: $(COMPILER)
	@echo "=== Compiling $(FILE) ==="
	$(QEMU) $(COMPILER) $(FILE) $(BUILD_DIR)/out.s
	$(AS) -o $(BUILD_DIR)/out.o $(BUILD_DIR)/out.s
	$(LD) -o $(BUILD_DIR)/out $(BUILD_DIR)/out.o
	@echo "=== Generated assembly ==="
	@cat $(BUILD_DIR)/out.s
	@echo "=== Running ==="
	@$(QEMU) $(BUILD_DIR)/out; echo "Exit code: $$?"

# Quick run: make run N=42
N ?= 42
run: $(COMPILER)
	@echo 'int main() { return $(N); }' > $(BUILD_DIR)/tmp.c
	@$(QEMU) $(COMPILER) $(BUILD_DIR)/tmp.c $(BUILD_DIR)/tmp.s
	@$(AS) -o $(BUILD_DIR)/tmp.o $(BUILD_DIR)/tmp.s
	@$(LD) -o $(BUILD_DIR)/out $(BUILD_DIR)/tmp.o
	@cat $(BUILD_DIR)/tmp.s
	@$(QEMU) $(BUILD_DIR)/out; echo "$$?"

test-suite: $(COMPILER)
	bash $(TEST_DIR)/run_tests.sh

clean:
	rm -rf $(BUILD_DIR)
	@echo "✓ Cleaned"
