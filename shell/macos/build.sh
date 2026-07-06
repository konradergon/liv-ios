#!/bin/sh
# Build the milestone-4 shell: the Rust seam, then the Swift agent.
set -e
cd "$(dirname "$0")"

cargo build --release -p lotus-ffi --manifest-path ../../Cargo.toml

mkdir -p build
swiftc -O \
    Sources/main.swift \
    -import-objc-header lotus.h \
    -L ../../target/release -llotus_ffi \
    -framework AppKit -framework Carbon \
    -o build/lotus-capture

echo "built: shell/macos/build/lotus-capture"
echo "run it, then press ctrl-option-space anywhere"
