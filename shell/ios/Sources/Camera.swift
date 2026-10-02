// liv iOS — the scanner (owner, 2026-10-01: "camera: scanning only"). The
// camera reads the words on a page into a new note and keeps nothing
// else: no photo is written, no file entity is born. On the simulator (no
// camera device) a PhotosPicker stands in for the shutter — same path.
// Failure = haptic buzz (the phone's beep), never an alert.

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

private enum CameraPermission { case unknown, granted, denied }

// MARK: - the AVFoundation engine (real device only)

/// Owns the session; every session/device touch rides one serial queue —
/// the UI never blocks on camera hardware.
private final class CameraEngine: NSObject, ObservableObject {
    /// The back camera: pages are read with it, and the flip went with the
    /// photo shutter.
    static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    let session = AVCaptureSession()
    @Published private(set) var canTorch = false
    @Published private(set) var torchOn = false
    var onPhoto: ((Data) -> Void)?
    var onShotFailed: (() -> Void)?

    private let queue = DispatchQueue(label: "liv.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false

    func start() {
        queue.async {
            if !self.configured {
                self.configured = true
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.attach()
                if self.session.canAddOutput(self.output) {
                    self.session.addOutput(self.output)
                }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func toggleTorch() {
        queue.async {
            guard let device = self.device, device.hasTorch else { return }
            let on = device.torchMode != .on
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = on }
            } catch {}
        }
    }

    /// One frame, for its words. The system shutter sound fires here.
    func shoot() {
        queue.async {
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    /// Queue only.
    private func attach() {
        for input in session.inputs { session.removeInput(input) }
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            self.device = nil
            DispatchQueue.main.async {
                self.canTorch = false
                self.torchOn = false
            }
            return
        }
        session.addInput(input)
        self.device = device
        let torch = device.hasTorch
        DispatchQueue.main.async {
            self.canTorch = torch
            self.torchOn = false
        }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.onShotFailed?() }
            return
        }
        DispatchQueue.main.async { self.onPhoto?(data) }
    }
}

// MARK: - viewfinder

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct CameraViewfinder: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: CameraPreviewUIView, context: Context) {}
}

// MARK: - the flow

struct CameraFlow: View {
    /// Fires with the note a scan made; the chrome opens it.
    var onDone: ((LivEntityID) -> Void)? = nil

    @EnvironmentObject var model: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var engine = CameraEngine()

    @State private var permission: CameraPermission = .unknown
    /// True while Vision is reading; `said` is the one line shown when a
    /// page turned out to have no words on it.
    @State private var scanning = false
    @State private var said = ""
    /// Close was pressed: whatever the reader finds after that is dropped.
    @State private var closed = false
    @State private var pickerItem: PhotosPickerItem?

    private let hasCamera = CameraEngine.hasCamera

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasCamera, permission == .granted {
                CameraViewfinder(session: engine.session).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                if hasCamera, permission == .denied { deniedHint }
                shutterRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .environment(\.colorScheme, .dark)  // controls float on a black ground
        .onAppear { begin() }
        .onDisappear {
            closed = true
            engine.stop()
        }
        // The simulator's stand-in for the shutter.
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    scan(data)
                } else {
                    CameraFlow.buzz()
                }
                pickerItem = nil
            }
        }
    }

    // MARK: top bar — the torch where there is one, and the way out

    private var topBar: some View {
        HStack(spacing: 10) {
            if hasCamera, permission == .granted, engine.canTorch {
                roundButton(engine.torchOn ? "bolt.fill" : "bolt.slash", "Torch") {
                    engine.toggleTorch()
                }
            }
            Spacer()
            roundButton("xmark", "Close") {
                closed = true
                dismiss()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func roundButton(
        _ symbol: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: LivType.strong, weight: .medium))
                .foregroundStyle(LivTheme.cameraInk)
                .frame(width: LivCamera.control, height: LivCamera.control)
                .background(LivTheme.cameraChrome, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var deniedHint: some View {
        VStack(spacing: 2) {
            EmptyHint("Camera is off")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.system(size: LivType.body, weight: .semibold))
            .foregroundStyle(LivTheme.accent)
        }
        .padding(.bottom, 12)
    }

    // MARK: the shutter — one control, and it reads

    @ViewBuilder private var shutterRow: some View {
        VStack(spacing: 6) {
            // The screen says what it does: a bare shutter reads as "take a
            // photo", and this one only reads.
            EmptyHint(scanning ? "Reading…" : said.isEmpty ? "Scan text" : said)
            if hasCamera {
                if permission == .granted {
                    Button {
                        shoot()
                    } label: {
                        shutterFace
                    }
                    .buttonStyle(.plain)
                    .disabled(scanning)
                    .accessibilityLabel("Scan text")
                }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) { shutterFace }
                    .disabled(scanning)
                    .accessibilityLabel("Scan text")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shutterFace: some View {
        ZStack {
            Circle().strokeBorder(LivTheme.cameraInk, lineWidth: LivCamera.shutterRing)
                .frame(width: LivCamera.shutter, height: LivCamera.shutter)
            Circle().fill(LivTheme.cameraInk)
                .frame(width: LivCamera.shutterCore, height: LivCamera.shutterCore)
        }
        .opacity(scanning ? 0.6 : 1)
        .contentShape(Circle())
    }

    // MARK: acts

    private func begin() {
        engine.onPhoto = { scan($0) }
        engine.onShotFailed = {
            scanning = false
            CameraFlow.buzz()
        }
        guard hasCamera else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
            engine.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    permission = ok ? .granted : .denied
                    if ok { engine.start() }
                }
            }
        default:
            permission = .denied
        }
    }

    private func shoot() {
        guard !scanning else { return }
        said = ""
        scanning = true
        engine.shoot()
    }

    /// A frame taken to be READ. The bytes are recognised and dropped —
    /// only the characters cross over, into a note you land in (owner,
    /// 2026-08-19: "scan into a note, drop the photo"). Liv reviews AFTER,
    /// in the editor: the same words, fully editable, and a note you did
    /// not want is one swipe from the trash.
    private func scan(_ data: Data) {
        scanning = true
        LivScan.read(data) { found in
            // Closed while it read: the page was put away, and no note
            // turns up later that nobody asked to keep (review, 2026-10-02).
            guard !closed else { return }
            let text = found.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                // NO empty note. A page with no words on it is not a
                // document you meant to make.
                scanning = false
                said = "No text found"
                CameraFlow.buzz()
                return
            }
            // ONE action, words and all, so one undo takes it back. NO name:
            // the first line names it, the core's rule for anything unnamed.
            //
            // plainSpans, NOT textToSpans: what the camera read is not
            // markdown someone typed. The editor's parser deletes a line of
            // three or more dashes — the separator on every receipt — and
            // turns a printed "- [ ]" into a real task.
            let spans = SpanText.json(SpanText.plainSpans(text))
            model.makeNote(name: nil, spansJson: spans) { id in
                scanning = false
                guard !id.isAbsent else {
                    CameraFlow.buzz()
                    return
                }
                // Stamped like every other creation door.
                workspaces.stamp(id, in: model)
                guard !closed else { return }
                onDone?(id)
                dismiss()
            }
        }
    }

    /// The macOS shell beeps on failure; the phone buzzes.
    private static func buzz() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
