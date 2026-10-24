# mizrab developer tasks. Run `make help` for the list.

SALAM ?= salam
CC ?= cc
BUILD := build
BIN := $(BUILD)/mizrab
ENTRY := main.salam
SOURCES := main.salam commands audio player
FLAGS := --log-level=warn --backend=llvm
SALAM_VERSION := $(shell cat .salam-version)
MINT ?= mint
MINT_VERSION := $(shell cat .mint-version)

# Vendored miniaudio (audio/). One implementation unit; the null backend stays
# compiled in, so no OS-conditional backend set is needed.
MINIAUDIO_DIR := audio
MINIAUDIO_OBJ := $(BUILD)/miniaudio.o
SHIM_OBJ := $(BUILD)/ma_shim.o
MINIAUDIO_DEFS := -DMA_NO_ENCODING -DMA_NO_GENERATION -DMA_NO_RESOURCE_MANAGER \
	-DMA_NO_NODE_GRAPH -DMA_NO_ENGINE

# Salam links with the host toolchain on macOS. Pin the deployment target to
# the running OS so the linker does not warn about mismatched SDK versions.
ifeq ($(shell uname -s),Darwin)
export MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion)
endif

.PHONY: help build run test check fmt fmt-check clean docs docs-check docs-format-check soak

help:
	@echo "make build     compile $(ENTRY) to $(BIN) with --backend=llvm"
	@echo "make run       build and run the player"
	@echo "make test      build and run tests/*_test.salam plus the CLI smoke checks"
	@echo "make fmt       format all Salam sources in place"
	@echo "make fmt-check fail if any Salam source would be rewritten"
	@echo "make check     run fmt-check, build and test in order: the tree-green gate"
	@echo "make clean     remove build output"
	@echo "make docs      serve the site locally with mint $(MINT_VERSION) (pinned in .mint-version)"
	@echo "make docs-check validate docs.json and check internal links and anchors"
	@echo "make docs-format-check fail if mint format would rewrite a page (stage edits first)"
	@echo "make soak      one hour of frames through the engine on a virtual clock (opt-in, not in test or CI)"
	@echo "Salam $(SALAM_VERSION)"

build: $(MINIAUDIO_OBJ) $(SHIM_OBJ)
	@mkdir -p $(BUILD)
	$(SALAM) build $(ENTRY) --output=$(BIN) $(FLAGS)

run: build
	./$(BIN)

test: build
	sh tests/run.sh

fmt:
	$(SALAM) format $(SOURCES)

fmt-check:
	$(SALAM) format --check $(SOURCES)

# The tree-green gate as one word: fmt-check first so a formatting failure is
# reported before the compile, then test (which depends on build).
check:
	$(MAKE) fmt-check
	$(MAKE) test

docs:
	$(MINT) dev

docs-check:
	$(MINT) validate
	$(MINT) broken-links --check-anchors

docs-format-check:
	$(MINT) format
	git diff --exit-code -- '*.mdx' 'docs.json'

clean:
	rm -rf $(BUILD) .salam-build

# The audio tests link these objects by path (`link static "../build/..."`), so
# `build` and `test` depend on them.
$(MINIAUDIO_OBJ): $(MINIAUDIO_DIR)/miniaudio.c $(MINIAUDIO_DIR)/miniaudio.h $(MINIAUDIO_DIR)/stb_vorbis.c
	@mkdir -p $(BUILD)
	$(CC) -c -O2 -I$(MINIAUDIO_DIR) $(MINIAUDIO_DEFS) -o $@ $<

$(SHIM_OBJ): $(MINIAUDIO_DIR)/ma_shim.c $(MINIAUDIO_DIR)/ma_shim.h $(MINIAUDIO_DIR)/miniaudio.h
	@mkdir -p $(BUILD)
	$(CC) -c -O2 -I$(MINIAUDIO_DIR) $(MINIAUDIO_DEFS) -o $@ $<

soak: build
	sh tests/soak.sh
