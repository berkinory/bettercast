import AppKit
@preconcurrency import AVFoundation
import Carbon.HIToolbox
import SwiftUI

fileprivate enum CameraState: Equatable {
    case requestingPermission
    case starting
    case ready
    case denied
    case unavailable
    case failed(String)
}

fileprivate struct CameraDevice: Equatable, Sendable {
    let id: String
    let name: String
}

fileprivate struct CameraKeyboardEvent: Equatable {
    enum Command: Equatable {
        case activate
        case moveUp
        case moveDown
        case toggleMenu
        case toggleMirroring
        case showCameras
        case close
    }

    let id = UUID()
    let command: Command
}

private enum CameraCaptureError: Error, Sendable {
    case deviceUnavailable
    case inputUnavailable
    case outputUnavailable
    case captureUnavailable
    case processingFailed

    var message: String {
        switch self {
        case .deviceUnavailable: return "The selected camera is no longer available."
        case .inputUnavailable: return "Bettercast couldn't connect to this camera."
        case .outputUnavailable: return "This camera doesn't support photo capture."
        case .captureUnavailable: return "The camera isn't ready to take a photo."
        case .processingFailed: return "Bettercast couldn't process the captured photo."
        }
    }
}

private final class CameraCaptureEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(
        label: "com.bettercast.camera-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var captureCompletion: (@Sendable (Result<Data, CameraCaptureError>) -> Void)?

    static func availableDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: .video)?.uniqueID
        var seen = Set<String>()
        return discovery.devices
            .filter { seen.insert($0.uniqueID).inserted }
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted {
                if $0.id == defaultID { return true }
                if $1.id == defaultID { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func start(
        deviceID: String,
        completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in
            switch configure(deviceID: deviceID) {
            case .success:
                if !session.isRunning { session.startRunning() }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func switchDevice(
        to deviceID: String,
        completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in completion(configure(deviceID: deviceID)) }
    }

    func capture(
        mirrored: Bool,
        completion: @escaping @Sendable (Result<Data, CameraCaptureError>) -> Void
    ) {
        queue.async { [self] in
            guard
                session.isRunning,
                captureCompletion == nil,
                let connection = photoOutput.connection(with: .video)
            else {
                completion(.failure(.captureUnavailable))
                return
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            captureCompletion = completion
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stop() {
        queue.sync { [self] in
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            if let currentInput {
                session.removeInput(currentInput)
                self.currentInput = nil
            }
            if session.outputs.contains(where: { $0 === photoOutput }) {
                session.removeOutput(photoOutput)
            }
            session.commitConfiguration()
            captureCompletion = nil
        }
    }

    private func configure(deviceID: String) -> Result<Void, CameraCaptureError> {
        guard let device = Self.captureDevices().first(where: { $0.uniqueID == deviceID }) else {
            return .failure(.deviceUnavailable)
        }
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: device)
        } catch {
            return .failure(.inputUnavailable)
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }

        let previousInput = currentInput
        if let previousInput { session.removeInput(previousInput) }
        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            return .failure(.inputUnavailable)
        }
        session.addInput(newInput)
        currentInput = newInput

        if !session.outputs.contains(where: { $0 === photoOutput }) {
            guard session.canAddOutput(photoOutput) else {
                session.removeInput(newInput)
                currentInput = nil
                if let previousInput, session.canAddInput(previousInput) {
                    session.addInput(previousInput)
                    currentInput = previousInput
                }
                return .failure(.outputUnavailable)
            }
            session.addOutput(photoOutput)
        }
        return .success(())
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

extension CameraCaptureEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let result: Result<Data, CameraCaptureError>
        if error != nil {
            result = .failure(.processingFailed)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(.processingFailed)
        }
        queue.async { [self] in
            let completion = captureCompletion
            captureCompletion = nil
            completion?(result)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        guard error != nil else { return }
        queue.async { [self] in
            let completion = captureCompletion
            captureCompletion = nil
            completion?(.failure(.processingFailed))
        }
    }
}

@MainActor
final class CameraSessionModel: ObservableObject {
    @Published fileprivate var state: CameraState = .starting
    @Published fileprivate var devices: [CameraDevice] = []
    @Published fileprivate var selectedDeviceID: String?
    @Published private(set) var isCapturing = false
    @Published var isMirrored = true
    @Published private(set) var feedback: String?
    @Published private(set) var feedbackToken = UUID()
    @Published private(set) var flashToken = UUID()
    @Published fileprivate var keyboardEvent: CameraKeyboardEvent?

    let session: AVCaptureSession
    private let engine = CameraCaptureEngine()
    private var feedbackTask: Task<Void, Never>?
    private var lifecycleID = UUID()
    private var isStarted = false

    init() {
        session = engine.session
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            discoverAndStart(lifecycleID: lifecycleID)
        case .notDetermined:
            state = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.isStarted, self.lifecycleID == lifecycleID else { return }
                    if granted {
                        self.discoverAndStart(lifecycleID: lifecycleID)
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func stop() {
        isStarted = false
        lifecycleID = UUID()
        feedbackTask?.cancel()
        feedbackTask = nil
        feedback = nil
        isCapturing = false
        engine.stop()
    }

    func takePhoto() {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true
        let lifecycleID = self.lifecycleID
        engine.capture(mirrored: isMirrored) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isStarted, self.lifecycleID == lifecycleID else { return }
                self.isCapturing = false
                switch result {
                case .success(let data):
                    guard
                        let png = NSBitmapImageRep(data: data)?.representation(
                            using: .png, properties: [:])
                    else {
                        self.showFeedback(CameraCaptureError.processingFailed.message)
                        return
                    }
                    Paster.copyImage(png)
                    self.flashToken = UUID()
                    self.showFeedback("Photo copied to clipboard")
                case .failure(let error):
                    self.showFeedback(error.message)
                }
            }
        }
    }

    func toggleMirroring() {
        isMirrored.toggle()
        showFeedback(isMirrored ? "Mirroring on" : "Mirroring off")
    }

    fileprivate func selectCamera(_ device: CameraDevice) {
        guard !isCapturing else { return }
        guard device.id != selectedDeviceID else {
            showFeedback("\(device.name) is already selected")
            return
        }
        guard devices.contains(device) else {
            showFeedback(CameraCaptureError.deviceUnavailable.message)
            return
        }
        state = .starting
        let lifecycleID = self.lifecycleID
        engine.switchDevice(to: device.id) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isStarted, self.lifecycleID == lifecycleID else { return }
                switch result {
                case .success:
                    self.selectedDeviceID = device.id
                    self.state = .ready
                    self.showFeedback("Switched to \(device.name)")
                case .failure(let error):
                    self.state = .failed(error.message)
                }
            }
        }
    }

    func openCameraSettings() {
        Permissions.openCameraSettings()
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let commandDown = event.modifierFlags.contains(.command)
        let keyCode = Int(event.keyCode)
        let command: CameraKeyboardEvent.Command?
        if commandDown {
            switch keyCode {
            case kVK_ANSI_K: command = .toggleMenu
            case kVK_ANSI_M: command = .toggleMirroring
            case kVK_ANSI_S: command = .showCameras
            default: command = nil
            }
        } else {
            switch keyCode {
            case kVK_Return, kVK_ANSI_KeypadEnter: command = .activate
            case kVK_UpArrow: command = .moveUp
            case kVK_DownArrow: command = .moveDown
            case kVK_Escape: command = .close
            default: command = nil
            }
        }
        guard let command else { return false }
        keyboardEvent = CameraKeyboardEvent(command: command)
        return true
    }

    private func discoverAndStart(lifecycleID: UUID) {
        devices = CameraCaptureEngine.availableDevices()
        guard let device = devices.first else {
            state = .unavailable
            return
        }
        selectedDeviceID = device.id
        state = .starting
        engine.start(deviceID: device.id) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isStarted, self.lifecycleID == lifecycleID else { return }
                switch result {
                case .success: self.state = .ready
                case .failure(let error): self.state = .failed(error.message)
                }
            }
        }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        feedback = text
        feedbackToken = UUID()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session, mirrored: mirrored)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.setMirrored(mirrored)
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.detach()
    }
}

private final class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession, mirrored: Bool) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        setMirrored(mirrored)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else {
            return
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    func detach() {
        previewLayer.session = nil
        previewLayer.removeFromSuperlayer()
    }

}

struct CameraView: View {
    private enum MenuLevel: Equatable {
        case actions
        case cameras
    }

    @EnvironmentObject private var palette: PaletteViewModel
    @ObservedObject var model: CameraSessionModel
    let onBack: () -> Void
    let onFeedback: (String) -> Void
    let onMenuOpenChanged: (Bool) -> Void

    @State private var menuOpen = false
    @State private var menuLevel = MenuLevel.actions
    @State private var menuSelection = 0
    @State private var flashOpacity = 0.0

    private var selectedDeviceName: String? {
        guard let id = model.selectedDeviceID else { return nil }
        return model.devices.first(where: { $0.id == id })?.name
    }

    private var actionItems: [PopoverMenuItem] {
        [
            PopoverMenuItem(
                title: "Take Photo", systemImage: "camera", shortcut: "↵",
                action: model.takePhoto),
            PopoverMenuItem(
                title: model.isMirrored ? "Turn Mirroring Off" : "Turn Mirroring On",
                systemImage: "arrow.left.and.right", shortcut: "⌘M", action: model.toggleMirroring),
            PopoverMenuItem(
                title: "Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera",
                shortcut: "⌘S", action: showCameraChoices),
        ]
    }

    private var cameraItems: [PopoverMenuItem] {
        model.devices.map { device in
            PopoverMenuItem(
                title: device.name,
                systemImage: device.id == model.selectedDeviceID ? "checkmark" : "video",
                action: { model.selectCamera(device) }
            )
        }
    }

    private var menuItems: [PopoverMenuItem] {
        switch menuLevel {
        case .actions: return actionItems
        case .cameras: return cameraItems
        }
    }

    var body: some View {
        ZStack {
            Color.black
            preview
            controls
            if menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenu)
                PopoverMenu(
                    header: menuLevel == .actions ? selectedDeviceName : "Select Camera",
                    items: menuItems,
                    selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(.trailing, Theme.Spacing.md)
                .padding(.bottom, Theme.Size.bottomBarHeight + Theme.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            Color.white
                .opacity(flashOpacity)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.flashToken) {
            flashOpacity = 0.7
            withAnimation(.easeOut(duration: 0.22)) { flashOpacity = 0 }
        }
        .onChange(of: model.keyboardEvent) { _, event in
            guard let event else { return }
            handleKeyboard(event.command)
        }
        .onChange(of: model.feedbackToken) {
            if let feedback = model.feedback { onFeedback(feedback) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch model.state {
        case .ready:
            CameraPreview(session: model.session, mirrored: model.isMirrored)
        case .requestingPermission:
            placeholder(
                icon: "video.badge.ellipsis", title: "Camera Access",
                message: "Allow Bettercast to use your camera in the macOS prompt.")
        case .starting:
            placeholder(
                icon: "camera", title: "Starting Camera", message: selectedDeviceName ?? "Connecting…", progress: true)
        case .denied:
            placeholder(
                icon: "video.slash", title: "Camera Access Is Off",
                message: "Allow Bettercast in Privacy & Security › Camera.", buttonTitle: "Open System Settings",
                buttonAction: model.openCameraSettings)
        case .unavailable:
            placeholder(
                icon: "video.slash", title: "No Camera Found", message: "Connect a camera and reopen this command.")
        case .failed(let message):
            placeholder(icon: "exclamationmark.triangle", title: "Camera Unavailable", message: message)
        }
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                if let feedback = palette.feedback {
                    PaletteFeedbackButton(message: feedback.message)
                } else {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "camera.fill")
                        Text(selectedDeviceName ?? "Open Camera")
                            .lineLimit(1)
                    }
                    .font(Theme.Typography.bar)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: Theme.Size.menuButton)
                    .frosted(in: Capsule())
                }
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    PaletteBarButton(action: model.takePhoto) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(model.isCapturing ? "Taking Photo…" : "Take Photo")
                                .font(Theme.Typography.bar)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            KeyCapChip(text: "↵", style: .outline)
                        }
                    }
                    .disabled(model.state != .ready || model.isCapturing)
                    PaletteBarButton(action: toggleMenu) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Actions")
                                .font(Theme.Typography.bar)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: Theme.Spacing.xxs) {
                                KeyCapChip(text: "⌘", style: .outline)
                                KeyCapChip(text: "K", style: .outline)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
                .frosted(in: Capsule())
            }
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private func placeholder(
        icon: String,
        title: String,
        message: String,
        progress: Bool = false,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            if progress {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(Theme.Typography.iconHero)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Theme.Spacing.xs) {
                Text(title).font(Theme.Typography.title3Semibold)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let buttonAction {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activateMenuItem(_ index: Int) {
        guard menuItems.indices.contains(index) else { return }
        let currentLevel = menuLevel
        menuItems[index].action()
        if currentLevel == menuLevel { closeMenu() }
    }

    private func handleKeyboard(_ command: CameraKeyboardEvent.Command) {
        switch command {
        case .activate:
            if menuOpen { activateMenuItem(menuSelection) } else { model.takePhoto() }
        case .moveUp:
            guard menuOpen else { return }
            menuSelection = max(0, menuSelection - 1)
        case .moveDown:
            guard menuOpen, !menuItems.isEmpty else { return }
            menuSelection = min(menuItems.count - 1, menuSelection + 1)
        case .toggleMenu:
            toggleMenu()
        case .toggleMirroring:
            model.toggleMirroring()
        case .showCameras:
            showCameraChoices()
        case .close:
            if menuOpen { closeMenu() } else { onBack() }
        }
    }

    private func toggleMenu() {
        if menuOpen {
            closeMenu()
        } else {
            menuLevel = .actions
            menuSelection = 0
            menuOpen = true
            onMenuOpenChanged(true)
        }
    }

    private func showCameraChoices() {
        guard !model.devices.isEmpty else { return }
        menuLevel = .cameras
        menuSelection = model.devices.firstIndex(where: { $0.id == model.selectedDeviceID }) ?? 0
        menuOpen = true
        onMenuOpenChanged(true)
    }

    private func closeMenu() {
        menuOpen = false
        menuLevel = .actions
        menuSelection = 0
        onMenuOpenChanged(false)
    }
}
