// liv iOS — the camera flow (design/ios.md §6). Shoot FIRST, tag after:
// the entity is committed at the shutter sound (bytes → Application
// Support/liv/photos, then liv_add_file_at); the tray tags while the
// viewfinder stays live. On the simulator (no camera device) a
// PhotosPicker stands in for the shutter — same downstream path.
// Failure = haptic buzz (the phone's beep), never an alert.

import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Solid ink for controls sitting on the live viewfinder. The rest of the
/// shell dropped blur materials (owner, 2026-07-29) and so does this — but
/// a themed surface would vanish against a bright frame in light mode, so
/// camera chrome carries its own opaque dark.
private let cameraChromeFill = Color(red: 0x1B / 255, green: 0x22 / 255, blue: 0x20 / 255)

// MARK: - session tray rows

private struct CameraShot: Identifiable {
    let id: UInt64  // the committed entity — real from the shutter sound
    let thumb: UIImage?
}

/// One chip already fired at an entity — display state only; the box
/// holds the truth.
private struct CameraApplied: Identifiable {
    let property: String
    let value: String
    var id: String { property + ":" + value }
}

/// Tag/person are multi-valued (addCell = membership); project and area
/// replace. Area is fixed furniture: its editor offers the six options
/// only — no type-to-create (§10's door rule).
private enum CameraChipKind: String, Identifiable {
    case area, tag, project, person
    var id: String { rawValue }
    var property: String {
        switch self {
        case .area: return "area"
        case .tag: return "subjects"
        case .project: return "project"
        case .person: return "people"
        }
    }
    var multi: Bool { self == .tag || self == .person }
    var label: String {
        switch self {
        case .area: return "Area"
        case .tag: return "Tag"
        case .project: return "Project"
        case .person: return "Person"
        }
    }
}

private enum CameraPermission { case unknown, granted, denied }

// MARK: - disk: <Application Support>/liv/photos/<uuid>.heic|jpg

/// Camera bytes pass through untouched (already HEIC or JPEG); picker
/// exotics (PNG…) re-encode — HEIC where the encoder exists, else JPEG.
private enum CameraStore {
    static func write(_ data: Data) -> String? {
        guard let (bytes, ext) = normalize(data) else { return nil }
        do {
            let dir = try directory()
            let url = dir.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try bytes.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private static func directory() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        .appendingPathComponent("liv", isDirectory: true)
        .appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
        return base
    }

    private static func normalize(_ data: Data) -> (Data, String)? {
        if let ext = sniff(data) { return (data, ext) }
        guard let image = UIImage(data: data) else { return nil }
        if let heic = encodeHEIC(image) { return (heic, "heic") }
        if let jpeg = image.jpegData(compressionQuality: 0.9) {
            return (jpeg, "jpg")
        }
        return nil
    }

    private static func sniff(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xD8 { return "jpg" }
        if b.count >= 12, b[4...7].elementsEqual("ftyp".utf8) {
            let brand = String(decoding: b[8...11], as: UTF8.self)
            if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) {
                return "heic"
            }
        }
        return nil
    }

    /// nil where the HEVC encoder is absent (older simulators) — JPEG
    /// fallback covers it.
    private static func encodeHEIC(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let out = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                out, UTType.heic.identifier as CFString, 1, nil)
        else { return nil }
        let options =
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(dest, cg, options)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

// MARK: - the AVFoundation engine (real device only)

/// Owns the session; every session/device touch rides one serial queue —
/// the UI never blocks on camera hardware.
private final class CameraEngine: NSObject, ObservableObject {
    static var hasCamera: Bool {
        AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    let session = AVCaptureSession()
    @Published private(set) var canTorch = false
    @Published private(set) var torchOn = false
    var onPhoto: ((Data) -> Void)?
    var onShotFailed: (() -> Void)?

    private let queue = DispatchQueue(label: "liv.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .back
    private var configured = false

    func start() {
        queue.async {
            if !self.configured {
                self.configured = true
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.attach(self.position)
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

    func flip() {
        queue.async {
            self.position = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            self.attach(self.position)
            self.session.commitConfiguration()
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

    /// HEIC when the pipeline offers HEVC, else the default (JPEG). The
    /// system shutter sound fires here — the commit's audible moment.
    func shoot() {
        queue.async {
            let settings: AVCapturePhotoSettings
            if self.output.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Queue only. Replaces the input; torch state resets with the device.
    private func attach(_ position: AVCaptureDevice.Position) {
        for input in session.inputs { session.removeInput(input) }
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: position),
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
    /// Fires on Done with the session's committed entity ids, in shot
    /// order. The chrome may open the last one as a desk tab; the flow
    /// itself never leaves the viewfinder mid-session.
    var onDone: (([UInt64]) -> Void)? = nil

    @EnvironmentObject var model: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var engine = CameraEngine()

    @State private var permission: CameraPermission = .unknown
    @State private var shots: [CameraShot] = []
    @State private var target: UInt64 = 0
    @State private var caption = ""
    @State private var captions: [UInt64: String] = [:]
    @State private var applied: [UInt64: [CameraApplied]] = [:]
    @State private var applyAll = false
    @State private var adding: CameraChipKind?
    @State private var chipText = ""
    @State private var suggestions: [String] = []
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
                tray
            }
        }
        .environment(\.colorScheme, .dark)  // controls float on a black ground
        .onAppear { begin() }
        .onDisappear { engine.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    ingest(data)
                } else {
                    CameraFlow.buzz()
                }
                pickerItem = nil
            }
        }
    }

    // MARK: top bar — torch/flip only where a camera exists; Done = exit

    private var topBar: some View {
        HStack(spacing: 10) {
            if hasCamera, permission == .granted {
                if engine.canTorch {
                    roundButton(engine.torchOn ? "bolt.fill" : "bolt.slash") {
                        engine.toggleTorch()
                    }
                }
                roundButton("arrow.triangle.2.circlepath.camera") {
                    engine.flip()
                }
            }
            Spacer()
            Button {
                commitCaption()
                onDone?(shots.map(\.id))
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(LivTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: LivType.strong, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(cameraChromeFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var deniedHint: some View {
        VStack(spacing: 2) {
            EmptyHint(
                "Camera access is off. Liv commits the photo at the shutter — allow the camera in Settings to shoot."
            )
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

    // MARK: tray — thumbnails, caption, chips; the viewfinder stays live

    private var tray: some View {
        VStack(spacing: 8) {
            if adding != nil { chipEditor }
            if !shots.isEmpty { trayPanel }
            shutterRow
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var trayPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shots) { shot in
                            thumbButton(shot)
                        }
                    }
                }
                .frame(height: LivRow.height)
                .onChange(of: shots.count) { _, _ in
                    if let last = shots.last {
                        withAnimation { proxy.scrollTo(last.id) }
                    }
                }
            }
            TextField("Caption", text: $caption)
                .font(.system(size: LivType.body))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { commitCaption() }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                        .fill(LivTheme.panel)
                )
            chipRow
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .fill(LivTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
    }

    private func thumbButton(_ shot: CameraShot) -> some View {
        Button {
            retarget(shot.id)
        } label: {
            Group {
                if let thumb = shot.thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    LivTheme.panel2.overlay(
                        Image(systemName: "photo")
                            .font(.system(size: LivType.body))
                            .foregroundStyle(LivTheme.muted)
                    )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: LivTheme.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(
                        shot.id == target ? LivTheme.accent : LivTheme.border,
                        lineWidth: shot.id == target ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .id(shot.id)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            // What the active workspace already put on this shot (M4).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(applied[target] ?? []) { chip in
                        ValueChip(chip.value)
                    }
                    // Fixed furniture leads: Area is the one filing question.
                    AddChip("Area") { openChip(.area) }
                    AddChip("Tag") { openChip(.tag) }
                    AddChip("Project") { openChip(.project) }
                    AddChip("Person") { openChip(.person) }
                }
            }
            if shots.count > 1 {
                Button {
                    applyAll.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(
                            systemName: applyAll
                                ? "checkmark.square.fill" : "square"
                        )
                        .font(.system(size: LivType.label))
                        Text("Apply to all (\(shots.count))")
                            .font(.system(size: LivType.label).monospacedDigit())
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        applyAll ? LivTheme.accent : LivTheme.text3
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Three-layer lite: used values (count-desc, fetched once on open) →
    /// type-to-create. Commit fires the verb(s) and closes. Area is the
    /// exception (§10): a pick-only row of the six areas — no text field,
    /// no create.
    private var chipEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if adding == .area {
                HStack(spacing: 6) {
                    Text("Area")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.text2)
                    Spacer()
                    Button {
                        adding = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: LivType.label, weight: .semibold))
                            .foregroundStyle(LivTheme.text3)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 6) {
                    TextField(
                        "New \(adding?.label.lowercased() ?? "value")",
                        text: $chipText
                    )
                    .font(.system(size: LivType.body))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { applyChip(chipText) }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                            .fill(LivTheme.panel)
                    )
                    Button { applyChip(chipText) } label: {
                        Text("Add")
                            .font(.system(size: LivType.body, weight: .semibold))
                            .foregroundStyle(LivTheme.accent)
                    }
                    .buttonStyle(.plain)
                    Button {
                        adding = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: LivType.label, weight: .semibold))
                            .foregroundStyle(LivTheme.text3)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !filteredSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(filteredSuggestions, id: \.self) { value in
                            Button { applyChip(value) } label: {
                                ValueChip(value)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .fill(LivTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
    }

    private var filteredSuggestions: [String] {
        // Area is pick-only: every option stays visible, nothing filters.
        if adding == .area { return suggestions }
        let typed = chipText.trimmingCharacters(in: .whitespaces)
        let pool =
            typed.isEmpty
            ? suggestions
            : suggestions.filter {
                $0.localizedCaseInsensitiveContains(typed)
            }
        return Array(pool.prefix(8))
    }

    // MARK: shutter row — real shutter, or the simulator's stand-in

    @ViewBuilder private var shutterRow: some View {
        if hasCamera {
            if permission == .granted {
                Button {
                    engine.shoot()
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3)
                            .frame(width: 62, height: 62)
                        Circle().fill(.white).frame(width: 50, height: 50)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shutter")
            }
        } else {
            VStack(spacing: 6) {
                EmptyHint("simulator: pick a photo to stand in for the shutter")
                    .padding(.vertical, 0)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3)
                            .frame(width: 62, height: 62)
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: LivType.display))
                            .foregroundStyle(.white)
                    }
                    .contentShape(Circle())
                }
                .accessibilityLabel("Pick a photo")
            }
        }
    }

    // MARK: acts

    private func begin() {
        engine.onPhoto = { ingest($0) }
        engine.onShotFailed = { CameraFlow.buzz() }
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

    /// Shutter and picker converge here: bytes to disk off-main, then
    /// liv_add_file_at — the entity exists before any tagging happens.
    private func ingest(_ data: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let path = CameraStore.write(data) else {
                DispatchQueue.main.async { CameraFlow.buzz() }
                return
            }
            let thumb = UIImage(data: data)?.preparingThumbnail(
                of: CGSize(width: 160, height: 160))
            DispatchQueue.main.async {
                model.addFile(path) { id in
                    guard id != 0 else {
                        CameraFlow.buzz()
                        return
                    }
                    commitCaption()  // the shot the user was captioning
                    // Photos inherit the active workspace like every other
                    // capture door (M4); the tray's stamp line says so.
                    workspaces.stamp(id, in: model)
                    shots.append(CameraShot(id: id, thumb: thumb))
                    target = id
                    caption = captions[id] ?? ""
                }
            }
        }
    }

    private func retarget(_ id: UInt64) {
        commitCaption()
        target = id
        caption = captions[id] ?? ""
    }

    /// Caption is per-shot (the apply-all toggle governs chips only).
    private func commitCaption() {
        guard target != 0 else { return }
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != (captions[target] ?? ""), !text.isEmpty else { return }
        captions[target] = text
        model.set(target, "name", text)
    }

    private func openChip(_ kind: CameraChipKind) {
        adding = kind
        chipText = ""
        if kind == .area {
            // Fixed furniture first; union in whatever the box holds.
            suggestions = Furnish.areaNames
            model.distinctValues(property: "area") { live in
                var merged = Furnish.areaNames
                for v in live
                where !merged.contains(where: {
                    $0.compare(v, options: .caseInsensitive) == .orderedSame
                }) {
                    merged.append(v)
                }
                suggestions = merged
            }
        } else {
            suggestions = []
            model.distinctValues(property: kind.property) { suggestions = $0 }
        }
    }

    /// One verb per entity: membership properties addCell, project/area
    /// set. Chip honesty: the chip is recorded ONLY in the verb's success
    /// callback — a refused write buzzes and leaves no chip.
    private func applyChip(_ raw: String) {
        guard let kind = adding else { return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let ids = applyAll ? shots.map(\.id) : [target]
        for id in ids where id != 0 {
            let done: (Bool) -> Void = { ok in
                guard ok else { return CameraFlow.buzz() }
                var list = applied[id, default: []]
                let chip = CameraApplied(property: kind.property, value: value)
                if !list.contains(where: { $0.id == chip.id }) {
                    list.append(chip)
                    applied[id] = list
                }
            }
            if kind.multi {
                model.addCell(id, kind.property, value, done: done)
            } else {
                model.set(id, kind.property, value, done: done)
            }
        }
        adding = nil
    }

    /// The macOS shell beeps on failure; the phone buzzes.
    private static func buzz() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
