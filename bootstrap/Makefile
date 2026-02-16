# fstCC Bootstrap Compiler Makefile

AS = riscv64-linux-gnu-as
LD = riscv64-linux-gnu-ld
QEMU = qemu-riscv64

SRC_DIR = src
BUILD_DIR = build
TEST_DIR = test

COMPILER = $(BUILD_DIR)/fstcc0

.PHONY: all clean test run

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
	@echo "=== Generated assembly ==="
	@cat $(BUILD_DIR)/out.s
	@echo "=== Assembling and linking ==="
	$(AS) -o $(BUILD_DIR)/out.o $(BUILD_DIR)/out.s
	$(LD) -o $(BUILD_DIR)/out $(BUILD_DIR)/out.o
	@echo "=== Running ==="
	@$(QEMU) $(BUILD_DIR)/out; echo "Exit code: $$?"

# Quick run: make run N=42
N ?= 42
run: $(COMPILER)
	@echo 'int main() { return $(N); }' > $(BUILD_DIR)/tmp.c
	@$(QEMU) $(COMPILER) $(BUILD_DIR)/tmp.c $(BUILD_DIR)/out.s
	@$(AS) -o $(BUILD_DIR)/out.o $(BUILD_DIR)/out.s
	@$(LD) -o $(BUILD_DIR)/out $(BUILD_DIR)/out.o
	@$(QEMU) $(BUILD_DIR)/out; echo "$$?"

clean:
	rm -rf $(BUILD_DIR)
	@echo "✓ Cleaned"
