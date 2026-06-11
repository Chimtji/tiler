import AppKit

/// Tracks the currently active layout and turns its tiles into "slots":
/// - Dropping a dragged window inside a slot snaps the window to it.
/// - ctrl+alt+arrow keys move the focused window to the nearest slot in that
///   direction.
final class SlotManager {
    static let shared = SlotManager()

    private(set) var activeLayout: Layout?
    private var slots: [CGRect] = [] // Accessibility (top-left origin) coordinates
    private var mouseMonitors: [Any] = []
    private var drag: DragTracking?
    private let overlay = SlotOverlay()

    /// Called whenever the active layout changes (used to refresh the menu).
    var onChange: (() -> Void)?

    private struct DragTracking {
        let window: AXUIElement
        let startFrame: CGRect
        var isWindowDrag = false
        var lastFrameCheck = Date.distantPast
    }

    private enum Direction {
        case left, right, up, down
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recomputeSlots()
        }
    }

    // MARK: - Activation

    func activate(_ layout: Layout) {
        activeLayout = layout
        recomputeSlots()
        installMouseMonitors()
        registerSlotHotkeys()
        onChange?()
    }

    func deactivate() {
        activeLayout = nil
        slots = []
        drag = nil
        overlay.hide()
        removeMouseMonitors()
        HotKeyManager.shared.unregister(group: HotKeyManager.slotsGroup)
        onChange?()
    }

    private func recomputeSlots() {
        guard let layout = activeLayout else {
            slots = []
            return
        }
        let screens = WindowManager.orderedScreens()
        slots = layout.tiles.map { WindowManager.cgFrame(for: $0, screens: screens) }
    }

    // MARK: - Drag-to-slot snapping

    private func installMouseMonitors() {
        removeMouseMonitors()
        let draggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.mouseDragged()
        }
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.mouseUp()
        }
        mouseMonitors = [draggedMonitor, upMonitor].compactMap { $0 }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
    }

    private func mouseDragged() {
        // Capture the window being interacted with at drag start.
        if drag == nil {
            guard let window = WindowManager.focusedWindow(),
                  let frame = WindowManager.frame(of: window)
            else { return }
            drag = DragTracking(window: window, startFrame: frame)
            return
        }
        guard var tracking = drag else { return }

        // Detect (throttled) whether the window is actually being moved —
        // as opposed to text selection or a resize — and show the slot
        // overlay as soon as it is.
        if !tracking.isWindowDrag {
            guard Date().timeIntervalSince(tracking.lastFrameCheck) > 0.08 else { return }
            tracking.lastFrameCheck = Date()
            if let frame = WindowManager.frame(of: tracking.window),
               abs(frame.origin.x - tracking.startFrame.origin.x) > 2
                || abs(frame.origin.y - tracking.startFrame.origin.y) > 2,
               abs(frame.width - tracking.startFrame.width) < 2,
               abs(frame.height - tracking.startFrame.height) < 2 {
                tracking.isWindowDrag = true
                overlay.show(slots: slots)
            }
            drag = tracking
        }

        if tracking.isWindowDrag {
            overlay.highlight(at: WindowManager.cgPoint(fromAppKit: NSEvent.mouseLocation))
        }
    }

    private func mouseUp() {
        guard let drag else { return }
        self.drag = nil
        overlay.hide()

        guard let frame = WindowManager.frame(of: drag.window) else { return }

        // Only snap if the window was moved (not a click or text selection)...
        let movedX = abs(frame.origin.x - drag.startFrame.origin.x)
        let movedY = abs(frame.origin.y - drag.startFrame.origin.y)
        guard movedX > 2 || movedY > 2 else { return }

        // ...and not resized (resizing from the left/top edge also moves the origin).
        guard abs(frame.width - drag.startFrame.width) < 2,
              abs(frame.height - drag.startFrame.height) < 2
        else { return }

        let mouse = WindowManager.cgPoint(fromAppKit: NSEvent.mouseLocation)
        guard let slot = slots.first(where: { $0.contains(mouse) }) else { return }
        WindowManager.setFrame(drag.window, slot)
    }

    // MARK: - Keyboard slot movement

    private func registerSlotHotkeys() {
        let manager = HotKeyManager.shared
        manager.unregister(group: HotKeyManager.slotsGroup)
        manager.register("ctrl+alt+left", group: HotKeyManager.slotsGroup) { [weak self] in
            self?.moveFocusedWindow(.left)
        }
        manager.register("ctrl+alt+right", group: HotKeyManager.slotsGroup) { [weak self] in
            self?.moveFocusedWindow(.right)
        }
        manager.register("ctrl+alt+up", group: HotKeyManager.slotsGroup) { [weak self] in
            self?.moveFocusedWindow(.up)
        }
        manager.register("ctrl+alt+down", group: HotKeyManager.slotsGroup) { [weak self] in
            self?.moveFocusedWindow(.down)
        }
    }

    private func moveFocusedWindow(_ direction: Direction) {
        guard !slots.isEmpty,
              let window = WindowManager.focusedWindow(),
              let frame = WindowManager.frame(of: window)
        else { return }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        let candidates = slots.filter { slot in
            let slotCenter = CGPoint(x: slot.midX, y: slot.midY)
            switch direction {
            case .left: return slotCenter.x < center.x - 1
            case .right: return slotCenter.x > center.x + 1
            case .up: return slotCenter.y < center.y - 1 // top-left origin: up = smaller y
            case .down: return slotCenter.y > center.y + 1
            }
        }

        guard let target = candidates.min(by: {
            distance(center, CGPoint(x: $0.midX, y: $0.midY))
                < distance(center, CGPoint(x: $1.midX, y: $1.midY))
        }) else { return }

        WindowManager.setFrame(window, target)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
