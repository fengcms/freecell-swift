import Foundation
import CoreGraphics
import FreeCellCore

public struct BoardAnimationRequest: Sendable {
    public let id: Int
    public let states: [GameState]
    public init(id: Int, states: [GameState]) { self.id = id; self.states = states }
}

public struct BoardCardPosition: Equatable, Sendable {
    public let location: Location
    public let offset: Int
    public func frame(in layout: BoardLayout) -> CGRect {
        switch location {
        case .tableau(let column): layout.cardFrame(column: column, offset: offset)
        case .cell(let index): layout.slotFrame(index)
        case .foundation(let suit): layout.slotFrame(suit.rawValue + 4)
        }
    }
}

public struct CardFlight: Sendable {
    public let card: Card
    public let source: BoardCardPosition
    public let destination: BoardCardPosition
    public func frame(progress: Double, in layout: BoardLayout) -> CGRect {
        let start = source.frame(in: layout), end = destination.frame(in: layout)
        if progress <= 0 { return start }
        if progress >= 1 { return end }
        let fraction = CGFloat(min(1, max(0, progress)))
        // Smoothstep has zero velocity at both endpoints and preserves a dragged group's spacing.
        let eased = fraction * fraction * (3 - 2 * fraction)
        return CGRect(x: start.minX + (end.minX - start.minX) * eased,
                      y: start.minY + (end.minY - start.minY) * eased,
                      width: layout.cardSize.width, height: layout.cardSize.height)
    }
}

public struct BoardMotionStep: Sendable {
    public let after: GameState
    public let flights: [CardFlight]
}

public struct BoardMotionFrame: Sendable {
    public let state: GameState
    public let flights: [CardFlight]
    public let progress: Double
}

/// Deterministic presentation only: sampling this timeline never mutates a game or its history.
public struct BoardMotionSequence: Sendable {
    public let steps: [BoardMotionStep]
    public let stepDuration: TimeInterval
    public let maximumColumnCounts: [Int]
    public let maximumColumnCount: Int
    public var duration: TimeInterval { stepDuration * Double(steps.count) }

    public init(states: [GameState]) {
        maximumColumnCounts = (0..<8).map { index in states.map { $0.tableau[index].count }.max() ?? 0 }
        maximumColumnCount = states.flatMap { $0.tableau.map(\.count) }.max() ?? 7
        func positions(in state: GameState) -> [Int: BoardCardPosition] {
            var result: [Int: BoardCardPosition] = [:]
            for index in state.tableau.indices {
                for (offset, card) in state.tableau[index].enumerated() {
                    result[card.id] = BoardCardPosition(location: .tableau(index), offset: offset)
                }
            }
            for index in state.cells.indices {
                if let card = state.cells[index] { result[card.id] = BoardCardPosition(location: .cell(index), offset: 0) }
            }
            for suit in Suit.allCases {
                for card in state.foundations[suit.rawValue] { result[card.id] = BoardCardPosition(location: .foundation(suit), offset: 0) }
            }
            return result
        }
        steps = zip(states, states.dropFirst()).compactMap { before, after in
            let starts = positions(in: before), ends = positions(in: after)
            let flights = Card.deck.compactMap { card -> CardFlight? in
                guard let source = starts[card.id], let destination = ends[card.id], source.location != destination.location else { return nil }
                return CardFlight(card: card, source: source, destination: destination)
            }.sorted {
                if $0.source.location == $1.source.location { return $0.source.offset < $1.source.offset }
                return $0.card.id < $1.card.id
            }
            return flights.isEmpty ? nil : BoardMotionStep(after: after, flights: flights)
        }
        stepDuration = max(0.06, min(0.28, 2.8 / Double(max(1, steps.count))))
    }
    public func frame(at elapsed: TimeInterval) -> BoardMotionFrame? {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return nil }
        let index = min(steps.count - 1, Int(elapsed / stepDuration))
        let step = steps[index]
        return BoardMotionFrame(state: step.after, flights: step.flights,
                                progress: (elapsed - Double(index) * stepDuration) / stepDuration)
    }
}
