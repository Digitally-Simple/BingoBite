import Foundation

/// Resolves the bundled `ffmpeg` binary shipped inside the app's
/// `Contents/Resources/bin` directory.
enum BinaryLocator {
    static let ffmpeg: URL = locate("ffmpeg")

    private static func locate(_ name: String) -> URL {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "bin"
        ) else {
            fatalError("Bundled binary missing: \(name). Add ffmpeg to Resources/bin and ensure the 'Copy & Sign' build phase runs.")
        }
        return url
    }
}
