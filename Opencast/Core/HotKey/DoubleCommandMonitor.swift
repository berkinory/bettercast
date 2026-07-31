import AppKit

@MainActor
final class DoubleCommandMonitor {
    var onDoubleCommand: (() -> Void)?
    var isPaused = false {
        didSet {
            if isPaused { detector.reset() }
        }
    }

    private var detector = DoubleCommandDetector()
    private var monitors: [Any] = []

    func start() {
        stop()
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask,
            handler: { [weak self] event in self?.handle(event) }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask,
            handler: { [weak self] event in
                self?.handle(event)
                return event
            }
        ) {
            monitors.append(monitor)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        guard !isPaused else { return }
        let time = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .keyDown:
            detector.keyDown()
        case .flagsChanged:
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if detector.flagsChanged(
                commandIsDown: flags.contains(.command),
                otherModifierIsDown: !flags.intersection([.option, .control, .shift]).isEmpty,
                at: time
            ) {
                onDoubleCommand?()
            }
        default:
            break
        }
    }
}
