import Foundation

/// Formats the text shown beside the menu bar icon.
public enum MenuBarTitle {
    /// Characters available in the menu bar, ellipsis included.
    public static let maxLength = 35

    /// `Title — Artist`, trimmed to fit. The ellipsis is inside the budget, not
    /// appended on top of it, so the result never exceeds `limit`.
    public static func format(title: String, artist: String, limit: Int = maxLength) -> String {
        let full = artist.isEmpty ? title : "\(title) — \(artist)"
        guard full.count > limit else { return full }
        return String(full.prefix(limit - 1)) + "…"
    }
}
