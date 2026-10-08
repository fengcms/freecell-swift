import Foundation

/// Prefer the packaged bundle; SwiftPM's generated accessor also has a development build path.
enum GameResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FreeCell_FreeCellApp.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return Bundle.module
    }()
}
