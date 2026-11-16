#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/momi_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$DIR"

echo "==> Typechecking momi app..."
swiftc -O -typecheck \
    src/App/*.swift \
    src/Core/*.swift \
    src/Readers/*.swift \
    src/UI/*.swift

echo "==> Running ZCode tests..."
for t in zcode_parser zcode_index zcode_speed; do
    swiftc "tests/${t}_test.swift" src/Readers/ZCodeParser.swift -o "$TMP_DIR/${t}"
    "$TMP_DIR/${t}"
done

echo "==> Running Alma tests..."
for t in alma_reader alma_index; do
    swiftc "tests/${t}_test.swift" src/Readers/AlmaReader.swift -o "$TMP_DIR/${t}"
    "$TMP_DIR/${t}"
done

echo "==> Running Core tests..."
swiftc tests/momi_core_test.swift src/Core/ModelFormatting.swift -o "$TMP_DIR/momi_core"
"$TMP_DIR/momi_core"

echo "==> All checks passed."
