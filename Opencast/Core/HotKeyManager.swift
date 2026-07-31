import Foundation

/// Owns all global shortcut bindings: persistence, Carbon registration (via `HotKeyCenter`), conflict lookup, and dispatch.
@MainActor
final class HotKeyManager: ObservableObject {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?
    var onToggleEmoji: (() -> Void)?

    /// The recorder currently capturing keystrokes, or `nil`; keeping this as plain app state makes recorders glitch-free, and any active recorder pauses Carbon so the typed combo can't fire a hotkey.
    @Published var recordingAction: HotKeyAction? {
        didSet {
            let paused = recordingAction != nil
            center.isPaused = paused
            doubleCommandMonitor.isPaused = paused
        }
    }

    private let center = HotKeyCenter()
    private let doubleCommandMonitor = DoubleCommandMonitor()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"

    func start() {
        register(.togglePalette)
        register(.toggleClipboard)
        register(.toggleEmoji)
        for bundleID in boundBundleIDs { register(.app(bundleID: bundleID)) }
        for bundleID in boundPaneBundleIDs { register(.settingsPane(bundleID: bundleID)) }
        doubleCommandMonitor.onDoubleCommand = { [weak self] in self?.performDoubleCommand() }
        doubleCommandMonitor.start()
    }

    /// Bundle IDs that currently have a per-app hotkey — lets `start()` know which records to load and lets launcher rows show keycaps.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Settings-pane bundle IDs with a hotkey — same role as `boundBundleIDs`, own namespace.
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        guard let json = UserDefaults.standard.string(forKey: action.defaultsKey) else { return nil }
        if json == "doubleCommand" { return .doubleCommand }
        guard let data = json.data(using: .utf8),
            let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data)
        else { return nil }
        return .key(shortcut)
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        guard case .key(let shortcut) = binding(for: action) else { return nil }
        return shortcut
    }

    /// Persists (or clears, when `nil`) the binding, swaps the live registration, and publishes so the launcher and recorders re-render.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        switch binding {
        case .key(let shortcut):
            guard
                let data = try? JSONEncoder().encode(shortcut),
                let json = String(data: data, encoding: .utf8)
            else { return }
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
            register(action)
        case .doubleCommand:
            UserDefaults.standard.set("doubleCommand", forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        case nil:
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        }
        switch action {
        case .app(let bundleID):
            var set = Set(boundBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .togglePalette, .toggleClipboard, .toggleEmoji:
            break
        }
        objectWillChange.send()
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        setBinding(shortcut.map(HotKeyBinding.key), for: action)
    }

    /// The display name of whatever else `binding` is bound to (or `nil` if free), driving the recorder's "Used by …" message.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        var candidates: [HotKeyAction] = [.togglePalette, .toggleClipboard, .toggleEmoji]
        candidates += boundBundleIDs.map { .app(bundleID: $0) }
        candidates += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        for candidate in candidates
        where candidate != action && self.binding(for: candidate) == binding {
            return displayName(of: candidate)
        }
        return nil
    }

    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        conflictOwner(of: .key(shortcut), excluding: action)
    }

    func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .toggleClipboard:
            return "Clipboard History"
        case .toggleEmoji:
            return "Emoji & Symbols"
        case .app(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .settingsPane(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?.name
                ?? bundleID
        }
    }

    private func register(_ action: HotKeyAction) {
        center.unregister(id: action.defaultsKey)
        guard case .key(let shortcut) = binding(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    private func performDoubleCommand() {
        var candidates: [HotKeyAction] = [.togglePalette, .toggleClipboard, .toggleEmoji]
        candidates += boundBundleIDs.map { .app(bundleID: $0) }
        candidates += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        guard let action = candidates.first(where: { binding(for: $0) == .doubleCommand }) else { return }
        perform(action)
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette: onTogglePalette?()
        case .toggleClipboard: onToggleClipboard?()
        case .toggleEmoji: onToggleEmoji?()
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        }
    }
}
