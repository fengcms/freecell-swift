import SwiftUI
import FreeCellPresentation

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @ViewBuilder private func sourceLink(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) { Link(title, destination: url) }
    }
    var body: some View {
        Form {
            Section("操作") {
                Toggle("自动安全收牌", isOn: $settings.values.autoCollect)
                Picker("自动移牌", selection: $settings.values.automaticMoveGesture) {
                    ForEach(AutomaticMoveGesture.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("按所选方式依次尝试收牌、接到其他列、暂存或空列。回车始终可自动移牌。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("动画与声音") {
                Picker("动画速度", selection: $settings.values.animationSpeed) {
                    ForEach(AnimationSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("背景音乐", isOn: $settings.values.backgroundMusic)
                Toggle("移动音效", isOn: $settings.values.moveSound)
                Text("暂停游戏或切换到其他应用时，音乐暂停。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("界面") { Toggle("功能按钮后显示快捷键", isOn: $settings.values.showShortcuts) }
            Section("声音来源") {
                Text("Dream Culture — Kevin MacLeod (incompetech.com)").font(.caption)
                HStack {
                    sourceLink("音乐来源", "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300046")
                    sourceLink("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
                    sourceLink("音效：Kenney · CC0", "https://kenney.nl/assets/interface-sounds")
                }.font(.caption)
            }
            if let error = settings.saveError { Text(error).foregroundStyle(.orange) }
        }.formStyle(.grouped).padding(12).frame(width: 490).fixedSize(horizontal: false, vertical: true)
    }
}
