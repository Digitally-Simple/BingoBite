import Foundation

/// Resolves the bundled `ffprobe` binary shipped inside the app's
/// `Contents/Resources/bin` directory.
enum BinaryLocator {
    static let ffprobe: URL = locate("ffprobe")

    private static func locate(_ name: String) -> URL {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "bin"
        ) else {
            fatalError("Bundled binary missing: \(name). Add ffprobe to Resources/bin and ensure the 'Copy & Sign' build phase runs.")
        }
        return url
    }
}
