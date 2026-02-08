import Foundation

struct BingoCard: Identifiable, Hashable {
    let id: Int       // 1-based card number
    let grid: [[Int]] // 5x5, values are 1-based song indices; 0 = free space
}
