import Foundation

/// Reads audio file tags without shelling out to `ffmpeg`.
///
/// The macOS build runs the bundled `ffmpeg` binary and parses its `ffmetadata`
/// output. iOS cannot spawn processes, so this reader parses the container
/// formats directly. It produces the same flat `[String: String]` tag
/// dictionary that `FolderScannerService` expects, using the same key names
/// ffmpeg emits (`title`, `artist`, `album`, `genre`, `date`, `language`, plus
/// the uppercase `TXXX` descriptions written by Music Downloader).
///
/// Supported: MP3 and WAV (ID3v2.2/2.3/2.4), FLAC (Vorbis comments), M4A/MP4
/// (`ilst` atoms including `----` freeform atoms).
enum AudioTagReader {

    struct Result {
        var tags: [String: String] = [:]
        var artwork: Data?
    }

    static func read(url: URL) -> Result {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return Result()
        }

        switch url.pathExtension.lowercased() {
        case "mp3":
            return readID3(from: data, at: 0)
        case "flac":
            return readFLAC(from: data)
        case "m4a", "mp4", "m4b":
            return readMP4(from: data)
        case "wav":
            return readWAV(from: data)
        default:
            return Result()
        }
    }

    // MARK: - ID3v2 (MP3, and the `id3 ` chunk inside WAV)

    /// Parses an ID3v2 tag beginning at `offset`. Handles v2.2 (3-char frame
    /// IDs) through v2.4, unsynchronisation, and extended headers.
    private static func readID3(from data: Data, at offset: Int) -> Result {
        var result = Result()
        guard data.count >= offset + 10 else { return result }

        let header = data.subdata(in: offset..<(offset + 10))
        guard header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return result } // "ID3"

        let majorVersion = header[3]
        let flags = header[5]
        let tagSize = Int(synchsafe(header, at: 6))
        let tagEnd = min(offset + 10 + tagSize, data.count)

        var cursor = offset + 10

        // Skip the extended header when present (v2.3 uses a plain size, v2.4 synchsafe).
        if flags & 0x40 != 0, cursor + 4 <= tagEnd {
            let extBytes = data.subdata(in: cursor..<(cursor + 4))
            let extSize = majorVersion >= 4
                ? Int(synchsafe(extBytes, at: 0))
                : Int(bigEndianUInt32(extBytes, at: 0)) + 4
            cursor += max(extSize, 4)
        }

        let idLength = majorVersion == 2 ? 3 : 4
        let headerLength = majorVersion == 2 ? 6 : 10

        while cursor + headerLength <= tagEnd {
            let idBytes = data.subdata(in: cursor..<(cursor + idLength))
            guard let frameID = String(data: idBytes, encoding: .isoLatin1),
                  frameID.first != "\0" else { break }

            let sizeStart = cursor + idLength
            let frameSize: Int
            if majorVersion == 2 {
                frameSize = Int(data[sizeStart]) << 16 | Int(data[sizeStart + 1]) << 8 | Int(data[sizeStart + 2])
            } else if majorVersion >= 4 {
                frameSize = Int(synchsafe(data, at: sizeStart))
            } else {
                frameSize = Int(bigEndianUInt32(data, at: sizeStart))
            }

            let payloadStart = cursor + headerLength
            let payloadEnd = payloadStart + frameSize
            guard frameSize > 0, payloadEnd <= tagEnd else { break }

            var payload = data.subdata(in: payloadStart..<payloadEnd)

            // Per-frame unsynchronisation (v2.4 frame flag) or whole-tag unsynchronisation.
            if majorVersion >= 4, headerLength == 10, data[cursor + 9] & 0x02 != 0 {
                payload = deunsynchronise(payload)
            } else if flags & 0x80 != 0 {
                payload = deunsynchronise(payload)
            }

            apply(frameID: frameID, payload: payload, into: &result)
            cursor = payloadEnd
        }

        resolveID3Date(&result)
        return result
    }

    /// ID3v2.4 carries a full timestamp in TDRC, but v2.3 splits it across TYER
    /// (year) and TDAT (DDMM). Recombine so both versions yield the same
    /// `date` value ffmpeg would report.
    private static func resolveID3Date(_ result: inout Result) {
        let year = result.tags.removeValue(forKey: dayMonthYearKey)
        let dayMonth = result.tags.removeValue(forKey: dayMonthKey)

        // A TDRC timestamp already won the `date` slot — nothing to rebuild.
        guard result.tags["date"] == nil, let year, year.count == 4 else { return }

        if let dayMonth, dayMonth.count == 4 {
            let day = dayMonth.prefix(2)
            let month = dayMonth.suffix(2)
            result.tags["date"] = "\(year)-\(month)-\(day)"
        } else {
            result.tags["date"] = year
        }
    }

    private static let dayMonthYearKey = "__id3_year"
    private static let dayMonthKey = "__id3_daymonth"

    private static func apply(frameID: String, payload: Data, into result: inout Result) {
        switch frameID {
        case "TXXX", "TXX":
            // <encoding><description>\0<value>
            guard let (description, value) = splitEncodedPair(payload) else { return }
            result.tags[description] = value

        case "COMM", "COM":
            // <encoding><lang×3><short description>\0<text>
            guard payload.count > 4 else { return }
            let body = payload.subdata(in: 4..<payload.count)
            var withEncoding = Data([payload[0]])
            withEncoding.append(body)
            guard let (description, value) = splitEncodedPair(withEncoding) else { return }
            // Music Downloader writes its notes with an empty COMM description.
            result.tags[description.isEmpty ? "comment" : description] = value

        case "WXXX", "WXX":
            guard let (description, value) = splitEncodedPair(payload) else { return }
            result.tags[description.isEmpty ? "url" : description] = value

        case "APIC", "PIC":
            result.artwork = result.artwork ?? attachedPicture(payload, isV22: frameID == "PIC")

        default:
            guard frameID.hasPrefix("T"), let key = id3TextKeys[frameID] else { return }
            guard let text = decodeText(payload) else { return }
            if result.tags[key] == nil { result.tags[key] = text }
        }
    }

    /// ffmpeg's key names for the standard ID3 text frames this app reads.
    private static let id3TextKeys: [String: String] = [
        "TIT2": "title",   "TT2": "title",
        "TPE1": "artist",  "TP1": "artist",
        "TALB": "album",   "TAL": "album",
        "TCON": "genre",   "TCO": "genre",
        "TDRC": "date",
        "TYER": dayMonthYearKey, "TYE": dayMonthYearKey,
        "TDAT": dayMonthKey,     "TDA": dayMonthKey,
        "TLAN": "language", "TLA": "language",
        "TPE2": "album_artist",
        "TCOM": "composer",
        "TRCK": "track",   "TRK": "track",
    ]

    /// Splits `<encoding><a>\0<b>` into its two strings.
    private static func splitEncodedPair(_ payload: Data) -> (String, String)? {
        guard let encoding = payload.first else { return nil }
        let body = payload.subdata(in: 1..<payload.count)

        switch encoding {
        case 0, 3: // ISO-8859-1 / UTF-8 — single-byte terminator
            guard let separator = body.firstIndex(of: 0) else { return nil }
            let first = body.subdata(in: body.startIndex..<separator)
            let second = body.subdata(in: body.index(after: separator)..<body.endIndex)
            let stringEncoding: String.Encoding = encoding == 0 ? .isoLatin1 : .utf8
            return (
                trimmed(String(data: first, encoding: stringEncoding) ?? ""),
                trimmed(String(data: second, encoding: stringEncoding) ?? "")
            )

        case 1, 2: // UTF-16 with/without BOM — double-byte terminator on an even boundary
            var separator: Int?
            var index = body.startIndex
            while index + 1 < body.endIndex {
                if body[index] == 0 && body[index + 1] == 0 {
                    separator = index
                    break
                }
                index += 2
            }
            guard let separator else { return nil }
            let first = body.subdata(in: body.startIndex..<separator)
            let secondStart = min(separator + 2, body.endIndex)
            let second = body.subdata(in: secondStart..<body.endIndex)
            return (
                trimmed(decodeUTF16(first)),
                trimmed(decodeUTF16(second))
            )

        default:
            return nil
        }
    }

    /// Decodes an ID3 text frame payload (`<encoding><text>`).
    private static func decodeText(_ payload: Data) -> String? {
        guard let encoding = payload.first, payload.count > 1 else { return nil }
        let body = payload.subdata(in: 1..<payload.count)
        let text: String
        switch encoding {
        case 0: text = String(data: body, encoding: .isoLatin1) ?? ""
        case 1, 2: text = decodeUTF16(body)
        case 3: text = String(data: body, encoding: .utf8) ?? ""
        default: return nil
        }
        let cleaned = trimmed(text)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func decodeUTF16(_ data: Data) -> String {
        guard data.count >= 2 else { return "" }
        if data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xFE {
            return String(data: data.subdata(in: (data.startIndex + 2)..<data.endIndex), encoding: .utf16LittleEndian) ?? ""
        }
        if data[data.startIndex] == 0xFE && data[data.startIndex + 1] == 0xFF {
            return String(data: data.subdata(in: (data.startIndex + 2)..<data.endIndex), encoding: .utf16BigEndian) ?? ""
        }
        return String(data: data, encoding: .utf16LittleEndian) ?? ""
    }

    /// Extracts the image bytes from an APIC (v2.3/2.4) or PIC (v2.2) frame.
    private static func attachedPicture(_ payload: Data, isV22: Bool) -> Data? {
        guard payload.count > 4 else { return nil }
        var cursor = payload.startIndex
        let encoding = payload[cursor]
        cursor += 1

        if isV22 {
            cursor += 3 // 3-character image format, e.g. "JPG"
        } else {
            guard let mimeEnd = payload[cursor...].firstIndex(of: 0) else { return nil }
            cursor = mimeEnd + 1
        }

        guard cursor < payload.endIndex else { return nil }
        cursor += 1 // picture type

        // Description, terminated per the text encoding.
        if encoding == 1 || encoding == 2 {
            while cursor + 1 < payload.endIndex {
                if payload[cursor] == 0 && payload[cursor + 1] == 0 { cursor += 2; break }
                cursor += 2
            }
        } else {
            guard let descriptionEnd = payload[cursor...].firstIndex(of: 0) else { return nil }
            cursor = descriptionEnd + 1
        }

        guard cursor < payload.endIndex else { return nil }
        return payload.subdata(in: cursor..<payload.endIndex)
    }

    /// Reverses ID3 unsynchronisation: `0xFF 0x00` -> `0xFF`.
    private static func deunsynchronise(_ data: Data) -> Data {
        var output = Data()
        output.reserveCapacity(data.count)
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            output.append(byte)
            if byte == 0xFF, index + 1 < data.endIndex, data[index + 1] == 0x00 {
                index += 2
            } else {
                index += 1
            }
        }
        return output
    }

    // MARK: - FLAC

    /// Parses FLAC metadata blocks: VORBIS_COMMENT (type 4) and PICTURE (type 6).
    private static func readFLAC(from data: Data) -> Result {
        var result = Result()
        guard data.count > 4,
              data[0] == 0x66, data[1] == 0x4C, data[2] == 0x61, data[3] == 0x43 // "fLaC"
        else { return result }

        var cursor = 4
        while cursor + 4 <= data.count {
            let header = data[cursor]
            let isLast = header & 0x80 != 0
            let blockType = header & 0x7F
            let length = Int(data[cursor + 1]) << 16 | Int(data[cursor + 2]) << 8 | Int(data[cursor + 3])
            let bodyStart = cursor + 4
            let bodyEnd = bodyStart + length
            guard bodyEnd <= data.count else { break }

            let body = data.subdata(in: bodyStart..<bodyEnd)
            if blockType == 4 {
                applyVorbisComments(body, into: &result)
            } else if blockType == 6 {
                result.artwork = result.artwork ?? flacPicture(body)
            }

            if isLast { break }
            cursor = bodyEnd
        }
        return result
    }

    /// Vorbis comment block: vendor string, then a count of `KEY=value` entries,
    /// all lengths little-endian UInt32.
    private static func applyVorbisComments(_ body: Data, into result: inout Result) {
        var cursor = body.startIndex
        guard let vendorLength = littleEndianUInt32(body, at: cursor) else { return }
        cursor += 4 + Int(vendorLength)

        guard let count = littleEndianUInt32(body, at: cursor) else { return }
        cursor += 4

        for _ in 0..<count {
            guard let length = littleEndianUInt32(body, at: cursor) else { return }
            cursor += 4
            let end = cursor + Int(length)
            guard end <= body.endIndex else { return }
            let entry = String(data: body.subdata(in: cursor..<end), encoding: .utf8) ?? ""
            cursor = end

            guard let equals = entry.firstIndex(of: "=") else { continue }
            let rawKey = String(entry[entry.startIndex..<equals])
            let value = trimmed(String(entry[entry.index(after: equals)...]))
            guard !value.isEmpty else { continue }
            result.tags[normalizedVorbisKey(rawKey)] = value
        }
    }

    /// Maps Vorbis field names onto the ffmpeg key names used elsewhere, leaving
    /// Music Downloader's custom uppercase fields untouched.
    private static func normalizedVorbisKey(_ key: String) -> String {
        switch key.uppercased() {
        case "TITLE": return "title"
        case "ARTIST": return "artist"
        case "ALBUM": return "album"
        case "GENRE": return "genre"
        case "DATE", "YEAR": return "date"
        case "LANGUAGE": return "language"
        case "ALBUMARTIST", "ALBUM ARTIST": return "album_artist"
        case "COMPOSER": return "composer"
        case "TRACKNUMBER": return "track"
        case "COMMENT": return "comment"
        default: return key
        }
    }

    /// FLAC PICTURE block: type, MIME, description, dimensions, then the image bytes.
    private static func flacPicture(_ body: Data) -> Data? {
        var cursor = body.startIndex + 4 // picture type
        guard let mimeLength = bigEndianUInt32(body, safeAt: cursor) else { return nil }
        cursor += 4 + Int(mimeLength)
        guard let descriptionLength = bigEndianUInt32(body, safeAt: cursor) else { return nil }
        cursor += 4 + Int(descriptionLength)
        cursor += 16 // width, height, colour depth, colour count
        guard let dataLength = bigEndianUInt32(body, safeAt: cursor) else { return nil }
        cursor += 4
        let end = cursor + Int(dataLength)
        guard end <= body.endIndex else { return nil }
        return body.subdata(in: cursor..<end)
    }

    // MARK: - MP4 / M4A

    /// Walks the MP4 atom tree to `moov/udta/meta/ilst` and reads its entries.
    private static func readMP4(from data: Data) -> Result {
        var result = Result()
        guard let moov = findAtom("moov", in: data, range: data.startIndex..<data.endIndex),
              let udta = findAtom("udta", in: data, range: moov),
              let meta = findAtom("meta", in: data, range: udta)
        else { return result }

        // The `meta` atom carries a 4-byte version/flags field before its children.
        let metaChildren = (meta.lowerBound + 4)..<meta.upperBound
        guard let ilst = findAtom("ilst", in: data, range: metaChildren) else { return result }

        var cursor = ilst.lowerBound
        while cursor + 8 <= ilst.upperBound {
            let size = Int(bigEndianUInt32(data, at: cursor))
            guard size >= 8, cursor + size <= ilst.upperBound else { break }
            let nameBytes = data.subdata(in: (cursor + 4)..<(cursor + 8))
            let name = String(data: nameBytes, encoding: .isoLatin1) ?? ""
            let body = (cursor + 8)..<(cursor + size)

            if name == "----" {
                applyMP4Freeform(data, range: body, into: &result)
            } else if let key = mp4Keys[name] {
                if let value = mp4StringValue(data, range: body), result.tags[key] == nil {
                    result.tags[key] = value
                }
            } else if name == "covr" {
                result.artwork = result.artwork ?? mp4DataValue(data, range: body)
            }

            cursor += size
        }
        return result
    }

    /// Standard `ilst` atom names. "©" is 0xA9 in MacRoman/Latin-1.
    private static let mp4Keys: [String: String] = [
        "\u{00A9}nam": "title",
        "\u{00A9}ART": "artist",
        "\u{00A9}alb": "album",
        "\u{00A9}gen": "genre",
        "\u{00A9}day": "date",
        "\u{00A9}cmt": "comment",
        "\u{00A9}wrt": "composer",
        "aART": "album_artist",
    ]

    /// A `----` atom holds `mean` (reverse-DNS namespace), `name`, then `data`.
    private static func applyMP4Freeform(_ data: Data, range: Range<Int>, into result: inout Result) {
        var name: String?
        var value: String?
        var cursor = range.lowerBound

        while cursor + 8 <= range.upperBound {
            let size = Int(bigEndianUInt32(data, at: cursor))
            guard size >= 8, cursor + size <= range.upperBound else { break }
            let kindBytes = data.subdata(in: (cursor + 4)..<(cursor + 8))
            let kind = String(data: kindBytes, encoding: .isoLatin1) ?? ""
            let bodyStart = cursor + 12 // skip the 4-byte version/flags
            let bodyEnd = cursor + size

            if bodyStart <= bodyEnd {
                let body = data.subdata(in: bodyStart..<bodyEnd)
                switch kind {
                case "name": name = String(data: body, encoding: .utf8)
                case "data": value = String(data: body.count > 4 ? body.subdata(in: 4..<body.count) : body, encoding: .utf8)
                default: break
                }
            }
            cursor += size
        }

        if let name, let value {
            let cleaned = trimmed(value)
            if !cleaned.isEmpty { result.tags[name] = cleaned }
        }
    }

    private static func mp4StringValue(_ data: Data, range: Range<Int>) -> String? {
        guard let raw = mp4DataValue(data, range: range),
              let text = String(data: raw, encoding: .utf8) else { return nil }
        let cleaned = trimmed(text)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Returns the payload of the nested `data` atom, past its version/flags and locale fields.
    private static func mp4DataValue(_ data: Data, range: Range<Int>) -> Data? {
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let size = Int(bigEndianUInt32(data, at: cursor))
            guard size >= 16, cursor + size <= range.upperBound else { return nil }
            let kindBytes = data.subdata(in: (cursor + 4)..<(cursor + 8))
            if String(data: kindBytes, encoding: .isoLatin1) == "data" {
                return data.subdata(in: (cursor + 16)..<(cursor + size))
            }
            cursor += size
        }
        return nil
    }

    /// Finds a direct child atom by name, returning the range of its body.
    private static func findAtom(_ name: String, in data: Data, range: Range<Int>) -> Range<Int>? {
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let size = Int(bigEndianUInt32(data, at: cursor))
            guard size >= 8, cursor + size <= range.upperBound else { return nil }
            let nameBytes = data.subdata(in: (cursor + 4)..<(cursor + 8))
            if String(data: nameBytes, encoding: .isoLatin1) == name {
                return (cursor + 8)..<(cursor + size)
            }
            cursor += size
        }
        return nil
    }

    // MARK: - WAV

    /// WAV files carry ID3 inside an `id3 ` RIFF chunk; LIST/INFO is the fallback.
    private static func readWAV(from data: Data) -> Result {
        guard data.count > 12,
              data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46 // "RIFF"
        else { return Result() }

        var cursor = 12
        var result = Result()
        while cursor + 8 <= data.count {
            let idBytes = data.subdata(in: cursor..<(cursor + 4))
            let chunkID = String(data: idBytes, encoding: .isoLatin1) ?? ""
            let size = Int(littleEndianUInt32(data, at: cursor + 4) ?? 0)
            let bodyStart = cursor + 8
            guard size > 0, bodyStart + size <= data.count else { break }

            if chunkID.lowercased() == "id3 " {
                let tag = readID3(from: data, at: bodyStart)
                result.tags.merge(tag.tags) { current, _ in current }
                result.artwork = result.artwork ?? tag.artwork
            } else if chunkID == "LIST" {
                applyRIFFInfo(data, range: bodyStart..<(bodyStart + size), into: &result)
            }

            cursor = bodyStart + size + (size % 2) // chunks are word-aligned
        }
        return result
    }

    private static func applyRIFFInfo(_ data: Data, range: Range<Int>, into result: inout Result) {
        guard range.count > 4,
              String(data: data.subdata(in: range.lowerBound..<(range.lowerBound + 4)), encoding: .isoLatin1) == "INFO"
        else { return }

        let infoKeys = ["INAM": "title", "IART": "artist", "IPRD": "album", "IGNR": "genre", "ICRD": "date", "ICMT": "comment"]
        var cursor = range.lowerBound + 4
        while cursor + 8 <= range.upperBound {
            let idBytes = data.subdata(in: cursor..<(cursor + 4))
            let chunkID = String(data: idBytes, encoding: .isoLatin1) ?? ""
            let size = Int(littleEndianUInt32(data, at: cursor + 4) ?? 0)
            let bodyStart = cursor + 8
            guard size > 0, bodyStart + size <= range.upperBound else { break }

            if let key = infoKeys[chunkID] {
                let raw = String(data: data.subdata(in: bodyStart..<(bodyStart + size)), encoding: .utf8) ?? ""
                let value = trimmed(raw)
                if !value.isEmpty, result.tags[key] == nil { result.tags[key] = value }
            }
            cursor = bodyStart + size + (size % 2)
        }
    }

    // MARK: - Byte helpers

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
    }

    /// ID3 synchsafe integer: 4 bytes, 7 significant bits each.
    private static func synchsafe(_ data: Data, at index: Int) -> UInt32 {
        let base = data.startIndex + (index - data.startIndex)
        guard base + 3 < data.endIndex else { return 0 }
        return UInt32(data[base] & 0x7F) << 21
            | UInt32(data[base + 1] & 0x7F) << 14
            | UInt32(data[base + 2] & 0x7F) << 7
            | UInt32(data[base + 3] & 0x7F)
    }

    private static func bigEndianUInt32(_ data: Data, at index: Int) -> UInt32 {
        guard index + 3 < data.endIndex else { return 0 }
        return UInt32(data[index]) << 24
            | UInt32(data[index + 1]) << 16
            | UInt32(data[index + 2]) << 8
            | UInt32(data[index + 3])
    }

    private static func bigEndianUInt32(_ data: Data, safeAt index: Int) -> UInt32? {
        guard index >= data.startIndex, index + 3 < data.endIndex else { return nil }
        return bigEndianUInt32(data, at: index)
    }

    private static func littleEndianUInt32(_ data: Data, at index: Int) -> UInt32? {
        guard index >= data.startIndex, index + 3 < data.endIndex else { return nil }
        return UInt32(data[index])
            | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16
            | UInt32(data[index + 3]) << 24
    }
}
