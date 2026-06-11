import AppKit

/// Click-through overlay shown while a window is being dragged with an active
/// layout: every slot gets a subtle outline, and the slot under the cursor is
/// highlighted to indicate the snap target.
final class SlotOverlay {
    private var windows: [NSWindow] = []
    private var views: [SlotOutlineView] = []
    private var frames: [CGRect] = [] // Accessibility (top-left origin) coordinates
    private var highlightedIndex: Int?
    private(set) var isVisible = false

    func show(slots: [CGRect]) {
        hide()
        frames = slots

        for cgFrame in slots {
            let frame = Self.appKitRect(cgFrame)
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            window.isReleasedWhenClosed = false

            let view = SlotOutlineView(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = view
            window.orderFrontRegardless()

            windows.append(window)
            views.append(view)
        }

        highlightedIndex = nil
        isVisible = true
    }

    /// Highlights the slot containing `point` (Accessibility coordinates).
    func highlight(at point: CGPoint) {
        guard isVisible else { return }
        let index = frames.firstIndex { $0.contains(point) }
        guard index != highlightedIndex else { return }
        if let old = highlightedIndex { views[old].isActive = false }
        if let new = index { views[new].isActive = true }
        highlightedIndex = index
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        frames.removeAll()
        highlightedIndex = nil
        isVisible = false
    }

    /// Converts an Accessibility (top-left origin) rect to an AppKit
    /// (bottom-left origin) rect for NSWindow placement.
    private static func appKitRect(_ cg: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: cg.minX,
            y: primaryHeight - cg.maxY,
            width: cg.width,
            height: cg.height
        )
    }
}

/// Draws the slot outline: a faint dashed border normally, and a prominent
/// accent-colored highlight when it's the snap target.
final class SlotOutlineView: NSView {
    var isActive = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)

        if isActive {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([7, 5], count: 2, phase: 0)
            path.stroke()
        }
    }
}
