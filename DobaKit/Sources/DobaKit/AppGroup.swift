import Foundation

/// Single source of truth for the App Group identifier that DobaApp and
/// DobaWidget use to share the on-disk JSON store.
///
/// The value is read at runtime from the `AppGroupIdentifier` key in each
/// target's Info.plist, which Xcode fills from `$(DOBA_BUNDLE_PREFIX)` (see
/// `Config/Doba.xcconfig`). That keeps the bundle prefix out of source code:
/// change it once in the xcconfig and the app, the widget and both
/// `.entitlements` files follow.
public enum AppGroup {
    /// e.g. `group.com.example.Doba`. Matches both `.entitlements` files, which
    /// use the same `$(DOBA_BUNDLE_PREFIX)` substitution.
    public static let identifier: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
        ?? "group.com.example.Doba"

    /// The shared container URL, or `nil` if the App Group isn't provisioned yet
    /// (e.g. capability not enabled in Xcode, or signing not set up).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
