import Foundation

public struct GameState: Equatable, Codable, Sendable {
    public internal(set) var tableau: [[Card]]
    public internal(set) var cells: [Card?]
    public internal(set) var foundations: [[Card]]

    public init(tableau: [[Card]], cells: [Card?], foundations: [[Card]]) throws {
        self.tableau = tableau; self.cells = cells; self.foundations = foundations
        try validate()
    }

    private enum CodingKeys: String, CodingKey { case tableau, cells, foundations }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tableau = try container.decode([[Card]].self, forKey: .tableau)
        cells = try container.decode([Card?].self, forKey: .cells)
        foundations = try container.decode([[Card]].self, forKey: .foundations)
        try validate()
    }

    public static func deal(cards: [Card]) throws -> GameState {
        guard cards.count == 52, Set(cards) == Set(Card.deck) else { throw GameError.invalidState }
        var columns = Array(repeating: [Card](), count: 8)
        for (index, card) in cards.enumerated() { columns[index % 8].append(card) }
        return try GameState(tableau: columns, cells: Array(repeating: nil, count: 4), foundations: Array(repeating: [], count: 4))
    }

    public func validate() throws {
        guard tableau.count == 8, cells.count == 4, foundations.count == 4 else { throw GameError.invalidState }
        let cards = tableau.flatMap { $0 } + cells.compactMap { $0 } + foundations.flatMap { $0 }
        guard cards.count == 52, Set(cards) == Set(Card.deck) else { throw GameError.invalidState }
        for suit in Suit.allCases {
            for (index, card) in foundations[suit.rawValue].enumerated() {
                guard card.suit == suit, card.rank.rawValue == index + 1 else { throw GameError.invalidState }
            }
        }
    }

    public var isWon: Bool { foundations.reduce(0) { $0 + $1.count } == 52 }
    public func topCard(at location: Location) -> Card? {
        switch location {
        case .tableau(let index): tableau.indices.contains(index) ? tableau[index].last : nil
        case .cell(let index): cells.indices.contains(index) ? cells[index] : nil
        case .foundation(let suit): foundations[suit.rawValue].last
        }
    }
}

/// Stable SplitMix64 + unbiased Fisher–Yates. Version 1; not Microsoft deal numbers.
public enum Dealer {
    public static let algorithmVersion = 1
    public static func cards(seed: UInt64) -> [Card] {
        var generator = SplitMix64(state: seed)
        var deck = Card.deck
        for index in stride(from: deck.count - 1, through: 1, by: -1) {
            deck.swapAt(index, generator.bounded(UInt64(index + 1)))
        }
        return deck
    }
}

private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
    mutating func bounded(_ upperBound: UInt64) -> Int {
        let threshold = (0 &- upperBound) % upperBound
        var value = next()
        while value < threshold { value = next() }
        return Int(value % upperBound)
    }
}
