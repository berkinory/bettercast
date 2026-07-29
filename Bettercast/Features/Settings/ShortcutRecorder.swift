import AppKit
import Carbon.HIToolbox
import SwiftUI

private enum ShortcutCaptureState: Equatable {
    case recording
    case editing(KeyShortcut)
    case conflict(owner: String, shortcut: KeyShortcut)
    case success(KeyShortcut)

    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Keeps focus in Settings while a local event monitor captures the binding.
struct ShortcutRecorder: View {
    private enum FocusedControl: Hashable {
        case recorder
        case clear
    }

    let action: HotKeyAction

    @ObservedObject private var hotKeys: HotKeyManager = AppCore.shared.hotKeys
    @StateObject private var session = CaptureSession()
    @State private var clearHovered = false
    @FocusState private var focusedControl: FocusedControl?

    private var isRecording: Bool { hotKeys.recordingAction == action }
    private var shortcut: KeyShortcut? { hotKeys.shortcut(for: action) }

    var body: some View {
        ZStack(alignment: .trailing) {
            recorderButton
            if shortcut != nil && !isRecording {
                HStack(spacing: 0) {
                    divider
                    clearButton
                }
            }
        }
        .frame(width: Theme.Settings.Size.shortcutRecorderWidth)
        .overlay(
            containerShape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .clipShape(containerShape)
        .contentShape(containerShape)
        .background {
            ShortcutCapturePopoverPresenter(isPresented: recordingBinding) {
                ShortcutCapturePopover(
                    session: session,
                    targetName: hotKeys.displayName(of: action),
                    targetIcon: targetIcon
                )
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                session.start(action: action, hotKeys: hotKeys)
            } else {
                session.stop()
            }
        }
        // Rows in the app-hotkeys list are lazy: a recording row scrolled out of existence must release its monitors and unpause the global hotkeys.
        .onDisappear {
            if isRecording { hotKeys.recordingAction = nil }
            session.stop()
        }
    }

    private var recorderButton: some View {
        Button(action: startRecording) {
            recorderContent
                .padding(.leading, Theme.Spacing.md)
                .padding(
                    .trailing,
                    shortcut == nil || isRecording
                        ? Theme.Spacing.md : Theme.Settings.Size.shortcutRecorderClearWidth
                )
                .frame(
                    width: Theme.Settings.Size.shortcutRecorderWidth,
                    height: Theme.Settings.Size.shortcutRecorderHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedControl, equals: .recorder)
        .onKeyPress(.return) {
            startRecording()
            return .handled
        }
        .help(shortcut == nil ? "Record hotkey" : "Change hotkey")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Space or Return to record a hotkey")
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Settings.Colors.rowDivider)
            .frame(width: 1, height: Theme.Size.keyCap)
    }

    private var clearButton: some View {
        Button(action: clearShortcut) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    clearHovered ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
                )
                .frame(
                    width: Theme.Settings.Size.shortcutRecorderClearWidth,
                    height: Theme.Settings.Size.shortcutRecorderHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedControl, equals: .clear)
        .onHover { clearHovered = $0 }
        .help("Clear hotkey")
        .accessibilityLabel("Clear hotkey")
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Settings.Radius.controlIcon, style: .continuous)
    }

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { isRecording },
            set: { presented in
                if !presented, isRecording { hotKeys.recordingAction = nil }
            }
        )
    }

    private var targetIcon: NSImage {
        switch action {
        case .app(let bundleID):
            return AppCore.shared.appIndex.apps.first {
                $0.kind == .application && $0.bundleID == bundleID
            }?.icon ?? NSApp.applicationIconImage
        case .settingsPane(let bundleID):
            return AppCore.shared.appIndex.apps.first {
                $0.kind == .systemSettings && $0.bundleID == bundleID
            }?.icon ?? NSApp.applicationIconImage
        case .togglePalette:
            return featureIcon(named: "magnifyingglass", description: "App Launcher")
        case .toggleClipboard:
            return featureIcon(named: "doc.on.clipboard", description: "Clipboard History")
        case .toggleEmoji:
            return featureIcon(named: "face.smiling", description: "Emoji & Symbols")
        }
    }

    private func featureIcon(named name: String, description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSApp.applicationIconImage
    }

    private var accessibilityLabel: String {
        guard let shortcut else { return "Record hotkey" }
        return "Change hotkey, currently \(shortcut.keycaps.joined())"
    }

    private func startRecording() {
        guard !isRecording else { return }
        hotKeys.recordingAction = action
    }

    private func clearShortcut() {
        hotKeys.setShortcut(nil, for: action)
        hotKeys.recordingAction = nil
    }

    @ViewBuilder
    private var recorderContent: some View {
        if isRecording, let captured = session.capturedShortcut {
            HotkeyInlineValue(caps: captured.keycaps)
        } else if isRecording {
            let caps = KeyShortcut.collapsedModifierSymbols(from: session.heldModifiers)
            if caps.isEmpty {
                Text("Press Keys")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                HotkeyInlineValue(caps: caps)
            }
        } else if let shortcut {
            HotkeyInlineValue(caps: shortcut.keycaps)
        } else {
            Text("Record Hotkey")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

private struct HotkeyInlineValue: View {
    let caps: [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
    }
}

private struct ShortcutCapturePopoverPresenter<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, content: content())
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        if !context.coordinator.popover.isShown {
            context.coordinator.host.rootView = content()
        }
        if isPresented {
            DispatchQueue.main.async { context.coordinator.present(from: nsView) }
        } else if context.coordinator.popover.isShown {
            context.coordinator.popover.close()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.popover.delegate = nil
        coordinator.popover.close()
    }

    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresented: Binding<Bool>
        let popover: NSPopover
        let host: NSHostingController<PopoverContent>

        init(isPresented: Binding<Bool>, content: PopoverContent) {
            self.isPresented = isPresented
            self.host = NSHostingController(rootView: content)
            self.popover = NSPopover()
            super.init()
            popover.animates = false
            popover.behavior = .applicationDefined
            popover.contentSize = NSSize(
                width: Theme.Settings.Size.shortcutPopoverWidth,
                height: Theme.Settings.Size.shortcutPopoverBodyHeight
                    + Theme.Settings.Size.shortcutPopoverFooterHeight + 1
            )
            popover.contentViewController = host
            popover.delegate = self
        }

        func present(from anchor: NSView) {
            guard isPresented.wrappedValue, !popover.isShown, anchor.window != nil else { return }
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }

        func popoverDidClose(_ notification: Notification) {
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
        }
    }
}

private struct ShortcutCapturePopover: View {
    @ObservedObject var session: CaptureSession
    let targetName: String
    let targetIcon: NSImage

    private var state: ShortcutCaptureState { session.state }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                feedbackBackground
                captureBody
                    .transaction { $0.disablesAnimations = true }
            }
            .frame(
                width: Theme.Settings.Size.shortcutPopoverWidth,
                height: Theme.Settings.Size.shortcutPopoverBodyHeight
            )

            Rectangle()
                .fill(Theme.Settings.Colors.rowDivider)
                .frame(height: 1)

            footer
                .frame(height: Theme.Settings.Size.shortcutPopoverFooterHeight)
        }
    }

    @ViewBuilder
    private var captureBody: some View {
        switch state {
        case .recording:
            VStack(spacing: Theme.Spacing.xxl) {
                if captureCaps.isEmpty {
                    Text("Press a hotkey")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    CaptureKeycaps(caps: captureCaps)
                }
            }
        case .editing(let shortcut), .success(let shortcut):
            CaptureKeycaps(caps: shortcut.keycaps)
        case .conflict(let owner, let shortcut):
            VStack(spacing: Theme.Spacing.xl) {
                Text("Already used by \(owner)")
                    .font(.headline)
                    .foregroundStyle(Theme.Settings.Colors.captureConflict)
                CaptureKeycaps(caps: shortcut.keycaps)
                Text("Discard or record a new hotkey")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var feedbackBackground: some View {
        ZStack {
            Theme.Settings.Colors.captureConflictFill
                .opacity(state.isConflict ? 1 : 0)
                .animation(
                    state.isConflict
                        ? .easeOut(duration: 0.1) : .easeOut(duration: 0.25),
                    value: state.isConflict
                )
            Theme.Settings.Colors.captureSuccessFill
                .opacity(state.isSuccess ? 1 : 0)
                .animation(
                    state.isSuccess
                        ? .easeOut(duration: 0.1) : .easeOut(duration: 0.25),
                    value: state.isSuccess
                )
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: targetIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            Text(targetName)
                .font(.callout.weight(.semibold))
            Spacer()
            Text("Close")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            CaptureKeycap(text: "Esc", compact: true)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var captureCaps: [String] {
        KeyShortcut.collapsedModifierSymbols(from: session.heldModifiers)
    }
}

private struct CaptureKeycaps: View {
    let caps: [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                CaptureKeycap(text: cap)
            }
        }
    }
}

private struct CaptureKeycap: View {
    let text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? Theme.Spacing.sm : Theme.Spacing.lg)
            .frame(
                minWidth: compact
                    ? Theme.Size.keyCap : Theme.Settings.Size.shortcutPopoverKeycap,
                minHeight: compact
                    ? Theme.Size.keyCap : Theme.Settings.Size.shortcutPopoverKeycap
            )
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .strokeBorder(Theme.Settings.Colors.searchStroke, lineWidth: 1)
            )
    }
}

@MainActor
private final class CaptureSession: ObservableObject {
    @Published var heldModifiers: NSEvent.ModifierFlags = []
    @Published var state: ShortcutCaptureState = .recording

    var capturedShortcut: KeyShortcut? {
        switch state {
        case .editing(let shortcut), .success(let shortcut): shortcut
        case .recording, .conflict: nil
        }
    }

    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var successResolutionTask: Task<Void, Never>?

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        state = .recording
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: {
                [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, action: action, hotKeys: hotKeys)
                }
                return nil
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: {
                [weak self] event in
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = flags
                    switch self.state {
                    case .editing,
                        .success where !flags.isEmpty:
                        self.successResolutionTask?.cancel()
                        self.successResolutionTask = nil
                        self.state = .recording
                    case .recording, .editing, .conflict, .success:
                        break
                    }
                }
                return event
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak hotKeys] event in
                MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
                return event
            })
        {
            monitors.append(monitor)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        successResolutionTask?.cancel()
        successResolutionTask = nil
        heldModifiers = []
        state = .recording
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags, action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let bareKey = flags.intersection([.command, .option, .control, .shift]).isEmpty

        successResolutionTask?.cancel()
        successResolutionTask = nil

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setShortcut(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }

        switch state {
        case .conflict, .editing, .success:
            state = .recording
        case .recording:
            break
        }

        heldModifiers = flags.intersection([.command, .option, .control, .shift])
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }

        if let owner = hotKeys.conflictOwner(of: shortcut, excluding: action) {
            state = .conflict(owner: owner, shortcut: shortcut)
            return
        }

        hotKeys.setShortcut(shortcut, for: action)
        state = .success(shortcut)
        successResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_050))
            guard !Task.isCancelled, let self else { return }
            self.state = .editing(shortcut)
            self.successResolutionTask = nil
        }
    }
}
