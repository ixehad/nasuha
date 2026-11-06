import Foundation

/// A surah:ayah pair, written "93:3".
public struct AyahKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let surah: Int
    public let ayah: Int

    public init(surah: Int, ayah: Int) {
        self.surah = surah
        self.ayah = ayah
    }

    /// Parses "93:3". Returns nil for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let s = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let a = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (1...114).contains(s), a >= 1
        else { return nil }
        self.init(surah: s, ayah: a)
    }

    public var description: String { "\(surah):\(ayah)" }

    /// EveryAyah-style file stem, e.g. "093003".
    public var everyAyahStem: String { String(format: "%03d%03d", surah, ayah) }

    public static func < (lhs: AyahKey, rhs: AyahKey) -> Bool {
        (lhs.surah, lhs.ayah) < (rhs.surah, rhs.ayah)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = AyahKey(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad ayah key \(raw)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
