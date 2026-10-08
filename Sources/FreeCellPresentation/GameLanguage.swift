import Foundation

public enum GameLanguage: String, Codable, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case french = "fr", german = "de", spanish = "es", arabic = "ar", japanese = "ja", korean = "ko"

    public var nativeName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .arabic: "العربية"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> GameLanguage {
        guard self == .system else { return self }
        // Resolve the primary system language, rather than a lower-priority fallback.
        guard let primary = preferredLanguages.first else { return .english }
        let parts = primary.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
        switch parts.first {
        case "zh":
            if parts.contains("hant") { return .traditionalChinese }
            if parts.contains("hans") { return .simplifiedChinese }
            return parts.contains("tw") || parts.contains("hk") || parts.contains("mo") ? .traditionalChinese : .simplifiedChinese
        case "en": return .english
        case "fr": return .french
        case "de": return .german
        case "es": return .spanish
        case "ar": return .arabic
        case "ja": return .japanese
        case "ko": return .korean
        default: return .english
        }
    }
    public var isRightToLeft: Bool { self == .arabic }
}
