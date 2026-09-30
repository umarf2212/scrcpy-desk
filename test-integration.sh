#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/scrcpydesk-tests.XXXXXX")
ARCH=$(uname -m)
mkdir -p "$TEST_DIR/Integration.app/Contents/MacOS" "$TEST_DIR/Integration.app/Contents/Resources/Engine/$ARCH"
cp IntegrationFixtures/* "$TEST_DIR/Integration.app/Contents/Resources/Engine/$ARCH/"
chmod +x "$TEST_DIR/Integration.app/Contents/Resources/Engine/$ARCH/"*
swiftc -swift-version 5 Core.swift Model.swift Updater.swift Integration.swift -o "$TEST_DIR/Integration.app/Contents/MacOS/Integration"
"$TEST_DIR/Integration.app/Contents/MacOS/Integration"
