import AppKit

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

/// Lookup of app names and icons for bundle identifiers (or app names),
/// used by the layout editor UI.
enum AppCatalog {
    private static var iconCache: [String: NSImage] = [:]
    private static var nameCache: [String: String] = [:]

    static func runningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func icon(for identifier: String) -> NSImage {
        if let cached = iconCache[identifier] { return cached }
        let icon: NSImage
        if let url = appURL(for: identifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        icon.size = NSSize(width: 64, height: 64)
        iconCache[identifier] = icon
        return icon
    }

    static func displayName(for identifier: String) -> String {
        if let cached = nameCache[identifier] { return cached }
        var name = identifier
        if let url = appURL(for: identifier) {
            name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        nameCache[identifier] = name
        return name
    }

    private static func appURL(for identifier: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url
        }
        // The identifier may be a plain app name (also supported by the matcher).
        return NSWorkspace.shared.runningApplications
            .first { $0.localizedName?.lowercased() == identifier.lowercased() }?
            .bundleURL
    }
}
