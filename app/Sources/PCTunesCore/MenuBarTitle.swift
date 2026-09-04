import Foundation

/// Formats the text shown beside the menu bar icon.
public enum MenuBarTitle {
    /// Characters kept in the menu bar, ellipsis included. This is a character budget,
    /// not a width budget — 35 wide graphemes still render wider than 35 Latin ones.
    public static let maxLength = 35

    /// Bounds accepted for a user-configured menu bar title length, in characters.
    /// Below the minimum the title stops being recognizable; above the maximum it
    /// crowds out the rest of the menu bar.
    public static let lengthRange = 10...80

    /// `Title — Artist`, trimmed to fit. The ellipsis is inside the budget, not
    /// appended on top of it, so the result never exceeds `limit`.
    public static func format(title: String, artist: String, limit: Int = maxLength) -> String {
        let full = artist.isEmpty ? title : "\(title) — \(artist)"
        guard full.count > limit else { return full }
        return String(full.prefix(max(0, limit - 1))) + "…"
    }

    /// Clamps a user-supplied title length (e.g. from `Settings`, including
    /// `UserDefaults`' zero-for-unset) into `lengthRange`.
    public static func clampLength(_ length: Int) -> Int {
        min(max(length, lengthRange.lowerBound), lengthRange.upperBound)
    }
}
