import AppKit
import SwiftUI

// MARK: - Editable models (UI-side mirror of the Config types)

struct EditableAssignment: Identifiable {
    let id = UUID()
    var appIdentifier: String
    var allWindows: Bool
}

struct EditableTile: Identifiable {
    let id = UUID()
    var screen: Int
    /// Fractional rect in 0...1 screen space, origin top-left.
    var rect: CGRect
    var apps: [EditableAssignment]
}

struct EditableLayout: Identifiable {
    let id = UUID()
    var name: String
    var hotkey: String
    var hideOthers: Bool
    var tiles: [EditableTile]
}

extension EditableLayout {
    init(_ layout: Layout) {
        self.init(
            name: layout.name,
            hotkey: layout.hotkey ?? "",
            hideOthers: layout.hideOthers ?? false,
            tiles: layout.tiles.map { tile in
                EditableTile(
                    screen: tile.screen ?? 0,
                    rect: CGRect(x: tile.x, y: tile.y, width: tile.w, height: tile.h),
                    apps: layout.assignments
                        .filter { $0.tile == tile.id }
                        .map { EditableAssignment(appIdentifier: $0.app, allWindows: $0.allWindows ?? false) }
                )
            }
        )
    }

    func toLayout() -> Layout {
        var outTiles: [Tile] = []
        var outAssignments: [Assignment] = []

        func round4(_ v: CGFloat) -> Double { (Double(v) * 10000).rounded() / 10000 }

        for (index, tile) in tiles.enumerated() {
            let tileID = "tile-\(index + 1)"
            outTiles.append(
                Tile(
                    id: tileID,
                    screen: tile.screen == 0 ? nil : tile.screen,
                    x: round4(tile.rect.minX),
                    y: round4(tile.rect.minY),
                    w: round4(tile.rect.width),
                    h: round4(tile.rect.height)
                )
            )
            for app in tile.apps {
                outAssignments.append(
                    Assignment(
                        app: app.appIdentifier,
                        tile: tileID,
                        allWindows: app.allWindows ? true : nil
                    )
                )
            }
        }

        return Layout(
            name: name.isEmpty ? "Untitled" : name,
            hotkey: hotkey.isEmpty ? nil : hotkey,
            hideOthers: hideOthers ? true : nil,
            tiles: outTiles,
            assignments: outAssignments
        )
    }
}

// MARK: - Grid density

enum GridDensity: String, CaseIterable, Identifiable {
    case coarse, medium, fine

    var id: Self { self }

    var label: String {
        switch self {
        case .coarse: return "Coarse grid"
        case .medium: return "Medium grid"
        case .fine: return "Fine grid"
        }
    }

    var columns: Int {
        switch self {
        case .coarse: return 12
        case .medium: return 24
        case .fine: return 48
        }
    }

    var rows: Int { columns / 2 }
}

// MARK: - Tile colors

enum TilePalette {
    static let colors: [Color] = [
        Color(red: 0.35, green: 0.56, blue: 1.00), // blue
        Color(red: 0.66, green: 0.47, blue: 1.00), // purple
        Color(red: 0.18, green: 0.84, blue: 0.72), // teal
        Color(red: 1.00, green: 0.62, blue: 0.32), // orange
        Color(red: 1.00, green: 0.45, blue: 0.66), // pink
        Color(red: 0.39, green: 0.83, blue: 0.43), // green
        Color(red: 1.00, green: 0.80, blue: 0.26), // yellow
        Color(red: 0.40, green: 0.78, blue: 1.00), // cyan
    ]

    static func color(at index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

// MARK: - Editor state

final class EditorState: ObservableObject {
    @Published var layouts: [EditableLayout]
    @Published var selectedLayoutID: UUID?
    @Published var selectedTileID: UUID?
    @Published var screenIndex: Int = 0
    @Published var gridDensity: GridDensity = .medium
    @Published var hasUnsavedChanges = false

    var onSave: ((Config) -> Void)?
    var onApply: ((Layout) -> Void)?

    init(config: Config) {
        let layouts = config.layouts.map(EditableLayout.init)
        self.layouts = layouts
        self.selectedLayoutID = layouts.first?.id
    }

    // MARK: Screens

    var screens: [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    var screenCount: Int { max(screens.count, 1) }

    var currentScreenAspect: CGFloat {
        guard screens.indices.contains(screenIndex) else { return 21.0 / 9.0 }
        let frame = screens[screenIndex].frame
        return frame.width / max(frame.height, 1)
    }

    var gridColumns: Int { gridDensity.columns }
    var gridRows: Int { gridDensity.rows }

    // MARK: Selection

    var selectedLayout: EditableLayout? {
        layouts.first { $0.id == selectedLayoutID }
    }

    var selectedTile: EditableTile? {
        selectedLayout?.tiles.first { $0.id == selectedTileID }
    }

    var currentScreenTiles: [EditableTile] {
        selectedLayout?.tiles.filter { $0.screen == screenIndex } ?? []
    }

    func colorIndex(of tileID: UUID) -> Int {
        selectedLayout?.tiles.firstIndex { $0.id == tileID } ?? 0
    }

    func selectLayout(_ id: UUID) {
        selectedLayoutID = id
        selectedTileID = nil
        if screenIndex >= screenCount { screenIndex = 0 }
    }

    // MARK: Layout mutations

    func addLayout() {
        let layout = EditableLayout(name: "Layout \(layouts.count + 1)", hotkey: "", hideOthers: false, tiles: [])
        layouts.append(layout)
        selectLayout(layout.id)
        hasUnsavedChanges = true
    }

    func deleteLayout(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        if selectedLayoutID == id {
            selectedLayoutID = layouts.first?.id
            selectedTileID = nil
        }
        hasUnsavedChanges = true
    }

    func duplicateLayout(_ id: UUID) {
        guard let source = layouts.first(where: { $0.id == id }) else { return }
        let copy = EditableLayout(
            name: source.name + " Copy",
            hotkey: "",
            hideOthers: source.hideOthers,
            tiles: source.tiles.map {
                EditableTile(
                    screen: $0.screen,
                    rect: $0.rect,
                    apps: $0.apps.map {
                        EditableAssignment(appIdentifier: $0.appIdentifier, allWindows: $0.allWindows)
                    }
                )
            }
        )
        layouts.append(copy)
        selectLayout(copy.id)
        hasUnsavedChanges = true
    }

    // MARK: Tile mutations

    func addTile(rect: CGRect) {
        let tile = EditableTile(screen: screenIndex, rect: rect, apps: [])
        withSelectedLayout { $0.tiles.append(tile) }
        selectedTileID = tile.id
        hasUnsavedChanges = true
    }

    func setTileRect(_ tileID: UUID, _ rect: CGRect) {
        withSelectedLayout { layout in
            guard let index = layout.tiles.firstIndex(where: { $0.id == tileID }),
                  layout.tiles[index].rect != rect
            else { return }
            layout.tiles[index].rect = rect
            hasUnsavedChanges = true
        }
    }

    func deleteTile(_ tileID: UUID) {
        withSelectedLayout { $0.tiles.removeAll { $0.id == tileID } }
        if selectedTileID == tileID { selectedTileID = nil }
        hasUnsavedChanges = true
    }

    func deleteSelectedTile() {
        guard let id = selectedTileID else { return }
        deleteTile(id)
    }

    // MARK: App assignment mutations

    func addApp(_ identifier: String, to tileID: UUID) {
        withSelectedLayout { layout in
            guard let index = layout.tiles.firstIndex(where: { $0.id == tileID }),
                  !layout.tiles[index].apps.contains(where: {
                      $0.appIdentifier.lowercased() == identifier.lowercased()
                  })
            else { return }
            layout.tiles[index].apps.append(
                EditableAssignment(appIdentifier: identifier, allWindows: false)
            )
            hasUnsavedChanges = true
        }
    }

    func removeApp(_ assignmentID: UUID, from tileID: UUID) {
        withSelectedLayout { layout in
            guard let index = layout.tiles.firstIndex(where: { $0.id == tileID }) else { return }
            layout.tiles[index].apps.removeAll { $0.id == assignmentID }
            hasUnsavedChanges = true
        }
    }

    func toggleAllWindows(_ assignmentID: UUID, in tileID: UUID) {
        withSelectedLayout { layout in
            guard let tileIndex = layout.tiles.firstIndex(where: { $0.id == tileID }),
                  let appIndex = layout.tiles[tileIndex].apps.firstIndex(where: { $0.id == assignmentID })
            else { return }
            layout.tiles[tileIndex].apps[appIndex].allWindows.toggle()
            hasUnsavedChanges = true
        }
    }

    // MARK: Field bindings

    func nameBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedLayout?.name ?? "" },
            set: { [weak self] value in
                self?.withSelectedLayout { $0.name = value }
                self?.hasUnsavedChanges = true
            }
        )
    }

    func hotkeyBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedLayout?.hotkey ?? "" },
            set: { [weak self] value in
                self?.withSelectedLayout { $0.hotkey = value }
                self?.hasUnsavedChanges = true
            }
        )
    }

    func hideOthersBinding() -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.selectedLayout?.hideOthers ?? false },
            set: { [weak self] value in
                self?.withSelectedLayout { $0.hideOthers = value }
                self?.hasUnsavedChanges = true
            }
        )
    }

    // MARK: Save / apply

    func saveAll() {
        let config = Config(layouts: layouts.map { $0.toLayout() })
        onSave?(config)
        hasUnsavedChanges = false
    }

    func applySelected() {
        guard let layout = selectedLayout?.toLayout() else { return }
        onApply?(layout)
    }

    // MARK: Helpers

    private func withSelectedLayout(_ body: (inout EditableLayout) -> Void) {
        guard let index = layouts.firstIndex(where: { $0.id == selectedLayoutID }) else { return }
        body(&layouts[index])
    }
}
