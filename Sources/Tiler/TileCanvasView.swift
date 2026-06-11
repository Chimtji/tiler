import AppKit
import SwiftUI

/// The interactive screen canvas: a grid where you drag to draw tiles, then
/// drag tiles to move them or drag their edges to resize. Everything snaps
/// to the grid.
struct TileCanvasView: View {
    @ObservedObject var state: EditorState

    @State private var rubberBand: CGRect? // fraction space
    @State private var activeDrag: ActiveTileDrag?

    private struct ActiveTileDrag {
        let tileID: UUID
        let zone: DragZone
        let startRect: CGRect
    }

    private enum DragZone {
        case move
        case resize(top: Bool, bottom: Bool, left: Bool, right: Bool)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                background(size: size)

                ForEach(state.currentScreenTiles) { tile in
                    tileView(tile, size: size)
                }

                if let band = rubberBand {
                    rubberBandView(band, size: size)
                }

                if state.currentScreenTiles.isEmpty && rubberBand == nil {
                    emptyHint(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .coordinateSpace(name: "tiler-canvas")
        }
        .aspectRatio(state.currentScreenAspect, contentMode: .fit)
    }

    // MARK: - Background + grid

    private func background(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.045))
            gridDots(size: size)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedTileID = nil }
        .gesture(newTileGesture(size: size))
    }

    private func gridDots(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let cols = state.gridColumns
            let rows = state.gridRows
            let cellW = canvasSize.width / CGFloat(cols)
            let cellH = canvasSize.height / CGFloat(rows)
            let dotColor = Color.primary.opacity(0.16)

            for c in 1..<cols {
                for r in 1..<rows {
                    let x = CGFloat(c) * cellW
                    let y = CGFloat(r) * cellH
                    let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    context.fill(Path(ellipseIn: dot), with: .color(dotColor))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func emptyHint(size: CGSize) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 30, weight: .light))
            Text("Click and drag to draw a tile")
                .font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Tiles

    private func tileView(_ tile: EditableTile, size: CGSize) -> some View {
        let frame = pixelRect(tile.rect, size)
        let color = TilePalette.color(at: state.colorIndex(of: tile.id))
        let isSelected = state.selectedTileID == tile.id

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(isSelected ? 0.55 : 0.42), color.opacity(isSelected ? 0.38 : 0.26)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? color : color.opacity(0.45),
                    lineWidth: isSelected ? 2 : 1
                )
            tileContent(tile, frame: frame, color: color)
        }
        .overlay(alignment: .topLeading) { if isSelected { handle.offset(x: -3, y: -3) } }
        .overlay(alignment: .topTrailing) { if isSelected { handle.offset(x: 3, y: -3) } }
        .overlay(alignment: .bottomLeading) { if isSelected { handle.offset(x: -3, y: 3) } }
        .overlay(alignment: .bottomTrailing) { if isSelected { handle.offset(x: 3, y: 3) } }
        .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 12)
        .padding(1.5)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .gesture(tileDragGesture(tile, size: size))
        .contextMenu {
            Button("Delete Tile", role: .destructive) { state.deleteTile(tile.id) }
        }
    }

    private var handle: some View {
        Circle()
            .fill(.white)
            .frame(width: 7, height: 7)
            .shadow(color: .black.opacity(0.4), radius: 2)
    }

    @ViewBuilder
    private func tileContent(_ tile: EditableTile, frame: CGRect, color: Color) -> some View {
        let iconSize = max(18, min(34, min(frame.width, frame.height) * 0.28))
        let compact = frame.height < 70 || frame.width < 90

        VStack(spacing: 5) {
            if tile.apps.isEmpty {
                if !compact {
                    Image(systemName: "app.dashed")
                        .font(.system(size: iconSize * 0.7, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(tile.apps.prefix(4)) { assignment in
                        Image(nsImage: AppCatalog.icon(for: assignment.appIdentifier))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSize, height: iconSize)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    if tile.apps.count > 4 {
                        Text("+\(tile.apps.count - 4)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            if !compact {
                Text("\(percent(tile.rect.width)) × \(percent(tile.rect.height))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .allowsHitTesting(false)
    }

    private func percent(_ fraction: CGFloat) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Rubber band (drawing new tiles)

    private func rubberBandView(_ band: CGRect, size: CGSize) -> some View {
        let frame = pixelRect(band, size)
        return RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }

    private func newTileGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tiler-canvas"))
            .onChanged { value in
                rubberBand = cellAlignedRect(
                    from: value.startLocation,
                    to: value.location,
                    size: size
                )
            }
            .onEnded { _ in
                if let band = rubberBand,
                   band.width > 0.001, band.height > 0.001 {
                    state.addTile(rect: band)
                }
                rubberBand = nil
            }
    }

    /// Returns the smallest grid-cell-aligned fraction rect containing both points.
    private func cellAlignedRect(from a: CGPoint, to b: CGPoint, size: CGSize) -> CGRect {
        let cols = CGFloat(state.gridColumns)
        let rows = CGFloat(state.gridRows)

        let fx0 = clamp(min(a.x, b.x) / size.width, 0, 1)
        let fx1 = clamp(max(a.x, b.x) / size.width, 0, 1)
        let fy0 = clamp(min(a.y, b.y) / size.height, 0, 1)
        let fy1 = clamp(max(a.y, b.y) / size.height, 0, 1)

        let minX = floor(fx0 * cols) / cols
        let maxX = ceil(fx1 * cols) / cols
        let minY = floor(fy0 * rows) / rows
        let maxY = ceil(fy1 * rows) / rows

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Tile move / resize

    private func tileDragGesture(_ tile: EditableTile, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("tiler-canvas"))
            .onChanged { value in
                if activeDrag == nil {
                    state.selectedTileID = tile.id
                    let frame = pixelRect(tile.rect, size)
                    activeDrag = ActiveTileDrag(
                        tileID: tile.id,
                        zone: dragZone(at: value.startLocation, frame: frame),
                        startRect: tile.rect
                    )
                }
                guard let drag = activeDrag, drag.tileID == tile.id else { return }
                // Ignore micro-movements so a plain click never nudges the tile.
                guard abs(value.translation.width) + abs(value.translation.height) > 3 else { return }
                state.setTileRect(
                    tile.id,
                    updatedRect(
                        start: drag.startRect,
                        translation: value.translation,
                        zone: drag.zone,
                        size: size
                    )
                )
            }
            .onEnded { _ in activeDrag = nil }
    }

    private func dragZone(at point: CGPoint, frame: CGRect) -> DragZone {
        let margin: CGFloat = 9
        let left = abs(point.x - frame.minX) <= margin
        let right = abs(point.x - frame.maxX) <= margin
        let top = abs(point.y - frame.minY) <= margin
        let bottom = abs(point.y - frame.maxY) <= margin
        if left || right || top || bottom {
            return .resize(top: top, bottom: bottom, left: left, right: right)
        }
        return .move
    }

    private func updatedRect(
        start: CGRect,
        translation: CGSize,
        zone: DragZone,
        size: CGSize
    ) -> CGRect {
        let dx = translation.width / size.width
        let dy = translation.height / size.height
        let cellW = 1.0 / CGFloat(state.gridColumns)
        let cellH = 1.0 / CGFloat(state.gridRows)

        func snapX(_ v: CGFloat) -> CGFloat { (v / cellW).rounded() * cellW }
        func snapY(_ v: CGFloat) -> CGFloat { (v / cellH).rounded() * cellH }

        switch zone {
        case .move:
            let x = clamp(snapX(start.minX + dx), 0, 1 - start.width)
            let y = clamp(snapY(start.minY + dy), 0, 1 - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height)

        case .resize(let top, let bottom, let left, let right):
            var minX = start.minX
            var maxX = start.maxX
            var minY = start.minY
            var maxY = start.maxY
            if left { minX = clamp(snapX(start.minX + dx), 0, maxX - cellW) }
            if right { maxX = clamp(snapX(start.maxX + dx), minX + cellW, 1) }
            if top { minY = clamp(snapY(start.minY + dy), 0, maxY - cellH) }
            if bottom { maxY = clamp(snapY(start.maxY + dy), minY + cellH, 1) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    // MARK: - Geometry helpers

    private func pixelRect(_ fraction: CGRect, _ size: CGSize) -> CGRect {
        CGRect(
            x: fraction.minX * size.width,
            y: fraction.minY * size.height,
            width: fraction.width * size.width,
            height: fraction.height * size.height
        )
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}
