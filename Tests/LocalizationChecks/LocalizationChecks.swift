import Foundation
import FreeCellPresentation

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        let url = GameResources.bundle.url(forResource: "Translations", withExtension: "json")!
        let catalog = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
        let languages = GameLanguage.allCases.filter { $0 != .system }
        let expected = Set(languages.map(\.rawValue))
        for (key, translations) in catalog {
            precondition(Set(translations.keys) == expected, "Incomplete language coverage: \(key)")
            let arguments = translations["en"]!.components(separatedBy: "%@").count - 1
            for (language, text) in translations {
                precondition(!text.isEmpty && text.components(separatedBy: "%@").count - 1 == arguments, "Invalid placeholders: \(key), \(language)")
            }
        }
        for language in languages {
            GameLocalization.shared.choice = language
            precondition(L("语言") == catalog["语言"]![language.rawValue])
            let selected = localized("已选择梅花A，请选择目标。")
            precondition(selected.contains("A") && !selected.contains("%@"))
            precondition(localized("已移至第3列。") == L("moved %@", L("column %@", "3")))
            precondition(localized("黑桃基础堆") == L("foundation %@", L("黑桃")))
            precondition(localized("空当和空列不足，此处最多移动 4 张。") == L("capacity %@", "4"))
            precondition(localized("提示：第1列 → 第2空当，3张。提示不保证最终可解。") == L("hint %@ %@ %@", L("column %@", "1"), L("cell %@", "2"), "3"))
            let formatted = L("moves %@ %@", "12", "01:23")
            precondition(formatted.contains("12") && formatted.contains("01:23") && !formatted.contains("%@"))
            print("PASS runtime translations: \(language.rawValue)")
        }
        print("PASS \(catalog.count) catalog entries, nine languages, formatting and dynamic messages")
    }
}
