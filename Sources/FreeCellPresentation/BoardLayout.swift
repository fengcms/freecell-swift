import Foundation
import CoreGraphics
import FreeCellCore

/// Shared drawing and hit-testing geometry. Both axes constrain card size; nothing needs to scroll.
public struct BoardLayout: Sendable {
    public let size: CGSize
    public let cardSize: CGSize
    public let spacing: CGFloat
    public let padding: CGFloat
    public let slotY: CGFloat
    public let columnY: CGFloat
    private let columnCounts: [Int]
    private let firstX: CGFloat
    private let gap: CGFloat

    public init(size: CGSize, maximumColumnCount: Int) {
        self.init(size: size, columnCounts: Array(repeating: maximumColumnCount, count: 8))
    }
    public init(size: CGSize, columnCounts: [Int]) {
        self.size = size
        self.columnCounts = columnCounts
        padding = min(28, max(0, min(size.width, size.height) * 0.04))
        let ratio: CGFloat = 384 / 264
        // Reserve room for thirteen cards before compressing overlap; card size depends only on the window.
        let rows = 13
        let horizontal = max(0, size.width - 2 * padding) / (8 + 7 * 0.14)
        let vertical = max(0, size.height - 2 * padding) / (2 * ratio + 0.30 + CGFloat(rows - 1) * 0.30)
        let width = min(horizontal, vertical)
        cardSize = CGSize(width: width, height: width * ratio)
        spacing = min(width * 0.30, max(0, size.height - 2 * padding - 2 * width * ratio - width * 0.30) / CGFloat(max(1, (columnCounts.max() ?? 1) - 1)))
        gap = width * 0.14
        firstX = (size.width - (8 * width + 7 * gap)) / 2
        slotY = padding
        columnY = slotY + cardSize.height + width * 0.30
    }
    public var cornerRadius: CGFloat { cardSize.width * 16 / 264 }
    public func spacing(for column: Int) -> CGFloat {
        let count = columnCounts.indices.contains(column) ? columnCounts[column] : 1
        let available = max(0, size.height - padding - columnY - cardSize.height)
        return min(cardSize.width * 0.30, available / CGFloat(max(1, count - 1)))
    }
    public func slotFrame(_ index: Int) -> CGRect {
        CGRect(x: firstX + CGFloat(index) * (cardSize.width + gap), y: slotY, width: cardSize.width, height: cardSize.height)
    }
    public func cardFrame(column: Int, offset: Int) -> CGRect {
        CGRect(x: slotFrame(column).minX, y: columnY + CGFloat(offset) * spacing(for: column),
               width: cardSize.width, height: cardSize.height)
    }
    public func columnFrame(_ index: Int, cardCount: Int) -> CGRect {
        CGRect(x: slotFrame(index).minX, y: columnY, width: cardSize.width,
               height: cardSize.height + CGFloat(max(0, cardCount - 1)) * spacing(for: index))
    }
    public func dropTarget(at point: CGPoint) -> Location? {
        for index in 0..<8 where slotFrame(index).contains(point) {
            return index < 4 ? .cell(index) : .foundation(Suit.allCases[index - 4])
        }
        for index in 0..<8 {
            let frame = CGRect(x: slotFrame(index).minX - gap / 2, y: columnY, width: cardSize.width + gap,
                               height: max(0, size.height - padding - columnY))
            if frame.contains(point) { return .tableau(index) }
        }
        return nil
    }
    public func clampedDragOrigin(_ proposed: CGPoint, cardCount: Int, overlap: CGFloat? = nil) -> CGPoint {
        let height = cardSize.height + CGFloat(max(0, cardCount - 1)) * (overlap ?? spacing)
        return CGPoint(x: min(max(0, proposed.x), max(0, size.width - cardSize.width)),
                       y: min(max(0, proposed.y), max(0, size.height - height)))
    }
}
