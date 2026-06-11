import AppKit
import ApplicationServices

enum WindowManager {

    // MARK: - Accessibility permission

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Applying layouts

    /// Applies a layout. Returns a list of human-readable problems (apps not
    /// running, unknown tiles, ...) — empty means everything was placed.
    ///
    /// Placement rules per app:
    /// - One tile, `allWindows` false → the app's main window goes in the tile.
    /// - One tile, `allWindows` true  → all windows go in the tile.
    /// - Multiple tiles, multiple windows → windows are distributed across the
    ///   tiles round-robin (extras stack on the tiles again).
    /// - Multiple tiles, a single window → the window spans the union of all
    ///   the app's tiles (fallback).
    @discardableResult
    static func apply(_ layout: Layout) -> [String] {
        var problems: [String] = []

        let screens = orderedScreens()
        guard !screens.isEmpty else { return ["No screens found."] }

        let tilesByID = Dictionary(uniqueKeysWithValues: layout.tiles.map { ($0.id, $0) })

        // Group assignments into per-app plans, preserving assignment order.
        struct Plan {
            let app: NSRunningApplication
            var frames: [CGRect] = []
            var allWindows = false
        }
        var plans: [pid_t: Plan] = [:]
        var planOrder: [pid_t] = []

        for assignment in layout.assignments {
            guard let tile = tilesByID[assignment.tile] else {
                problems.append("Unknown tile \"\(assignment.tile)\" for \(assignment.app).")
                continue
            }
            guard let app = findRunningApp(matching: assignment.app) else {
                problems.append("\(assignment.app) is not running.")
                continue
            }
            let pid = app.processIdentifier
            if plans[pid] == nil {
                plans[pid] = Plan(app: app)
                planOrder.append(pid)
            }
            plans[pid]?.frames.append(cgFrame(for: tile, screens: screens))
            if assignment.allWindows ?? false {
                plans[pid]?.allWindows = true
            }
        }

        var placedWindows: [AXUIElement] = []

        for pid in planOrder {
            guard let plan = plans[pid] else { continue }
            let windows = standardWindows(of: plan.app)
            guard !windows.isEmpty else {
                problems.append("\(plan.app.localizedName ?? "App") has no windows.")
                continue
            }
            let frames = plan.frames

            if frames.count > 1 && windows.count == 1 {
                // Fallback: a single window spans the union of all its tiles.
                let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                place(windows[0], in: union, placed: &placedWindows)
            } else if frames.count == 1 {
                let targets = plan.allWindows ? windows : [windows[0]]
                for window in targets {
                    place(window, in: frames[0], placed: &placedWindows)
                }
            } else {
                // Distribute windows across the app's tiles round-robin.
                for (index, window) in windows.enumerated() {
                    place(window, in: frames[index % frames.count], placed: &placedWindows)
                }
            }
        }

        if layout.hideOthers == true {
            minimizeOtherWindows(placed: placedWindows)
        }

        return problems
    }

    private static func place(_ window: AXUIElement, in frame: CGRect, placed: inout [AXUIElement]) {
        unminimize(window)
        setFrame(window, frame)
        placed.append(window)
    }

    private static func minimizeOtherWindows(placed: [AXUIElement]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard app.processIdentifier != pid_t(ownPID) else { continue }
            for window in standardWindows(of: app, strict: true) {
                let isPlaced = placed.contains { CFEqual($0, window) }
                if !isPlaced {
                    AXUIElementSetAttributeValue(
                        window, kAXMinimizedAttribute as CFString, kCFBooleanTrue
                    )
                }
            }
        }
    }

    // MARK: - App / window lookup

    private static func findRunningApp(matching identifier: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let needle = identifier.lowercased()

        // 1. Exact bundle identifier match.
        if let app = apps.first(where: { $0.bundleIdentifier?.lowercased() == needle }) {
            return app
        }
        // 2. Exact app name match.
        if let app = apps.first(where: { $0.localizedName?.lowercased() == needle }) {
            return app
        }
        // 3. Fallback: name contains.
        return apps.first(where: { $0.localizedName?.lowercased().contains(needle) == true })
    }

    /// All windows of an app with the standard-window subrole.
    /// When `strict` is false and no standard windows exist, all windows are
    /// returned as a fallback.
    static func standardWindows(of app: NSRunningApplication, strict: Bool = false) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return [] }

        let standard = windows.filter { window in
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            guard let subrole = subroleValue as? String else { return !strict }
            return subrole == kAXStandardWindowSubrole as String
        }
        if strict { return standard }
        return standard.isEmpty ? windows : standard
    }

    /// The focused window of the frontmost app.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - Geometry

    static func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// Converts a fractional tile into a CGRect in Accessibility (top-left
    /// origin) global coordinates. Fractions are clamped to the screen so a
    /// malformed config can never produce frames outside the visible area.
    static func cgFrame(for tile: Tile, screens: [NSScreen]) -> CGRect {
        guard !screens.isEmpty else { return .zero }
        let index = min(max(tile.screen ?? 0, 0), screens.count - 1)
        let visible = screens[index].visibleFrame // bottom-left origin (AppKit)

        // Clamp config-supplied fractions to sane values.
        let fx = min(max(tile.x, 0), 1)
        let fy = min(max(tile.y, 0), 1)
        let fw = min(max(tile.w, 0), 1 - fx)
        let fh = min(max(tile.h, 0), 1 - fy)

        let x = visible.origin.x + fx * visible.width
        let width = fw * visible.width
        let height = fh * visible.height
        // Top edge of the tile in AppKit coordinates:
        let topYAppKit = visible.maxY - fy * visible.height

        // NSScreen.screens[0] is always the primary screen (origin 0,0).
        let primaryHeight = NSScreen.screens[0].frame.height
        let yCG = primaryHeight - topYAppKit

        return CGRect(x: x, y: yCG, width: width, height: height)
    }

    /// Converts an AppKit (bottom-left origin) point, e.g. NSEvent.mouseLocation,
    /// to Accessibility (top-left origin) coordinates.
    static func cgPoint(fromAppKit point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    // MARK: - AX accessors

    /// The window's current frame in Accessibility coordinates.
    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue((positionValue as! AXValue), .cgPoint, &origin)
        AXValueGetValue((sizeValue as! AXValue), .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func unminimize(_ window: AXUIElement) {
        var minimized: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
        if (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size

        // Position → size → position again: some apps clamp the position when
        // the window is still large, or adjust origin during resize.
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }
}
