#!/bin/sh
# Build the iOS shell: the Rust seam for the simulator, then the Swift app bundle.
# No Xcode project — one swiftc invocation for the app and one for the
# share extension inside it (2026-09-09).
set -e
cd "$(dirname "$0")"

# System tools first. This machine has plan9 grep/sed earlier in PATH, and
# they have neither `grep -m` nor `sed -E` — which silently emptied the
# signing identity and made a device build claim the certificate was
# missing. Everything else (cargo, swiftc) still resolves further down.
PATH="/usr/bin:/bin:$PATH"

BUNDLE_ID="app.liv.ios"
SHARE_ID="app.liv.ios.share"

# THE SHARE EXTENSION — Liv in every app's share row. A second bundle
# inside the app (PlugIns/LivShare.appex) with its own binary, built by
# a second swiftc: `-application-extension` keeps it to the APIs an
# extension may use, `-e _NSExtensionMain` is the entry point every
# extension has (Foundation's, not a main.swift), and the entitlements
# are linked into a `__TEXT,__entitlements` section, which is where the
# simulator reads them from (Xcode does the same for its simulator
# builds). It links UIKit and Foundation only — no Rust, no SwiftUI —
# and shares exactly one source file with the app (Catch.swift).
#
# This used to be believed to need a real Xcode project (design/ios.md
# M1 status, Routes.swift). It needs a plist, a second swiftc and a
# signature, all of which this script already knew how to do.
#   $1 the swiftc target, $2 the app bundle, $3 the extension's plist
share_extension() {
    APPEX="$2/PlugIns/LivShare.appex"
    mkdir -p "$APPEX"
    swiftc -O -parse-as-library -application-extension \
        -module-name LivShare \
        ShareExtension/*.swift Sources/Catch.swift \
        -sdk "$SDK" \
        -target "$1" \
        -framework UIKit -framework Foundation \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker Liv.entitlements \
        -o "$APPEX/LivShare"
    cp "$3" "$APPEX/Info.plist"
}

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

    # The extension needs a profile of its OWN, scoped to $SHARE_ID, and
    # both profiles must carry the App Group (Liv.entitlements) or the
    # extension has nowhere to leave a catch. Made the same way as the
    # app's (design/ios.md — testing on a device). Without one the app
    # still builds and runs; it just has no share row entry.
    SHARE_PROFILE=""
    for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
        [ -e "$f" ] || continue
        name="$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name xml1 -o - - 2>/dev/null)"
        case "$name" in
        *"$SHARE_ID"*) SHARE_PROFILE="$f"; break ;;
        esac
    done
    if [ -n "$SHARE_PROFILE" ]; then
        share_extension arm64-apple-ios17.0 build/LivDevice.app ShareExtension/Info-device.plist
        cp "$SHARE_PROFILE" "$APPEX/embedded.mobileprovision"
        security cms -D -i "$SHARE_PROFILE" 2>/dev/null \
            | plutil -extract Entitlements xml1 -o build/share-entitlements.plist -
        codesign --force --sign "$IDENTITY" \
            --entitlements build/share-entitlements.plist \
            "$APPEX"
    else
        echo "no provisioning profile scoped to $SHARE_ID — building without the share extension." >&2
    fi

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
SIM_TARGET="arm64-apple-ios17.0-simulator"

mkdir -p build/Liv.app
swiftc -O -parse-as-library \
    Sources/*.swift \
    -sdk "$SDK" \
    -target "$SIM_TARGET" \
    -import-objc-header ../../ffi/liv.h \
    ../../target/aarch64-apple-ios-sim/release/libliv_ffi.a \
    -framework SwiftUI -framework UIKit -framework AVFoundation \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker Liv.entitlements \
    -o build/Liv.app/Liv

cp Info.plist build/Liv.app/Info.plist
share_extension "$SIM_TARGET" build/Liv.app ShareExtension/Info.plist

# AD-HOC SIGNED, ENTITLEMENTS INCLUDED. Simulator bundles used to go
# unsigned ("the plist is the whole assembly") and could, because nothing
# in them claimed an entitlement. The App Group is a claim, and the
# extension is a second signed thing inside the first; this is what Xcode
# does for its own simulator builds. Inner bundle first.
codesign --force --sign - --entitlements Liv.entitlements "$APPEX"
codesign --force --sign - --entitlements Liv.entitlements build/Liv.app

echo "built: shell/ios/build/Liv.app (with PlugIns/LivShare.appex)"

if [ "$1" = "run" ]; then
    UDID="$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    [ -n "$UDID" ] || { echo "no available iPhone simulator" >&2; exit 1; }
    xcrun simctl boot "$UDID" 2>/dev/null || true   # already-booted is fine
    open -a Simulator
    xcrun simctl install "$UDID" build/Liv.app
    xcrun simctl launch "$UDID" app.liv.ios
    echo "screenshot: xcrun simctl io booted screenshot /tmp/liv.png"
fi
