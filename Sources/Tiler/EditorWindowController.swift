import AppKit
import SwiftUI

/// Hosts the SwiftUI layout editor in a standalone window. Only one editor
/// window exists at a time.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var current: EditorWindowController?

    private let state: EditorState
    private var keyMonitor: Any?

    static func show(
        config: Config,
        onSave: @escaping (Config) -> Void,
        onApply: @escaping (Layout) -> Void
    ) {
        if let existing = current {
            NSApp.activate(ignoringOtherApps: true)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = EditorWindowController(config: config, onSave: onSave, onApply: onApply)
        current = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(
        config: Config,
        onSave: @escaping (Config) -> Void,
        onApply: @escaping (Layout) -> Void
    ) {
        let state = EditorState(config: config)
        state.onSave = onSave
        state.onApply = onApply
        self.state = state

        let hosting = NSHostingController(rootView: LayoutEditorView(state: state))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Tiler Layouts"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 1120, height: 660))
        window.minSize = NSSize(width: 940, height: 560)

        super.init(window: window)
        window.delegate = self
        installKeyMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Keyboard (delete tile / deselect)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            // Don't steal keys while a text field is being edited.
            let editingText = self.window?.firstResponder is NSTextView

            switch event.keyCode {
            case 51, 117: // delete / forward delete
                if !editingText, self.state.selectedTileID != nil {
                    self.state.deleteSelectedTile()
                    return nil
                }
            case 53: // escape
                if !editingText, self.state.selectedTileID != nil {
                    self.state.selectedTileID = nil
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard state.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to your layouts?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            state.saveAll()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        Self.current = nil
    }
}
