import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UpdateInstaller.applyIfRequested() { return }
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}
