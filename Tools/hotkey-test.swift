import Foundation

@main
private struct HotKeyTests {
    static func main() {
        var detector = DoubleCommandDetector(maximumInterval: 0.35)
        precondition(!detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 0))
        precondition(!detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 0.1))
        precondition(!detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 0.2))
        precondition(detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 0.3))

        detector.reset()
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 1)
        detector.keyDown()
        detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 1.1)
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 1.2)
        precondition(!detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 1.3))

        detector.reset()
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 2)
        detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 2.1)
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 2.6)
        precondition(!detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 2.7))

        detector.reset()
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 3)
        detector.flagsChanged(commandIsDown: true, otherModifierIsDown: true, at: 3.1)
        detector.flagsChanged(commandIsDown: false, otherModifierIsDown: true, at: 3.2)
        precondition(!detector.flagsChanged(commandIsDown: true, otherModifierIsDown: false, at: 3.3))
        precondition(!detector.flagsChanged(commandIsDown: false, otherModifierIsDown: false, at: 3.4))

        print("hotkey tests passed")
    }
}
