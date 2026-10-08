import Foundation
import CoreGraphics
import FreeCellCore
import FreeCellPresentation

func boardFitsEveryWindow() throws {
    for size in [CGSize(width: 760, height: 320), CGSize(width: 1120, height: 570), CGSize(width: 1800, height: 900),
                 CGSize(width: 760, height: 1400), CGSize(width: 2200, height: 340)] {
        for count in [1, 7, 13, 26, 52] {
            let layout = BoardLayout(size: size, maximumColumnCount: count)
            try expect(layout.cardSize.width > 0)
            try expect(abs(layout.cardSize.height / layout.cardSize.width - 384.0 / 264.0) < 0.0001)
            for index in 0..<8 {
                for frame in [layout.slotFrame(index), layout.columnFrame(index, cardCount: count)] {
                    try expect(frame.minX >= 0 && frame.minY >= 0)
                    try expect(frame.maxX <= size.width + 0.001 && frame.maxY <= size.height + 0.001)
                }
            }
        }
    }
    let small = BoardLayout(size: CGSize(width: 760, height: 320), maximumColumnCount: 7)
    let large = BoardLayout(size: CGSize(width: 1500, height: 1000), maximumColumnCount: 7)
    try expect(large.cardSize.width > small.cardSize.width)
}

func boardHitTestingAndDragBounds() throws {
    let size = CGSize(width: 1000, height: 600)
    let layout = BoardLayout(size: size, maximumColumnCount: 13)
    for index in 0..<8 {
        let frame = layout.slotFrame(index)
        let target: Location = index < 4 ? .cell(index) : .foundation(Suit.allCases[index - 4])
        try expect(layout.dropTarget(at: CGPoint(x: frame.midX, y: frame.midY)) == target)
        let column = layout.columnFrame(index, cardCount: 13)
        try expect(layout.dropTarget(at: CGPoint(x: column.midX, y: column.maxY - 1)) == .tableau(index))
    }
    try expect(layout.dropTarget(at: CGPoint(x: -10, y: -10)) == nil)
    for count in [1, 7, 13] {
        for point in [CGPoint(x: -100, y: -100), CGPoint(x: 5000, y: 5000)] {
            let origin = layout.clampedDragOrigin(point, cardCount: count)
            try expect(origin.x >= 0 && origin.y >= 0)
            try expect(origin.x + layout.cardSize.width <= size.width)
            try expect(origin.y + layout.cardSize.height + CGFloat(count - 1) * layout.spacing <= size.height + 0.001)
        }
    }
}

func cardSizeStableAndColumnsCompressIndependently() throws {
    for size in [CGSize(width: 760, height: 320), CGSize(width: 1120, height: 570), CGSize(width: 1800, height: 900)] {
        let initial = BoardLayout(size: size, columnCounts: [7, 6, 7, 6, 7, 6, 7, 6])
        for count in [1, 13, 26, 52] {
            let longer = BoardLayout(size: size, columnCounts: [count, 6, 7, 6, 7, 6, 7, 6])
            try expect(initial.cardSize == longer.cardSize)
            try expect(initial.columnY == longer.columnY)
            try expect(initial.cardFrame(column: 1, offset: 5) == longer.cardFrame(column: 1, offset: 5))
            try expect(longer.columnFrame(0, cardCount: count).maxY <= size.height - longer.padding + 0.001)
            try expect(longer.spacing(for: 0) <= longer.cardSize.width * 0.30)
        }
        let reserve = size.height - initial.padding - initial.columnFrame(0, cardCount: 7).maxY
        try expect(reserve >= initial.cardSize.width * 0.30 * 6 - 0.001)
        try expect(abs(initial.cornerRadius / initial.cardSize.width - 6.87 / 167.0869141) < 0.0001)
    }
}
