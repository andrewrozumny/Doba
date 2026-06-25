import Foundation

/// Single source of truth for the App Group identifier that DobaApp and
/// DobaWidget use to share the on-disk JSON store.
///
/// If you change the App Group ID in Xcode (Signing & Capabilities) or in the
/// `.entitlements` files, change it **here too** — this constant must match the
/// entitlement string exactly, or `containerURL(...)` returns nil and the store
/// silently falls back to a per-app directory (no sharing).
public enum AppGroup {
    /// Keep in sync with DobaApp/DobaApp.entitlements and
    /// DobaWidget/DobaWidget.entitlements.
    public static let identifier = "group.com.andreyrozumny.Doba"

    /// The shared container URL, or `nil` if the App Group isn't provisioned yet
    /// (e.g. capability not enabled in Xcode, or signing not set up).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
