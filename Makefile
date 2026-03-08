# fstCC - First Self-hosting Tiny C Compiler
# Root Makefile — delegates to bootstrap/ for Stage 0

.PHONY: all test clean

all:
	$(MAKE) -C bootstrap

test:
	$(MAKE) -C bootstrap test-suite

clean:
	$(MAKE) -C bootstrap clean
