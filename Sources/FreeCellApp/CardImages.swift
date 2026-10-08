import AppKit
import FreeCellCore

@MainActor
final class CardImages {
    static let shared = CardImages()
    private var images: [Int: NSImage] = [:]
    private(set) var missingNames: [String] = []
    private init() {
        let resources = GameResources.bundle
        for card in Card.deck {
            if let url = resources.url(forResource: String(card.id), withExtension: "png", subdirectory: "Cards"),
               let image = NSImage(contentsOf: url) { images[card.id] = image }
            else { missingNames.append(card.name) }
        }
    }
    func image(for card: Card) -> NSImage? { images[card.id] }
}
