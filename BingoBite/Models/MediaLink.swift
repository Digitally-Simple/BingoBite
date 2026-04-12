import Foundation

/// A link to an external music service (Spotify, Apple Music, etc.).
struct MediaLink: Codable, Hashable {
    let provider: String
    let url: URL
}
