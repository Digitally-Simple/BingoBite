import Foundation
import SwiftData

@Model
final class Playlist {
    var uuid: String = ""
    var name: String = ""
    var descriptionText: String = ""
    var creationDate: Date = Date()
    var folderPath: String = ""
    var bookmarkData: Data = Data()
    var songKeys: [String] = []
    var numberOfCards: Int = 0
    var hasFreeSpace: Bool = true
    var cardsData: Data = Data()
    var coverArtData: Data? = nil
    var cardDesignData: Data? = nil

    /// Short code identifying this deck of printed cards, e.g. `AB`.
    ///
    /// Cards print as `AB-1`, `AB-2`… so that when several decks get shuffled
    /// together on a table they can be sorted back apart, and you can tell
    /// which deck a given card number belongs to.
    var setID: String = ""

    /// Letters used in generated set codes.
    ///
    /// `I`, `O` and `Q` are left out — these are read off paper in a dim room
    /// and get confused with `1` and `0`.
    static let setIDAlphabet = Array("ABCDEFGHJKLMNPRSTUVWXYZ")

    /// A two-letter code not already used by `existing`.
    ///
    /// 23 letters gives 529 combinations, far more than anyone will have
    /// playlists; the loop falls back to a three-letter code rather than spin
    /// forever in the impossible case that they're all taken.
    static func generateSetID(avoiding existing: Set<String>) -> String {
        for _ in 0..<200 {
            let candidate = String((0..<2).map { _ in setIDAlphabet.randomElement()! })
            if !existing.contains(candidate) { return candidate }
        }
        for _ in 0..<200 {
            let candidate = String((0..<3).map { _ in setIDAlphabet.randomElement()! })
            if !existing.contains(candidate) { return candidate }
        }
        return String((0..<4).map { _ in setIDAlphabet.randomElement()! })
    }

    /// How a card in this deck is labelled, honouring the print settings.
    /// Returns nil when card numbers are switched off entirely.
    func cardLabel(number: Int, settings: CardDesignSettings) -> String? {
        guard settings.showCardNumbers else { return nil }
        guard settings.showSetID, !setID.isEmpty else { return "Card #\(number)" }
        return "\(setID)-\(number)"
    }

    var songCount: Int {
        songKeys.count
    }

    init(
        uuid: String = UUID().uuidString,
        name: String,
        descriptionText: String = "",
        folderPath: String,
        bookmarkData: Data,
        songKeys: [String],
        numberOfCards: Int,
        hasFreeSpace: Bool,
        cardsData: Data,
        coverArtData: Data? = nil,
        cardDesignData: Data? = nil,
        creationDate: Date = Date()
    ) {
        self.uuid = uuid
        self.name = name
        self.descriptionText = descriptionText
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.songKeys = songKeys
        self.numberOfCards = numberOfCards
        self.hasFreeSpace = hasFreeSpace
        self.cardsData = cardsData
        self.coverArtData = coverArtData
        self.cardDesignData = cardDesignData
        self.creationDate = creationDate
    }
}
