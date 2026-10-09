import AppKit
import Foundation
import Observation
import OSLog

@MainActor @Observable
final class StatisticsStore {
    private(set) var database = StatisticsDatabase()
    private(set) var errorMessage: String?
    let fileURL: URL
    private let logger = Logger(subsystem: "local.fungleo.FreeCell", category: "Statistics")

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let args = ProcessInfo.processInfo.arguments
        let verification = args.contains("--verification")
        var folder = FileManager.default.temporaryDirectory.appendingPathComponent("FreeCell-Verification")
        if let index = args.firstIndex(of: "--verification-directory"), args.indices.contains(index + 1) {
            folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        }
        self.fileURL = fileURL ?? (verification ? folder.appendingPathComponent("statistics-v1.json") : base.appendingPathComponent("FreeCell-Swift/statistics-v1.json"))
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                let data = try Data(contentsOf: self.fileURL)
                guard data.count <= 64 * 1024 * 1024 else { throw StatisticsError.tooLarge }
                let loaded = try JSONDecoder().decode(StatisticsDatabase.self, from: data)
                try Self.validate(loaded); database = loaded
            }
        } catch {
            errorMessage = "统计数据无法读取，原文件已保留；统计写入已暂停。"
            logger.error("Statistics load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var summary: StatisticsSummary { database.summary }
    func isExcluded(_ id: UUID) -> Bool { database.excludedGameIDs.contains(id) }
    func excludedIdentity(seed: UInt64, algorithm: Int) -> UUID? { database.excludedDealIdentities["\(algorithm):\(seed)"] }
    func persistSnapshot() { persist() }
    var games: [StatisticsGame] { database.games.sorted { $0.startedAt > $1.startedAt } }
    var dealGroups: [DealStatistics] {
        Dictionary(grouping: database.games, by: { "\($0.algorithmVersion):\($0.seed)" }).map { key, games in
            DealStatistics(key: key, algorithmVersion: games.first?.algorithmVersion ?? 0, seed: games.first?.seed ?? "",
                           games: games, wins: games.filter { $0.outcome == .won }.count,
                           best: games.filter { $0.outcome == .won }.min { $0.moves < $1.moves },
                           fastest: games.filter { $0.outcome == .won }.min { $0.seconds < $1.seconds })
        }.sorted { $0.games.count == $1.games.count ? $0.seed < $1.seed : $0.games.count > $1.games.count }
    }

    func registerStart(id: UUID, seed: UInt64, algorithm: Int, baselineMoves: Int = 0,
                       baselineSeconds: TimeInterval = 0, legacy: Bool = false, autoCollect: Bool) {
        guard errorMessage == nil, !database.excludedGameIDs.contains(id) else { return }
        if database.games.contains(where: { $0.id == id }) { return }
        let now = Date()
        var game = StatisticsGame(id: id, seed: String(seed), algorithmVersion: algorithm, startedAt: now,
            startedLocalDay: StatisticsDatabase.day(now), startedTimeZone: TimeZone.current.identifier,
            settledAt: nil, settledLocalDay: nil, settledTimeZone: nil,
            outcome: .inProgress, moves: baselineMoves, seconds: baselineSeconds, cumulativeSeconds: 0,
            hints: 0, undos: 0, redos: 0, restarts: 0, automaticMoves: 0, manualCollections: 0,
            foundationTakebacks: 0, autoCollectUsed: autoCollect, noAssistEligible: !legacy && !autoCollect,
            noAssistReason: legacy ? "legacy" : (autoCollect ? "autoCollect" : nil), legacyUnknown: legacy,
            importedOnly: false, revision: 1,
            attempts: [StatisticsAttempt(id: UUID(), startedAt: now, endedAt: nil, moves: baselineMoves, seconds: baselineSeconds)],
            wonLocalDay: nil, wonTimeZone: nil)
        if legacy { game.noAssistEligible = false }
        database.games.append(game); database.updatedAt = now
        persist()
    }

    func action(_ kind: StatisticsEventKind, id: UUID, moves: Int, seconds: TimeInterval, autoCollect: Bool = false) {
        guard errorMessage == nil, let index = database.games.firstIndex(where: { $0.id == id }), database.games[index].outcome == .inProgress else { return }
        var game = database.games[index]
        game.moves = max(0, moves); game.seconds = max(0, seconds); game.revision += 1
        if let attempt = game.attempts.indices.last { game.attempts[attempt].moves = game.moves; game.attempts[attempt].seconds = game.seconds }
        switch kind {
        case .hint: game.hints += 1; disqualify(&game, "hint")
        case .undo: game.undos += 1; disqualify(&game, "undo")
        case .redo: game.redos += 1; disqualify(&game, "redo")
        case .restart: game.restarts += 1; disqualify(&game, "restart")
        case .automaticMove: game.automaticMoves += 1; disqualify(&game, "automaticMove")
        case .collect: game.manualCollections += 1; disqualify(&game, "manualCollect")
        case .foundationTakeback: game.foundationTakebacks += 1; disqualify(&game, "foundationTakeback")
        case .autoCollect: game.autoCollectUsed = true; disqualify(&game, "autoCollect")
        case .move, .playTime, .noAssistDisqualification: break
        }
        if autoCollect { game.autoCollectUsed = true; disqualify(&game, "autoCollect") }
        database.games[index] = game
        recordEvent(gameID: id, kind: kind, seconds: 0, shouldPersist: false)
        persist()
    }

    func addTime(id: UUID, seconds: TimeInterval, attemptSeconds: TimeInterval, localDay: String, timeZone: String) {
        guard errorMessage == nil, seconds > 0, seconds < 60, let index = database.games.firstIndex(where: { $0.id == id }), database.games[index].outcome == .inProgress else { return }
        database.games[index].cumulativeSeconds += seconds
        database.games[index].seconds = max(0, attemptSeconds)
        if let attempt = database.games[index].attempts.indices.last { database.games[index].attempts[attempt].seconds = max(0, attemptSeconds) }
        database.games[index].revision += 1
        let now = Date()
        database.events.append(StatisticsEvent(id: UUID(), gameID: id, kind: .playTime, timestamp: now, localDay: localDay, timeZone: timeZone, seconds: seconds))
        database.updatedAt = now
    }

    func settleWin(id: UUID, moves: Int, seconds: TimeInterval) -> Bool {
        guard errorMessage == nil, let index = database.games.firstIndex(where: { $0.id == id }) else { return false }
        guard database.games[index].outcome != .won else { return false }
        guard database.games[index].outcome == .inProgress else { return false }
        let now = Date(); var game = database.games[index]
        game.outcome = .won; game.settledAt = now; game.moves = max(0, moves); game.seconds = max(0, seconds); game.revision += 1
        game.wonLocalDay = StatisticsDatabase.day(now); game.wonTimeZone = TimeZone.current.identifier
        game.settledLocalDay = game.wonLocalDay; game.settledTimeZone = game.wonTimeZone
        if let attempt = game.attempts.indices.last { game.attempts[attempt].moves = game.moves; game.attempts[attempt].seconds = game.seconds; game.attempts[attempt].endedAt = now }
        database.games[index] = game; database.updatedAt = now; persist(); return true
    }

    func abandon(id: UUID) {
        guard let index = database.games.firstIndex(where: { $0.id == id }), database.games[index].outcome == .inProgress else { return }
        let now = Date(); database.games[index].outcome = .abandoned; database.games[index].settledAt = now; database.games[index].revision += 1
        database.games[index].settledLocalDay = StatisticsDatabase.day(now); database.games[index].settledTimeZone = TimeZone.current.identifier
        if let attempt = database.games[index].attempts.indices.last { database.games[index].attempts[attempt].endedAt = now }
        database.updatedAt = now
        persist()
    }

    func restart(id: UUID, moves: Int, seconds: TimeInterval) {
        guard let index = database.games.firstIndex(where: { $0.id == id }), database.games[index].outcome == .inProgress else { return }
        var game = database.games[index]; game.restarts += 1; disqualify(&game, "restart")
        if let attempt = game.attempts.indices.last { game.attempts[attempt].moves = moves; game.attempts[attempt].seconds = seconds; game.attempts[attempt].endedAt = Date() }
        game.attempts.append(StatisticsAttempt(id: UUID(), startedAt: Date(), endedAt: nil, moves: 0, seconds: 0)); game.moves = 0; game.seconds = 0; game.revision += 1
        database.games[index] = game; recordEvent(gameID: id, kind: .restart, seconds: 0, shouldPersist: false); database.updatedAt = Date(); persist()
    }

    func recordHintBeforeStart(id: UUID) { action(.hint, id: id, moves: 0, seconds: 0) }
    func disqualifyBeforeStart(id: UUID, reason: String) {
        guard errorMessage == nil, let index = database.games.firstIndex(where: { $0.id == id }), database.games[index].outcome == .inProgress else { return }
        var game = database.games[index]; disqualify(&game, reason); game.revision += 1; database.games[index] = game
        recordEvent(gameID: id, kind: .noAssistDisqualification, seconds: 0, shouldPersist: false); persist()
    }
    nonisolated static func writeExport(_ database: StatisticsDatabase, to url: URL) throws {
        let data = try JSONEncoder.statistics.encode(database)
        try data.write(to: url, options: .atomic)
    }
    nonisolated static func readImport(from url: URL) throws -> StatisticsDatabase {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 64 * 1024 * 1024 else { throw StatisticsError.tooLarge }
        let imported = try JSONDecoder.statistics.decode(StatisticsDatabase.self, from: Data(contentsOf: url))
        try Self.validate(imported); guard imported.games.count <= 100_000, imported.events.count <= 1_000_000 else { throw StatisticsError.tooLarge }
        return imported
    }
    func merge(_ incoming: StatisticsDatabase) throws {
        try Self.validate(incoming)
        var games = Dictionary(uniqueKeysWithValues: database.games.map { ($0.id, $0) })
        for candidate in incoming.games {
            if let current = games[candidate.id] {
                if current.outcome == .won || current.outcome == .abandoned {
                    guard current == candidate else { throw StatisticsError.conflict }
                } else if candidate.revision > current.revision {
                    var copy = candidate; if copy.outcome == .inProgress { copy.outcome = .recordOnly }; games[candidate.id] = copy
                }
                else if candidate.revision == current.revision && candidate != current { throw StatisticsError.conflict }
            } else {
                var copy = candidate; copy.importedOnly = true
                if copy.outcome == .inProgress { copy.outcome = .recordOnly }
                games[copy.id] = copy
            }
        }
        var events = Dictionary(uniqueKeysWithValues: database.events.map { ($0.id, $0) })
        for event in incoming.events { if let old = events[event.id], old != event { throw StatisticsError.conflict }; events[event.id] = event }
        guard games.count <= 100_000, events.count <= 1_000_000 else { throw StatisticsError.tooLarge }
        var merged = database; merged.games = Array(games.values); merged.events = Array(events.values); merged.periodStartedAt = min(database.periodStartedAt, incoming.periodStartedAt); merged.updatedAt = Date()
        try commit(merged)
    }
    func replace(with incoming: StatisticsDatabase, excluding currentGameID: UUID, seed: UInt64, algorithm: Int) throws {
        try Self.validate(incoming); var copy = incoming; copy.sourceID = UUID(); copy.updatedAt = Date()
        copy.games = copy.games.map { game in var value = game; value.importedOnly = true; if value.outcome == .inProgress { value.outcome = .recordOnly }; return value }
        copy.excludedGameIDs = [currentGameID]; copy.excludedDealIdentities = ["\(algorithm):\(seed)": currentGameID]
        try commit(copy)
    }
    func reset(excluding currentGameID: UUID, seed: UInt64, algorithm: Int) throws {
        var empty = StatisticsDatabase(); empty.sourceID = database.sourceID; empty.excludedGameIDs = [currentGameID]
        empty.excludedDealIdentities = ["\(algorithm):\(seed)": currentGameID]; try commit(empty)
    }
    func revealDataFolder() { NSWorkspace.shared.open(fileURL.deletingLastPathComponent()) }

    private func disqualify(_ game: inout StatisticsGame, _ reason: String) { game.noAssistEligible = false; if game.noAssistReason == nil { game.noAssistReason = reason } }
    private func recordEvent(gameID: UUID, kind: StatisticsEventKind, seconds: TimeInterval, shouldPersist: Bool) {
        let now = Date(); database.events.append(StatisticsEvent(id: UUID(), gameID: gameID, kind: kind, timestamp: now,
            localDay: StatisticsDatabase.day(now), timeZone: TimeZone.current.identifier, seconds: seconds))
        database.updatedAt = now
        if shouldPersist { persist() }
    }
    private func commit(_ value: StatisticsDatabase) throws {
        let data = try JSONEncoder.statistics.encode(value)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic); database = value; errorMessage = nil
    }
    private func persist() {
        guard errorMessage == nil else { return }
        do { try commit(database) }
        catch { errorMessage = "统计数据保存失败；原有统计仍保留。"; logger.error("Statistics write failed: \(error.localizedDescription, privacy: .public)") }
    }
    nonisolated private static func validate(_ value: StatisticsDatabase) throws {
        guard value.schemaVersion == 1, value.metricVersion == 1, value.games.count <= 100_000, value.events.count <= 1_000_000,
              value.periodStartedAt.timeIntervalSince1970.isFinite, value.updatedAt.timeIntervalSince1970.isFinite,
              Set(value.games.map(\.id)).count == value.games.count, Set(value.events.map(\.id)).count == value.events.count,
              Set(value.excludedGameIDs).count == value.excludedGameIDs.count, value.excludedGameIDs.count <= 100_000,
              value.excludedDealIdentities.count <= 100_000,
              value.excludedDealIdentities.values.allSatisfy({ value.excludedGameIDs.contains($0) }) else { throw StatisticsError.invalid }
        let gameIDs = Set(value.games.map(\.id))
        for game in value.games {
            guard UInt64(game.seed) != nil, game.moves >= 0, game.seconds.isFinite, game.seconds >= 0,
                  game.cumulativeSeconds.isFinite, game.cumulativeSeconds >= 0, game.attempts.count <= 10_000,
                  game.hints >= 0, game.undos >= 0, game.redos >= 0, game.restarts >= 0, game.automaticMoves >= 0,
                  game.manualCollections >= 0, game.foundationTakebacks >= 0,
                  game.startedAt.timeIntervalSince1970.isFinite,
                  game.settledAt?.timeIntervalSince1970.isFinite ?? true,
                  Self.validDay(game.startedLocalDay), TimeZone(identifier: game.startedTimeZone) != nil,
                  game.settledLocalDay.map(Self.validDay) ?? true,
                  game.settledTimeZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
                  game.attempts.allSatisfy({ $0.moves >= 0 && $0.seconds.isFinite && $0.seconds >= 0 && $0.startedAt.timeIntervalSince1970.isFinite && ($0.endedAt?.timeIntervalSince1970.isFinite ?? true) }) else { throw StatisticsError.invalid }
        }
        guard value.events.allSatisfy({ gameIDs.contains($0.gameID) && $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds < 10_000 && $0.timestamp.timeIntervalSince1970.isFinite && Self.validDay($0.localDay) && TimeZone(identifier: $0.timeZone) != nil }) else { throw StatisticsError.invalid }
    }
    nonisolated private static func validDay(_ value: String) -> Bool { value.count == 10 && StatisticsDatabase.parseDay(value) != nil }
}

struct DealStatistics: Identifiable { var id: String { key }; let key: String; let algorithmVersion: Int; let seed: String; let games: [StatisticsGame]; let wins: Int; let best: StatisticsGame?; let fastest: StatisticsGame? }
enum StatisticsError: Error, Sendable { case tooLarge, invalid, conflict }
extension JSONEncoder { static var statistics: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value } }
extension JSONDecoder { static var statistics: JSONDecoder { JSONDecoder() } }
