import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root editor view

struct LayoutEditorView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(state: state)
                .frame(width: 215)
            Divider()
            mainColumn
            Divider()
            InspectorView(state: state)
                .frame(width: 285)
        }
        .frame(minWidth: 940, minHeight: 560)
        .background(VisualEffectBackground().ignoresSafeArea())
        .onExitCommand { state.selectedTileID = nil }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            if state.selectedLayout != nil {
                TopBarView(state: state)
                Spacer(minLength: 0)
                TileCanvasView(state: state)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text("No layouts yet")
                .font(.title3.weight(.semibold))
            Text("Create a layout, then draw tiles on the grid\nand assign your apps to them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                state.addLayout()
            } label: {
                Label("New Layout", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var state: EditorState
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layouts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: state.addLayout) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New layout")
            }
            .padding(.horizontal, 16)
            .padding(.top, 42)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(state.layouts) { layout in
                        row(layout)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
        }
        .background(Color.primary.opacity(0.035))
    }

    private func row(_ layout: EditableLayout) -> some View {
        let isSelected = state.selectedLayoutID == layout.id
        let isHovered = hoveredID == layout.id

        return HStack(spacing: 9) {
            Image(systemName: "rectangle.split.3x1.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(layout.name.isEmpty ? "Untitled" : layout.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(layout.tiles.count) tile\(layout.tiles.count == 1 ? "" : "s")")
                    if !layout.hotkey.isEmpty {
                        Text(HotKeyManager.pretty(layout.hotkey))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isHovered {
                Button {
                    state.deleteLayout(layout.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete layout")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.17)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectLayout(layout.id) }
        .onHover { hovering in
            if hovering {
                hoveredID = layout.id
            } else if hoveredID == layout.id {
                hoveredID = nil
            }
        }
        .contextMenu {
            Button("Duplicate") { state.duplicateLayout(layout.id) }
            Button("Delete", role: .destructive) { state.deleteLayout(layout.id) }
        }
    }
}

// MARK: - Top bar

struct TopBarView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 12) {
            if state.screenCount > 1 {
                Picker("", selection: $state.screenIndex) {
                    ForEach(0..<state.screenCount, id: \.self) { index in
                        Text("Screen \(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }

            Spacer()

            Picker("", selection: $state.gridDensity) {
                ForEach(GridDensity.allCases) { density in
                    Text(density.label).tag(density)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Grid snapping density")

            Button {
                state.applySelected()
            } label: {
                Label("Apply", systemImage: "play.fill")
            }
            .help("Arrange your windows with this layout now")
            .disabled(state.selectedLayout?.tiles.isEmpty ?? true)

            Button {
                state.saveAll()
            } label: {
                Label(
                    state.hasUnsavedChanges ? "Save" : "Saved",
                    systemImage: state.hasUnsavedChanges ? "square.and.arrow.down" : "checkmark"
                )
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!state.hasUnsavedChanges)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if state.selectedLayout != nil {
                    layoutSection
                    Divider()
                    if let tile = state.selectedTile {
                        tileSection(tile)
                    } else {
                        canvasHints
                    }
                }
            }
            .padding(16)
            .padding(.top, 30)
        }
        .background(Color.primary.opacity(0.035))
    }

    // MARK: Layout section

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Layout")

            TextField("Name", text: state.nameBinding())
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    TextField("Hotkey · e.g. ctrl+alt+1", text: state.hotkeyBinding())
                        .textFieldStyle(.roundedBorder)
                    if let hotkey = state.selectedLayout?.hotkey, !hotkey.isEmpty {
                        Image(systemName: hotkeyValid(hotkey)
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill")
                            .foregroundStyle(hotkeyValid(hotkey) ? Color.green : Color.orange)
                            .help(hotkeyValid(hotkey)
                                ? "Hotkey is valid"
                                : "Unrecognized hotkey — use e.g. ctrl+alt+1")
                    }
                }
                Text("Global shortcut to apply this layout")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: state.hideOthersBinding()) {
                    Text("Minimize other windows")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Windows not placed by this layout get minimized")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hotkeyValid(_ spec: String) -> Bool {
        HotKeyManager.parse(spec) != nil
    }

    // MARK: Tile section

    private func tileSection(_ tile: EditableTile) -> some View {
        let color = TilePalette.color(at: state.colorIndex(of: tile.id))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 11, height: 11)
                sectionHeader("Tile")
                Spacer()
                Text(tileSummary(tile))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apps in this tile")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if tile.apps.isEmpty {
                    Text("No apps assigned yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.04))
                        )
                }

                ForEach(tile.apps) { assignment in
                    appRow(assignment, tile: tile)
                }
            }

            addAppMenu(tile)

            Divider()

            Button(role: .destructive) {
                state.deleteSelectedTile()
            } label: {
                Label("Delete Tile", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func tileSummary(_ tile: EditableTile) -> String {
        let w = Int((tile.rect.width * 100).rounded())
        let h = Int((tile.rect.height * 100).rounded())
        return "\(w)% × \(h)%"
    }

    private func appRow(_ assignment: EditableAssignment, tile: EditableTile) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: AppCatalog.icon(for: assignment.appIdentifier))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 0) {
                Text(AppCatalog.displayName(for: assignment.appIdentifier))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if assignment.allWindows {
                    Text("All windows")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button(assignment.allWindows ? "Move only main window" : "Move all windows") {
                    state.toggleAllWindows(assignment.id, in: tile.id)
                }
                Divider()
                Button("Remove", role: .destructive) {
                    state.removeApp(assignment.id, from: tile.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func addAppMenu(_ tile: EditableTile) -> some View {
        Menu {
            Section("Running apps") {
                ForEach(AppCatalog.runningApps()) { app in
                    Button {
                        state.addApp(app.bundleID, to: tile.id)
                    } label: {
                        Label {
                            Text(app.name)
                        } icon: {
                            Image(nsImage: AppCatalog.icon(for: app.bundleID))
                        }
                    }
                }
            }
            Divider()
            Button("Choose from Applications…") {
                chooseApp(tileID: tile.id)
            }
        } label: {
            Label("Add App", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
    }

    private func chooseApp(tileID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an app to assign to this tile"
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundleID = Bundle(url: url)?.bundleIdentifier {
            state.addApp(bundleID, to: tileID)
        }
    }

    // MARK: Hints

    private var canvasHints: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tile")
            VStack(alignment: .leading, spacing: 8) {
                hint(icon: "plus.square.dashed", text: "Drag on the grid to draw a tile")
                hint(icon: "cursorarrow.motionlines", text: "Drag a tile to move it")
                hint(icon: "arrow.up.left.and.arrow.down.right", text: "Drag a tile's edge to resize")
                hint(icon: "delete.left", text: "Press ⌫ to delete the selected tile")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )

            sectionHeader("While a layout is active")
            VStack(alignment: .leading, spacing: 8) {
                hint(icon: "cursorarrow.and.square.on.square.dashed", text: "Drop a window inside a tile to snap it there")
                hint(icon: "keyboard", text: "⌃⌥ arrows move the focused window between tiles")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    private func hint(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
    }
}

// MARK: - Window background material

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
