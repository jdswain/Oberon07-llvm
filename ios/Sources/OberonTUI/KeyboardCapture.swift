// KeyboardCapture — UIKit responder that turns hardware keystrokes
// into oc_dispatch_key calls.
//
// We use this instead of SwiftUI's .onKeyPress because the latter
// is unreliable on iPad: it requires the SwiftUI view to be in the
// keyboard focus chain, which neither .focusable() nor a true
// @FocusState binding seems to achieve consistently on iOS 17.
//
// The view is laid out invisibly (no content, no opaque background)
// and becomes first responder on view-did-appear. It captures every
// hardware press, maps to an Oberon code, and dispatches; anything
// it doesn't map falls back to super so system shortcuts still
// work.
//
// Autorepeat: UIKit's pressesBegan only fires once per physical
// press. We implement classic terminal-style autorepeat ourselves
// — a leading 400 ms delay, then a 40 ms repeat — driven by a
// Timer, cancelled on key-up.

import SwiftUI
import UIKit
import OberonRuntime

public struct KeyboardCapture: UIViewControllerRepresentable {
    public init() {}

    public func makeUIViewController(context: Context) -> KeyCaptureController {
        KeyCaptureController()
    }

    public func updateUIViewController(_ ctrl: KeyCaptureController, context: Context) {
        // Re-claim first responder on every SwiftUI update — focus
        // can drift when the user dismisses the soft keyboard or
        // switches apps.
        DispatchQueue.main.async { _ = ctrl.becomeFirstResponder() }
    }
}

public final class KeyCaptureController: UIViewController {
    public override var canBecomeFirstResponder: Bool { true }

    // Per-press map: holds the code that was dispatched, keyed by
    // the UIPress instance so we can correctly cancel when that
    // specific key lifts even if other keys are held.
    private var heldKeys: [ObjectIdentifier: Int32] = [:]
    private var repeatTimer: Timer?
    private let repeatDelay:    TimeInterval = 0.40   // matches macOS default
    private let repeatInterval: TimeInterval = 0.04   // 25 Hz

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let code = mapUIKey(key) else {
                unhandled.insert(press)
                continue
            }
            oc_dispatch_key(code)
            heldKeys[ObjectIdentifier(press)] = code
        }
        if !heldKeys.isEmpty { scheduleRepeat() }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { heldKeys.removeValue(forKey: ObjectIdentifier(press)) }
        if heldKeys.isEmpty { cancelRepeat() }
        super.pressesEnded(presses, with: event)
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { heldKeys.removeValue(forKey: ObjectIdentifier(press)) }
        if heldKeys.isEmpty { cancelRepeat() }
        super.pressesCancelled(presses, with: event)
    }

    // ---- Autorepeat -------------------------------------------------

    private func scheduleRepeat() {
        cancelRepeat()
        // Fire once after `repeatDelay`, then switch to the steady
        // repeat-interval loop. Mirrors what macOS does for held
        // keys at default settings.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatDelay,
                                           repeats: false) { [weak self] _ in
            self?.startRepeatLoop()
        }
    }

    private func startRepeatLoop() {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInterval,
                                           repeats: true) { [weak self] _ in
            guard let self else { return }
            for code in self.heldKeys.values {
                oc_dispatch_key(code)
            }
        }
    }

    private func cancelRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
