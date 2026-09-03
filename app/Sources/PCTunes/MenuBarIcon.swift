import AppKit

/// The menu bar's icon.
///
/// Read from the installed YouTube Music PWA at runtime rather than bundled, so this
/// repository never ships a copy of Google's artwork and the icon always matches what
/// the user actually has installed.
enum MenuBarIcon {
    /// Menu bar art is measured in points and the bar is 22pt tall; 18 leaves the
    /// padding the system expects.
    private static let side: CGFloat = 18

    static let image: NSImage? = {
        let path = YouTubeMusicLauncher.pwaPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let source = NSWorkspace.shared.icon(forFile: path)
        let resized = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        // The PWA icon is full colour, so it must not be treated as a template mask.
        resized.isTemplate = false
        return resized
    }()
}
