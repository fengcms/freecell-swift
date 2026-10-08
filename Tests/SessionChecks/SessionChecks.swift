import Foundation
import FreeCellPresentation

@main struct SessionChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "FreeCell.SessionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.values.backgroundMusic = false
        let url = folder.appendingPathComponent("game.json")
        let original = Data("damaged archive: preserve me".utf8)
        try original.write(to: url)
        let session = GameSession(settings: settings, saveURL: url, backupArchive: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        session.connectSettings()
        settings.values.language = .german
        settings.values.autoCollect.toggle()
        settings.values.moveSound.toggle()
        settings.values.animationSpeed = .fast
        session.newGame(seed: 42)
        session.restart()
        session.undo()
        session.redo()
        session.collect()
        session.tick()
        session.togglePause()
        session.setActive(false)
        session.persist()
        guard await session.saveBeforeQuit() == false else { fatalError("Blocked final write succeeded") }
        try await Task.sleep(for: .milliseconds(100))
        guard try Data(contentsOf: url) == original else { fatalError("Original archive was overwritten") }
        let normalURL = folder.appendingPathComponent("normal.json")
        let normal = GameSession(settings: settings, saveURL: normalURL)
        normal.connectSettings()
        guard await normal.saveBeforeQuit() else { fatalError("Normal save failed") }
        let saved = try Data(contentsOf: normalURL)
        settings.values.language = .japanese
        normal.applySettings()
        try await Task.sleep(for: .milliseconds(100))
        guard try Data(contentsOf: normalURL) == saved else { fatalError("Language setting rewrote archive") }
        print("PASS failed-backup archive preservation and settings write isolation")
    }
}
