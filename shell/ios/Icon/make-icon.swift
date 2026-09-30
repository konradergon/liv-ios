// Draws the app icon Liv ships to TestFlight and the App Store.
//
// PLACEHOLDER, on purpose. Apple refuses a build with no icon, so this
// exists to unblock distribution, not to be the mark. It is a wordmark on
// the app's one live colour (Palette.accent, light scheme, #3167A5) so it
// at least belongs to the app rather than to a template. Replace the body
// of `draw` when the real mark exists; nothing else in the pipeline knows
// what this looks like.
//
// Apple's rules for the 1024 store icon, all enforced below: square, no
// alpha channel, no rounded corners (the system masks it), no transparency.
//
//   swiftc -O Icon/make-icon.swift -o build/make-icon && build/make-icon <out.png>

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024

func draw(into ctx: CGContext) {
    // The ground: the app's accent, light scheme.
    ctx.setFillColor(CGColor(red: 0x31 / 255.0, green: 0x67 / 255.0, blue: 0xA5 / 255.0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

    // The wordmark, big. The owner's standing note on this app is that
    // marks are drawn too small and too quiet; this fills the square.
    let size = CGFloat(side) * 0.42
    // CoreText's own attribute keys, not AppKit's `.font` / `.foregroundColor`
    // — those live in AppKit/UIKit, and this tool links neither.
    let font = CTFontCreateWithName("SFProDisplay-Bold" as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        // No kerning: CoreText hangs the trailing kern off the last glyph,
        // which optical bounds then count as ink, and the wordmark sits
        // visibly left of centre.
    ]
    let line = CTLineCreateWithAttributedString(
        CFAttributedStringCreate(nil, "liv" as CFString, attrs as CFDictionary))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(
        x: (CGFloat(side) - bounds.width) / 2 - bounds.minX,
        y: (CGFloat(side) - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, ctx)
}

// NO ALPHA. `.noneSkipLast` rather than `premultipliedLast`: an icon with
// an alpha channel is rejected at upload ("Invalid large app icon"), and
// that rejection arrives minutes later from Apple rather than from here.
guard let ctx = CGContext(
    data: nil, width: side, height: side,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("could not make the bitmap context") }

draw(into: ctx)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <out.png>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not open \(out.path) for writing") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path) — \(side)x\(side), no alpha")
