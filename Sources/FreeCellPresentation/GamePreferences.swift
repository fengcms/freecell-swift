import Foundation
import FreeCellCore

public enum AutomaticMoveGesture: String, Codable, CaseIterable, Sendable {
    case doubleClick, rightClick
    public var title: String { self == .doubleClick ? "双击" : "右击" }
}
public enum AnimationSpeed: String, Codable, CaseIterable, Sendable {
    case none, slow, medium, fast
    public var title: String {
        switch self { case .none: "无"; case .slow: "慢"; case .medium: "中等"; case .fast: "快" }
    }
    public var durationMultiplier: Double {
        switch self { case .none: 0; case .slow: 1.8; case .medium: 1; case .fast: 0.5 }
    }
}
public struct GamePreferences: Codable, Equatable, Sendable {
    public var language: GameLanguage = .system
    public var autoCollect = true
    public var automaticMoveGesture: AutomaticMoveGesture = .doubleClick
    public var automaticMovePriority: AutomaticMovePriority = .freeCellFirst
    public var animationSpeed: AnimationSpeed = .medium
    public var backgroundMusic = true
    public var moveSound = true
    public var showShortcuts = false
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case language, autoCollect, automaticMoveGesture, automaticMovePriority, animationSpeed, backgroundMusic, moveSound, showShortcuts
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? values.decodeIfPresent(GameLanguage.self, forKey: .language)) ?? .system
        autoCollect = try values.decodeIfPresent(Bool.self, forKey: .autoCollect) ?? true
        automaticMoveGesture = try values.decodeIfPresent(AutomaticMoveGesture.self, forKey: .automaticMoveGesture) ?? .doubleClick
        automaticMovePriority = try values.decodeIfPresent(AutomaticMovePriority.self, forKey: .automaticMovePriority) ?? .freeCellFirst
        animationSpeed = try values.decodeIfPresent(AnimationSpeed.self, forKey: .animationSpeed) ?? .medium
        backgroundMusic = try values.decodeIfPresent(Bool.self, forKey: .backgroundMusic) ?? true
        moveSound = try values.decodeIfPresent(Bool.self, forKey: .moveSound) ?? true
        showShortcuts = try values.decodeIfPresent(Bool.self, forKey: .showShortcuts) ?? false
    }
    public var summary: String {
        "\(autoCollect ? "自动收" : "手动收") · \(automaticMoveGesture.title) · 动画\(animationSpeed == .medium ? "中" : animationSpeed.title) · 音乐\(backgroundMusic ? "开" : "关") · 音效\(moveSound ? "开" : "关") · 快捷键\(showShortcuts ? "显" : "隐")"
    }
}
