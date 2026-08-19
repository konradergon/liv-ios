import UIKit
import Vision

// MARK: - Scan text: a photographed page becomes words (owner, 2026-08-19)

/// On-device text recognition. No network, no key, no service.
///
/// The bytes are read and thrown away — the picture is never filed
/// (owner: *"scan into a note, drop the photo"*). This is Apple Notes'
/// Scan Text shape: the characters cross over and no image asset is
/// created. Keep and Google Docs keep the image and append the words
/// beside it; OneNote only fills the clipboard. Nobody keeps a photo you
/// took in order to read it.
///
/// Vision is an Apple framework, so this is one of the few things that
/// genuinely cannot live in the portable Rust core. Nothing here touches
/// the box: it takes bytes and returns a string.
enum LivScan {
    /// Read the words off an image. Empty is a perfectly good answer —
    /// most photographs have no words in them, and a picture of a dog
    /// must never put "dog" in your notes.
    static func read(_ data: Data, done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = recognise(data)
            DispatchQueue.main.async { done(found) }
        }
    }

    private static func recognise(_ data: Data) -> String {
        let request = VNRecognizeTextRequest()
        // .accurate is already the default; it is named here because the
        // choice is not only about speed — .fast supports SIX languages
        // (en, fr, it, de, es, pt) at every revision, so anything else
        // silently forces this path anyway.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Pinned. `revision` defaults to the latest of the SDK you LINKED
        // against, not the latest the device has — so a future SDK's
        // revision 4 would become the default on a phone that has no
        // revision 4. Revision 3 is iOS 16+, which every device this app
        // runs on has.
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = languages(for: request)

        // DATA, not cgImage. `VNImageRequestHandler(cgImage:)` has no
        // orientation and treats every buffer as upright, while
        // `UIImage(data:)?.cgImage` hands back the RAW sensor pixels — so
        // a page photographed in portrait arrives sideways and loses its
        // small glyphs, and a mirrored one comes back as gibberish
        // (measured, all eight EXIF values). The data handler reads the
        // EXIF tag itself. Passing an explicit `orientation:` here would
        // make it WORSE: the argument supersedes the file's own tag
        // rather than combining with it.
        let handler = VNImageRequestHandler(data: data, options: [:])
        try? handler.perform([request])

        // Reading order, one line per observation. This is right for a
        // page and wrong for two columns, which it reads across — the
        // words are all there, in the wrong order, and the editor you
        // land in is where that gets fixed.
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// What to ask for, filtered by what this OS actually has.
    ///
    /// Setting a language Vision does not support neither throws nor
    /// warns — the request just runs with a model you did not choose. And
    /// the list grew: Swedish was still missing in iOS 18.1 and is
    /// present now, so a hard-coded list is wrong on one OS or the other.
    /// Ask, intersect, and fall back to the default rather than guessing.
    private static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let wanted = ["sv-SE", "en-US"]
        guard let have = try? request.supportedRecognitionLanguages() else {
            return ["en-US"]
        }
        let usable = wanted.filter { have.contains($0) }
        return usable.isEmpty ? ["en-US"] : usable
    }
}
