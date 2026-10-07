import SwiftUI

/// State and flow layout of the switcher grid. Tiles keep their window's aspect ratio, are packed into
/// rows, and everything is scaled down together when there are too many windows to fit on screen.
final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected = 0
    @Published var rows: [[Int]] = []
    @Published var scale: CGFloat = 1
    private(set) var needsScroll = false

    private var settings: Settings { Settings.shared }

    func thumbSize(_ w: WindowInfo) -> CGSize {
        if settings.showThumbnails {
            let h = settings.tileSize.thumbHeight * scale
            let aspect = w.bounds.width > 20 && w.bounds.height > 20 ? w.bounds.width / w.bounds.height : 1.6
            return CGSize(width: min(max(h * aspect, h * 0.95), h * 2.1).rounded(), height: h.rounded())
        }
        return CGSize(width: (118 * scale).rounded(), height: (64 * scale).rounded())
    }

    func tileSize(_ w: WindowInfo) -> CGSize {
        let t = thumbSize(w)
        let title: CGFloat = settings.showTitles ? (settings.showThumbnails ? 26 : 36) : 0
        return CGSize(width: t.width + Layout.tilePad * 2, height: t.height + title + Layout.tilePad * 2)
    }

    /// Computes rows and scale for the given limits and returns the panel's content size.
    func layout(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let contentWidth = maxWidth - Layout.pad * 2
        var s: CGFloat = 1
        var size = CGSize.zero
        while true {
            scale = s
            rows = flow(maxRowWidth: contentWidth)
            size = measure()
            if size.height <= maxHeight || s <= 0.5 { break }
            s -= 0.05
        }
        needsScroll = size.height > maxHeight
        return CGSize(width: min(size.width, maxWidth), height: min(size.height, maxHeight))
    }

    private func flow(maxRowWidth: CGFloat) -> [[Int]] {
        var result = [[Int]](), row = [Int](), used: CGFloat = 0
        for (i, w) in windows.enumerated() {
            let tw = tileSize(w).width
            if !row.isEmpty, used + Layout.gap + tw > maxRowWidth {
                result.append(row); row = []; used = 0
            }
            used += (row.isEmpty ? 0 : Layout.gap) + tw
            row.append(i)
        }
        if !row.isEmpty { result.append(row) }
        return result
    }

    private func measure() -> CGSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for row in rows {
            let rowWidth = row.reduce(CGFloat(0)) { $0 + tileSize(windows[$1]).width } + CGFloat(row.count - 1) * Layout.gap
            width = max(width, rowWidth)
            height += row.map { tileSize(windows[$0]).height }.max() ?? 0
        }
        height += CGFloat(max(0, rows.count - 1)) * Layout.gap
        return CGSize(width: width + Layout.pad * 2, height: height + Layout.pad * 2)
    }

    /// Frame of a tile inside the grid (rows are centred in the widest row). Lets the glass selection be placed
    /// without measuring every tile with a GeometryReader on each frame.
    func frame(of index: Int) -> CGRect? {
        guard rowsMatchWindows, let r = rows.firstIndex(where: { $0.contains(index) }) else { return nil }
        func width(_ row: [Int]) -> CGFloat {
            row.reduce(CGFloat(0)) { $0 + tileSize(windows[$1]).width } + CGFloat(max(0, row.count - 1)) * Layout.gap
        }
        func height(_ row: [Int]) -> CGFloat { row.map { tileSize(windows[$0]).height }.max() ?? 0 }
        let widest = rows.map(width).max() ?? 0
        var y: CGFloat = 0
        for k in 0..<r { y += height(rows[k]) + Layout.gap }
        var x = (widest - width(rows[r])) / 2
        for i in rows[r] {
            let size = tileSize(windows[i])
            if i == index { return CGRect(x: x, y: y, width: size.width, height: size.height) }
            x += size.width + Layout.gap
        }
        return nil
    }

    /// `rows` is recomputed by `layout`, so for a moment after the window list changes (or is cleared as the
    /// switcher closes) it can point past the end of `windows`. Anything indexing through it must check this.
    private var rowsMatchWindows: Bool {
        rows.allSatisfy { row in row.allSatisfy { windows.indices.contains($0) } }
    }

    /// Moves the selection one row up/down, landing on the tile whose center is closest horizontally.
    func moveVertically(_ delta: Int) {
        guard rowsMatchWindows, let r = rows.firstIndex(where: { $0.contains(selected) }) else { return }
        let target = r + delta
        guard rows.indices.contains(target) else { return }
        func center(_ index: Int, in row: [Int]) -> CGFloat {
            var x: CGFloat = 0
            for i in row {
                let w = tileSize(windows[i]).width
                if i == index { return x + w / 2 }
                x += w + Layout.gap
            }
            return x
        }
        let from = center(selected, in: rows[r])
        selected = rows[target].min { abs(center($0, in: rows[target]) - from) < abs(center($1, in: rows[target]) - from) } ?? selected
    }
}
