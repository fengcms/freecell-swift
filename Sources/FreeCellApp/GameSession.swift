import AppKit
import Foundation
import Observation
import OSLog
import FreeCellCore
import FreeCellPresentation

private actor SaveWriter {
    private var latestRevision = 0
    func write(_ data: Data, to url: URL, revision: Int) throws {
        guard revision > latestRevision else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        latestRevision = revision
    }
}

@MainActor @Observable
final class GameSession {
    private(set) var archive: GameArchive
    private(set) var boardVersion = 0
    private(set) var animationRequest: BoardAnimationRequest?
    var selection: Int?
    var hintMove: Move?
    var message = "选择一张牌，再点击目标；也可以直接拖动。"
    var paused = false
    var active = true
    var recoveryMessage: String?
    private(set) var saveError: String?
    private let saveURL: URL
    private let writer = SaveWriter()
    private var revision = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastSave = ProcessInfo.processInfo.systemUptime
    private let logger = Logger(subsystem: "local.fungleo.FreeCell", category: "Session")

    var state: GameState { archive.current }
    var canUndo: Bool { archive.cursor > 0 }
    var canRedo: Bool { archive.cursor < archive.history.count }
    var moves: Int { archive.cursor }
    var elapsed: String {
        let seconds = Int(min(archive.elapsed, 359_999_999))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
    var autoCollect: Bool {
        get { archive.autoCollect }
        set { archive.autoCollect = newValue; persist() }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let verification = ProcessInfo.processInfo.arguments.contains("--verification")
        let arguments = ProcessInfo.processInfo.arguments
        let verificationFolder: URL
        if let index = arguments.firstIndex(of: "--verification-directory"), arguments.indices.contains(index + 1) {
            verificationFolder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            verificationFolder = FileManager.default.temporaryDirectory.appendingPathComponent("FreeCell-Verification")
        }
        saveURL = verification ? verificationFolder.appendingPathComponent("game-v1.json")
            : base.appendingPathComponent("FreeCell-Swift/game-v1.json")
        // A generated deck is structurally valid by construction; handle initialization without force unwraps.
        do { archive = try GameArchive(seed: UInt64.random(in: 1...UInt64.max)) }
        catch { fatalError("Internal deck construction failed: \(error)") }
        if FileManager.default.fileExists(atPath: saveURL.path) {
            do {
                let data = try Data(contentsOf: saveURL)
                guard data.count <= 64 * 1024 * 1024 else { throw GameError.invalidArchive }
                let loaded = try JSONDecoder().decode(GameArchive.self, from: data)
                try loaded.validate(); archive = loaded
                message = "已恢复上次牌局。"
            } catch {
                let backup = saveURL.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")
                do {
                    try FileManager.default.moveItem(at: saveURL, to: backup)
                    recoveryMessage = "无法恢复原存档，已在存档目录保留备份。现在显示新牌局。"
                } catch {
                    recoveryMessage = "无法恢复或备份原存档，自动保存已停止。可以在存档目录检查文件。"
                    saveError = "原存档无法备份，暂停自动保存。"
                }
                logger.error("Archive recovery failed")
            }
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - lastTick
        lastTick = now
        // Exclude sleep or scheduling gaps rather than count hours spent away from the game.
        if active && !paused && !state.isWon && delta >= 0 && delta < 3 { archive.elapsed += delta }
        if now - lastSave >= 10 { lastSave = now; persist() }
    }
    func setActive(_ value: Bool) { tick(); active = value; persist() }
    func togglePause() { tick(); paused.toggle(); selection = nil; hintMove = nil; persist() }

    func newGame(seed: UInt64? = nil) {
        do {
            let preference = archive.autoCollect
            archive = try GameArchive(seed: seed ?? UInt64.random(in: 1...UInt64.max))
            archive.autoCollect = preference
            clearInteraction(); paused = false; lastTick = ProcessInfo.processInfo.systemUptime
            message = "新牌局已发好。"; persist()
        } catch { report(error) }
    }
    func restart() { archive.restart(); clearInteraction(); paused = false; message = "已恢复本局初始发牌。"; persist() }
    func undo() { archive.undo(); clearInteraction(); message = "已撤销；计时继续累计。"; persist() }
    func redo() { archive.redo(); clearInteraction(); message = state.isWon ? "恭喜，全部牌已归位！" : "已重做。"; persist() }
    private func clearInteraction() { selection = nil; hintMove = nil; animationRequest = nil; boardVersion += 1 }

    func source(for cardID: Int) -> (Location, Int)? {
        guard let selection = Rules.selection(for: cardID, in: state) else { return nil }
        return (selection.source, selection.cards.count)
    }

    func click(card: Card, at location: Location) {
        guard !paused else { return }
        if selection == card.id { selection = nil; return }
        if let selected = selection, let (source, _) = source(for: selected), source != location {
            move(cardID: selected, to: location, animated: true)
        } else if source(for: card.id) != nil {
            selection = card.id; hintMove = nil
            message = "已选择\(card.name)，请选择目标。"
        } else { message = "只能操作工作列的有序牌组或基础堆最上方的一张牌。" }
    }
    func clickEmpty(_ location: Location) {
        guard let selected = selection else { message = "请先选择要移动的牌。"; return }
        move(cardID: selected, to: location, animated: true)
    }
    @discardableResult
    func move(cardID: Int, to destination: Location, animated: Bool = false) -> Bool {
        guard !paused, let (source, count) = source(for: cardID) else { return false }
        let move = Move(from: source, to: destination, count: count)
        do {
            let moved = try Rules.applying(move, to: state)
            var steps = [moved]
            if autoCollect {
                switch source {
                case .foundation: break // Intentional take-back must not immediately be collected again.
                default: steps = Rules.safeCollectionSteps(from: moved)
                }
            }
            guard let next = steps.last else { return false }
            let visualSteps = animated ? [state] + steps : steps
            archive.commit(next, move: move); clearInteraction()
            if visualSteps.count > 1 { animationRequest = BoardAnimationRequest(id: boardVersion, states: visualSteps) }
            message = state.isWon ? "恭喜，全部牌已归位！" : "已移至\(destination.name)。"
            persist()
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func doubleClick(cardID: Int) -> Bool {
        guard !paused else { return false }
        guard let move = Rules.automaticMove(for: cardID, in: state) else {
            selection = cardID; hintMove = nil
            message = "这张牌目前没有可用目标。"
            return false
        }
        return self.move(cardID: cardID, to: move.destination, animated: true)
    }

    func collect() {
        guard !paused, !state.isWon else { return }
        let steps = Rules.safeCollectionSteps(from: state)
        guard let next = steps.last, next != state else { message = "目前没有可安全收取的牌。"; return }
        archive.commit(next, move: nil); clearInteraction()
        animationRequest = BoardAnimationRequest(id: boardVersion, states: steps)
        message = state.isWon ? "恭喜，全部牌已归位！" : "已收取安全牌，可一次撤销。"
        persist()
    }
    func showHint() {
        guard !paused, !state.isWon else { return }
        let candidate = Rules.hint(in: state, avoiding: hintMove)
        hintMove = candidate
        if let move = candidate {
            let card: Card?
            if case .tableau(let index) = move.source { card = state.tableau[index].suffix(move.count).first }
            else { card = state.topCard(at: move.source) }
            selection = card?.id
            message = "提示：\(move.source.name) → \(move.destination.name)，\(move.count)张。提示不保证最终可解。"
        } else {
            selection = nil
            message = Rules.legalMoves(in: state).isEmpty ? "当前无合法移动，可撤销或重开。" : "当前没有有意义的提示，可尝试其他合法移动。"
        }
    }
    func cancelSelection() { clearInteraction(); message = "已取消选择。" }
    func revealSaveFolder() { NSWorkspace.shared.open(saveURL.deletingLastPathComponent()) }
    private func report(_ error: Error) { message = (error as? GameError)?.message ?? "操作失败，请重试。" }
    func saveBeforeQuit() async -> Bool {
        tick()
        guard saveError != "原存档无法备份，暂停自动保存。" else { return false }
        do {
            let data = try JSONEncoder().encode(archive)
            revision += 1
            try await writer.write(data, to: saveURL, revision: revision)
            return true
        } catch {
            saveError = "保存失败，请检查存档目录权限。"
            logger.error("Final archive write failed")
            return false
        }
    }

    func persist() {
        guard saveError != "原存档无法备份，暂停自动保存。" else { return }
        do {
            let data = try JSONEncoder().encode(archive)
            revision += 1
            let currentRevision = revision
            let url = saveURL
            Task {
                do { try await writer.write(data, to: url, revision: currentRevision); saveError = nil }
                catch { saveError = "保存失败，请检查存档目录权限。"; logger.error("Archive write failed") }
            }
        } catch { saveError = "无法编码牌局，尚未保存。" }
    }
}
