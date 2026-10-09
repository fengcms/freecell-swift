import SwiftUI

struct VictoryCelebrationView: View {
    let moves: Int
    let elapsed: String
    let record: String?
    let animationsDisabled: Bool
    let onPlayAgain: () -> Void

    private let gold = Color(red: 0.91, green: 0.77, blue: 0.46)

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .medium))
                    .symbolEffect(.bounce, value: animationsDisabled)
                    .foregroundStyle(gold)
                Text(L("全部归位，恭喜过关！"))
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(gold)
                Text(L("moves %@ %@", String(moves), elapsed))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                if let record {
                    Text(L(record)).font(.headline).foregroundStyle(gold)
                }
                Button(action: onPlayAgain) {
                    Label(L("再来一局"), systemImage: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(minWidth: 250, minHeight: 62)
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(gold)
                .foregroundStyle(.black)
                Text(L("胜利后空格或右键开始新牌局"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 48).padding(.vertical, 40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(gold.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(VictoryInputMonitor(isActive: true, onPlayAgain: onPlayAgain)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
    }
}
