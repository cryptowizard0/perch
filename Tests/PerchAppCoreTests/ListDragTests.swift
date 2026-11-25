import PerchAppCore
import Testing

/// Dragging a row in the Lists… window (#70): where it lands, how the others make room, the order it leaves.
@Suite struct ListDragTests {
    func drag(from: Int, offset: Double, count: Int = 4) -> ListDrag {
        ListDrag(from: from, offset: offset, rowHeight: 28, count: count)
    }

    @Test func itLandsOnTheNearestRow() {
        #expect(drag(from: 1, offset: 0).target == 1)
        #expect(drag(from: 1, offset: 13).target == 1)
        #expect(drag(from: 1, offset: 14).target == 2)  // half a row is enough
        #expect(drag(from: 1, offset: 30).target == 2)
        #expect(drag(from: 1, offset: 56).target == 3)
        #expect(drag(from: 2, offset: -14).target == 1)
        #expect(drag(from: 2, offset: -50).target == 0)
    }

    @Test func itStaysInsideTheList() {
        #expect(drag(from: 1, offset: 500).target == 3)
        #expect(drag(from: 1, offset: -500).target == 0)
        #expect(drag(from: 0, offset: 10, count: 1).target == 0)
    }

    @Test func rowsItPassesStepAsideTowardWhereItCameFrom() {
        // Row 0 dragged down two rows: rows 1 and 2 move up, row 3 stays.
        let down = drag(from: 0, offset: 56)
        #expect((0..<4).map(down.shift(of:)) == [0, -1, -1, 0])
        // Row 3 dragged up to row 1: rows 1 and 2 move down, row 0 stays.
        let up = drag(from: 3, offset: -56)
        #expect((0..<4).map(up.shift(of:)) == [0, 1, 1, 0])
        // Not far enough to pass anything: nobody moves.
        #expect((0..<4).map(drag(from: 2, offset: 5).shift(of:)) == [0, 0, 0, 0])
    }

    @Test func dropMovesOnlyTheDraggedRow() {
        let ids = ["perch", "reminders", "work", "home"]
        #expect(drag(from: 2, offset: -28).reordered(ids) == ["perch", "work", "reminders", "home"])
        #expect(drag(from: 0, offset: 84).reordered(ids) == ["reminders", "work", "home", "perch"])
        #expect(drag(from: 1, offset: 6).reordered(ids) == ids)
    }
}
