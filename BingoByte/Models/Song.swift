import Foundation
import AppKit

struct Song: Identifiable, Hashable {
    var id: URL
    var fileName: String
    var fileSize: Int64
    var duration: TimeInterval?
    var artist: String?
    var title: String?
    var album: String?
    var artworkData: Data?

    var artworkImage: NSImage? {
        guard let data = artworkData else { return nil }
        return NSImage(data: data)
    }

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        return fileName
    }

    var formattedDuration: String {
        guard let duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}
