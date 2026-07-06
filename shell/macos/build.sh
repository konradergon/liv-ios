#!/bin/sh
# Build the milestone-4 shell: the Rust seam, then the Swift agent.
set -e
cd "$(dirname "$0")"

cargo build --release -p lotus-ffi --manifest-path ../../Cargo.toml

mkdir -p build
swiftc -O \
    Sources/main.swift Sources/Window.swift Sources/Editor.swift Sources/Tokens.swift Sources/Commands.swift Sources/Dialogs.swift Sources/Chrome.swift \
    -import-objc-header lotus.h \
    -L ../../target/release -llotus_ffi \
    -framework AppKit -framework Carbon -framework SwiftUI \
    -o build/lotus

echo "built: shell/macos/build/lotus"
echo "run it: the window opens, and ctrl-option-space captures from anywhere"
