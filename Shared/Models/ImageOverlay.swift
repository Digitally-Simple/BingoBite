import Foundation
import SwiftUI

struct ImageOverlay: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var imageData: Data
    var normalizedX: CGFloat = 0.5
    var normalizedY: CGFloat = 0.5
    var normalizedScale: CGFloat = 0.25
    var opacity: CGFloat = 1.0
    var label: String = "Image"

    // MARK: - Image Cache

    private static let imageCache = NSCache<NSString, PlatformImage>()

    var cachedImage: PlatformImage? {
        let key = id as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return cached
        }
        guard let image = PlatformImage(data: imageData) else { return nil }
        Self.imageCache.setObject(image, forKey: key)
        return image
    }

    static func clearCache(for id: String) {
        imageCache.removeObject(forKey: id as NSString)
    }

    // MARK: - Import Helper

    /// Downsamples the image to max 1024px on the longest side and returns PNG data.
    static func downsampledData(from url: URL, maxDimension: CGFloat = 1024) -> Data? {
        ImageDownsampler.downsampledPNG(from: url, maxDimension: maxDimension)
    }

    /// Downsamples in-memory image bytes (used by the iPad photo/file pickers).
    static func downsampledData(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        ImageDownsampler.downsampledPNG(from: data, maxDimension: maxDimension)
    }
}
