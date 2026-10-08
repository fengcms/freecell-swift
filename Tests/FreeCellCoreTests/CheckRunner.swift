import Foundation
import FreeCellCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ expression: @autoclosure () throws -> Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    guard try expression() else { throw CheckFailure(description: "\(file):\(line): expectation failed") }
}
func require<Value>(_ optional: Value?, file: StaticString = #fileID, line: UInt = #line) throws -> Value {
    guard let value = optional else { throw CheckFailure(description: "\(file):\(line): required value missing") }
    return value
}
func expectThrows(_ expected: GameError, file: StaticString = #fileID, line: UInt = #line, body: () throws -> some Any) throws {
    do { _ = try body() }
    catch let error as GameError {
        try expect(error == expected, file: file, line: line)
        return
    }
    throw CheckFailure(description: "\(file):\(line): expected \(expected)")
}
func expectAnyError(file: StaticString = #fileID, line: UInt = #line, body: () throws -> some Any) throws {
    do { _ = try body() } catch { return }
    throw CheckFailure(description: "\(file):\(line): expected an error")
}

@main
struct CheckRunner {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
    private static func log(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
    private static func run() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--write-pre-win-fixture" {
            try writePreWinFixture(from: URL(fileURLWithPath: CommandLine.arguments[2]), to: URL(fileURLWithPath: CommandLine.arguments[3]))
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--write-interaction-fixture" {
            try writeInteractionFixture(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--validate-archive" {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let archive = try JSONDecoder().decode(GameArchive.self, from: data)
            try archive.validate()
            log("PASS persisted archive: \(archive.cursor) moves, \(archive.current.foundations.flatMap { $0 }.count)/52 collected")
            return
        }

        let checks: [(String, () throws -> Void)] = [
            ("发牌与可复现性", dealAndDeterminism),
            ("洗牌版本固定牌序", shuffleVersionGoldenSequence),
            ("工作列、空当与非法操作", tableauAndCellMoves),
            ("接牌花色点数边界", { for (suit, rank) in [(Suit.clubs, 8), (.hearts, 8), (.clubs, 9), (.clubs, 6)] { try rejectWrongTableauTarget(suit, rank) } }),
            ("A与K不循环", aceKingDoesNotWrap),
            ("基础堆规则", foundationOrderAndLocking),
            ("整组容量与单牌移动证明", { for cells in 0...4 { try capacityAndSingleCardWitness(cells) } }),
            ("无空间及乱序牌组", noSpaceAndUnorderedGroups),
            ("保守收牌条件", safeCollectionConservativeCondition),
            ("完成与无合法动作", completionAndNoMoves),
            ("12个种子各80步的不变量与拆解", randomLegalPlayMaintainsInvariants),
            ("历史、自动收牌事务、存档往返", archiveHistoryRoundTripAndBranch),
            ("损坏存档与不支持版本", rejectCorruptArchive),
            ("完整52张发牌至胜利", completeFullGameFromDeal),
            ("手动收牌与历史篡改", archiveManualCollectAndHistoryCorruption),
            ("0至3个中转空列递归证明", multipleEmptyColumnsWitness),
            ("基础堆取回与合法边界", foundationReturnAndRoundTrip),
            ("双击目标优先级与最左目标", doubleClickPriority),
            ("双击整组及无目标", doubleClickGroupsAndNoTarget),
            ("基础堆取回历史与存档", returnedFoundationHistoryPersists),
            ("窗口比例及52张极长列完整适配", boardFitsEveryWindow),
            ("牌宽固定、底部预留及各列独立压缩", cardSizeStableAndColumnsCompressIndependently),
            ("绘制命中一致及牌龙拖动边界", boardHitTestingAndDragBounds),
            ("暂存牌双击不互换空当", storedCardDoubleClickSkipsCells),
            ("收牌动画序列顺序与终点", collectionTimelineAndBoundaries),
            ("动画坐标及窗口边界", collectionFlightCoordinates),
            ("整组动画保持牌龙间距", groupAnimationPreservesDragon)
        ]
        var failures = 0
        for (name, run) in checks {
            do { try run(); log("PASS \(name)") }
            catch { failures += 1; log("FAIL \(name): \(error)") }
        }
        guard failures == 0 else { throw CheckFailure(description: "\(failures) check groups failed") }
        log("All \(checks.count) check groups passed.")
    }
}
