public enum Suit: Int, CaseIterable, Codable, Sendable {
    case clubs, diamonds, hearts, spades

    public var isRed: Bool { self == .diamonds || self == .hearts }
    public var symbol: String { ["♣", "♦", "♥", "♠"][rawValue] }
    public var name: String { ["梅花", "方块", "红桃", "黑桃"][rawValue] }
}

public enum Rank: Int, CaseIterable, Codable, Sendable {
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king
    public var label: String {
        switch self {
        case .ace: "A"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        default: String(rawValue)
        }
    }
}

public struct Card: Hashable, Codable, Sendable, Identifiable {
    public let suit: Suit
    public let rank: Rank
    public init(suit: Suit, rank: Rank) { self.suit = suit; self.rank = rank }
    public var id: Int { suit.rawValue * 13 + rank.rawValue }
    public var name: String { suit.name + rank.label }
    public static var deck: [Card] { Suit.allCases.flatMap { suit in Rank.allCases.map { Card(suit: suit, rank: $0) } } }
}

public enum Location: Hashable, Codable, Sendable {
    case tableau(Int), cell(Int), foundation(Suit)
    public var name: String {
        switch self {
        case .tableau(let index): "第\(index + 1)列"
        case .cell(let index): "第\(index + 1)空当"
        case .foundation(let suit): "\(suit.name)基础堆"
        }
    }
}

public struct Move: Hashable, Codable, Sendable {
    public let source: Location
    public let destination: Location
    public let count: Int
    public init(from source: Location, to destination: Location, count: Int = 1) {
        self.source = source; self.destination = destination; self.count = count
    }
}

public enum GameError: Error, Equatable, Sendable {
    case invalidState, invalidLocation, sameLocation, invalidCount, unavailableCard
    case unorderedSequence, occupiedCell, wrongTableauOrder, wrongFoundationOrder
    case foundationDestination, insufficientCapacity(Int), invalidArchive
    public var message: String {
        switch self {
        case .invalidState: "牌局数据不完整。"
        case .invalidLocation: "这个位置不存在。"
        case .sameLocation: "请选择另一个目标位置。"
        case .invalidCount: "这个位置只能移动一张牌。"
        case .unavailableCard: "这里没有可移动的牌。"
        case .unorderedSequence: "牌组必须按点数递减、红黑交替排列。"
        case .occupiedCell: "这个空当已有一张牌。"
        case .wrongTableauOrder: "工作列需要红黑交替，来牌比目标小一点。"
        case .wrongFoundationOrder: "基础堆需要同花色，从 A 开始依次递增。"
        case .foundationDestination: "基础堆最上方的牌只能移回工作列。"
        case .insufficientCapacity(let capacity): "空当和空列不足，此处最多移动 \(capacity) 张。"
        case .invalidArchive: "存档损坏或版本不受支持。"
        }
    }
}


public struct CardSelection: Equatable, Sendable {
    public let source: Location
    public let cards: [Card]
    public init(source: Location, cards: [Card]) { self.source = source; self.cards = cards }
}
