# fstCC - First Self-hosting Tiny C Compiler (RISC-V 64-bit)
# Targets: all, stage0, test, test-stage0, bootstrap, clean

# --- Cross-compilation toolchain (override for native) ---
CROSS = riscv64-linux-gnu-
CC = $(CROSS)gcc
CFLAGS = -Wall -Wextra -std=c99 -g -march=rv64imac -mabi=lp64
AS = $(CROSS)as
ASFLAGS = -march=rv64imac
LD = $(CROSS)ld
QEMU = qemu-riscv64

SRCDIR = src
BUILDDIR = build

SRCS = $(SRCDIR)/main.c $(SRCDIR)/lexer.c $(SRCDIR)/parser.c \
       $(SRCDIR)/codegen.c $(SRCDIR)/symtab.c
OBJS = $(patsubst $(SRCDIR)/%.c,$(BUILDDIR)/%.o,$(SRCS))
TARGET = $(BUILDDIR)/fstcc

.PHONY: all stage0 test test-stage0 bootstrap clean

# --- Stage 1: build with gcc ---
all: $(TARGET)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $^ -o $@

# --- Stage 0: assemble bootstrap compiler ---
stage0: $(BUILDDIR)/fstcc0

$(BUILDDIR)/fstcc0: bootstrap/fstcc0.s | $(BUILDDIR)
	$(AS) $(ASFLAGS) -o $(BUILDDIR)/fstcc0.o bootstrap/fstcc0.s
	$(LD) -o $(BUILDDIR)/fstcc0 $(BUILDDIR)/fstcc0.o

# --- Run with QEMU (for cross-compiled binaries) ---
run-stage0: $(BUILDDIR)/fstcc0
	$(QEMU) $(BUILDDIR)/fstcc0

# --- Tests ---
test: $(TARGET)
	@echo "=== Stage 1 Tests ==="
	$(QEMU) $(TARGET) --test
	@echo ""
	@echo "=== Stage 1 compiling test files ==="
	@for f in tests/stage0/*.c; do \
		base=$$(basename $$f .c); \
		$(QEMU) $(TARGET) $$f $(BUILDDIR)/test_$$base.s && \
		echo "  OK: $$f -> $(BUILDDIR)/test_$$base.s" || \
		echo "  FAIL: $$f"; \
	done

test-stage0: $(BUILDDIR)/fstcc0
	@echo "=== Stage 0 Tests ==="
	@bash tests/run_tests.sh $(BUILDDIR)/fstcc0

# --- Bootstrap verification ---
bootstrap: $(BUILDDIR)/fstcc0 $(TARGET)
	@echo "=== Bootstrap: Stage 0 compiling Stage 1 sources ==="
	@mkdir -p $(BUILDDIR)/bootstrap
	@for f in $(SRCS); do \
		base=$$(basename $$f .c); \
		echo "  Stage 0: $$f -> $(BUILDDIR)/bootstrap/$$base.s"; \
		$(QEMU) $(BUILDDIR)/fstcc0 $$f $(BUILDDIR)/bootstrap/$$base.s; \
	done
	@echo "=== Bootstrap complete ==="

clean:
	rm -rf $(BUILDDIR)
