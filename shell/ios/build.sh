#!/bin/sh
# Build the iOS shell: the Rust seam for the simulator, then the Swift app bundle.
# No Xcode project — one swiftc invocation, same as the macOS shell.
set -e
cd "$(dirname "$0")"

# System tools first. This machine has plan9 grep/sed earlier in PATH, and
# they have neither `grep -m` nor `sed -E` — which silently emptied the
# signing identity and made a device build claim the certificate was
# missing. Everything else (cargo, swiftc) still resolves further down.
PATH="/usr/bin:/bin:$PATH"

BUNDLE_ID="app.liv.ios"

# `./build.sh device [run]` — a real iPhone instead of the simulator. This
# needs a signing certificate + a provisioning profile scoped to
# app.liv.ios, which only Xcode can create; that's a one-time manual step
# (design/ios.md — testing on a device), done once via a throwaway Xcode
# project. Once done, both live on disk and this finds them itself.
if [ "$1" = "device" ]; then
    cargo build --release -p liv-ffi --target aarch64-apple-ios --manifest-path ../../Cargo.toml

    SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

    mkdir -p build/LivDevice.app
    swiftc -O -parse-as-library \
        Sources/*.swift \
        -sdk "$SDK" \
        -target arm64-apple-ios17.0 \
        -import-objc-header ../../ffi/liv.h \
        ../../target/aarch64-apple-ios/release/libliv_ffi.a \
        -framework SwiftUI -framework UIKit -framework AVFoundation \
        -o build/LivDevice.app/Liv

    cp Info-device.plist build/LivDevice.app/Info.plist

    IDENTITY="$(security find-identity -v -p codesigning \
        | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/')"
    [ -n "$IDENTITY" ] || {
        echo "no 'Apple Development' signing identity in the keychain." >&2
        echo "Run the one-time Xcode signing setup first (see design/ios.md)." >&2
        exit 1
    }

    PROFILE=""
    for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
        [ -e "$f" ] || continue
        name="$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name xml1 -o - - 2>/dev/null)"
        case "$name" in
        *"$BUNDLE_ID"*) PROFILE="$f"; break ;;
        esac
    done
    [ -n "$PROFILE" ] || {
        echo "no provisioning profile scoped to $BUNDLE_ID." >&2
        echo "Run the one-time Xcode signing setup first (see design/ios.md)." >&2
        exit 1
    }

    cp "$PROFILE" build/LivDevice.app/embedded.mobileprovision
    security cms -D -i "$PROFILE" 2>/dev/null \
        | plutil -extract Entitlements xml1 -o build/entitlements.plist -

    codesign --force --sign "$IDENTITY" \
        --entitlements build/entitlements.plist \
        build/LivDevice.app

    echo "built + signed: shell/ios/build/LivDevice.app"

    if [ "$2" = "run" ]; then
        xcrun devicectl list devices --json-output build/devices.json >/dev/null
        UDID="$(plutil -extract result.devices.0.identifier raw build/devices.json 2>/dev/null)"
        [ -n "$UDID" ] || { echo "no iPhone found by devicectl — plug it in and unlock it" >&2; exit 1; }
        xcrun devicectl device install app --device "$UDID" build/LivDevice.app
        xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
        echo "installed + launched on device $UDID"
    fi
    exit 0
fi

cargo build --release -p liv-ffi --target aarch64-apple-ios-sim --manifest-path ../../Cargo.toml

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

mkdir -p build/Liv.app
swiftc -O -parse-as-library \
    Sources/*.swift \
    -sdk "$SDK" \
    -target arm64-apple-ios17.0-simulator \
    -import-objc-header ../../ffi/liv.h \
    ../../target/aarch64-apple-ios-sim/release/libliv_ffi.a \
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
