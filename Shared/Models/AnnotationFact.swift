import Foundation

/// A single Genius annotation mapped to a lyrics fragment.
struct AnnotationFact: Codable, Sendable, Hashable {
    let fragment: String    // lyrics text being annotated
    let body: String        // annotation text
    let authors: String     // comma-separated author names
    let verified: Bool      // artist-verified annotation?
    let votes: Int          // total votes
}
