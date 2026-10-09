import Foundation

enum StatisticsOutcome: String, Codable, CaseIterable, Sendable { case inProgress, won, abandoned, recordOnly }
enum StatisticsEventKind: String, Codable, CaseIterable, Sendable { case move, collect, hint, undo, redo, restart, automaticMove, foundationTakeback, autoCollect, noAssistDisqualification, playTime }

struct StatisticsEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let gameID: UUID
    let kind: StatisticsEventKind
    let timestamp: Date
    let localDay: String
    let timeZone: String
    var seconds: TimeInterval
}

struct StatisticsAttempt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var moves: Int
    var seconds: TimeInterval
}

struct StatisticsGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let seed: String
    let algorithmVersion: Int
    var startedAt: Date
    var startedLocalDay: String
    var startedTimeZone: String
    var settledAt: Date?
    var settledLocalDay: String?
    var settledTimeZone: String?
    var outcome: StatisticsOutcome
    var moves: Int
    var seconds: TimeInterval
    var cumulativeSeconds: TimeInterval
    var hints: Int
    var undos: Int
    var redos: Int
    var restarts: Int
    var automaticMoves: Int
    var manualCollections: Int
    var foundationTakebacks: Int
    var autoCollectUsed: Bool
    var noAssistEligible: Bool
    var noAssistReason: String?
    var legacyUnknown: Bool
    var importedOnly: Bool
    var revision: Int
    var attempts: [StatisticsAttempt]
    var wonLocalDay: String?
    var wonTimeZone: String?
    var isNoAssistWin: Bool { outcome == .won && noAssistEligible && !legacyUnknown }
}

struct StatisticsDatabase: Codable, Sendable {
    var schemaVersion = 1
    var metricVersion = 1
    var sourceID = UUID()
    var periodStartedAt = Date()
    var updatedAt = Date()
    var games: [StatisticsGame] = []
    var events: [StatisticsEvent] = []
    var excludedGameIDs: [UUID] = []
    var excludedDealIdentities: [String: UUID] = [:]
}

struct StatisticsSummary {
    let started: Int; let wins: Int; let abandoned: Int; let unsettled: Int
    let winRate: Double?; let currentStreak: Int; let bestStreak: Int
    let bestMoves: StatisticsGame?; let fastest: StatisticsGame?
    let averageMoves: Double?; let averageSeconds: Double?
    let cumulativeSeconds: TimeInterval; let currentDays: Int; let bestDays: Int
    let hints: Int; let undos: Int; let redos: Int; let restarts: Int
    let noAssistWins: Int; let noAssistBestMoves: StatisticsGame?; let noAssistFastest: StatisticsGame?
}

extension StatisticsDatabase {
    var summary: StatisticsSummary {
        let settled = games.filter { $0.outcome == .won || $0.outcome == .abandoned }
        let wins = games.filter { $0.outcome == .won }
        let sorted = settled.sorted { ($0.settledAt ?? .distantPast, $0.id.uuidString) < ($1.settledAt ?? .distantPast, $1.id.uuidString) }
        var streak = 0, bestStreak = 0
        for game in sorted { if game.outcome == .won { streak += 1; bestStreak = max(bestStreak, streak) } else { streak = 0 } }
        let activeDates = Set(events.filter { $0.kind != .hint && $0.kind != .playTime }.map(\.localDay)).sorted()
        let longest = Self.longestRun(activeDates)
        let today = Self.day(Date())
        var current = 0
        if let last = activeDates.last, let lastDate = Self.parseDay(last), let todayDate = Self.parseDay(today) {
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: lastDate, to: todayDate).day ?? 999
            if days <= 1 { current = longestEnding(activeDates, at: last) }
        }
        let eligible = wins.filter(\.isNoAssistWin)
        return StatisticsSummary(started: games.count,
            wins: wins.count, abandoned: games.filter { $0.outcome == .abandoned }.count,
            unsettled: games.filter { $0.outcome == .inProgress || $0.outcome == .recordOnly }.count,
            winRate: settled.isEmpty ? nil : Double(wins.count) / Double(settled.count),
            currentStreak: streak, bestStreak: bestStreak,
            bestMoves: wins.min { $0.moves < $1.moves }, fastest: wins.min { $0.seconds < $1.seconds },
            averageMoves: wins.isEmpty ? nil : Double(wins.reduce(0) { $0 + $1.moves }) / Double(wins.count),
            averageSeconds: wins.isEmpty ? nil : wins.reduce(0) { $0 + $1.seconds } / Double(wins.count),
            cumulativeSeconds: games.reduce(0) { $0 + $1.cumulativeSeconds }, currentDays: current, bestDays: longest,
            hints: games.reduce(0) { $0 + $1.hints }, undos: games.reduce(0) { $0 + $1.undos },
            redos: games.reduce(0) { $0 + $1.redos }, restarts: games.reduce(0) { $0 + $1.restarts },
            noAssistWins: eligible.count, noAssistBestMoves: eligible.min { $0.moves < $1.moves },
            noAssistFastest: eligible.min { $0.seconds < $1.seconds })
    }
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func parseDay(_ value: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: value)
    }
    private func longestEnding(_ dates: [String], at end: String) -> Int {
        guard let index = dates.firstIndex(of: end) else { return 0 }
        guard index > 0 else { return 1 }
        var length = 1
        for i in stride(from: index, through: 1, by: -1) {
            guard let a = Self.parseDay(dates[i - 1]), let b = Self.parseDay(dates[i]),
                  Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day == 1 else { break }
            length += 1
        }
        return length
    }
    private static func longestRun(_ dates: [String]) -> Int {
        guard !dates.isEmpty else { return 0 }
        var best = 1, run = 1
        for i in 1..<dates.count {
            if let a = parseDay(dates[i - 1]), let b = parseDay(dates[i]), Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day == 1 { run += 1 }
            else { run = 1 }
            best = max(best, run)
        }
        return best
    }
}
