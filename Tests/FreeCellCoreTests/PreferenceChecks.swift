import Foundation
import FreeCellCore
import FreeCellPresentation

func preferencesDefaultsAndRoundTrip() throws {
    let defaults = GamePreferences()
    try expect(defaults.autoCollect && defaults.backgroundMusic && defaults.moveSound)
    try expect(defaults.automaticMoveGesture == .doubleClick && defaults.animationSpeed == .medium)
    try expect(!defaults.showShortcuts && defaults.language == .system)
    try expect(JSONDecoder().decode(GamePreferences.self, from: Data("{}".utf8)) == defaults)
    try expect(JSONDecoder().decode(GamePreferences.self, from: Data("{\"autoCollect\":false}".utf8)).autoCollect == false)
    var custom = defaults
    custom.autoCollect = false; custom.backgroundMusic = false; custom.moveSound = false
    custom.language = .arabic
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

func languageResolutionAndMigration() throws {
    let cases: [(String, GameLanguage)] = [
        ("en-US", .english), ("zh-CN", .simplifiedChinese), ("zh-SG", .simplifiedChinese),
        ("zh-TW", .traditionalChinese), ("zh_HK", .traditionalChinese), ("zh-MO", .traditionalChinese),
        ("zh-Hans-TW", .simplifiedChinese), ("zh-Hant-CN", .traditionalChinese),
        ("fr-CA", .french), ("de-DE", .german), ("es-MX", .spanish), ("ar-SA", .arabic),
        ("ja-JP", .japanese), ("ko-KR", .korean), ("pt-BR", .english), ("ru-RU", .english)
    ]
    for (identifier, expected) in cases {
        try expect(GameLanguage.system.resolved(preferredLanguages: [identifier, "zh-CN"]) == expected)
    }
    try expect(GameLanguage.system.resolved(preferredLanguages: []) == .english)
    try expect(GameLanguage.japanese.resolved(preferredLanguages: ["de-DE"]) == .japanese)
    try expect(GameLanguage.arabic.isRightToLeft && !GameLanguage.english.isRightToLeft)
    let future = try JSONDecoder().decode(GamePreferences.self, from: Data("{\"language\":\"future-language\",\"autoCollect\":false}".utf8))
    try expect(future.language == .system && !future.autoCollect)
    for language in GameLanguage.allCases {
        var values = GamePreferences(); values.language = language
        try expect(JSONDecoder().decode(GamePreferences.self, from: JSONEncoder().encode(values)) == values)
    }
}
