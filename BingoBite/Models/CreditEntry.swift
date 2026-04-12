import Foundation

/// A single performance credit (e.g., "Guitar" played by ["Person A"]).
struct CreditEntry: Codable, Hashable {
    let role: String
    let artists: [String]
}
