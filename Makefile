# sml-ratelimit build
#
#   make            build the test binary with MLton (default)
#   make test       build + run tests under MLton
#   make test-poly  run tests under Poly/ML (use-and-run; no link step)
#   make all-tests  run the suite under both compilers
#   make example    build + run examples/demo.sml
#   make clean      remove build artifacts
#
# Layout A (standalone): own sources live in src/; no vendored dependencies.

MLTON      ?= mlton
POLY       ?= poly
BIN        := bin
TEST_MLB   := test/sources.mlb
SRCS       := $(wildcard src/* test/*.sml) $(TEST_MLB)

.PHONY: all test poly test-poly all-tests example clean

all: $(BIN)/test-mlton

example: $(BIN)/demo
	./$(BIN)/demo

$(BIN)/demo: $(SRCS) examples/demo.sml examples/sources.mlb | $(BIN)
	$(MLTON) -output $@ examples/sources.mlb

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

# Poly/ML has no native .mlb support; the suite runs at top level and exits on
# its own. Load the sig, then the implementation, then the test driver, in
# dependency order.
poly test-poly:
	printf 'use "src/ratelimit.sig";\nuse "src/ratelimit.sml";\nuse "test/harness.sml";\nuse "test/support.sml";\nuse "test/test_tokenbucket.sml";\nuse "test/test_leakybucket.sml";\nuse "test/test_slidingwindow.sml";\nuse "test/entry.sml";\nuse "test/main.sml";\n' | $(POLY) -q --error-exit

all-tests: test test-poly

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -f $(BIN)/test-mlton $(BIN)/demo
