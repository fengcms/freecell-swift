import Foundation
import FreeCellCore

/// Real seeded deal with recorded legal history, for independent native UI smoke checks.
func writeInteractionFixture(to url: URL) throws {
    for seed in 0..<10_000 {
        let initial = try GameArchive(seed: UInt64(seed))
        for index in initial.current.tableau.indices {
            guard let ace = initial.current.tableau[index].last, ace.rank == .ace else { continue }
            let collect = Move(from: .tableau(index), to: .foundation(ace.suit))
            let collected = try Rules.applying(collect, to: initial.current)
            let moves = Rules.legalMoves(in: collected)
            guard let returning = moves.first(where: { $0.source == .foundation(ace.suit) }),
                  let group = moves.first(where: { $0.count == 2 }) else { continue }
            var archive = initial
            archive.commit(collected, move: collect)
            try archive.validate()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            if case .tableau(let source) = group.source {
                let cards = Array(collected.tableau[source].suffix(2))
                print("Fixture seed=\(seed), group=\(cards.map(\.name)) \(group.source.name)→\(group.destination.name), foundation=\(ace.name)→\(returning.destination.name)")
            }
            return
        }
    }
    throw CheckFailure(description: "No interaction fixture found")
}

func writePreWinFixture(from source: URL, to destination: URL) throws {
    let saved = try JSONDecoder().decode(GameArchive.self, from: Data(contentsOf: source))
    try saved.validate()
    let index = try require(saved.history.lastIndex(where: { $0.after.isWon }))
    let entry = saved.history[index]
    var fixture = saved
    fixture.history = Array(saved.history.prefix(index))
    fixture.cursor = index; fixture.current = entry.before
    if let move = entry.move {
        fixture.commit(try Rules.applying(move, to: fixture.current), move: move)
    }
    fixture.autoCollect = false
    try expect(Rules.collectingSafely(fixture.current).isWon)
    try fixture.validate()
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(fixture).write(to: destination, options: .atomic)
    print("Created valid pre-win fixture: \(fixture.current.foundations.flatMap { $0 }.count)/52 collected")
}
