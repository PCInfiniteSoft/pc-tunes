import AppKit
import Carbon.HIToolbox
import PCTunesCore
import SwiftUI

/// Names a key the way the user's own keyboard does.
enum KeyLabel {
    /// Asks the active keyboard layout what a key code produces, so the shortcut a Thai
    /// or Dvorak user sees matches the legend on the key they actually pressed. Keys
    /// that print nothing (arrows, Space, F-keys) are named from `KeyCombo`'s table.
    static func label(for keyCode: UInt32) -> String {
        if let name = KeyCombo.specialKeyName(for: keyCode) { return name }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return fallback(keyCode)
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0, // No modifiers: the label is the bare key, the symbols carry the rest.
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return fallback(keyCode) }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static func fallback(_ keyCode: UInt32) -> String { "Key \(keyCode)" }
}

/// A click-then-press control for rebinding one hotkey.
///
/// Capture is a local event monitor rather than a first-responder `NSView`: the
/// settings window is the only place this appears and PC Tunes is active while it is
/// open, so a local monitor sees every key — and unlike a global monitor it needs no
/// Accessibility permission, which this app goes out of its way never to ask for.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stop() } else { start() }
        } label: {
            Text(isRecording ? "Press a shortcut…" : combo.displayString(keyLabel: KeyLabel.label(for: combo.keyCode)))
                .font(.body.monospaced())
                .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
        .help(isRecording ? "Press the keys you want, or Escape to cancel" : "Click, then press the keys you want")
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Swallowed either way: while recording, a keystroke is the input to this
            // control and must not also reach the window behind it.
            handle(event)
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == 53 { // Escape cancels rather than binding itself.
            stop()
            return
        }
        let candidate = KeyCombo(keyCode: keyCode, modifiers: Self.carbonModifiers(event.modifierFlags))
        // A combo with no modifier — or shift only — would swallow an ordinary typing
        // key everywhere in the system. Keep listening instead of binding it.
        guard candidate.hasRequiredModifier else { return }
        combo = candidate
        stop()
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        return modifiers
    }
}
