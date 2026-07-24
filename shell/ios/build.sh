#!/bin/sh
# Build the iOS shell: the Rust seam for the simulator, then the Swift app bundle.
# No Xcode project — one swiftc invocation, same as the macOS shell.
set -e
cd "$(dirname "$0")"

cargo build --release -p liv-ffi --target aarch64-apple-ios-sim --manifest-path ../../Cargo.toml

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

mkdir -p build/Liv.app
swiftc -O -parse-as-library \
    Sources/*.swift \
    -sdk "$SDK" \
    -target arm64-apple-ios17.0-simulator \
    -import-objc-header ../macos/liv.h \
    -L ../../target/aarch64-apple-ios-sim/release -lliv_ffi \
    -framework SwiftUI -framework UIKit -framework AVFoundation \
    -o build/Liv.app/Liv

# Simulator bundles are unsigned; the plist is the whole assembly.
cp Info.plist build/Liv.app/Info.plist

echo "built: shell/ios/build/Liv.app"

if [ "$1" = "run" ]; then
    UDID="$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    [ -n "$UDID" ] || { echo "no available iPhone simulator" >&2; exit 1; }
    xcrun simctl boot "$UDID" 2>/dev/null || true   # already-booted is fine
    open -a Simulator
    xcrun simctl install "$UDID" build/Liv.app
    xcrun simctl launch "$UDID" app.liv.ios
    echo "screenshot: xcrun simctl io booted screenshot /tmp/liv.png"
fi
