import Foundation

/// One reciter, as listed in Resources/reciters.json.
public struct Reciter: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// The reading, e.g. "Hafs 'an 'Asim".
    public let riwayah: String
    /// Folder of per-ayah MP3s named `SSSAAA.mp3`.
    public let baseURL: URL
    /// False until the rights holder has given permission. Audio stays hidden while it is false.
    public let licenceCleared: Bool

    public init(id: String, name: String, riwayah: String, baseURL: URL, licenceCleared: Bool) {
        self.id = id
        self.name = name
        self.riwayah = riwayah
        self.baseURL = baseURL
        self.licenceCleared = licenceCleared
    }

    /// Address of one ayah's recording.
    public func url(for key: AyahKey) -> URL {
        baseURL.appendingPathComponent("\(key.everyAyahStem).mp3")
    }
}

/// The reciter list. Only reciters whose licence is cleared can be played.
public struct ReciterCatalog: Codable, Equatable, Sendable {
    public let defaultReciter: String
    public let reciters: [Reciter]

    public static let empty = ReciterCatalog(defaultReciter: "", reciters: [])

    public init(defaultReciter: String, reciters: [Reciter]) {
        self.defaultReciter = defaultReciter
        self.reciters = reciters
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(ReciterCatalog.self, from: data)
    }

    /// Loads reciters.json from a bundle. An unreadable file gives an empty list, which hides audio.
    public static func bundled(in bundle: Bundle = .main) -> ReciterCatalog {
        guard let url = bundle.url(forResource: "reciters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? ReciterCatalog(data: data)
        else { return .empty }
        return catalog
    }

    /// Reciters that may be played. `includeUncleared` is for testing on a developer's own device only.
    public func playable(includeUncleared: Bool = false) -> [Reciter] {
        reciters.filter { $0.licenceCleared || includeUncleared }
    }

    /// The reciter to play with: the user's choice if playable, else the default, else the first playable one.
    public func reciter(preferred id: String?, includeUncleared: Bool = false) -> Reciter? {
        let list = playable(includeUncleared: includeUncleared)
        return list.first { $0.id == id } ?? list.first { $0.id == defaultReciter } ?? list.first
    }
}

/// What to play: a list of ayahs, repeated a number of times.
public struct PlaybackPlan: Equatable, Sendable {
    public static let repeatChoice = 3

    public let keys: [AyahKey]
    public let repeatCount: Int

    public init(keys: [AyahKey], repeatCount: Int = 1) {
        self.keys = keys
        self.repeatCount = max(1, repeatCount)
    }

    /// Every ayah of a surah, in order.
    public init(surah: Int, ayahCount: Int, from start: Int = 1) {
        let first = max(1, start)
        self.init(keys: first <= ayahCount ? (first...ayahCount).map { AyahKey(surah: surah, ayah: $0) } : [])
    }

    /// The full play order, with repeats laid out.
    public var sequence: [AyahKey] {
        Array(repeating: keys, count: repeatCount).flatMap { $0 }
    }

    public var isEmpty: Bool { keys.isEmpty }
}
