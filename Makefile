# mizrab developer tasks. Run `make help` for the list.

SALAM ?= salam
CC ?= cc
BUILD := build
BIN := $(BUILD)/mizrab
ENTRY := main.salam
SOURCES := main.salam commands
FLAGS := --log-level=warn --backend=llvm
SALAM_VERSION := $(shell cat .salam-version)
MINT ?= mint
MINT_VERSION := $(shell cat .mint-version)

# Vendored miniaudio (audio/). One implementation unit; the null backend stays
# compiled in, so no OS-conditional backend set is needed.
MINIAUDIO_DIR := audio
MINIAUDIO_OBJ := $(BUILD)/miniaudio.o
SHIM_OBJ := $(BUILD)/ma_shim.o
SPIKE_MEASURE_BIN := $(BUILD)/spike-measure
MINIAUDIO_DEFS := -DMA_NO_ENCODING -DMA_NO_GENERATION -DMA_NO_RESOURCE_MANAGER \
	-DMA_NO_NODE_GRAPH -DMA_NO_ENGINE

# Salam links with the host toolchain on macOS. Pin the deployment target to
# the running OS so the linker does not warn about mismatched SDK versions.
ifeq ($(shell uname -s),Darwin)
export MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion)
endif

.PHONY: help build run test fmt fmt-check clean docs docs-check docs-format-check spike-build spike-run spike-check spike-check-device spike-measure

help:
	@echo "make build     compile $(ENTRY) to $(BIN) with --backend=llvm"
	@echo "make run       build and run the player"
	@echo "make test      build and run tests/*_test.salam plus the CLI smoke checks"
	@echo "make fmt       format all Salam sources in place"
	@echo "make fmt-check fail if any Salam source would be rewritten"
	@echo "make clean     remove build output"
	@echo "make docs      serve the site locally with mint $(MINT_VERSION) (pinned in .mint-version)"
	@echo "make docs-check validate docs.json and check internal links and anchors"
	@echo "make docs-format-check fail if mint format would rewrite a page (stage edits first)"
	@echo "make spike-build compile $(MINIAUDIO_OBJ), $(SHIM_OBJ) and spike/tone.salam into $(BUILD)/spike"
	@echo "make spike-run   build and run the tone spike on the default device"
	@echo "make spike-check build and run the tone spike on the null backend"
	@echo "make spike-check-device build and run the tone spike on the default device"
	@echo "make spike-measure print the STAGE-03 measurement table (M1-M8, real device)"
	@echo "Salam $(SALAM_VERSION)"

build: $(MINIAUDIO_OBJ)
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

# The objects are linked by path from spike/tone.salam. The compiler checks the
# path relative to the source file but hands it to the linker from the current
# directory, so the build runs from spike/ and the source says ../$(BUILD).
$(MINIAUDIO_OBJ): $(MINIAUDIO_DIR)/miniaudio.c $(MINIAUDIO_DIR)/miniaudio.h $(MINIAUDIO_DIR)/stb_vorbis.c
	@mkdir -p $(BUILD)
	$(CC) -c -O2 -I$(MINIAUDIO_DIR) $(MINIAUDIO_DEFS) -o $@ $<

$(SHIM_OBJ): spike/ma_shim.c spike/ma_shim.h $(MINIAUDIO_DIR)/miniaudio.h
	@mkdir -p $(BUILD)
	$(CC) -c -O2 -I$(MINIAUDIO_DIR) $(MINIAUDIO_DEFS) -o $@ $<

spike-build: $(MINIAUDIO_OBJ) $(SHIM_OBJ)
	cd spike && $(SALAM) build tone.salam --output=../$(BUILD)/spike $(FLAGS)

spike-run: spike-build
	./$(BUILD)/spike

spike-check: spike-build
	./$(BUILD)/spike --null

spike-check-device: spike-build
	./$(BUILD)/spike

# The measurement binary is separate so `spike-check` (the CI path) keeps
# exactly the behaviour it shipped with; measure.salam still defaults to a tone.
$(SPIKE_MEASURE_BIN): $(MINIAUDIO_OBJ) $(SHIM_OBJ) spike/measure.salam
	cd spike && $(SALAM) build measure.salam --output=../$(SPIKE_MEASURE_BIN) $(FLAGS)

spike-measure: $(SPIKE_MEASURE_BIN)
	sh spike/measure.sh
