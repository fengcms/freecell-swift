import Foundation

public struct HistoryEntry: Equatable, Codable, Sendable {
    public let before: GameState
    public let after: GameState
    public let move: Move?
    public init(before: GameState, after: GameState, move: Move?) {
        self.before = before; self.after = after; self.move = move
    }
}

public struct GameArchive: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let seed: UInt64
    public let initial: GameState
    public var current: GameState
    public var history: [HistoryEntry]
    public var cursor: Int
    public var elapsed: TimeInterval
    public var autoCollect: Bool
    /// Stable identity for statistics. Missing in pre-statistics archives.
    public var statisticsID: UUID?
    public var statisticsExcluded: Bool
    public var statisticsLegacy: Bool

    public init(seed: UInt64) throws {
        schemaVersion = 1; algorithmVersion = Dealer.algorithmVersion; self.seed = seed
        initial = try GameState.deal(cards: Dealer.cards(seed: seed)); current = initial
        history = []; cursor = 0; elapsed = 0; autoCollect = false; statisticsID = UUID(); statisticsExcluded = false; statisticsLegacy = false
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, algorithmVersion, seed, initial, current, history, cursor, elapsed, autoCollect, statisticsID, statisticsExcluded, statisticsLegacy
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        algorithmVersion = try values.decode(Int.self, forKey: .algorithmVersion)
        seed = try values.decode(UInt64.self, forKey: .seed)
        initial = try values.decode(GameState.self, forKey: .initial)
        current = try values.decode(GameState.self, forKey: .current)
        history = try values.decode([HistoryEntry].self, forKey: .history)
        cursor = try values.decode(Int.self, forKey: .cursor)
        elapsed = try values.decode(TimeInterval.self, forKey: .elapsed)
        autoCollect = try values.decode(Bool.self, forKey: .autoCollect)
        statisticsID = try values.decodeIfPresent(UUID.self, forKey: .statisticsID)
        statisticsExcluded = try values.decodeIfPresent(Bool.self, forKey: .statisticsExcluded) ?? false
        statisticsLegacy = try values.decodeIfPresent(Bool.self, forKey: .statisticsLegacy) ?? false
    }
    public mutating func assignStatisticsIdentity(_ identity: UUID = UUID()) { statisticsID = identity }
    public mutating func startNewStatisticsIdentity() { statisticsID = UUID() }

    public mutating func commit(_ next: GameState, move: Move?) {
        guard next != current else { return }
        history = Array(history.prefix(cursor))
        history.append(HistoryEntry(before: current, after: next, move: move))
        cursor += 1; current = next
    }
    public mutating func undo() {
        guard cursor > 0 else { return }
        cursor -= 1; current = history[cursor].before
    }
    public mutating func redo() {
        guard cursor < history.count else { return }
        current = history[cursor].after; cursor += 1
    }
    public mutating func restart() {
        current = initial; history = []; cursor = 0; elapsed = 0
    }
    public func validate() throws {
        guard schemaVersion == 1, algorithmVersion == Dealer.algorithmVersion,
              cursor >= 0, cursor <= history.count, elapsed.isFinite, elapsed >= 0,
              history.count <= 20_000 else { throw GameError.invalidArchive }
        try initial.validate(); try current.validate()
        guard initial == (try GameState.deal(cards: Dealer.cards(seed: seed))) else { throw GameError.invalidArchive }
        var expected = initial
        for entry in history {
            try entry.before.validate(); try entry.after.validate()
            guard entry.before == expected else { throw GameError.invalidArchive }
            let moved: GameState
            if let move = entry.move { moved = try Rules.applying(move, to: entry.before) }
            else { moved = entry.before }
            guard entry.after == moved || entry.after == Rules.collectingSafely(moved), entry.before != entry.after else {
                throw GameError.invalidArchive
            }
            expected = entry.after
        }
        let expectedCurrent = cursor == 0 ? initial : history[cursor - 1].after
        guard current == expectedCurrent else { throw GameError.invalidArchive }
    }
}
