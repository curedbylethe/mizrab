# mizrab developer tasks. Run `make help` for the list.

SALAM ?= salam
CC ?= cc
BUILD := build
BIN := $(BUILD)/mizrab
ENTRY := main.salam
SOURCES := main.salam commands
FLAGS := --log-level=warn --backend=llvm
SALAM_VERSION := $(shell cat .salam-version)

# Vendored miniaudio (audio/). One implementation unit; the null backend stays
# compiled in, so no OS-conditional backend set is needed.
MINIAUDIO_DIR := audio
MINIAUDIO_OBJ := $(BUILD)/miniaudio.o
MINIAUDIO_DEFS := -DMA_NO_DECODING -DMA_NO_ENCODING -DMA_NO_WAV -DMA_NO_FLAC \
	-DMA_NO_MP3 -DMA_NO_GENERATION -DMA_NO_RESOURCE_MANAGER -DMA_NO_NODE_GRAPH \
	-DMA_NO_ENGINE

# Salam links with the host toolchain on macOS. Pin the deployment target to
# the running OS so the linker does not warn about mismatched SDK versions.
ifeq ($(shell uname -s),Darwin)
export MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion)
endif

.PHONY: help build run test fmt fmt-check clean spike-build spike-run

help:
	@echo "make build     compile $(ENTRY) to $(BIN) with --backend=llvm"
	@echo "make run       build and run the player"
	@echo "make test      build and run tests/*_test.salam plus the CLI smoke checks"
	@echo "make fmt       format all Salam sources in place"
	@echo "make fmt-check fail if any Salam source would be rewritten"
	@echo "make clean     remove build output"
	@echo "make spike-build compile $(MINIAUDIO_OBJ) and spike/probe.salam into $(BUILD)/spike"
	@echo "make spike-run build and run the miniaudio linkage spike"
	@echo "Salam $(SALAM_VERSION)"

build:
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

clean:
	rm -rf $(BUILD) .salam-build

# The object is linked by path from spike/probe.salam. The compiler checks that
# path relative to the source file but hands it to the linker from the current
# directory, so the build runs from spike/ and the source says ../$(BUILD).
$(MINIAUDIO_OBJ): $(MINIAUDIO_DIR)/miniaudio.c $(MINIAUDIO_DIR)/miniaudio.h
	@mkdir -p $(BUILD)
	$(CC) -c -O2 -I$(MINIAUDIO_DIR) $(MINIAUDIO_DEFS) -o $@ $<

spike-build: $(MINIAUDIO_OBJ)
	cd spike && $(SALAM) build probe.salam --output=../$(BUILD)/spike $(FLAGS)

spike-run: spike-build
	./$(BUILD)/spike
