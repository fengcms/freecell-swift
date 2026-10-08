import Foundation
import Observation
import FreeCellPresentation

@MainActor @Observable
final class AppSettings {
    var values: GamePreferences { didSet { GameLocalization.shared.choice = values.language; save(); onChange?() } }
    var saveError: String?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "game-preferences-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(GamePreferences.self, from: data) {
            values = saved
        } else { values = GamePreferences() }
        GameLocalization.shared.choice = values.language
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
            let settings = AppSettings(defaults: UserDefaults(suiteName: "local.fungleo.FreeCell.verification." + suffix) ?? .standard)
            if let index = arguments.firstIndex(of: "--verification-language"), arguments.indices.contains(index + 1),
               let language = GameLanguage(rawValue: arguments[index + 1]) { settings.values.language = language }
            if arguments.contains("--verification-silent") { settings.values.backgroundMusic = false; settings.values.moveSound = false }
            return settings
        }
        return AppSettings(defaults: UserDefaults(suiteName: "local.fungleo.FreeCell.preferences") ?? .standard)
    }
}
