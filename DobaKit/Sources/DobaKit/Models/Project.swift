import Foundation

/// A lightweight tag for grouping tasks. Optional on a task.
///
/// `colorHex` is a plain "#RRGGBB" string; turning it into a SwiftUI `Color`
/// is the UI layer's job (DobaKit stays free of any UI framework so it can be
/// linked into the widget without dragging SwiftUI into the model layer).
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// Optional per-project hourly rate; overrides the global rate for this
    /// project's billable tasks. nil → use the global rate. (Optional keeps old
    /// stores decoding unchanged.)
    public var rate: Double?

    public init(id: UUID = UUID(), name: String, colorHex: String, rate: Double? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.rate = rate
    }

    /// Preset colors assigned to newly created projects (inline create + the
    /// NL parser). UI swatches in the editor reuse this list.
    public static let palette = ["#4F8EF7", "#9B59B6", "#2ECC71", "#E67E22", "#E74C3C", "#1ABC9C"]
}
