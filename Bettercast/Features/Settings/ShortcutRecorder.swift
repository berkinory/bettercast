import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Keeps focus in Settings while a local event monitor captures the binding.
struct ShortcutRecorder: View {
    let action: HotKeyAction

    @ObservedObject private var hotKeys: HotKeyManager = AppCore.shared.hotKeys
    /// Observed so bound chips re-render when the Hyper Key display settings change how `keycaps` renders.
    @ObservedObject private var settings = AppCore.shared.settings
    @StateObject private var session = CaptureSession()
    @State private var hovered = false
    @FocusState private var focused: Bool

    private var isRecording: Bool { hotKeys.recordingAction == action }
    private var shortcut: KeyShortcut? { hotKeys.shortcut(for: action) }
    private var accent: Color { isRecording ? .orange : .accentColor }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                hotKeys.recordingAction = action
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: Theme.Spacing.xl)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, Theme.Spacing.md)
                .padding(.trailing, shortcut == nil ? Theme.Spacing.md : Theme.Spacing.xxl)
                .frame(minWidth: 132, minHeight: Theme.Settings.Size.controlHeight)
                .background(backgroundShape)
                .overlay(borderShape)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: Theme.Settings.Radius.controlIcon,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focusable()
            .focused($focused)
            .onKeyPress(.return) {
                hotKeys.recordingAction = action
                return .handled
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)

            if shortcut != nil, !isRecording {
                Button(action: clearShortcut) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(
                            width: Theme.Settings.Size.visibilityButton,
                            height: Theme.Settings.Size.controlHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .settingsFocusRing(cornerRadius: Theme.Settings.Radius.controlIcon)
                .opacity(hovered || focused ? 1 : 0.4)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onHover { hovered = $0 }
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

    private var backgroundShape: some View {
        RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.controlIcon,
            style: .continuous
        )
        .fill(
            isRecording
                ? Color.orange.opacity(0.12)
                : hovered ? Theme.Colors.rowHover : Theme.Settings.Colors.searchFill
        )
    }

    private var borderShape: some View {
        RoundedRectangle(
            cornerRadius: Theme.Settings.Radius.controlIcon,
            style: .continuous
        )
        .strokeBorder(
            isRecording
                ? Color.orange.opacity(0.55)
                : focused
                    ? Theme.Settings.Colors.searchFocus
                    : hovered ? accent.opacity(0.30) : Theme.Settings.Colors.searchStroke,
            lineWidth: focused ? 2 : 1
        )
    }

    private var accessibilityLabel: String {
        if isRecording { return "Recording keyboard shortcut" }
        guard let shortcut else { return "Record keyboard shortcut, not set" }
        return "Change keyboard shortcut, currently \(shortcut.keycaps.joined())"
    }

    private var accessibilityHint: String {
        isRecording
            ? "Press Escape to cancel or Delete to clear the shortcut"
            : "Press Space or Return to record a new shortcut"
    }

    private func clearShortcut() {
        hotKeys.setShortcut(nil, for: action)
        hotKeys.recordingAction = nil
    }

    @ViewBuilder
    private var content: some View {
        if isRecording {
            recordingLabel
        } else if let shortcut {
            boundLabel(shortcut)
        } else {
            Text("Record shortcut")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var recordingLabel: some View {
        Group {
            if let owner = session.conflictOwner {
                Text("Used by \(owner)")
                    .foregroundStyle(.orange)
            } else if !session.heldModifiers.isEmpty {
                Text(KeyShortcut.collapsedModifierSymbols(from: session.heldModifiers).joined())
                    .foregroundStyle(.primary)
            } else {
                Text("Press shortcut…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.weight(.medium))
    }

    private func boundLabel(_ shortcut: KeyShortcut) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(
                        minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                    )
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                        )
                        .fill(Theme.Colors.controlSurface)
                    )
            }
        }
    }
}

/// Owns the local event monitors for the one active recording, live only between `start()` and `stop()` and entirely on the main actor.
@MainActor
private final class CaptureSession: ObservableObject {
    /// Modifiers currently held, for the live "⌃⌥…" preview while recording.
    @Published var heldModifiers: NSEvent.ModifierFlags = []
    /// Owner of a just-typed conflicting combo; shown for a moment, then recording resumes.
    @Published var conflictOwner: String?

    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var conflictReset: Task<Void, Never>?

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        // The handlers run on the main thread but AppKit predates actor annotations, hence assumeIsolated; only Sendable event pieces (key code, flags) cross in.
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
                return nil  // always consume: no beeps, no leaking keys to the window
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: {
                [weak self] event in
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                MainActor.assumeIsolated { self?.heldModifiers = flags }
                return event
            })
        {
            monitors.append(monitor)
        }

        // A click anywhere ends the recording, then travels on — so a click on another recorder cancels this one and starts that one in a single click.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak hotKeys] event in
                MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
                return event
            })
        {
            monitors.append(monitor)
        }

        // Local monitors go quiet when the settings window resigns key — treat it as a cancel so the paused global hotkeys come back.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
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
        conflictReset?.cancel()
        conflictReset = nil
        conflictOwner = nil
        heldModifiers = []
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags, action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let bareKey = flags.intersection([.command, .option, .control, .shift]).isEmpty

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        // Plain Delete clears the existing binding.
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setShortcut(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        // Not a bindable combo (e.g. a bare letter): swallow it and keep recording.
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }

        if let owner = hotKeys.conflictOwner(of: shortcut, excluding: action) {
            flashConflict(owner)
            return
        }
        hotKeys.setShortcut(shortcut, for: action)
        hotKeys.recordingAction = nil
    }

    private func flashConflict(_ owner: String) {
        conflictOwner = owner
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.conflictOwner = nil
        }
    }
}
