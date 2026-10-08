import Foundation
import Observation
import FreeCellPresentation

@MainActor @Observable
final class AppSettings {
    var values: GamePreferences { didSet { save(); onChange?() } }
    var saveError: String?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "game-preferences-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(GamePreferences.self, from: data) {
            values = saved
        } else { values = GamePreferences() }
    }
    private func save() {
        do { defaults.set(try JSONEncoder().encode(values), forKey: Self.key); saveError = nil }
        catch { saveError = "设置保存失败，请重试。" }
    }
    static func forCurrentLaunch() -> AppSettings {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--verification") {
            let index = arguments.firstIndex(of: "--verification-directory")
            let folder = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "default"
            let suffix = Data(folder.utf8).base64EncodedString()
            return AppSettings(defaults: UserDefaults(suiteName: "local.fungleo.FreeCell.verification." + suffix) ?? .standard)
        }
        return AppSettings(defaults: UserDefaults(suiteName: "local.fungleo.FreeCell.preferences") ?? .standard)
    }
}
