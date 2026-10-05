import Foundation

/// A hold threshold around the physical shortcut state. Time is monotonic and
/// supplied by the caller so releases and interruption handling are deterministic.
public struct HotkeyTriggerState: Sendable {
    public enum Disposition: Equatable, Sendable { case pass, buffer, consume }
    public struct Result: Equatable, Sendable {
        public var transition: HotkeyPressState.Transition? = nil
        public var disposition: Disposition = .pass
        public var replayBuffered = false
        public var discardBuffered = false
    }

    public static let delayRange = 0...1000
    public static func clampedDelay(_ milliseconds: Int) -> Int {
        min(delayRange.upperBound, max(delayRange.lowerBound, milliseconds))
    }

    private enum Phase: Sendable { case idle, pending, active, bypassed }
    private var phase: Phase = .idle
    private var press = HotkeyPressState()
    public private(set) var deadline: TimeInterval?
    public var isDown: Bool { press.isDown }

    public init() {}

    public mutating func handle(
        _ event: HotkeyPressState.Event, hotkey: Hotkey, keyCode: UInt16,
        flags: UInt64, isRepeat: Bool = false, modifierKeyIsDown: Bool = false,
        now: TimeInterval, delayMilliseconds: Int
    ) -> Result {
        let physical = press.handle(event, hotkey: hotkey, keyCode: keyCode,
            flags: flags, isRepeat: isRepeat, modifierKeyIsDown: modifierKeyIsDown)

        if physical.transition == .released {
            let result: Result
            switch phase {
            case .pending: result = Result(replayBuffered: true)
            case .active:
                result = Result(transition: .released,
                    disposition: physical.consumesEvent ? .consume : .pass)
            case .idle, .bypassed: result = Result()
            }
            phase = .idle
            deadline = nil
            return result
        }

        if phase == .pending {
            // A modifier used to type, or a shortcut that becomes another chord,
            // belongs to the focused app. Do not arm again until it is released.
            let otherKey = event == .keyDown && (hotkey.isModifierOnly || keyCode != hotkey.keyCode)
            let expectedFlags = hotkey.isModifierOnly && hotkey.modifiers == 0
                ? Hotkey.modifierFlag(for: hotkey.keyCode) ?? 0 : hotkey.modifiers
            let changedChord = event == .flagsChanged &&
                flags & Hotkey.relevantModifierMask != expectedFlags
            if otherKey || changedChord {
                return cancelPending()
            }
        }

        if physical.transition == .pressed {
            let delay = Self.clampedDelay(delayMilliseconds)
            if delay > 0, hotkey.isModifierOnly, hotkey.modifiers == 0,
               flags & Hotkey.relevantModifierMask != Hotkey.modifierFlag(for: hotkey.keyCode) {
                phase = .bypassed
                return Result()
            }
            if delay == 0 {
                phase = .active
                return Result(transition: .pressed,
                    disposition: physical.consumesEvent ? .consume : .pass)
            }
            phase = .pending
            deadline = now + Double(delay) / 1000
        }

        switch phase {
        case .pending:
            return Result(disposition: physical.consumesEvent ? .buffer : .pass)
        case .active:
            // Keep repeats consumed even if the user lifts a chord modifier.
            let repeatOfTrigger = !hotkey.isModifierOnly && keyCode == hotkey.keyCode && event == .keyDown
            return Result(disposition: physical.consumesEvent || repeatOfTrigger ? .consume : .pass)
        case .idle, .bypassed: return Result()
        }
    }

    public mutating func fire(now: TimeInterval) -> Result {
        guard phase == .pending, let deadline, now >= deadline else { return Result() }
        phase = .active
        self.deadline = nil
        return Result(transition: .pressed, discardBuffered: true)
    }

    /// Cancel without re-arming an already held key, for focus changes or a tap
    /// interruption. The backend replays any withheld input exactly once.
    public mutating func cancelPending() -> Result {
        guard phase == .pending else { return Result() }
        phase = .bypassed
        deadline = nil
        return Result(replayBuffered: true)
    }

    public mutating func reconcile(hotkey: Hotkey, modifierFlags: UInt64, keyIsDown: Bool) -> Result {
        var result = cancelPending()
        if press.reconcile(afterInterruption: true, hotkey: hotkey,
                           modifierFlags: modifierFlags, keyIsDown: keyIsDown) == .released {
            if phase == .active { result.transition = .released }
            phase = .idle
        }
        return result
    }

    public mutating func reset() -> Result {
        let result = Result(transition: phase == .active ? .released : nil,
                            replayBuffered: phase == .pending)
        _ = press.reset()
        phase = .idle
        deadline = nil
        return result
    }
}
