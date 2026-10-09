import SwiftUI
import FreeCellPresentation
import FreeCellCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @ViewBuilder private func sourceLink(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) { Link(localized(title), destination: url) }
    }
    var body: some View {
        Form {
            Section(L("操作")) {
                Toggle(L("自动安全收牌"), isOn: $settings.values.autoCollect)
                Picker(L("自动移牌"), selection: $settings.values.automaticMoveGesture) {
                    ForEach(AutomaticMoveGesture.allCases, id: \.self) { Text(localized($0.title)).tag($0) }
                }.pickerStyle(.segmented)
                Picker(L("空位优先级"), selection: $settings.values.automaticMovePriority) {
                    Text(L("优先空当")).tag(AutomaticMovePriority.freeCellFirst)
                    Text(L("优先空列")).tag(AutomaticMovePriority.emptyColumnFirst)
                }.pickerStyle(.segmented)
                Text(L("自动移牌先尝试收牌和可接牌列，再按此偏好选择空位。回车始终可自动移牌。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("动画与声音")) {
                Picker(L("动画速度"), selection: $settings.values.animationSpeed) {
                    ForEach(AnimationSpeed.allCases, id: \.self) { Text(localized($0.title)).tag($0) }
                }.pickerStyle(.segmented)
                Toggle(L("背景音乐"), isOn: $settings.values.backgroundMusic)
                Toggle(L("移动音效"), isOn: $settings.values.moveSound)
                Text(L("暂停游戏或切换到其他应用时，音乐暂停。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("界面")) {
                Picker(L("语言"), selection: $settings.values.language) {
                    ForEach(GameLanguage.allCases, id: \.self) { language in
                        Text(language == .system ? L("跟随系统") : language.nativeName).tag(language)
                    }
                }
                Text(L("语言立即生效；系统语言不受支持时使用英语。")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("功能按钮后显示快捷键"), isOn: $settings.values.showShortcuts) }
            Section(L("声音来源")) {
                Text("Dream Culture — Kevin MacLeod (incompetech.com)").font(.caption)
                HStack {
                    sourceLink(L("音乐来源"), "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300046")
                    sourceLink("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
                    sourceLink(L("音效：Kenney · CC0"), "https://kenney.nl/assets/interface-sounds")
                }.font(.caption)
            }
            if let error = settings.saveError { Text(localized(error)).foregroundStyle(.orange) }
        }.formStyle(.grouped).padding(12).frame(width: 580, height: 680)
    }
}
