import Foundation
import AppKit

struct ImageOverlay: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var imageData: Data
    var normalizedX: CGFloat = 0.5
    var normalizedY: CGFloat = 0.5
    var normalizedScale: CGFloat = 0.25
    var opacity: CGFloat = 1.0
    var label: String = "Image"

    // MARK: - Image Cache

    private static let imageCache = NSCache<NSString, NSImage>()

    var cachedImage: NSImage? {
        let key = id as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(data: imageData) else { return nil }
        Self.imageCache.setObject(image, forKey: key)
        return image
    }

    static func clearCache(for id: String) {
        imageCache.removeObject(forKey: id as NSString)
    }

    // MARK: - Import Helper

    /// Downsamples the image to max 1024px on the longest side and returns PNG data.
    static func downsampledData(from url: URL, maxDimension: CGFloat = 1024) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}
