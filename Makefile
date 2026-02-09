CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -g
SRCDIR = src
BUILDDIR = build

SRCS = $(SRCDIR)/main.c $(SRCDIR)/lexer.c $(SRCDIR)/parser.c $(SRCDIR)/codegen.c $(SRCDIR)/symtab.c
OBJS = $(patsubst $(SRCDIR)/%.c,$(BUILDDIR)/%.o,$(SRCS))
TARGET = $(BUILDDIR)/fstcc

.PHONY: all clean test

all: $(TARGET)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $^ -o $@

test: $(TARGET)
	$(TARGET) --test

clean:
	rm -rf $(BUILDDIR)
