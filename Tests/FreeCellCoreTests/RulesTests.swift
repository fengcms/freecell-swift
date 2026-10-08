import Foundation
import FreeCellCore
import FreeCellPresentation
import CoreGraphics

private func card(_ suit: Suit, _ value: Int) throws -> Card {
    try require(Rank(rawValue: value)).mapCard(suit)
}
private extension Rank { func mapCard(_ suit: Suit) -> Card { Card(suit: suit, rank: self) } }

/// Fill unused cards into a designated blocker column, preserving a complete real deck.
private func fixture(columns: [[Card]], cells: [Card?] = Array(repeating: nil, count: 4),
                     foundations: [[Card]] = Array(repeating: [], count: 4), filler: Int = 7) throws -> GameState {
    var columns = columns
    let used = Set(columns.flatMap { $0 } + cells.compactMap { $0 } + foundations.flatMap { $0 })
    columns[filler] += Card.deck.filter { !used.contains($0) }
    return try GameState(tableau: columns, cells: cells, foundations: foundations)
}

func dealAndDeterminism() throws {
    let cards = Dealer.cards(seed: 20261007)
    try expect(cards == Dealer.cards(seed: 20261007))
    try expect(cards != Dealer.cards(seed: 20261008))
    let state = try GameState.deal(cards: cards)
    try expect(state.tableau.map(\.count) == [7, 7, 7, 7, 6, 6, 6, 6])
    try expect(state.cells.allSatisfy { $0 == nil })
    try expect(state.foundations.allSatisfy(\.isEmpty))
    try expect(state.tableau[0][0] == cards[0])
    try expect(state.tableau[0][1] == cards[8])
    try state.validate()
    try expectThrows(GameError.invalidState) { try GameState.deal(cards: Array(cards.dropLast())) }
    try expectThrows(GameError.invalidState) { try GameState.deal(cards: Array(repeating: cards[0], count: 52)) }
}

func shuffleVersionGoldenSequence() throws {
    // Golden result independently calculated with the documented version-1 algorithm.
    try expect(Dealer.algorithmVersion == 1)
    try expect(Dealer.cards(seed: 0).map(\.id) == [47, 37, 9, 41, 15, 25, 45, 10, 16, 1, 11, 7, 35, 8, 51, 39, 31, 2, 29, 5, 27, 6, 43, 23, 18, 34, 21, 14, 38, 49, 12, 24, 42, 17, 28, 22, 3, 26, 40, 46, 48, 20, 50, 32, 52, 4, 33, 44, 19, 30, 13, 36])
}

func tableauAndCellMoves() throws {
    let redSeven = try card(.hearts, 7), blackEight = try card(.clubs, 8)
    let state = try fixture(columns: [[redSeven], [blackEight], [], [], [], [], [], []])
    let move = Move(from: .tableau(0), to: .tableau(1))
    let next = try Rules.applying(move, to: state)
    try expect(next.tableau[1] == [blackEight, redSeven])
    try expect(next.tableau[0].isEmpty)
    try next.validate()
    let parked = try Rules.applying(Move(from: .tableau(1), to: .cell(0)), to: next)
    try expect(parked.cells[0] == redSeven)
    try expectThrows(GameError.occupiedCell) { try Rules.applying(Move(from: .tableau(1), to: .cell(0)), to: parked) }
    let restored = try Rules.applying(Move(from: .cell(0), to: .tableau(1)), to: parked)
    try expect(restored == next)
    try expectThrows(GameError.sameLocation) { try Rules.validate(Move(from: .cell(0), to: .cell(0)), in: parked) }
    try expectThrows(GameError.invalidLocation) { try Rules.validate(Move(from: .tableau(-1), to: .cell(0)), in: state) }
    try expectThrows(GameError.unavailableCard) { try Rules.validate(Move(from: .cell(0), to: .tableau(0)), in: state) }
    try expect(state.tableau[0] == [redSeven])
}

func rejectWrongTableauTarget(_ suit: Suit, _ rank: Int) throws {
    let incoming = try card(.diamonds, 7), target = try card(suit, rank)
    let state = try fixture(columns: [[incoming], [target], [], [], [], [], [], []])
    if suit == .clubs && rank == 8 { try Rules.validate(Move(from: .tableau(0), to: .tableau(1)), in: state) }
    else { try expectThrows(GameError.wrongTableauOrder) { try Rules.validate(Move(from: .tableau(0), to: .tableau(1)), in: state) } }
}

func aceKingDoesNotWrap() throws {
    try expect(!Rules.canStack(try card(.hearts, 13), on: card(.clubs, 1)))
    try expect(!Rules.canStack(try card(.hearts, 1), on: card(.clubs, 13)))
}

func foundationOrderAndLocking() throws {
    let ace = try card(.hearts, 1), two = try card(.hearts, 2), three = try card(.hearts, 3)
    var state = try fixture(columns: [[three, two, ace], [], [], [], [], [], [], []])
    try expectThrows(GameError.wrongFoundationOrder) { try Rules.validate(Move(from: .tableau(0), to: .foundation(.clubs)), in: state) }
    for expected in 1...3 {
        state = try Rules.applying(Move(from: .tableau(0), to: .foundation(.hearts)), to: state)
        try expect(state.foundations[Suit.hearts.rawValue].count == expected)
        try state.validate()
    }
    try expectThrows(GameError.foundationDestination) { try Rules.validate(Move(from: .foundation(.hearts), to: .cell(0)), in: state) }
    try expectThrows(GameError.wrongFoundationOrder) { try Rules.validate(Move(from: .tableau(7), to: .foundation(.hearts)), in: state) }
}

func capacityAndSingleCardWitness(_ freeCells: Int) throws {
    let sequence = try [card(.clubs, 8), card(.hearts, 7), card(.spades, 6), card(.diamonds, 5), card(.clubs, 4), card(.hearts, 3)]
    let target = try card(.diamonds, 9)
    let blockerCards = try [card(.clubs, 13), card(.diamonds, 13), card(.hearts, 13), card(.spades, 13)]
    var cells: [Card?] = Array(repeating: nil, count: 4)
    for index in 0..<(4 - freeCells) { cells[index] = blockerCards[index] }
    let state = try fixture(columns: [sequence, [target], [], [try card(.clubs, 10)], [try card(.diamonds, 10)], [try card(.hearts, 10)], [try card(.spades, 10)], []], cells: cells)
    try expect(Rules.capacity(from: 0, to: 1, in: state) == (freeCells + 1) * 2)
    try expect(Rules.capacity(from: 0, to: 2, in: state) == freeCells + 1)
    for length in 1...sequence.count {
        // Target chosen for the head of each suffix.
        let destination = 2
        let move = Move(from: .tableau(0), to: .tableau(destination), count: length)
        if length <= freeCells + 1 {
            let result = try Rules.applying(move, to: state)
            var witnessState = state
            for single in try Rules.singleCardMoves(for: move, in: state) {
                try expect(single.count == 1)
                witnessState = try Rules.applying(single, to: witnessState)
                try witnessState.validate()
            }
            try expect(witnessState == result)
        } else {
            try expectThrows(GameError.insufficientCapacity(freeCells + 1)) { try Rules.validate(move, in: state) }
        }
    }
    let full = Move(from: .tableau(0), to: .tableau(1), count: sequence.count)
    if sequence.count <= (freeCells + 1) * 2 {
        let result = try Rules.applying(full, to: state)
        var witnessState = state
        for single in try Rules.singleCardMoves(for: full, in: state) { witnessState = try Rules.applying(single, to: witnessState) }
        try expect(result == witnessState)
    } else {
        try expectThrows(GameError.insufficientCapacity((freeCells + 1) * 2)) { try Rules.validate(full, in: state) }
    }
}

func noSpaceAndUnorderedGroups() throws {
    let sequence = try [card(.clubs, 8), card(.hearts, 7)]
    let cells: [Card?] = try [card(.clubs, 13), card(.diamonds, 13), card(.hearts, 13), card(.spades, 13)]
    let columns = try [sequence, [card(.diamonds, 9)], [card(.clubs, 10)], [card(.diamonds, 10)], [card(.hearts, 10)], [card(.spades, 10)], [card(.clubs, 11)], []]
    let state = try fixture(columns: columns, cells: cells)
    try expect(Rules.capacity(from: 0, to: 1, in: state) == 1)
    try expectThrows(GameError.insufficientCapacity(1)) { try Rules.validate(Move(from: .tableau(0), to: .tableau(1), count: 2), in: state) }
    let unordered = try fixture(columns: [[card(.clubs, 8), card(.spades, 7)], [], [], [], [], [], [], []])
    try expectThrows(GameError.unorderedSequence) { try Rules.validate(Move(from: .tableau(0), to: .tableau(1), count: 2), in: unordered) }
    try expectThrows(GameError.invalidCount) { try Rules.validate(Move(from: .tableau(0), to: .cell(0), count: 2), in: state) }
}

func safeCollectionConservativeCondition() throws {
    let heartThree = try card(.hearts, 3)
    let foundations = [try [card(.clubs, 1), card(.clubs, 2)], try [card(.diamonds, 1)], try [card(.hearts, 1), card(.hearts, 2)], try [card(.spades, 1), card(.spades, 2)]]
    let safe = try fixture(columns: [[heartThree], [], [], [], [], [], [], []], foundations: foundations)
    try expect(Rules.safeFoundationMove(in: safe) == Move(from: .tableau(0), to: .foundation(.hearts)))
    var insufficient = foundations; insufficient[0] = Array(insufficient[0].prefix(1))
    let unsafe = try fixture(columns: [[heartThree], [], [], [], [], [], [], []], foundations: insufficient)
    // The filler column ends in a spade K, so no other exposed safe candidates exist.
    try expect(Rules.safeFoundationMove(in: unsafe) == nil)
    try Rules.collectingSafely(safe).validate()
}

func completionAndNoMoves() throws {
    let state = try GameState(tableau: Array(repeating: [], count: 8), cells: Array(repeating: nil, count: 4), foundations: Suit.allCases.map { suit in Rank.allCases.map { Card(suit: suit, rank: $0) } })
    try expect(state.isWon)
    try expect(Rules.legalMoves(in: state).allSatisfy { if case .foundation = $0.source { return true }; return false })
    try expect(Rules.legalMoves(in: state).count == 32)
    var foundations = state.foundations
    let king = foundations[0].removeLast()
    let almost = try GameState(tableau: state.tableau, cells: [king, nil, nil, nil], foundations: foundations)
    try expect(!almost.isWon)
    try expect(try Rules.applying(Move(from: .cell(0), to: .foundation(.clubs)), to: almost).isWon)
}

func randomLegalPlayMaintainsInvariants() throws {
    for seed in 0..<12 {
        var state = try GameState.deal(cards: Dealer.cards(seed: UInt64(seed)))
        for step in 0..<80 {
            let moves = Rules.legalMoves(in: state)
            guard !moves.isEmpty else { break }
            let move = moves[(step * 17 + seed * 31) % moves.count]
            let next = try Rules.applying(move, to: state)
            var witnessed = state
            for single in try Rules.singleCardMoves(for: move, in: state) { witnessed = try Rules.applying(single, to: witnessed) }
            try expect(witnessed == next)
            state = next; try state.validate()
        }
    }
}

func archiveHistoryRoundTripAndBranch() throws {
    var archive = try GameArchive(seed: 21)
    let original = archive.current
    let first = try require(Rules.legalMoves(in: original).first)
    let moved = try Rules.applying(first, to: original)
    let collected = Rules.collectingSafely(moved)
    archive.commit(collected, move: first)
    archive.elapsed = 30
    try archive.validate()
    archive.undo(); try expect(archive.current == original); try expect(archive.elapsed == 30)
    archive.redo(); try expect(archive.current == collected)
    let decoded = try JSONDecoder().decode(GameArchive.self, from: JSONEncoder().encode(archive))
    try decoded.validate()
    try expect(decoded.current == collected)
    archive.undo()
    let alternative = try require(Rules.legalMoves(in: original).last)
    archive.commit(try Rules.applying(alternative, to: original), move: alternative)
    try expect(archive.history.count == 1); try expect(archive.cursor == 1)
    try archive.validate()
    archive.restart(); try expect(archive.current == original); try expect(archive.elapsed == 0)
    try expect(archive.history.isEmpty)
}

func rejectCorruptArchive() throws {
    let archive = try GameArchive(seed: 0)
    var object = try require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
    object["schemaVersion"] = 999
    let decoded = try JSONDecoder().decode(GameArchive.self, from: JSONSerialization.data(withJSONObject: object))
    try expectThrows(GameError.invalidArchive) { try decoded.validate() }
    var invalid = archive; invalid.cursor = -1
    try expectThrows(GameError.invalidArchive) { try invalid.validate() }
    invalid = archive; invalid.elapsed = -.infinity
    try expectThrows(GameError.invalidArchive) { try invalid.validate() }
    invalid = archive
    try expectThrows(GameError.invalidState) { try JSONDecoder().decode(GameState.self, from: Data("{\"tableau\":[],\"cells\":[],\"foundations\":[]}".utf8)) }
    try expectAnyError { try JSONDecoder().decode(GameArchive.self, from: Data("broken".utf8)) }
}


func completeFullGameFromDeal() throws {
    // Reverse rank order exposes A, then 2, etc. across alternating sets of four columns.
    let cards = Rank.allCases.reversed().flatMap { rank in Suit.allCases.map { Card(suit: $0, rank: rank) } }
    var state = try GameState.deal(cards: cards)
    var steps = 0
    while let move = Rules.safeFoundationMove(in: state) {
        state = try Rules.applying(move, to: state)
        steps += 1
        try state.validate()
    }
    try expect(steps == 52)
    try expect(state.isWon)
    try expect(state.tableau.allSatisfy(\.isEmpty))
}

func archiveManualCollectAndHistoryCorruption() throws {
    var archive = try GameArchive(seed: 0)
    // Find an exposed ace or two using legal cell moves, then commit a manual collection.
    for _ in 0..<8 {
        if Rules.safeFoundationMove(in: archive.current) != nil { break }
        guard let index = archive.current.cells.firstIndex(where: { $0 == nil }),
              let source = archive.current.tableau.indices.first(where: { !archive.current.tableau[$0].isEmpty }) else { break }
        let move = Move(from: .tableau(source), to: .cell(index))
        archive.commit(try Rules.applying(move, to: archive.current), move: move)
    }
    let before = archive.current
    let next = Rules.collectingSafely(before)
    if next != before {
        archive.commit(next, move: nil)
        try archive.validate()
        archive.undo(); try expect(archive.current == before)
        archive.redo(); try expect(archive.current == next)
    }
    let validMove = try require(Rules.legalMoves(in: archive.current).first)
    let after = try Rules.applying(validMove, to: archive.current)
    archive.commit(after, move: validMove)
    // A structurally valid but unrelated state cannot be substituted for a historical transition.
    archive.history[archive.history.count - 1] = HistoryEntry(before: before, after: archive.initial, move: validMove)
    try expectAnyError { try archive.validate() }
}


func multipleEmptyColumnsWitness() throws {
    let sequence = try (1...12).reversed().map { try card($0.isMultiple(of: 2) ? .clubs : .hearts, $0) }
    for freeCells in 0...4 {
        for emptyColumns in 0...3 {
            for emptyTarget in [false, true] {
                var columns = Array(repeating: [Card](), count: 8)
                columns[0] = sequence
                if !emptyTarget { columns[1] = [try card(.hearts, 13)] }
                var unused = Card.deck.filter { !columns.flatMap({ $0 }).contains($0) }
                var cells: [Card?] = Array(repeating: nil, count: 4)
                for index in 0..<(4 - freeCells) { cells[index] = unused.removeLast() }
                for index in (2 + emptyColumns)..<8 { columns[index] = [unused.removeLast()] }
                let state = try fixture(columns: columns, cells: cells)
                let capacity = (freeCells + 1) * (1 << emptyColumns)
                try expect(Rules.capacity(from: 0, to: 1, in: state) == capacity)
                let lengths = emptyTarget ? Array(1...12) : [12]
                for length in lengths {
                    let move = Move(from: .tableau(0), to: .tableau(1), count: length)
                    if length > capacity {
                        try expectThrows(GameError.insufficientCapacity(capacity)) { try Rules.validate(move, in: state) }
                    } else {
                        var witnessed = state
                        for single in try Rules.singleCardMoves(for: move, in: state) {
                            witnessed = try Rules.applying(single, to: witnessed)
                            try witnessed.validate()
                        }
                        try expect(witnessed == Rules.applying(move, to: state))
                    }
                }
            }
        }
    }
}

func foundationReturnAndRoundTrip() throws {
    let three = try card(.hearts, 3), blackFour = try card(.clubs, 4)
    let foundations = [[], [], try [card(.hearts, 1), card(.hearts, 2), three], []]
    let state = try fixture(columns: [[], [blackFour], [], [], [], [], [], []], foundations: foundations)
    let move = Move(from: .foundation(.hearts), to: .tableau(1))
    let returned = try Rules.applying(move, to: state)
    try expect(returned.tableau[1] == [blackFour, three])
    try expect(returned.foundations[2].count == 2)
    try returned.validate()
    try expect(Rules.selection(for: three.id, in: state)?.source == .foundation(.hearts))
    try expect(Rules.selection(for: card(.hearts, 1).id, in: state) == nil)
    try expect(Rules.selection(for: card(.hearts, 2).id, in: returned)?.source == .foundation(.hearts))
    let restored = try Rules.applying(Move(from: .tableau(1), to: .foundation(.hearts)), to: returned)
    try expect(restored == state)
    try expect(try Rules.applying(Move(from: .foundation(.hearts), to: .tableau(0)), to: state).tableau[0] == [three])
    try expectThrows(GameError.wrongTableauOrder) { try Rules.validate(Move(from: .foundation(.hearts), to: .tableau(7)), in: state) }
    try expectThrows(GameError.invalidCount) { try Rules.validate(Move(from: .foundation(.hearts), to: .tableau(0), count: 2), in: state) }
    try expectThrows(GameError.foundationDestination) { try Rules.validate(Move(from: .foundation(.hearts), to: .cell(0)), in: state) }
    try expect(Rules.legalMoves(in: state).contains(move))
}

func doubleClickPriority() throws {
    let seven = try card(.hearts, 7), eight = try card(.clubs, 8), otherEight = try card(.spades, 8)
    var foundations = Array(repeating: [Card](), count: 4)
    foundations[2] = try (1...6).map { try card(.hearts, $0) }
    let collectable = try fixture(columns: [[seven], [eight], [otherEight], [], [], [], [], []], foundations: foundations)
    try expect(Rules.automaticMove(for: seven.id, in: collectable) == Move(from: .tableau(0), to: .foundation(.hearts)))
    let stackable = try fixture(columns: [[seven], [eight], [otherEight], [], [], [], [], []])
    try expect(Rules.automaticMove(for: seven.id, in: stackable) == Move(from: .tableau(0), to: .tableau(1)))
    let parkable = try fixture(columns: [[seven], [], [], [], [], [], [], []])
    try expect(Rules.automaticMove(for: seven.id, in: parkable) == Move(from: .tableau(0), to: .cell(0)))
    let fullCells: [Card?] = try [card(.clubs, 13), card(.hearts, 13), card(.diamonds, 13), card(.spades, 13)]
    let emptyColumn = try fixture(columns: [[seven], [card(.hearts, 8)], [], [], [], [], [], []], cells: fullCells)
    try expect(Rules.automaticMove(for: seven.id, in: emptyColumn) == Move(from: .tableau(0), to: .tableau(2)))
}

func doubleClickGroupsAndNoTarget() throws {
    let group = try [card(.clubs, 8), card(.hearts, 7), card(.spades, 6)]
    let state = try fixture(columns: [group, [card(.diamonds, 9)], [], [], [], [], [], []])
    let move = try require(Rules.automaticMove(for: group[0].id, in: state))
    try expect(move.count == 3)
    try expect(move.destination == .tableau(1))
    try expect(Rules.selection(for: group[0].id, in: state)?.cards == group)
    let seven = try card(.hearts, 7)
    let cells: [Card?] = try [card(.clubs, 13), card(.hearts, 13), card(.diamonds, 13), card(.spades, 13)]
    let blocked = try fixture(columns: [[seven], [card(.hearts, 8)], [card(.hearts, 9)], [card(.hearts, 10)], [card(.hearts, 11)], [card(.hearts, 12)], [card(.hearts, 6)], []], cells: cells)
    try expect(Rules.automaticMove(for: seven.id, in: blocked) == nil)
    let unordered = try fixture(columns: [[card(.clubs, 8), card(.clubs, 7)], [], [], [], [], [], [], []])
    try expect(Rules.automaticMove(for: card(.clubs, 8).id, in: unordered) == nil)
}

func returnedFoundationHistoryPersists() throws {
    var candidate: (GameArchive, Move, Move)?
    for seed in 0..<1000 {
        let archive = try GameArchive(seed: UInt64(seed))
        for source in archive.current.tableau.indices {
            guard let ace = archive.current.tableau[source].last, ace.rank == .ace else { continue }
            let collect = Move(from: .tableau(source), to: .foundation(ace.suit))
            let collected = try Rules.applying(collect, to: archive.current)
            if let returning = Rules.legalMoves(in: collected).first(where: { $0.source == .foundation(ace.suit) }) {
                candidate = (archive, collect, returning); break
            }
        }
        if candidate != nil { break }
    }
    let found = try require(candidate)
    var archive = found.0
    archive.commit(try Rules.applying(found.1, to: archive.current), move: found.1)
    let before = archive.current
    let after = try Rules.applying(found.2, to: before)
    archive.commit(after, move: found.2)
    try archive.validate()
    archive.undo(); try expect(archive.current == before)
    archive.redo(); try expect(archive.current == after)
    let restored = try JSONDecoder().decode(GameArchive.self, from: JSONEncoder().encode(archive))
    try restored.validate(); try expect(restored.current == after)
}

func storedCardDoubleClickSkipsCells() throws {
    let king = Card(suit: .hearts, rank: .king)
    let open = try fixture(columns: Array(repeating: [], count: 8), cells: [king, nil, nil, nil])
    try expect(Rules.automaticMove(for: king.id, in: open) == Move(from: .cell(0), to: .tableau(0)))
    let blockers = Card.deck.filter { $0 != king }.prefix(7).map { [$0] } + [[]]
    let blocked = try fixture(columns: blockers, cells: [king, nil, nil, nil])
    try expect(Rules.automaticMove(for: king.id, in: blocked) == nil)
    let ace = Card(suit: .clubs, rank: .ace)
    let collectable = try fixture(columns: Array(repeating: [], count: 8), cells: [ace, nil, nil, nil])
    try expect(Rules.automaticMove(for: ace.id, in: collectable) == Move(from: .cell(0), to: .foundation(.clubs)))
    let seven = try card(.hearts, 7)
    let stackable = try fixture(columns: [[card(.clubs, 8)], [], [], [], [], [], [], []], cells: [seven, nil, nil, nil])
    try expect(Rules.automaticMove(for: seven.id, in: stackable) == Move(from: .cell(0), to: .tableau(0)))
}


func groupAnimationPreservesDragon() throws {
    let group = try [card(.hearts, 12), card(.clubs, 11), card(.hearts, 10)]
    let before = try fixture(columns: [group, [card(.clubs, 13)], [], [], [], [], [], []])
    let after = try Rules.applying(Move(from: .tableau(0), to: .tableau(1), count: 3), to: before)
    let motion = BoardMotionSequence(states: [before, after])
    try expect(motion.steps.count == 1)
    try expect(motion.steps[0].flights.map(\.card) == group)
    let layout = BoardLayout(size: CGSize(width: 1000, height: 600), maximumColumnCount: motion.maximumColumnCount)
    for progress in [0.0, 0.25, 0.5, 0.75, 1] {
        let frames = motion.steps[0].flights.map { $0.frame(progress: progress, in: layout) }
        for index in 1..<frames.count {
            try expect(abs(frames[index].minY - frames[index - 1].minY - layout.spacing) < 0.0001)
            try expect(frames[index].minX == frames[0].minX)
        }
    }
    try before.validate(); try after.validate()
}
