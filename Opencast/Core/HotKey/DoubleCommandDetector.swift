import Foundation

struct DoubleCommandDetector: Sendable {
    let maximumInterval: TimeInterval

    private(set) var commandDown = false
    private var cycleValid = true
    private var previousRelease: TimeInterval?

    init(maximumInterval: TimeInterval = 0.35) {
        self.maximumInterval = maximumInterval
    }

    @discardableResult
    mutating func flagsChanged(
        commandIsDown: Bool,
        otherModifierIsDown: Bool,
        at time: TimeInterval
    ) -> Bool {
        if commandIsDown == commandDown {
            if commandDown, otherModifierIsDown { cycleValid = false }
            return false
        }

        if commandIsDown {
            commandDown = true
            cycleValid = !otherModifierIsDown
            if let previousRelease, time - previousRelease > maximumInterval {
                self.previousRelease = nil
            }
            return false
        }

        let recognized =
            commandDown
            && cycleValid
            && !otherModifierIsDown
            && previousRelease.map { time - $0 <= maximumInterval } == true

        if commandDown, cycleValid, !otherModifierIsDown {
            previousRelease = recognized ? nil : time
        } else {
            previousRelease = nil
        }
        commandDown = false
        cycleValid = true
        return recognized
    }

    mutating func keyDown() {
        if commandDown { cycleValid = false }
    }

    mutating func reset() {
        commandDown = false
        cycleValid = true
        previousRelease = nil
    }
}
