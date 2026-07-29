import SwiftUI
import ImageIO
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    /// Builds a SwiftUI `Image` from the platform's native image type.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// Decodes image data, returning nil for undecodable bytes.
    static func decode(_ data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }
}

// MARK: - Image downsampling

enum ImageDownsampler {
    /// Downsamples image data to `maxDimension` on the longest side and re-encodes as PNG.
    /// Uses ImageIO so it behaves identically on macOS and iOS.
    static func downsampledPNG(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func downsampledPNG(from url: URL, maxDimension: CGFloat = 1024) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return downsampledPNG(from: data, maxDimension: maxDimension)
    }
}

// MARK: - Available font families

enum PlatformFonts {
    /// Font families offered in the card designer, "System" first.
    static var families: [String] {
        #if os(macOS)
        ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
        #else
        ["System"] + UIFont.familyNames.sorted()
        #endif
    }
}
