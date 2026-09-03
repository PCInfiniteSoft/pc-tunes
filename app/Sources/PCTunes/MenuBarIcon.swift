import AppKit

/// The menu bar's icon: a ringed play triangle, drawn rather than bundled.
///
/// It is a template image, so macOS tints it to match the menu bar in both light and
/// dark appearance and it sits consistently beside the system's own icons.
enum MenuBarIcon {
    /// The menu bar is 22pt tall; 18 leaves the padding the system expects.
    private static let side: CGFloat = 18

    static let image: NSImage = {
        let image = NSImage(
            size: NSSize(width: side, height: side),
            flipped: false
        ) { rect in
            let lineWidth: CGFloat = 1.4
            let inset = lineWidth / 2 + 0.6

            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
            ring.lineWidth = lineWidth
            NSColor.black.setStroke()
            ring.stroke()

            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let reach = rect.width * 0.20
            let triangle = NSBezierPath()
            triangle.move(to: CGPoint(x: centre.x + reach * 1.15, y: centre.y))
            triangle.line(to: CGPoint(x: centre.x - reach * 0.75, y: centre.y + reach))
            triangle.line(to: CGPoint(x: centre.x - reach * 0.75, y: centre.y - reach))
            triangle.close()
            NSColor.black.setFill()
            triangle.fill()

            return true
        }
        // Alpha is used as a mask when this is set, so the black above becomes whatever
        // colour the menu bar needs.
        image.isTemplate = true
        return image
    }()
}
