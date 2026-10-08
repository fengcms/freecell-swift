import Foundation
import CoreGraphics
import FreeCellCore
import FreeCellPresentation

func collectionTimelineAndBoundaries() throws {
    let cards = Rank.allCases.reversed().flatMap { rank in Suit.allCases.map { Card(suit: $0, rank: rank) } }
    let original = try GameState.deal(cards: cards)
    let states = Rules.safeCollectionSteps(from: original)
    try expect(states.count == 53)
    try expect(states.first == original)
    try expect(states.last == Rules.collectingSafely(original))
    try expect(states.last?.isWon == true)
    let sequence = BoardMotionSequence(states: states)
    try expect(sequence.steps.count == 52)
    try expect(sequence.duration <= 3.2)
    for (index, step) in sequence.steps.enumerated() {
        try step.after.validate()
        try expect(step.flights.count == 1)
        try expect(step.after.foundations.flatMap { $0 }.count == index + 1)
        let frame = try require(sequence.frame(at: Double(index) * sequence.stepDuration + sequence.stepDuration / 2))
        try expect(frame.state == step.after)
        try expect(abs(frame.progress - 0.5) < 0.0001)
    }
    try expect(sequence.frame(at: -1) == nil)
    try expect(sequence.frame(at: .nan) == nil)
    try expect(sequence.frame(at: sequence.duration) == nil)
    try expect(BoardMotionSequence(states: [original]).steps.isEmpty)
    try expect(BoardMotionSequence(states: []).frame(at: 0) == nil)
    try expect(original.foundations.allSatisfy(\.isEmpty))
}

func collectionFlightCoordinates() throws {
    let cards = Rank.allCases.reversed().flatMap { rank in Suit.allCases.map { Card(suit: $0, rank: rank) } }
    let sequence = BoardMotionSequence(states: Rules.safeCollectionSteps(from: try GameState.deal(cards: cards)))
    for size in [CGSize(width: 760, height: 320), CGSize(width: 2200, height: 900)] {
        let layout = BoardLayout(size: size, maximumColumnCount: sequence.maximumColumnCount)
        for step in sequence.steps {
            for flight in step.flights {
                try expect(flight.frame(progress: 0, in: layout) == flight.source.frame(in: layout))
                try expect(flight.frame(progress: 1, in: layout) == flight.destination.frame(in: layout))
                for progress in [0.0, 0.25, 0.5, 0.75, 1] {
                    let frame = flight.frame(progress: progress, in: layout)
                    try expect(frame.minX >= 0 && frame.minY >= 0)
                    try expect(frame.maxX <= size.width + 0.001 && frame.maxY <= size.height + 0.001)
                }
            }
        }
    }
}
