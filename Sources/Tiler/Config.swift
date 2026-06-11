import Foundation

// MARK: - Config model

struct Tile: Codable {
    var id: String
    /// Screen index, ordered left-to-right by position. Defaults to 0.
    var screen: Int?
    /// Fractional coordinates relative to the screen's visible frame.
    /// x/y is the top-left corner (0,0 = top-left of screen), w/h the size.
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct Assignment: Codable {
    /// Bundle identifier (e.g. "com.google.Chrome") or app name (e.g. "Terminal").
    var app: String
    /// The tile id this app's window should be placed in.
    var tile: String
    /// If true, all standard windows of the app are placed in the tile.
    /// Defaults to false (only the first/main window).
    var allWindows: Bool?
}

struct Layout: Codable {
    var name: String
    /// Global hotkey, e.g. "ctrl+alt+1" or "cmd+shift+f1". Optional.
    var hotkey: String?
    /// If true, applying the layout minimizes all windows it doesn't place.
    var hideOthers: Bool?
    var tiles: [Tile]
    var assignments: [Assignment]
}

struct Config: Codable {
    var layouts: [Layout]
}

// MARK: - Loading / persistence

enum ConfigError: LocalizedError {
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Could not parse config.json: \(detail)"
        }
    }
}

enum ConfigStore {
    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("tiler", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static func createDefaultConfigIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return }
        try? fm.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? defaultConfigJSON.data(using: .utf8)?.write(to: configURL, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    static func load() throws -> Config {
        let data = try Data(contentsOf: configURL)
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.invalidJSON(String(describing: error))
        }
    }

    static func save(_ config: Config) throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static let defaultConfigJSON = """
    {
      "layouts": [
        {
          "name": "Coding",
          "hotkey": "ctrl+alt+1",
          "tiles": [
            { "id": "left",   "x": 0.0,  "y": 0.0, "w": 0.25, "h": 1.0 },
            { "id": "center", "x": 0.25, "y": 0.0, "w": 0.5,  "h": 1.0 },
            { "id": "right",  "x": 0.75, "y": 0.0, "w": 0.25, "h": 1.0 }
          ],
          "assignments": [
            { "app": "com.google.Chrome", "tile": "left" },
            { "app": "dev.zed.Zed",       "tile": "center" },
            { "app": "Terminal",          "tile": "right" }
          ]
        },
        {
          "name": "Focus",
          "hotkey": "ctrl+alt+2",
          "tiles": [
            { "id": "main", "x": 0.2, "y": 0.0, "w": 0.6, "h": 1.0 }
          ],
          "assignments": [
            { "app": "dev.zed.Zed", "tile": "main" }
          ]
        },
        {
          "name": "Comms",
          "hotkey": "ctrl+alt+3",
          "tiles": [
            { "id": "left-top",    "x": 0.0, "y": 0.0, "w": 0.3, "h": 0.5 },
            { "id": "left-bottom", "x": 0.0, "y": 0.5, "w": 0.3, "h": 0.5 },
            { "id": "main",        "x": 0.3, "y": 0.0, "w": 0.7, "h": 1.0 }
          ],
          "assignments": [
            { "app": "com.apple.MobileSMS",     "tile": "left-top" },
            { "app": "com.tinyspeck.slackmacgap", "tile": "left-bottom" },
            { "app": "com.apple.mail",          "tile": "main" }
          ]
        }
      ]
    }
    """
}
