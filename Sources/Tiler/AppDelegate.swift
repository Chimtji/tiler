import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var config: Config?
    private var configError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.3x1",
                accessibilityDescription: "Tiler"
            )
        }

        ConfigStore.createDefaultConfigIfNeeded()
        // Prompt for Accessibility permission on first launch.
        _ = WindowManager.isTrusted(prompt: true)

        SlotManager.shared.onChange = { [weak self] in self?.rebuildMenu() }

        reloadConfig()
    }

    // MARK: - Config

    private func reloadConfig() {
        configError = nil
        do {
            config = try ConfigStore.load()
        } catch {
            config = nil
            configError = error.localizedDescription
        }

        // Keep the active layout in sync with the new config (slots may have
        // changed); deactivate if it no longer exists.
        if let active = SlotManager.shared.activeLayout {
            if let updated = config?.layouts.first(where: { $0.name == active.name }) {
                SlotManager.shared.activate(updated)
            } else {
                SlotManager.shared.deactivate()
            }
        }

        registerHotkeys()
        rebuildMenu()
    }

    private func registerHotkeys() {
        HotKeyManager.shared.unregister(group: HotKeyManager.layoutsGroup)
        guard let config else { return }

        for layout in config.layouts {
            guard let hotkey = layout.hotkey else { continue }
            let ok = HotKeyManager.shared.register(hotkey, group: HotKeyManager.layoutsGroup) { [weak self] in
                self?.apply(layout: layout)
            }
            if !ok {
                NSLog("Tiler: could not register hotkey \"%@\" for layout \"%@\"", hotkey, layout.name)
            }
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        if let configError {
            let item = NSMenuItem(title: "⚠️ Config error", action: #selector(showConfigError), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
            _ = configError // detail shown via alert
        }

        if let config, !config.layouts.isEmpty {
            let activeName = SlotManager.shared.activeLayout?.name
            for (index, layout) in config.layouts.enumerated() {
                let title = layout.hotkey.map { "\(layout.name)   (\(HotKeyManager.pretty($0)))" } ?? layout.name
                let item = NSMenuItem(title: title, action: #selector(applyLayoutItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = layout.name == activeName ? .on : .off
                menu.addItem(item)
            }
        } else if configError == nil {
            menu.addItem(NSMenuItem(title: "No layouts in config", action: nil, keyEquivalent: ""))
        }

        if SlotManager.shared.activeLayout != nil {
            menu.addItem(.separator())
            let deactivate = NSMenuItem(
                title: "Deactivate Layout",
                action: #selector(deactivateLayout),
                keyEquivalent: ""
            )
            deactivate.target = self
            menu.addItem(deactivate)
        }

        menu.addItem(.separator())

        let editor = NSMenuItem(title: "Edit Layouts…", action: #selector(openLayoutEditor), keyEquivalent: "e")
        editor.target = self
        menu.addItem(editor)

        let edit = NSMenuItem(title: "Open Config File", action: #selector(editConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let reload = NSMenuItem(title: "Reload Config", action: #selector(reloadConfigItem), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        if !WindowManager.isTrusted(prompt: false) {
            let ax = NSMenuItem(
                title: "⚠️ Grant Accessibility Access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            ax.target = self
            menu.addItem(ax)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(title: "Quit Tiler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openLayoutEditor() {
        let config = (try? ConfigStore.load()) ?? Config(layouts: [])
        EditorWindowController.show(
            config: config,
            onSave: { [weak self] newConfig in
                do {
                    try ConfigStore.save(newConfig)
                } catch {
                    NSLog("Tiler: failed to save config: %@", error.localizedDescription)
                }
                self?.reloadConfig()
            },
            onApply: { [weak self] layout in
                self?.apply(layout: layout)
            }
        )
    }

    @objc private func applyLayoutItem(_ sender: NSMenuItem) {
        guard let config, config.layouts.indices.contains(sender.tag) else { return }
        apply(layout: config.layouts[sender.tag])
    }

    private func apply(layout: Layout) {
        guard WindowManager.isTrusted(prompt: true) else {
            rebuildMenu()
            return
        }
        let problems = WindowManager.apply(layout)
        SlotManager.shared.activate(layout)
        if !problems.isEmpty {
            NSLog("Tiler: layout \"%@\": %@", layout.name, problems.joined(separator: " | "))
        }
    }

    @objc private func deactivateLayout() {
        SlotManager.shared.deactivate()
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(ConfigStore.configURL)
    }

    @objc private func reloadConfigItem() {
        reloadConfig()
    }

    @objc private func showConfigError() {
        let alert = NSAlert()
        alert.messageText = "Tiler config error"
        alert.informativeText = configError ?? "Unknown error."
        alert.addButton(withTitle: "Edit Config")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            editConfig()
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
