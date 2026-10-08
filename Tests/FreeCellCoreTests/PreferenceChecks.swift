import Foundation
import FreeCellCore
import FreeCellPresentation

func preferencesDefaultsAndRoundTrip() throws {
    let defaults = GamePreferences()
    try expect(defaults.autoCollect && defaults.backgroundMusic && defaults.moveSound)
    try expect(defaults.automaticMoveGesture == .doubleClick && defaults.animationSpeed == .medium)
    try expect(!defaults.showShortcuts)
    try expect(JSONDecoder().decode(GamePreferences.self, from: Data("{}".utf8)) == defaults)
    try expect(JSONDecoder().decode(GamePreferences.self, from: Data("{\"autoCollect\":false}".utf8)).autoCollect == false)
    var custom = defaults
    custom.autoCollect = false; custom.backgroundMusic = false; custom.moveSound = false
    custom.automaticMoveGesture = .rightClick; custom.animationSpeed = .fast; custom.showShortcuts = true
    try expect(JSONDecoder().decode(GamePreferences.self, from: JSONEncoder().encode(custom)) == custom)
    try expect(custom.summary.contains("右击") && custom.summary.contains("音乐关") && custom.summary.contains("快捷键显"))
    try expectAnyError { try JSONDecoder().decode(GamePreferences.self, from: Data("{\"animationSpeed\":\"unknown\"}".utf8)) }
}
func animationSpeedTimelines() throws {
    let cards = Rank.allCases.reversed().flatMap { rank in Suit.allCases.map { Card(suit: $0, rank: rank) } }
    let states = Rules.safeCollectionSteps(from: try GameState.deal(cards: cards))
    let normal = BoardMotionSequence(states: states)
    for speed in AnimationSpeed.allCases {
        let sequence = BoardMotionSequence(states: states, speed: speed)
        try expect(sequence.steps.count == normal.steps.count)
        try expect(abs(sequence.duration - normal.duration * speed.durationMultiplier) < 0.0001)
        if speed == .none {
            try expect(sequence.duration == 0 && sequence.frame(at: 0) == nil)
        } else {
            let sample = try require(sequence.frame(at: sequence.stepDuration / 2))
            try expect(abs(sample.progress - 0.5) < 0.0001)
            try expect(sample.state == normal.steps[0].after)
            try expect(sequence.frame(at: sequence.duration) == nil)
        }
    }
    try expect(BoardMotionSequence(states: []).frame(at: 0) == nil)
}
