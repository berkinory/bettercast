.DEFAULT_GOAL := check

SHELL := /bin/bash

PROJECT := Bettercast.xcodeproj
SCHEME := Bettercast
CONFIGURATION ?= Debug
DERIVED_DATA ?= build/DerivedData
TEST_BIN_DIR := build/tests
SWIFT_FORMAT ?= swift-format
CODE_SIGNING_ALLOWED ?= NO

SWIFT_FILES := $(shell find Bettercast Tools -type f -name '*.swift' ! -name '*generated.swift' -print)

.PHONY: check tools format lint build release unsigned-dmg test generate clean

check: lint test build

tools:
	@command -v "$(SWIFT_FORMAT)" >/dev/null || { echo "error: $(SWIFT_FORMAT) is required" >&2; exit 1; }
	@command -v swift >/dev/null || { echo "error: swift is required" >&2; exit 1; }
	@command -v swiftc >/dev/null || { echo "error: swiftc is required" >&2; exit 1; }
	@command -v xcodebuild >/dev/null || { echo "error: xcodebuild is required" >&2; exit 1; }

format: tools
	$(SWIFT_FORMAT) format --in-place --configuration .swift-format.json $(SWIFT_FILES)

lint: tools
	$(SWIFT_FORMAT) lint --strict --configuration .swift-format.json $(SWIFT_FILES)

build: tools
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=$(CODE_SIGNING_ALLOWED) build

release:
	./build-dmg.sh

unsigned-dmg:
	SKIP_SIGNING=1 ./build-dmg.sh

test: tools
	@mkdir -p $(TEST_BIN_DIR)
	swift Tools/fuzz-test.swift
	swiftc -swift-version 6 Bettercast/Core/LauncherRankingStore.swift Tools/ranking-test.swift -o $(TEST_BIN_DIR)/ranking-test
	$(TEST_BIN_DIR)/ranking-test
	swiftc Bettercast/Core/Calculator/*.swift Tools/calc-test.swift -o $(TEST_BIN_DIR)/calc-test
	$(TEST_BIN_DIR)/calc-test
	swiftc -swift-version 6 Bettercast/Core/ClipboardStore.swift Tools/clipboard-test.swift -o $(TEST_BIN_DIR)/clipboard-test
	$(TEST_BIN_DIR)/clipboard-test
	swiftc Bettercast/Core/Emoji/EmojiCatalog.swift Bettercast/Core/Emoji/EmojiGridGeometry.swift Bettercast/Core/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o $(TEST_BIN_DIR)/emoji-test
	$(TEST_BIN_DIR)/emoji-test

generate:
	@command -v xcodegen >/dev/null || { echo "error: xcodegen is required" >&2; exit 1; }
	xcodegen generate

clean:
	rm -rf $(DERIVED_DATA) $(TEST_BIN_DIR)
