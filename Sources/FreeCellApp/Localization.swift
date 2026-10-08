import Foundation
import Observation
import FreeCellPresentation

/// A runtime locale, independent of system-wide preferences and game archives.
@MainActor @Observable
final class GameLocalization {
    static let shared = GameLocalization()
    var choice: GameLanguage = .system
    var language: GameLanguage { choice.resolved() }
    @ObservationIgnored private let catalog: [String: [String: String]]
    private init() {
        guard let url = GameResources.bundle.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            preconditionFailure("Missing or invalid translation catalog")
        }
        catalog = decoded
    }
    func isTranslation(_ text: String, of key: String) -> Bool {
        text == key || catalog[key]?.values.contains(text) == true
    }
    func text(_ key: String, _ arguments: [String] = []) -> String {
        let format = catalog[key]?[language.rawValue] ?? catalog[key]?["en"] ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments.map { $0 as NSString })
    }
    private static let patterns: [(NSRegularExpression, String)] = [
            (#"^已选择(.+)，请选择目标。$"#, "selected %@"),
            (#"^已移至(.+)。$"#, "moved %@"),
            (#"^提示：(.+) → (.+)，([0-9]+)张。提示不保证最终可解。$"#, "hint %@ %@ %@"),
            (#"^空当和空列不足，此处最多移动 ([0-9]+) 张。$"#, "capacity %@"),
            (#"^第([0-9]+)列$"#, "column %@"),
            (#"^第([0-9]+)空当$"#, "cell %@"),
            (#"^(.+)基础堆$"#, "foundation %@")
    ].compactMap { pattern, key in
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (regex, key)
    }

    /// Legacy core message keys are translated at the UI boundary without altering archives.
    func render(_ value: String) -> String {
        if catalog[value] != nil { return text(value) }
        for (regex, key) in Self.patterns {
            let fullRange = NSRange(value.startIndex..., in: value)
            if let match = regex.firstMatch(in: value, range: fullRange) {
                let arguments = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: value).map { render(String(value[$0])) } }
                return text(key, arguments)
            }
        }
        for suit in ["梅花", "方块", "红桃", "黑桃"] where value.hasPrefix(suit) {
            return text(suit) + " " + String(value.dropFirst(suit.count))
        }
        return value
    }
}

@MainActor func L(_ key: String, _ arguments: String...) -> String {
    GameLocalization.shared.text(key, arguments)
}
@MainActor func localized(_ value: String) -> String { GameLocalization.shared.render(value) }
