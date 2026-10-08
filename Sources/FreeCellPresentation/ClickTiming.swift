import Foundation

/// A complete second press must finish inside the first press's double-click window.
public enum ClickTiming {
    public static func isDoubleClick(firstDown: TimeInterval, secondUp: TimeInterval, interval: TimeInterval) -> Bool {
        let elapsed = secondUp - firstDown
        return elapsed >= 0 && elapsed <= interval
    }
}
