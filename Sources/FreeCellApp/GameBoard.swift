import AppKit
import SwiftUI
import FreeCellCore
import FreeCellPresentation

struct GameBoard: NSViewRepresentable {
    let state: GameState
    let selection: Int?
    let hint: Move?
    let version: Int
    let animationRequest: BoardAnimationRequest?
    let enabled: Bool
    let reduceMotion: Bool
    let animationSpeed: AnimationSpeed
    let automaticMoveGesture: AutomaticMoveGesture
    let onCardClick: (Card, Location) -> Void
    let onEmptyClick: (Location) -> Void
    let onDoubleClick: (Int) -> Bool
    let onMove: (Int, Location) -> Bool
    let onCancel: () -> Void

    func makeNSView(context: Context) -> BoardSurface { BoardSurface() }
    func updateNSView(_ view: BoardSurface, context: Context) {
        view.onCardClick = onCardClick; view.onEmptyClick = onEmptyClick
        view.onDoubleClick = onDoubleClick; view.onMove = onMove; view.onCancel = onCancel
        view.update(state: state, selection: selection, hint: hint, version: version, animationRequest: animationRequest, enabled: enabled, reduceMotion: reduceMotion, animationSpeed: animationSpeed, automaticMoveGesture: automaticMoveGesture)
    }
    static func dismantleNSView(_ view: BoardSurface, coordinator: ()) { view.cancelInteraction() }
}

/// Window-local dragging avoids the system's translucent drag image. The rules state is committed only on release.
@MainActor
final class BoardSurface: NSView {
    var onCardClick: ((Card, Location) -> Void)?
    var onEmptyClick: ((Location) -> Void)?
    var onDoubleClick: ((Int) -> Bool)?
    var onMove: ((Int, Location) -> Bool)?
    var onCancel: (() -> Void)?

    private var state: GameState?
    private var selection: Int?
    private var hint: Move?
    private var version = 0
    private var enabled = true
    private var reduceMotion = false
    private var animationSpeed: AnimationSpeed = .medium
    private var automaticMoveGesture: AutomaticMoveGesture = .doubleClick
    private var press: Press?
    private var drag: Drag?
    private var clickTask: Task<Void, Never>?
    private var pendingClick: (Item, Int)?
    private var feedbackTask: Task<Void, Never>?
    private var feedbackCardID: Int?
    private var feedbackStart: TimeInterval = 0
    private var motion: BoardMotionSequence?
    private var motionStart: TimeInterval = 0
    private var motionTask: Task<Void, Never>?
    private var lastAnimationID: Int?
    private var pendingVictory = false
    private var victoryStart: TimeInterval?
    private var victoryTask: Task<Void, Never>?
    private var focusedIndex: Int?
    private var accessibleCards: [String: BoardAccessibilityElement] = [:]
    private let gold = NSColor(calibratedRed: 0.91, green: 0.77, blue: 0.46, alpha: 1)

    private struct Item: Sendable {
        let card: Card?
        let location: Location
        let frame: CGRect
        let visibleHeight: CGFloat
        var key: String { card.map { "card-\($0.id)" } ?? "slot-\(location)" }
    }
    private struct Press {
        let item: Item
        let point: CGPoint
        let doubleClick: Bool
    }
    private struct Drag {
        let selected: CardSelection
        let origin: CGPoint
        let anchor: CGPoint
        let version: Int
        let spacing: CGFloat
        var pointer: CGPoint
        var hiddenIDs: Set<Int> { Set(selected.cards.map(\.id)) }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { enabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var layout: BoardLayout {
        BoardLayout(size: bounds.size, columnCounts: motion?.maximumColumnCounts ?? state?.tableau.map(\.count) ?? [])
    }

    func update(state: GameState, selection: Int?, hint: Move?, version: Int,
                animationRequest: BoardAnimationRequest?, enabled: Bool, reduceMotion: Bool, animationSpeed: AnimationSpeed, automaticMoveGesture: AutomaticMoveGesture) {
        let wonNow = state.isWon && self.state?.isWon != true
        if self.version != version || !enabled || self.animationSpeed != animationSpeed || self.automaticMoveGesture != automaticMoveGesture { cancelInteraction() }
        let oldFocus = focusedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let previousState = self.state
        let changed = self.state != state
        self.state = state; self.selection = selection; self.hint = hint
        self.version = version; self.enabled = enabled; self.reduceMotion = reduceMotion || animationSpeed == .none
        self.animationSpeed = animationSpeed; self.automaticMoveGesture = automaticMoveGesture
        if changed, let oldFocus {
            let current = items.first(where: { $0.key == oldFocus.key })
            if let current, case .tableau(let column) = current.location,
               current.location != oldFocus.location || previousState?.tableau[column] != state.tableau[column] {
                focusedIndex = items.lastIndex(where: { $0.location == .tableau(column) })
            } else if case .tableau(let column) = oldFocus.location,
                      previousState?.tableau[column] != state.tableau[column] {
                focusedIndex = items.lastIndex(where: { $0.location == .tableau(column) })
            } else { focusedIndex = items.firstIndex(where: { $0.key == oldFocus.key }) }
        }
        if let request = animationRequest, request.id != lastAnimationID {
            lastAnimationID = request.id
            if enabled && !self.reduceMotion {
                let sequence = BoardMotionSequence(states: request.states, speed: animationSpeed)
                if !sequence.steps.isEmpty { startMotion(sequence, celebrate: wonNow) }
            }
        }
        if wonNow && motion == nil && enabled { startVictory() }
        if self.reduceMotion { stopMotion(); stopVictory() }
        needsDisplay = true
        refreshAccessibility()
    }
    override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize { cancelInteraction() }
        super.setFrameSize(newSize)
        needsDisplay = true
        refreshAccessibility()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAccessibility() }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { cancelInteraction(); needsDisplay = true; return true }

    func cancelInteraction() {
        clickTask?.cancel(); clickTask = nil; pendingClick = nil
        if drag != nil { NSCursor.arrow.set() }
        press = nil; drag = nil
        stopMotion(); stopVictory()
        feedbackTask?.cancel(); feedbackTask = nil; feedbackCardID = nil
        needsDisplay = true
    }

    private var items: [Item] {
        guard let state else { return [] }
        let layout = layout
        var result: [Item] = []
        for index in 0..<4 {
            result.append(Item(card: state.cells[index], location: .cell(index), frame: layout.slotFrame(index), visibleHeight: layout.cardSize.height))
        }
        for suit in Suit.allCases {
            result.append(Item(card: state.foundations[suit.rawValue].last, location: .foundation(suit), frame: layout.slotFrame(suit.rawValue + 4), visibleHeight: layout.cardSize.height))
        }
        for index in 0..<8 {
            let cards = state.tableau[index]
            if cards.isEmpty {
                result.append(Item(card: nil, location: .tableau(index), frame: layout.cardFrame(column: index, offset: 0), visibleHeight: layout.cardSize.height))
            }
            for (offset, card) in cards.enumerated() {
                result.append(Item(card: card, location: .tableau(index), frame: layout.cardFrame(column: index, offset: offset),
                                   visibleHeight: offset == cards.count - 1 ? layout.cardSize.height : layout.spacing(for: index)))
            }
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let current = state else { return }
        let motionFrame = motion?.frame(at: ProcessInfo.processInfo.systemUptime - motionStart)
        let state = motionFrame?.state ?? current
        let layout = layout
        let hidden = (drag?.hiddenIDs ?? []).union(motionFrame?.flights.map { $0.card.id } ?? [])
        let dropTarget = drag.flatMap { layout.dropTarget(at: $0.pointer) }
        for index in 0..<8 {
            let location: Location = index < 4 ? .cell(index) : .foundation(Suit.allCases[index - 4])
            drawSlot(layout.slotFrame(index), symbol: index < 4 ? "·" : Suit.allCases[index - 4].symbol, highlighted: hint?.destination == location)
            let card: Card?
            if index < 4 { card = state.cells[index] }
            else {
                let stack = state.foundations[index - 4]
                card = stack.last(where: { !hidden.contains($0.id) })
            }
            if let card, !hidden.contains(card.id) {
                drawCard(card, in: layout.slotFrame(index), selected: isSelected(card), highlighted: hint?.destination == location)
            }
        }
        for index in 0..<8 {
            let frame = layout.cardFrame(column: index, offset: 0)
            drawSlot(frame, symbol: "", highlighted: hint?.destination == .tableau(index))
            for (offset, card) in state.tableau[index].enumerated() where !hidden.contains(card.id) {
                drawCard(card, in: layout.cardFrame(column: index, offset: offset), selected: isSelected(card), highlighted: hint?.destination == .tableau(index))
            }
        }
        if let target = dropTarget, let drag {
            let move = Move(from: drag.selected.source, to: target, count: drag.selected.cards.count)
            let legal = (try? Rules.validate(move, in: state)) != nil
            let targetFrame: CGRect
            switch target {
            case .cell(let index): targetFrame = layout.slotFrame(index)
            case .foundation(let suit): targetFrame = layout.slotFrame(suit.rawValue + 4)
            case .tableau(let index): targetFrame = layout.columnFrame(index, cardCount: state.tableau[index].count)
            }
            (legal ? gold : .systemRed).setStroke()
            let path = NSBezierPath(roundedRect: targetFrame.insetBy(dx: -2, dy: -2), xRadius: layout.cornerRadius + 2, yRadius: layout.cornerRadius + 2)
            path.lineWidth = 2; path.stroke()
        }
        if let drag {
            let proposed = CGPoint(x: drag.origin.x + drag.pointer.x - drag.anchor.x, y: drag.origin.y + drag.pointer.y - drag.anchor.y)
            let origin = layout.clampedDragOrigin(proposed, cardCount: drag.selected.cards.count, overlap: drag.spacing)
            for (offset, card) in drag.selected.cards.enumerated() {
                drawCard(card, in: CGRect(origin: CGPoint(x: origin.x, y: origin.y + CGFloat(offset) * drag.spacing), size: layout.cardSize), selected: false, highlighted: false)
            }
        }
        if let frame = motionFrame {
            for flight in frame.flights {
                drawCard(flight.card, in: flight.frame(progress: frame.progress, in: layout), selected: false, highlighted: false)
            }
        }
        drawVictory()
        if window?.firstResponder === self, drag == nil, motion == nil, let focusedIndex, items.indices.contains(focusedIndex) {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let frame = items[focusedIndex].frame
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: layout.cornerRadius + 2, yRadius: layout.cornerRadius + 2)
            path.lineWidth = 2; path.stroke()
        }
    }

    private func drawSlot(_ frame: CGRect, symbol: String, highlighted: Bool) {
        let path = NSBezierPath(roundedRect: frame, xRadius: layout.cornerRadius, yRadius: layout.cornerRadius)
        NSColor.white.withAlphaComponent(0.025).setFill(); path.fill()
        (highlighted ? gold : NSColor.white.withAlphaComponent(0.18)).setStroke()
        path.lineWidth = highlighted ? 3 : 1
        path.setLineDash([5, 5], count: 2, phase: 0); path.stroke()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let size = frame.width * 0.36
        (symbol as NSString).draw(in: CGRect(x: frame.minX, y: frame.midY - size * 0.6, width: frame.width, height: size * 1.4),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.white.withAlphaComponent(0.2), .paragraphStyle: style])
    }
    private func drawCard(_ card: Card, in originalFrame: CGRect, selected: Bool, highlighted: Bool) {
        var frame = originalFrame
        let shaking = feedbackCardID == card.id || feedbackContains(card)
        if shaking && !reduceMotion {
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - feedbackStart) / (0.36 * animationSpeed.durationMultiplier))
            frame.origin.x += sin(progress * .pi * 8) * (1 - progress) * 9
        }
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: frame, xRadius: layout.cornerRadius, yRadius: layout.cornerRadius)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: 2); shadow.set()
        NSColor(calibratedRed: 238.0 / 255, green: 228.0 / 255, blue: 207.0 / 255, alpha: 1).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // Fully opaque cards, including their backing; no native system drag preview is used.
        if let image = CardImages.shared.image(for: card) {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            (card.name as NSString).draw(in: frame, withAttributes: [.font: NSFont.systemFont(ofSize: max(10, frame.width * 0.18)), .foregroundColor: card.suit.isRed ? NSColor.systemRed : .black])
        }
        NSGraphicsContext.restoreGraphicsState()
        (shaking ? NSColor.systemRed : selected || highlighted ? gold : NSColor.black.withAlphaComponent(0.18)).setStroke()
        path.lineWidth = shaking || selected || highlighted ? 3 : 0.5; path.stroke()
    }
    private func isSelected(_ card: Card) -> Bool {
        guard let selection, let state, let selected = Rules.selection(for: selection, in: state) else { return false }
        return selected.cards.contains(card)
    }
    private func feedbackContains(_ card: Card) -> Bool {
        guard let id = feedbackCardID, let state, let selected = Rules.selection(for: id, in: state) else { return false }
        return selected.cards.contains(card)
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled, motion == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let item = items.reversed().first(where: { $0.frame.contains(point) }) else {
            cancelInteraction(); focusedIndex = nil; onCancel?(); return
        }
        if item.card == nil && selection == nil {
            cancelInteraction(); focusedIndex = nil; onCancel?(); return
        }
        if let pending = pendingClick {
            clickTask?.cancel(); clickTask = nil; pendingClick = nil
            if event.clickCount != 2 || automaticMoveGesture != .doubleClick || pending.0.key != item.key {
                if pending.1 == version { activate(pending.0) }
            }
        }
        window?.makeFirstResponder(self)
        focusedIndex = items.firstIndex(where: { $0.key == item.key }) ?? 0
        press = Press(item: item, point: point, doubleClick: event.clickCount == 2 && automaticMoveGesture == .doubleClick)
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) {
        guard enabled, motion == nil, automaticMoveGesture == .rightClick else { return }
        cancelInteraction()
        let point = convert(event.locationInWindow, from: nil)
        guard let item = items.reversed().first(where: { $0.frame.contains(point) }), let card = item.card else {
            focusedIndex = nil; onCancel?(); return
        }
        window?.makeFirstResponder(self)
        focusedIndex = items.firstIndex(where: { $0.key == item.key })
        if onDoubleClick?(card.id) != true { shake(card.id) }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, motion == nil, let press, let state, let card = press.item.card else { return }
        let point = convert(event.locationInWindow, from: nil)
        if drag == nil {
            guard hypot(point.x - press.point.x, point.y - press.point.y) >= 3 else { return }
            clickTask?.cancel(); clickTask = nil; pendingClick = nil
            guard let selected = Rules.selection(for: card.id, in: state), Rules.isOrdered(selected.cards) else {
                self.press = nil; shake(card.id); return
            }
            drag = Drag(selected: selected, origin: press.item.frame.origin, anchor: press.point, version: version, spacing: { if case .tableau(let index) = selected.source { return layout.spacing(for: index) }; return layout.spacing }(), pointer: point)
            NSCursor.closedHand.set()
        } else { drag?.pointer = point }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
        guard enabled, motion == nil, let press else { cancelInteraction(); return }
        self.press = nil
        if let drag {
            self.drag = nil
            let point = convert(event.locationInWindow, from: nil)
            if drag.version == version, let target = layout.dropTarget(at: point), let first = drag.selected.cards.first {
                if onMove?(first.id, target) != true { shake(first.id) }
            }
            needsDisplay = true
            return
        }
        guard press.item.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        if press.doubleClick, let card = press.item.card {
            if onDoubleClick?(card.id) != true { shake(card.id) }
        } else {
            let expectedVersion = version
            pendingClick = (press.item, expectedVersion)
            // Delay the commit so the first click of a double-click cannot perform a separate move.
            clickTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
                guard let self, self.enabled, self.motion == nil, self.version == expectedVersion else { return }
                self.pendingClick = nil
                self.activate(press.item)
                self.clickTask = nil
            }
        }
    }
    private func activate(_ item: Item) {
        guard enabled, motion == nil else { return }
        clickTask?.cancel(); clickTask = nil; pendingClick = nil
        if let card = item.card { onCardClick?(card, item.location) }
        else { onEmptyClick?(item.location) }
    }
    private func shake(_ cardID: Int) {
        feedbackTask?.cancel()
        feedbackCardID = cardID; feedbackStart = ProcessInfo.processInfo.systemUptime
        let pulses = max(1, Int(24 * animationSpeed.durationMultiplier))
        feedbackTask = Task { [weak self] in
            for _ in 0..<pulses {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                self.needsDisplay = true
            }
            self?.feedbackCardID = nil; self?.needsDisplay = true
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard enabled, motion == nil else { return }
        clickTask?.cancel(); clickTask = nil; pendingClick = nil
        let items = items
        guard !items.isEmpty else { return }
        switch event.keyCode {
        case 123, 124, 125, 126:
            let delta = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? 8 : -8
            focusedIndex = focusedIndex.map { ($0 + delta + items.count) % items.count } ?? 0
            needsDisplay = true
        case 49: if let focusedIndex { activate(items[focusedIndex]) }
        case 36, 76:
            if let focusedIndex, let card = items[focusedIndex].card, onDoubleClick?(card.id) != true { shake(card.id) }
        case 53: cancelInteraction(); focusedIndex = nil; onCancel?()
        default: super.keyDown(with: event)
        }
    }

    private func startMotion(_ sequence: BoardMotionSequence, celebrate: Bool) {
        stopMotion()
        motion = sequence; motionStart = ProcessInfo.processInfo.systemUptime
        pendingVictory = celebrate
        motionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self, let motion = self.motion else { return }
                self.needsDisplay = true
                if ProcessInfo.processInfo.systemUptime - self.motionStart >= motion.duration {
                    let celebrate = self.pendingVictory
                    self.motion = nil; self.motionTask = nil; self.pendingVictory = false
                    self.refreshAccessibility()
                    if celebrate && self.state?.isWon == true { self.startVictory() }
                    return
                }
            }
        }
    }
    private func stopMotion() {
        motionTask?.cancel(); motionTask = nil; motion = nil; pendingVictory = false
    }
    private func startVictory() {
        guard !reduceMotion else { return }
        stopVictory()
        victoryStart = ProcessInfo.processInfo.systemUptime
        let pulses = max(1, Int(210 * animationSpeed.durationMultiplier))
        victoryTask = Task { [weak self] in
            for _ in 0..<pulses {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                self.needsDisplay = true
            }
            self?.victoryStart = nil; self?.victoryTask = nil; self?.needsDisplay = true
        }
    }
    private func stopVictory() {
        victoryTask?.cancel(); victoryTask = nil; victoryStart = nil
    }
    private func drawVictory() {
        guard let start = victoryStart, !reduceMotion else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) / animationSpeed.durationMultiplier
        let colors: [NSColor] = [gold, .systemMint, .white, .systemOrange]
        for index in 0..<84 {
            let age = elapsed - Double(index) / 84 * 0.65
            guard age >= 0 && age < 2.6 else { continue }
            let slot = layout.slotFrame(4 + index % 4)
            let horizontal = CGFloat((index * 47) % 101 - 50) / 100
            let upward = CGFloat(0.26 + Double(index % 7) * 0.025)
            let x = slot.midX + horizontal * bounds.width * CGFloat(age)
            let y = slot.midY - upward * bounds.height * CGFloat(age) + 0.34 * bounds.height * CGFloat(age * age)
            let side = max(3, min(8, bounds.width / 150))
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: x, yBy: y); transform.rotate(byDegrees: CGFloat(age * 150 + Double(index * 19)))
            transform.concat()
            colors[index % colors.count].withAlphaComponent(min(1, (2.6 - age) / 0.6)).setFill()
            let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: index.isMultiple(of: 2) ? side : side * 0.45)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func refreshAccessibility() {
        setAccessibilityElement(false)
        setAccessibilityLabel("空当接龙牌桌")
        let children = items.map { item in
            let element = accessibleCards[item.key] ?? BoardAccessibilityElement { [weak self] in
                guard let self, let current = self.items.first(where: { $0.key == item.key }) else { return }
                self.activate(current)
            }
            accessibleCards[item.key] = element
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(item.card.map { $0.name + "，" + item.location.name } ?? item.location.name + "，空")
            element.setAccessibilityHelp("空格选牌或移动；回车按优先顺序自动移动")
            element.setAccessibilityEnabled(enabled && motion == nil)
            let visible = CGRect(x: item.frame.minX, y: item.frame.minY, width: item.frame.width, height: item.visibleHeight)
            element.setAccessibilityFrame(window?.convertToScreen(convert(visible, to: nil)) ?? .zero)
            return element
        }
        let keys = Set(items.map(\.key))
        accessibleCards = accessibleCards.filter { keys.contains($0.key) }
        setAccessibilityChildren(children)
    }
}

private final class BoardAccessibilityElement: NSAccessibilityElement {
    private let onPress: @MainActor @Sendable () -> Void
    init(onPress: @escaping @MainActor @Sendable () -> Void) {
        self.onPress = onPress
        super.init()
    }
    override func accessibilityPerformPress() -> Bool {
        let action = onPress
        Task { @MainActor in action() }
        return true
    }
}
