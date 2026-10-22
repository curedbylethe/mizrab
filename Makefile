# mizrab developer tasks. Run `make help` for the list.

SALAM ?= salam
BUILD := build
BIN := $(BUILD)/mizrab
ENTRY := main.salam
SOURCES := main.salam commands
FLAGS := --log-level=warn --backend=llvm
SALAM_VERSION := $(shell cat .salam-version)

# Salam links with the host toolchain on macOS. Pin the deployment target to
# the running OS so the linker does not warn about mismatched SDK versions.
ifeq ($(shell uname -s),Darwin)
export MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion)
endif

.PHONY: help build run fmt fmt-check clean

help:
	@echo "make build     compile $(ENTRY) to $(BIN) with --backend=llvm"
	@echo "make run       build and run the player"
	@echo "make fmt       format all Salam sources in place"
	@echo "make fmt-check fail if any Salam source would be rewritten"
	@echo "make clean     remove build output"
	@echo "Salam $(SALAM_VERSION)"

build:
	@mkdir -p $(BUILD)
	$(SALAM) build $(ENTRY) --output=$(BIN) $(FLAGS)

run: build
	./$(BIN)

fmt:
	$(SALAM) format $(SOURCES)

fmt-check:
	$(SALAM) format --check $(SOURCES)

clean:
	rm -rf $(BUILD) .salam-build
