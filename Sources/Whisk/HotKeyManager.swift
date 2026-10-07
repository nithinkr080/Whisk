import AppKit
import CoreGraphics

/// Global keyboard handling through a CGEventTap (requires the Accessibility permission).
///
///  - <modifier> Tab           → switch between all windows (add ⇧ to go backwards)
///  - <modifier> `             → switch between windows of the frontmost app
///  - while open: ← → ↑ ↓, Return, Esc, Q quit app, W close window, M minimize, H hide app
@MainActor
final class HotKeyManager {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let controller = SwitcherController.shared

    private enum Key {
        static let tab = 48, backtick = 50, escape = 53, enter = 36, keypadEnter = 76
        static let left = 123, right = 124, down = 125, up = 126
        static let q = 12, w = 13, m = 46, h = 4
    }

    var isInstalled: Bool { tap != nil }

    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { manager.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// ⌘Tab / ⌘` are owned by the system; free them up while ⌘ is the chosen trigger.
    func applySystemShortcutOverrides() {
        let takeOver = Settings.shared.triggerModifier == .command
        for id: Int32 in [1, 2, 27] { _ = CGSSetSymbolicHotKeyEnabled(id, !takeOver) }
    }

    func restoreSystemShortcuts() {
        for id: Int32 in [1, 2, 27] { _ = CGSSetSymbolicHotKeyEnabled(id, true) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let flags = event.flags
        let trigger = Settings.shared.triggerModifier.flag
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            if controller.isActive, !flags.contains(trigger) { controller.commit() }
            return pass

        case .keyDown:
            if !controller.isActive {
                guard code == Key.tab || code == Key.backtick, holdsOnlyTrigger(flags, trigger) else { return pass }
                let reverse = flags.contains(.maskShift)
                let mode: SwitchMode = code == Key.tab ? .allApps : .currentApp
                return controller.begin(mode: mode, reverse: reverse) ? nil : pass
            }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            switch code {
            case Key.tab, Key.backtick: controller.advance(flags.contains(.maskShift) ? -1 : 1)
            case Key.right: controller.advance(1)
            case Key.left: controller.advance(-1)
            case Key.down: controller.moveVertically(1)
            case Key.up: controller.moveVertically(-1)
            case Key.escape: controller.cancel()
            case Key.enter, Key.keypadEnter: controller.commit()
            case Key.q where !isRepeat: controller.quitSelectedApp()
            case Key.w where !isRepeat: controller.closeSelectedWindow()
            case Key.m where !isRepeat: controller.toggleMinimizeSelected()
            case Key.h where !isRepeat: controller.hideSelectedApp()
            default: break
            }
            return nil   // swallow every key while the switcher is open

        case .keyUp:
            return controller.isActive ? nil : pass

        default:
            return pass
        }
    }

    /// True when the trigger modifier is down and no other of ⌘ ⌃ ⌥ is (⇧ is allowed for reverse).
    private func holdsOnlyTrigger(_ flags: CGEventFlags, _ trigger: CGEventFlags) -> Bool {
        let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        return flags.intersection(relevant) == trigger
    }
}
