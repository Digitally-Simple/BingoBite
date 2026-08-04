import Foundation

/// Parses a pasted song list and matches each line against the library.
///
/// The wire format is written by Music Downloader's `PlaylistTextExporter`:
///
///     #BingoBite Playlist: 2000s Bangers
///     Outkast — Hey Ya! [u:ytdl-PWgvGjAhvIw]
///
/// Everything here is shaped by one fact: the text usually arrives via Notes,
/// Messages or Mail, which rewrite it in transit. Smart substitution turns
/// `--` into an em dash and straightens quotes into curly ones, so the parser
/// accepts every separator and quote variant the text might come back as. The
/// UID is optional — a hand-typed `Artist — Title` still matches, one rung down.
enum SongListParser {

    static let headerPrefix = "#bingobite playlist:"

    /// Every form the artist/title separator can arrive in.
    ///
    /// The exporter writes an em dash, but autocorrect and hand-typing produce
    /// the rest. Ordered longest-first so a double hyphen isn't mistaken for a
    /// single one.
    private static let separators = [
        " \u{2014} ",   // em dash — what the exporter writes
        " \u{2013} ",   // en dash, from some autocorrect paths
        " -- ",         // double hyphen, before smart substitution runs
        " - ",          // plain hyphen, hand-typed
    ]

    struct ParsedLine: Identifiable {
        let id = UUID()
        /// 1-based position in the pasted text, for pointing the user at it.
        let lineNumber: Int
        let raw: String
        var artist: String
        var title: String
        var uid: String?
    }

    struct ParseResult {
        var playlistName: String?
        var lines: [ParsedLine]
    }

    struct Match: Identifiable {
        let line: ParsedLine
        var song: Song?
        /// Candidates offered when the match was fuzzy or failed outright.
        var suggestions: [Song]
        var rung: Rung

        var id: UUID { line.id }
        var isResolved: Bool { song != nil }
    }

    /// Which rung of the ladder produced a match. Anything below `.normalized`
    /// is shown to the user for confirmation rather than applied silently.
    enum Rung {
        case uid
        case exact
        case normalized
        case fuzzy(Double)
        case unmatched

        var isAutomatic: Bool {
            switch self {
            case .uid, .exact, .normalized: true
            case .fuzzy, .unmatched: false
            }
        }

        var displayName: String {
            switch self {
            case .uid:        "Matched by ID"
            case .exact:      "Matched"
            case .normalized: "Matched"
            case .fuzzy(let score): "Close match (\(Int(score * 100))%)"
            case .unmatched:  "Not found"
            }
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> ParseResult {
        var name: String?
        var lines: [ParsedLine] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = normalizePunctuation(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let lowered = line.lowercased()
                if lowered.hasPrefix(headerPrefix) {
                    let value = line.dropFirst(headerPrefix.count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { name = value }
                }
                continue
            }

            // Strip and remember the trailing UID token.
            var body = line
            var uid: String?
            if let range = body.range(of: #"\[u:[^\]]+\]"#, options: .regularExpression) {
                uid = parseUIDToken(String(body[range]))
                body.removeSubrange(range)
                body = body.trimmingCharacters(in: .whitespaces)
            }

            // Tolerate list markers that a notes app may have added.
            body = stripListMarker(body)
            guard !body.isEmpty else { continue }

            let (artist, title) = splitArtistTitle(body)
            lines.append(
                ParsedLine(lineNumber: offset + 1, raw: rawLine, artist: artist, title: title, uid: uid)
            )
        }

        return ParseResult(playlistName: name, lines: lines)
    }

    /// `[u:ytdl-dQw4w9WgXcQ]` → `ytdl:dQw4w9WgXcQ`.
    ///
    /// The token uses `-` rather than `:` because a bare `ytdl:` prefix gets
    /// treated as a URL scheme and turned into a hyperlink.
    static func parseUIDToken(_ token: String) -> String? {
        var body = token
        if body.hasPrefix("[") { body.removeFirst() }
        if body.hasSuffix("]") { body.removeLast() }
        guard body.lowercased().hasPrefix("u:") else { return nil }
        body.removeFirst(2)
        guard let dash = body.firstIndex(of: "-") else { return nil }
        let namespace = String(body[body.startIndex..<dash])
        let value = String(body[body.index(after: dash)...])
        guard !namespace.isEmpty, !value.isEmpty else { return nil }
        return "\(namespace):\(value)"
    }

    /// Undoes the substitutions a notes app makes on paste, so the parser sees
    /// consistent text regardless of what the string travelled through.
    static func normalizePunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    /// Removes `1. `, `- `, `• ` and similar, which Notes adds when it decides
    /// a block of lines is a list.
    private static func stripListMarker(_ text: String) -> String {
        var body = text
        if let range = body.range(of: #"^\s*(\d+[\.\)]\s+|[-–—•*]\s+)"#, options: .regularExpression) {
            body.removeSubrange(range)
        }
        return body.trimmingCharacters(in: .whitespaces)
    }

    private static func splitArtistTitle(_ body: String) -> (artist: String, title: String) {
        for separator in separators {
            if let range = body.range(of: separator) {
                let artist = String(body[body.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let title = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty, !title.isEmpty { return (artist, title) }
            }
        }
        // No separator — treat the whole line as a title and match on that.
        return ("", body)
    }

    // MARK: - Matching

    /// Matches parsed lines against `songs`, most reliable rung first.
    static func match(_ parsed: ParseResult, against songs: [Song]) -> [Match] {
        var byUID: [String: Song] = [:]
        var byExact: [String: Song] = [:]
        var byNormalized: [String: Song] = [:]
        var byTitle: [String: Song] = [:]

        for song in songs {
            if let uid = song.uid, !uid.isEmpty, byUID[uid] == nil { byUID[uid] = song }

            let exact = "\(song.displayArtist.lowercased())|\(song.displayTitle.lowercased())"
            if byExact[exact] == nil { byExact[exact] = song }

            let key = normalizedKey(artist: song.displayArtist, title: song.displayTitle)
            if !key.isEmpty, byNormalized[key] == nil { byNormalized[key] = song }

            let titleKey = normalize(song.displayTitle)
            if !titleKey.isEmpty, byTitle[titleKey] == nil { byTitle[titleKey] = song }
        }

        return parsed.lines.map { line in
            // 1 — the embedded UID.
            if let uid = line.uid, let song = byUID[uid] {
                return Match(line: line, song: song, suggestions: [], rung: .uid)
            }

            // 2 — exact artist + title.
            let exact = "\(line.artist.lowercased())|\(line.title.lowercased())"
            if let song = byExact[exact] {
                return Match(line: line, song: song, suggestions: [], rung: .exact)
            }

            // 3 — normalized, which drops "(Official Video)" and friends.
            let key = normalizedKey(artist: line.artist, title: line.title)
            if !key.isEmpty, let song = byNormalized[key] {
                return Match(line: line, song: song, suggestions: [], rung: .normalized)
            }
            // Artist-less lines still match on title alone.
            if line.artist.isEmpty {
                let titleKey = normalize(line.title)
                if !titleKey.isEmpty, let song = byTitle[titleKey] {
                    return Match(line: line, song: song, suggestions: [], rung: .normalized)
                }
            }

            // 4 — fuzzy. Never applied without confirmation.
            let target = key.isEmpty ? normalize(line.title) : key
            var scored: [(song: Song, score: Double)] = []
            for song in songs {
                let candidate = normalizedKey(artist: song.displayArtist, title: song.displayTitle)
                guard !candidate.isEmpty else { continue }
                let score = similarity(target, candidate)
                if score >= 0.82 { scored.append((song, score)) }
            }
            scored.sort { $0.score > $1.score }
            let suggestions = Array(scored.prefix(3).map(\.song))

            if let best = scored.first {
                return Match(line: line, song: nil, suggestions: suggestions, rung: .fuzzy(best.score))
            }
            return Match(line: line, song: nil, suggestions: [], rung: .unmatched)
        }
    }

    // MARK: - Normalization

    /// Mirrors `DedupeEngine.normalize` in Music Downloader — the two have to
    /// agree or a list exported from one won't match in the other.
    private static let noisePatterns = [
        #"\(.*?\)"#,
        #"\[.*?\]"#,
        #"\bfeat\.?\b.*$"#,
        #"\bft\.?\b.*$"#,
        #"\bofficial\s+(music\s+)?video\b"#,
        #"\bofficial\s+audio\b"#,
        #"\blyrics?\b"#,
        #"\bremaster(ed)?(\s+\d{4})?\b"#,
        #"\bhd\b"#,
        #"\b4k\b"#,
    ]

    static func normalize(_ raw: String) -> String {
        var text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        for pattern in noisePatterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        let stripped = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(stripped))
    }

    static func normalizedKey(artist: String, title: String) -> String {
        let a = normalize(artist)
        let t = normalize(title)
        guard !t.isEmpty else { return "" }
        return a.isEmpty ? t : "\(a)|\(t)"
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        let distance = levenshtein(Array(lhs), Array(rhs))
        return 1 - (Double(distance) / Double(max(lhs.count, rhs.count)))
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let (short, long) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        var previous = Array(0...short.count)
        var current = [Int](repeating: 0, count: short.count + 1)

        for (i, longChar) in long.enumerated() {
            current[0] = i + 1
            for (j, shortChar) in short.enumerated() {
                let substitution = previous[j] + (longChar == shortChar ? 0 : 1)
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[short.count]
    }
}
