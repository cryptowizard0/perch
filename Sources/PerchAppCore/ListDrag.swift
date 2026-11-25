/// Dragging a row in the Lists… window (#70) to reorder it. A plain mouse drag, not AppKit drag and drop: a drag
/// session hands the keyboard back to the frontmost app when it ends without telling the popup, so Esc no longer
/// reached the window and nothing closed it (2026-11-25). `offset` is how far the pointer has moved since the row was
/// picked up, down positive, in points.
public struct ListDrag: Equatable, Sendable {
    /// The dragged row's index.
    public var from: Int
    public var offset: Double
    public var rowHeight: Double
    /// How many rows there are.
    public var count: Int

    public init(from: Int, offset: Double, rowHeight: Double, count: Int) {
        self.from = from
        self.offset = offset
        self.rowHeight = rowHeight
        self.count = count
    }

    /// Where it would land now: the nearest row (half a row is enough), never past either end.
    public var target: Int {
        let rows = Int((offset / rowHeight).rounded())
        return min(max(from + rows, 0), max(count - 1, 0))
    }

    /// How many rows the row at `index` steps aside to make room: -1 (up), 1 (down) or 0. The dragged row itself
    /// follows the pointer instead.
    public func shift(of index: Int) -> Int {
        let target = target
        if from < target, index > from, index <= target { return -1 }
        if target < from, index >= target, index < from { return 1 }
        return 0
    }

    /// `ids`, the rows in order, with the dragged one moved to `target`.
    public func reordered<ID>(_ ids: [ID]) -> [ID] {
        guard ids.indices.contains(from) else { return ids }
        var ids = ids
        let moved = ids.remove(at: from)
        ids.insert(moved, at: min(target, ids.count))
        return ids
    }
}
