import Foundation

/// A song relationship entry (samples, sampled_in, cover_of, etc.).
struct SongRelationshipEntry: Codable, Hashable {
    let type: String
    let title: String
    let artist: String
}
