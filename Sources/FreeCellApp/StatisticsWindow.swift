import AppKit
import Charts
import SwiftUI
import FreeCellCore

@MainActor
enum StatisticsWindowController {
    private static var controller: NSWindowController?
    static func show(session: GameSession) {
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L("统计")
            window.minSize = NSSize(width: 720, height: 560)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: StatisticsView(session: session).modifier(GameLocaleModifier()))
            window.center(); controller = NSWindowController(window: window)
        }
        controller?.showWindow(nil); controller?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    static func refreshTitle() { controller?.window?.title = L("统计") }
    static func confirm(title: String, message: String, confirmTitle: String, extraTitle: String? = nil,
                        onExtra: @escaping @MainActor () -> Void = {},
                        onConfirm: @escaping @MainActor () -> Void,
                        onCancel: @escaping @MainActor () -> Void = {}) {
        guard let parent = controller?.window, parent.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.alertStyle = .warning
        let cancel = alert.addButton(withTitle: L("取消")); cancel.keyEquivalent = "\r"; cancel.keyEquivalentModifierMask = []
        if let extraTitle { alert.addButton(withTitle: extraTitle) }
        alert.addButton(withTitle: confirmTitle)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alert] event in
            let handled = MainActor.assumeIsolated {
                guard let alert, event.window === alert.window else { return false }
                let commandC = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.charactersIgnoringModifiers?.lowercased() == "c"
                if event.keyCode == 53 || commandC { alert.buttons[0].performClick(nil); return true }
                return false
            }
            return handled ? nil : event
        }
        alert.beginSheetModal(for: parent) { response in
            if let monitor { NSEvent.removeMonitor(monitor) }
            if response == .alertFirstButtonReturn { onCancel() }
            else if extraTitle != nil && response == .alertSecondButtonReturn { onExtra() }
            else if response == (extraTitle == nil ? .alertSecondButtonReturn : .alertThirdButtonReturn) { onConfirm() }
        }
    }
}

@MainActor private enum StatisticsTab: String, CaseIterable {
    case overview, games, deals, trends
    var id: String { rawValue }
    var title: String { switch self { case .overview: L("总览"); case .games: L("对局"); case .deals: L("牌局纪录"); case .trends: L("趋势") } }
    var icon: String { switch self { case .overview: "square.grid.2x2"; case .games: "list.bullet.rectangle"; case .deals: "number.square"; case .trends: "chart.bar" } }
}

@MainActor
private struct StatisticsView: View {
    let session: GameSession
    @State private var tab: StatisticsTab = .overview
    @State private var filter = "all"
    @State private var search = ""
    @State private var page = 1
    @State private var filterByDate = false
    @State private var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo = Date()
    @State private var detail: StatisticsGame?
    @State private var imported: StatisticsDatabase?
    @State private var importError: String?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var trendRange = "weeks"
    @State private var trendMetric = "outcomes"
    @State private var dealSort = "count"
    @State private var noAssistOnly = false

    private var store: StatisticsStore { session.statistics }
    private var matchingGames: [StatisticsGame] {
        store.games.filter { game in
            let resultMatches = filter == "all" || (filter == "won" && game.outcome == .won) || (filter == "abandoned" && game.outcome == .abandoned) || (filter == "unsettled" && (game.outcome == .inProgress || game.outcome == .recordOnly))
            let assistMatches = !noAssistOnly || game.isNoAssistWin
            let lowerDay = StatisticsDatabase.day(dateFrom); let upperDay = StatisticsDatabase.day(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo)) ?? dateTo)
            let dateMatches = !filterByDate || (game.startedLocalDay >= lowerDay && game.startedLocalDay < upperDay)
            return resultMatches && assistMatches && dateMatches && (search.isEmpty || game.seed == search.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    private var pageGames: [StatisticsGame] { Array(matchingGames.prefix(page * 50)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(StatisticsTab.allCases, id: \.self) { value in
                    Button { tab = value } label: {
                        Label(value.title, systemImage: value.icon).frame(maxWidth: .infinity).padding(.vertical, 9)
                    }.buttonStyle(.plain).background(tab == value ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityAddTraits(tab == value ? .isSelected : [])
                }
            }.padding(.horizontal, 20).padding(.top, 12)
            Divider().padding(.top, 10)
            Group {
                switch tab {
                case .overview: overview
                case .games: gamesPage
                case .deals: dealsPage
                case .trends: trendsPage
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if session.archive.statisticsExcluded { Label(L("当前牌局未计入；下一局或重开后开始记录。"), systemImage: "info.circle").foregroundStyle(.secondary) }
                if let error = store.errorMessage ?? importError { Label(localized(error), systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2) }
                if isImporting {
                    ProgressView(L("正在读取统计文件…"))
                    Button(L("取消读取")) { importTask?.cancel(); importTask = nil; isImporting = false }
                }
                if isExporting { ProgressView(L("正在导出统计…")) }
                Spacer()
                Button(L("打开数据目录")) { store.revealDataFolder() }
                Button(L("导出…")) { exportStatistics() }
                Button(L("导入…")) { importStatistics() }
                Button(L("重置统计…"), role: .destructive) {
                    StatisticsWindowController.confirm(title: L("重置所有统计？"), message: L("所有统计、对局记录、趋势和个人纪录将被清除。当前牌局和游戏设置保留。"), confirmTitle: L("重置统计")) {
                        let identity = session.archive.statisticsID ?? UUID()
                        do { try store.reset(excluding: identity, seed: session.archive.seed, algorithm: session.archive.algorithmVersion); session.excludeCurrentGameFromStatistics(identity: identity) }
                        catch { importError = L("统计数据保存失败；原有统计仍保留。") }
                    }
                }
            }.buttonStyle(.bordered).controlSize(.small).padding(14)
        }
        .background(.background)
        .sheet(item: $detail) { game in detailSheet(game) }
        .alert(L("导入统计"), isPresented: Binding(get: { imported != nil }, set: { _ in })) {
            Button(L("取消"), role: .cancel) { imported = nil }
            Button(L("合并")) { applyImport(replace: false) }
            Button(L("替换…"), role: .destructive) {
                DispatchQueue.main.async {
                    StatisticsWindowController.confirm(title: L("替换当前统计？"), message: L("当前统计将被替换，当前牌局与设置保留。"), confirmTitle: L("替换"), extraTitle: L("先导出当前统计…"), onExtra: { exportStatistics() }, onConfirm: { applyImport(replace: true) }, onCancel: { imported = nil })
                }
            }
        } message: { Text(importPreviewText) }
        .onChange(of: search) { _, _ in page = 1 }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if store.games.isEmpty {
                    ContentUnavailableView(L("完成一局，开始积累你的记录。"), systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    let s = store.summary
                    HStack(spacing: 14) {
                        metricCard(L("胜率"), s.winRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—", subtitle: L("胜率仅计算已结束对局"), prominent: true)
                        metricCard(L("总对局"), "\(s.started)", subtitle: L("胜利 %@ · 放弃 %@", "\(s.wins)", "\(s.abandoned)"))
                        let localOngoing = store.database.games.filter { $0.outcome == .inProgress }.count
                        metricCard(L("未结算"), "\(s.unsettled)", subtitle: L("本机进行中 %@ · 外部记录 %@", "\(localOngoing)", "\(s.unsettled - localOngoing)"))
                    }
                    Toggle(L("显示无辅助纪录"), isOn: $noAssistOnly).toggleStyle(.switch).frame(maxWidth: 260)
                    sectionTitle(L(noAssistOnly ? "无辅助个人纪录" : "个人纪录"))
                    HStack(spacing: 14) {
                        if noAssistOnly {
                            metricCard(L("无辅助胜局"), "\(s.noAssistWins)", subtitle: L("完整资格记录"))
                            recordCard(L("无辅助最少步数"), s.noAssistBestMoves.map { "\($0.moves)" } ?? "—", game: s.noAssistBestMoves)
                            recordCard(L("无辅助最快用时"), s.noAssistFastest.map { Self.duration($0.seconds) } ?? "—", game: s.noAssistFastest)
                        } else {
                            recordCard(L("最少步数"), s.bestMoves.map { "\($0.moves)" } ?? "—", game: s.bestMoves)
                            recordCard(L("最快用时"), s.fastest.map { Self.duration($0.seconds) } ?? "—", game: s.fastest)
                            metricCard(L("最高连胜"), "\(s.bestStreak)", subtitle: L("当前连胜 %@", "\(s.currentStreak)"))
                        }
                    }
                    sectionTitle(L("游玩习惯"))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(L("平均步数"), s.averageMoves.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", subtitle: L("仅统计胜局"))
                        metricCard(L("平均用时"), s.averageSeconds.map(Self.duration) ?? "—", subtitle: L("仅统计胜局"))
                        metricCard(L("累计时间"), Self.longDuration(s.cumulativeSeconds), subtitle: L("所有已登记尝试"))
                        metricCard(L("连续游玩天数"), "\(s.currentDays) / \(s.bestDays)", subtitle: L("当前 / 最长"))
                        metricCard(L("提示 · 撤销"), "\(s.hints) · \(s.undos)", subtitle: L("记录的辅助操作"))
                        metricCard(L("重做 · 重开"), "\(s.redos) · \(s.restarts)", subtitle: L("记录的牌局操作"))
                    }
                    Text(L("连续天数按本地自然日计算；首次有效操作后开始记录。统计开始于 %@。", store.database.periodStartedAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22)
        }
    }

    private var gamesPage: some View {
        VStack(spacing: 10) {
            HStack {
                TextField(L("搜索牌局编号"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker(L("结果"), selection: $filter) {
                    Text(L("全部")).tag("all"); Text(L("胜利")).tag("won"); Text(L("放弃")).tag("abandoned"); Text(L("未结算")).tag("unsettled")
                }.frame(width: 150)
                Toggle(L("无辅助"), isOn: $noAssistOnly).toggleStyle(.checkbox)
                Toggle(L("日期范围"), isOn: $filterByDate).toggleStyle(.checkbox)
                if filterByDate {
                    DatePicker(L("从"), selection: $dateFrom, displayedComponents: .date).labelsHidden().frame(width: 125)
                    DatePicker(L("到"), selection: $dateTo, displayedComponents: .date).labelsHidden().frame(width: 125)
                }
                Spacer(); Text(L("共 %@ 局", "\(matchingGames.count)")).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.top, 14)
            if matchingGames.isEmpty { ContentUnavailableView(L("没有符合条件的记录"), systemImage: "line.3.horizontal.decrease.circle") }
            else {
                List(pageGames) { game in
                    Button { detail = game } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("#\(game.seed)").font(.system(.body, design: .monospaced))
                Text(Self.localizedDay(game.startedLocalDay)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(outcomeTitle(game)).frame(width: 90, alignment: .trailing)
                            Text(game.outcome == .recordOnly ? "—" : L("%@ 步", "\(game.moves)")).frame(width: 80, alignment: .trailing)
                            Text(game.outcome == .recordOnly ? "—" : Self.duration(game.seconds)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            if game.isNoAssistWin { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help(L("无辅助胜局")) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.inset)
                if pageGames.count < matchingGames.count { Button(L("加载更多")) { page += 1 }.padding(.bottom, 8) }
            }
        }
    }

    private var dealsPage: some View {
        VStack(spacing: 10) {
            HStack { Text(L("按洗牌版本与牌局编号汇总挑战成绩。" )).foregroundStyle(.secondary); Spacer(); Picker(L("排序"), selection: $dealSort) { Text(L("挑战次数")).tag("count"); Text(L("最近挑战")).tag("recent"); Text(L("牌局编号")).tag("seed") }.frame(width: 150); TextField(L("搜索牌局编号"), text: $search).textFieldStyle(.roundedBorder).frame(width: 220) }.padding(.horizontal, 18).padding(.top, 14)
            List(sortedDealGroups.filter { search.isEmpty || $0.seed == search.trimmingCharacters(in: .whitespacesAndNewlines) }) { group in
                DisclosureGroup {
                    ForEach(group.games.sorted { $0.startedAt > $1.startedAt }) { game in
                        HStack { Text(game.startedAt.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(outcomeTitle(game)); Text(game.outcome == .won ? L("%@ 步", "\(game.moves)") : "—"); if game.isNoAssistWin { Text(L("无辅助")) } }
                            .font(.caption).contentShape(Rectangle()).onTapGesture { detail = game }
                    }
                } label: {
                        HStack {
                        VStack(alignment: .leading) { Text("#\(group.seed)").font(.system(.body, design: .monospaced)); Text(L("洗牌版本 %@", "\(group.algorithmVersion)")).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(L("挑战 %@ 次", "\(group.games.count)")); Text(L("胜利 %@", "\(group.wins)"));
                        Text(group.best.map { L("最少 %@ 步", "\($0.moves)") } ?? L("最少 —"));
                        let unassisted = group.games.filter(\.isNoAssistWin)
                        Text(L("无辅助 %@ / %@", unassisted.min { $0.moves < $1.moves }.map { "\($0.moves)" } ?? "—", unassisted.min { $0.seconds < $1.seconds }.map { Self.duration($0.seconds) } ?? "—")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.listStyle(.inset)
        }
    }

    private var trendsPage: some View {
        let data = trendData
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker(L("趋势范围"), selection: $trendRange) { Text(L("最近 8 周")).tag("weeks"); Text(L("最近 12 个月")).tag("months") }.pickerStyle(.segmented).frame(maxWidth: 360)
                Picker(L("指标"), selection: $trendMetric) { Text(L("对局结果")).tag("outcomes"); Text(L("胜率")).tag("rate"); Text(L("时间" )).tag("time") }.pickerStyle(.segmented).frame(maxWidth: 330)
            }.padding(.horizontal, 20).padding(.top, 16)
            if data.isEmpty { ContentUnavailableView(L("完成一局，开始积累你的记录。"), systemImage: "chart.bar.xaxis") }
            else {
                Chart(data) { item in
                    if trendMetric == "outcomes" {
                        BarMark(x: .value(L("周期"), item.label), y: .value(L("胜利"), item.wins)).foregroundStyle(Color.green.gradient).position(by: .value(L("结果"), L("胜利")))
                        BarMark(x: .value(L("周期"), item.label), y: .value(L("放弃"), item.abandoned)).foregroundStyle(Color.orange.gradient).position(by: .value(L("结果"), L("放弃")))
                    } else if trendMetric == "rate", let rate = item.rate {
                        LineMark(x: .value(L("周期"), item.label), y: .value(L("胜率"), rate)).foregroundStyle(Color.blue).symbol(.circle)
                    } else if trendMetric == "time" {
                        BarMark(x: .value(L("周期"), item.label), y: .value(L("时间"), item.seconds / 3600)).foregroundStyle(Color.teal.gradient)
                    }
                }.frame(height: 270).padding(.horizontal, 22).accessibilityLabel(L("每周期胜利与放弃数量图表"))
                Table(data) {
                    TableColumn(L("周期"), value: \.label)
                    TableColumn(L("开始")) { Text("\($0.started)") }
                    TableColumn(L("胜利")) { Text("\($0.wins)") }
                    TableColumn(L("放弃")) { Text("\($0.abandoned)") }
                    TableColumn(L("胜率")) { Text($0.rate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—") }
                    TableColumn(L("时间")) { Text(Self.longDuration($0.seconds)) }
                    TableColumn(L("活跃天数")) { Text("\($0.activeDays)") }
                }.padding(.horizontal, 18)
            }
            Spacer(minLength: 0)
        }
    }

    private var trendData: [TrendPoint] {
        var calendar = Calendar.current; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let now = Date()
        if trendRange == "weeks" {
            let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (0..<8).compactMap { offset in
                guard let start = calendar.date(byAdding: .weekOfYear, value: offset - 7, to: monday), let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
                return makeTrend(start: start, end: end, label: start.formatted(.dateTime.month(.abbreviated).day()))
            }
        }
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return (0..<12).compactMap { offset in guard let start = calendar.date(byAdding: .month, value: offset - 11, to: month), let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }; return makeTrend(start: start, end: end, label: start.formatted(.dateTime.year().month(.abbreviated))) }
    }
    private var sortedDealGroups: [DealStatistics] {
        switch dealSort {
        case "recent": store.dealGroups.sorted { ($0.games.map(\.startedAt).max() ?? .distantPast) > ($1.games.map(\.startedAt).max() ?? .distantPast) }
        case "seed": store.dealGroups.sorted { $0.seed.localizedStandardCompare($1.seed) == .orderedAscending }
        default: store.dealGroups
        }
    }
    private func makeTrend(start: Date, end: Date, label: String) -> TrendPoint {
        let startDay = StatisticsDatabase.day(start); let endDay = StatisticsDatabase.day(end)
        let games = store.database.games
        let started = games.filter { $0.startedLocalDay >= startDay && $0.startedLocalDay < endDay }.count
        let settled = games.filter { ($0.outcome == .won || $0.outcome == .abandoned) && ($0.settledLocalDay ?? "") >= startDay && ($0.settledLocalDay ?? "") < endDay }
        let wins = settled.filter { $0.outcome == .won }.count; let abandoned = settled.count - wins
        let events = store.database.events.filter { $0.localDay >= startDay && $0.localDay < endDay }
        return TrendPoint(label: label, started: started, wins: wins, abandoned: abandoned,
                          rate: settled.isEmpty ? nil : Double(wins) / Double(settled.count),
                          seconds: events.reduce(0) { $0 + $1.seconds }, activeDays: Set(events.filter { $0.kind != .playTime && $0.kind != .hint }.map(\.localDay)).count)
    }

    private func detailSheet(_ game: StatisticsGame) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text(L("对局详情")).font(.title2.bold()); Spacer(); Button(L("关闭")) { detail = nil }.keyboardShortcut(.cancelAction) }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                detailRow(L("牌局编号"), game.seed); detailRow(L("洗牌版本"), "\(game.algorithmVersion)")
                detailRow(L("状态"), outcomeTitle(game)); detailRow(L("开始时间"), Self.localizedTimestamp(game.startedAt, timeZone: game.startedTimeZone))
                let hasPlayableProgress = game.outcome != .recordOnly
                detailRow(L("步数"), hasPlayableProgress ? "\(game.moves)" : "—"); detailRow(L("用时"), hasPlayableProgress ? Self.duration(game.seconds) : "—")
                detailRow(L("累计用时"), Self.longDuration(game.cumulativeSeconds)); detailRow(L("提示 / 撤销 / 重做"), "\(game.hints) / \(game.undos) / \(game.redos)")
                detailRow(L("重开 / 自动移牌 / 收牌"), "\(game.restarts) / \(game.automaticMoves) / \(game.manualCollections)")
                detailRow(L("自动收牌次数"), "\(store.database.events.filter { $0.gameID == game.id && $0.kind == .autoCollect }.count)")
                detailRow(L("无辅助资格"), game.isNoAssistWin ? L("符合") : localized(game.noAssistReason ?? (game.legacyUnknown ? "legacy" : "notWon")))
                if let settled = game.settledAt { detailRow(L("结束时间"), game.settledLocalDay.map(Self.localizedDay) ?? settled.formatted(date: .complete, time: .shortened)) }
            }
            if !game.attempts.isEmpty {
                Text(L("尝试记录")).font(.headline).padding(.top, 6)
                ForEach(Array(game.attempts.enumerated()), id: \.element.id) { index, attempt in
                    HStack { Text(L("第 %@ 次", "\(index + 1)")); Spacer(); Text(L("%@ 步", "\(attempt.moves)")); Text(Self.duration(attempt.seconds)); if attempt.endedAt == nil { Text(L("进行中")).foregroundStyle(.secondary) } }.font(.callout)
                }
            }
            HStack { Spacer(); Button(L("重新挑战此局")) {
                guard let seed = UInt64(game.seed) else { return }
                detail = nil
                if session.state.isWon { session.newGame(seed: seed) }
                else { ResetConfirmation.present(title: L("开始此牌局？")) { session.newGame(seed: seed) } }
            }.disabled(game.algorithmVersion != Dealer.algorithmVersion) }
        }.padding(24).frame(width: 540).background(.background)
    }
    private func detailRow(_ title: String, _ value: String) -> some View { GridRow { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    private func metricCard(_ title: String, _ value: String, subtitle: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(prominent ? .largeTitle : .title2, design: .rounded).weight(.semibold)).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1); Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
    private func recordCard(_ title: String, _ value: String, game: StatisticsGame?) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit(); if let game { Text(L("牌局 #%@", game.seed)).font(.caption2).foregroundStyle(.secondary); Text(game.settledLocalDay.map(Self.localizedDay) ?? "").font(.caption2).foregroundStyle(.secondary) } else { Text("—").font(.caption2) } }
            .frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.headline).padding(.top, 2) }
    private func outcomeTitle(_ game: StatisticsGame) -> String {
        switch game.outcome { case .won: L("胜利"); case .abandoned: L("放弃"); case .recordOnly: L("未结算（仅记录）"); case .inProgress: L("进行中") }
    }
    private var importPreviewText: String {
        guard let imported else { return "" }
        let days = imported.games.map(\.startedLocalDay).sorted()
        let range = days.first.map { first in days.last.map { L("%@ 至 %@", Self.localizedDay(first), Self.localizedDay($0)) } ?? Self.localizedDay(first) } ?? L("无日期记录")
        return L("记录 %@ 条，胜利 %@，未结算 %@。", "\(imported.games.count)", "\(imported.games.filter { $0.outcome == .won }.count)", "\(imported.games.filter { $0.outcome == .inProgress || $0.outcome == .recordOnly }.count)") + "\n" + L("日期范围：%@", range)
    }
    private func exportStatistics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "FreeCell-Statistics-\(StatisticsDatabase.day(Date())).json"; panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isExporting = true
            let snapshot = store.database
            Task.detached(priority: .userInitiated) {
                do { try StatisticsStore.writeExport(snapshot, to: url); await MainActor.run { importError = nil; isExporting = false } }
                catch { await MainActor.run { importError = L("导出失败，请检查目标文件夹权限。"); isExporting = false } }
            }
        }
    }
    private func importStatistics() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isImporting = true
            importTask = Task.detached(priority: .userInitiated) {
                do {
                    let incoming = try StatisticsStore.readImport(from: url)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { imported = incoming; importError = nil; isImporting = false; importTask = nil }
                } catch {
                    await MainActor.run { importError = L("导入文件无效、超出限制或与现有记录冲突。"); isImporting = false; importTask = nil }
                }
            }
        }
    }
    private func applyImport(replace: Bool) {
        guard let incoming = imported else { return }
        if !replace, let currentID = session.archive.statisticsID {
            let local = store.database.games.first(where: { $0.id == currentID })
            if let external = incoming.games.first(where: { $0.id == currentID }), local != external {
                importError = L("导入文件无效、超出限制或与现有记录冲突。"); imported = nil; return
            }
            if local == nil && incoming.games.contains(where: { $0.id == currentID }) {
                importError = L("导入文件无效、超出限制或与现有记录冲突。"); imported = nil; return
            }
        }
        do {
            if replace {
                let identity = session.archive.statisticsID ?? UUID()
                try store.replace(with: incoming, excluding: identity, seed: session.archive.seed, algorithm: session.archive.algorithmVersion)
                session.excludeCurrentGameFromStatistics(identity: identity)
            } else { try store.merge(incoming) }
            imported = nil; importError = nil
        }
        catch { importError = L("导入文件无效、超出限制或与现有记录冲突。"); imported = nil }
    }
    private static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded())); return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
    private static func longDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60)); let hours = minutes / 60; return hours > 0 ? L("%@ 小时 %@ 分", "\(hours)", "\(minutes % 60)") : L("%@ 分", "\(minutes)")
    }
    private static func localizedDay(_ day: String) -> String {
        guard let date = StatisticsDatabase.parseDay(day) else { return day }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: GameLocalization.shared.language.rawValue)
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium; formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    private static func localizedTimestamp(_ date: Date, timeZone: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: GameLocalization.shared.language.rawValue)
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current; formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct TrendPoint: Identifiable { var id: String { label }; let label: String; let started: Int; let wins: Int; let abandoned: Int; let rate: Double?; let seconds: Double; let activeDays: Int }
