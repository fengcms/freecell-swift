public enum Rules {
    public static func canStack(_ card: Card, on target: Card) -> Bool {
        card.suit.isRed != target.suit.isRed && card.rank.rawValue + 1 == target.rank.rawValue
    }

    public static func isOrdered(_ cards: [Card]) -> Bool {
        zip(cards, cards.dropFirst()).allSatisfy { canStack($1, on: $0) }
    }

    public static func capacity(from source: Int, to destination: Int, in state: GameState) -> Int {
        let freeCells = state.cells.filter { $0 == nil }.count
        let freeColumns = state.tableau.indices.filter {
            $0 != source && $0 != destination && state.tableau[$0].isEmpty
        }.count
        return (freeCells + 1) * (1 << freeColumns)
    }

    public static func validate(_ move: Move, in state: GameState) throws {
        guard move.source != move.destination else { throw GameError.sameLocation }
        guard move.count > 0 else { throw GameError.invalidCount }
        let cards: [Card]
        switch move.source {
        case .foundation(let suit):
            guard move.count == 1 else { throw GameError.invalidCount }
            guard case .tableau = move.destination else { throw GameError.foundationDestination }
            guard let card = state.foundations[suit.rawValue].last else { throw GameError.unavailableCard }
            cards = [card]
        case .cell(let index):
            guard state.cells.indices.contains(index) else { throw GameError.invalidLocation }
            guard move.count == 1 else { throw GameError.invalidCount }
            guard let card = state.cells[index] else { throw GameError.unavailableCard }
            cards = [card]
        case .tableau(let index):
            guard state.tableau.indices.contains(index) else { throw GameError.invalidLocation }
            guard state.tableau[index].count >= move.count else { throw GameError.unavailableCard }
            cards = Array(state.tableau[index].suffix(move.count))
            guard isOrdered(cards) else { throw GameError.unorderedSequence }
        }
        guard let first = cards.first else { throw GameError.unavailableCard }
        switch move.destination {
        case .cell(let index):
            guard state.cells.indices.contains(index) else { throw GameError.invalidLocation }
            guard move.count == 1 else { throw GameError.invalidCount }
            guard state.cells[index] == nil else { throw GameError.occupiedCell }
        case .foundation(let suit):
            guard move.count == 1 else { throw GameError.invalidCount }
            guard first.suit == suit, first.rank.rawValue == state.foundations[suit.rawValue].count + 1 else {
                throw GameError.wrongFoundationOrder
            }
        case .tableau(let index):
            guard state.tableau.indices.contains(index) else { throw GameError.invalidLocation }
            if let top = state.tableau[index].last, !canStack(first, on: top) { throw GameError.wrongTableauOrder }
            if case .tableau(let source) = move.source {
                let limit = capacity(from: source, to: index, in: state)
                guard move.count <= limit else { throw GameError.insufficientCapacity(limit) }
            }
        }
    }

    public static func applying(_ move: Move, to state: GameState) throws -> GameState {
        try validate(move, in: state)
        var result = state
        let cards: [Card]
        switch move.source {
        case .tableau(let index):
            cards = Array(result.tableau[index].suffix(move.count))
            result.tableau[index].removeLast(move.count)
        case .cell(let index):
            guard let card = result.cells[index] else { throw GameError.unavailableCard }
            cards = [card]; result.cells[index] = nil
        case .foundation(let suit):
            cards = [result.foundations[suit.rawValue].removeLast()]
        }
        switch move.destination {
        case .tableau(let index): result.tableau[index].append(contentsOf: cards)
        case .cell(let index): result.cells[index] = cards.first
        case .foundation(let suit): result.foundations[suit.rawValue].append(contentsOf: cards)
        }
        return result
    }

    public static func legalMoves(in state: GameState) -> [Move] {
        let destinations = state.tableau.indices.map(Location.tableau)
            + state.cells.indices.map(Location.cell) + Suit.allCases.map(Location.foundation)
        var result: [Move] = []
        for source in state.tableau.indices.map(Location.tableau) + state.cells.indices.map(Location.cell) + Suit.allCases.map(Location.foundation) {
            let count: Int
            if case .tableau(let index) = source { count = state.tableau[index].count } else { count = state.topCard(at: source) == nil ? 0 : 1 }
            guard count > 0 else { continue }
            for length in 1...count {
                for destination in destinations {
                    let move = Move(from: source, to: destination, count: length)
                    if (try? validate(move, in: state)) != nil { result.append(move) }
                }
            }
        }
        return result
    }

    /// A clicked card selects the suffix below it; only the exposed foundation card is selectable.
    public static func selection(for cardID: Int, in state: GameState) -> CardSelection? {
        for index in state.tableau.indices {
            if let offset = state.tableau[index].firstIndex(where: { $0.id == cardID }) {
                return CardSelection(source: .tableau(index), cards: Array(state.tableau[index].suffix(from: offset)))
            }
        }
        for index in state.cells.indices {
            if let card = state.cells[index], card.id == cardID { return CardSelection(source: .cell(index), cards: [card]) }
        }
        for suit in Suit.allCases {
            if let card = state.foundations[suit.rawValue].last, card.id == cardID { return CardSelection(source: .foundation(suit), cards: [card]) }
        }
        return nil
    }

    /// Double-click order: foundation, occupied columns, empty cells, then empty columns; ties go left to right.
    /// Cards already in a cell skip other cells.
    public static func automaticMove(for cardID: Int, in state: GameState) -> Move? {
        guard let selection = selection(for: cardID, in: state) else { return nil }
        let emptyCells: [Location]
        if case .cell = selection.source { emptyCells = [] }
        else { emptyCells = state.cells.indices.filter { state.cells[$0] == nil }.map(Location.cell) }
        let candidates = Suit.allCases.map(Location.foundation)
            + state.tableau.indices.filter { !state.tableau[$0].isEmpty }.map(Location.tableau)
            + emptyCells
            + state.tableau.indices.filter { state.tableau[$0].isEmpty }.map(Location.tableau)
        for destination in candidates {
            let move = Move(from: selection.source, to: destination, count: selection.cards.count)
            if (try? validate(move, in: state)) != nil { return move }
        }
        return nil
    }

    public static func safeFoundationMove(in state: GameState) -> Move? {
        for source in state.tableau.indices.map(Location.tableau) + state.cells.indices.map(Location.cell) {
            guard let card = state.topCard(at: source) else { continue }
            let move = Move(from: source, to: .foundation(card.suit))
            guard (try? validate(move, in: state)) != nil else { continue }
            let rank = card.rank.rawValue
            if rank <= 2 || Suit.allCases.filter({ $0 != card.suit }).allSatisfy({ suit in
                state.foundations[suit.rawValue].count >= rank - (suit.isRed == card.suit.isRed ? 2 : 1)
            }) { return move }
        }
        return nil
    }

    /// Includes the initial state and one snapshot per collected card, for ordered visual playback.
    public static func safeCollectionSteps(from state: GameState) -> [GameState] {
        var result = state
        var states = [state]
        while let move = safeFoundationMove(in: result), let next = try? applying(move, to: result) {
            result = next; states.append(next)
        }
        return states
    }

    public static func collectingSafely(_ state: GameState) -> GameState {
        var result = state
        while let move = safeFoundationMove(in: result), let next = try? applying(move, to: result) { result = next }
        return result
    }

    /// Local heuristic only, not a proof of solvability.
    public static func hint(in state: GameState, avoiding previous: Move? = nil) -> Move? {
        let safe = safeFoundationMove(in: state)
        let moves = legalMoves(in: state).filter { move in
            if case .cell = move.source, case .cell = move.destination { return false }
            if case .tableau(let source) = move.source, case .tableau(let target) = move.destination,
               state.tableau[target].isEmpty, move.count == state.tableau[source].count { return false }
            return true
        }
        func score(_ move: Move) -> Int {
            var value = move == previous ? -100 : 0
            if move == safe { value += 100 }
            if case .foundation = move.destination { value += 5 }
            if case .tableau = move.destination { value += 20 + move.count }
            if case .cell = move.source { value += 15 }
            if case .tableau(let source) = move.source, move.count == state.tableau[source].count { value += 30 }
            return value
        }
        return moves.enumerated().sorted {
            let left = score($0.element), right = score($1.element)
            return left == right ? $0.offset < $1.offset : left > right
        }.first?.element
    }

    /// Produces a legal single-card witness for a supermove, without changing the caller's state.
    public static func singleCardMoves(for move: Move, in initial: GameState) throws -> [Move] {
        try validate(move, in: initial)
        guard move.count > 1, case .tableau(let source) = move.source,
              case .tableau(let target) = move.destination else { return [move] }
        var state = initial
        var moves: [Move] = []
        func perform(_ action: Move) throws {
            state = try applying(action, to: state); moves.append(action)
        }
        func transfer(_ count: Int, from source: Int, to target: Int, using columns: [Int]) throws {
            if count == 1 { try perform(Move(from: .tableau(source), to: .tableau(target))); return }
            let cells = state.cells.indices.filter { state.cells[$0] == nil }
            if count <= cells.count + 1 {
                let used = Array(cells.prefix(count - 1))
                for cell in used { try perform(Move(from: .tableau(source), to: .cell(cell))) }
                try perform(Move(from: .tableau(source), to: .tableau(target)))
                for cell in used.reversed() { try perform(Move(from: .cell(cell), to: .tableau(target))) }
            } else {
                guard let temporary = columns.first else { throw GameError.insufficientCapacity(cells.count + 1) }
                let remaining = Array(columns.dropFirst())
                let halfCapacity = (cells.count + 1) * (1 << remaining.count)
                let tail = min(halfCapacity, count - 1)
                try transfer(tail, from: source, to: temporary, using: remaining)
                try transfer(count - tail, from: source, to: target, using: remaining)
                try transfer(tail, from: temporary, to: target, using: remaining)
            }
        }
        let columns = state.tableau.indices.filter { $0 != source && $0 != target && state.tableau[$0].isEmpty }
        try transfer(move.count, from: source, to: target, using: columns)
        return moves
    }
}
