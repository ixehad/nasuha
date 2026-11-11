import Foundation

public enum AudioError: Error, Equatable {
    case badResponse(status: Int)
    case emptyFile
}

/// Fetches one file to a temporary location. `URLSession` does this on device.
public protocol AudioFetching: Sendable {
    func fetch(_ url: URL) async throws -> (file: URL, status: Int)
}

public struct URLSessionAudioFetcher: AudioFetching {
    private let session: URLSession

    /// A session with no cookies and no shared cache: a plain file download and nothing else.
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    public func fetch(_ url: URL) async throws -> (file: URL, status: Int) {
        let (file, response) = try await session.download(from: url)
        return (file, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Per-ayah recordings, downloaded on demand and kept in Application Support.
public final class AudioCache: Sendable {
    public let root: URL
    private let fetcher: AudioFetching

    public init(root: URL, fetcher: AudioFetching = URLSessionAudioFetcher()) {
        self.root = root
        self.fetcher = fetcher
    }

    /// The cache folder inside Application Support.
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Audio", isDirectory: true)
    }

    public func localURL(reciter: Reciter, key: AyahKey) -> URL {
        root.appendingPathComponent(reciter.id, isDirectory: true)
            .appendingPathComponent("\(key.everyAyahStem).mp3")
    }

    public func isCached(reciter: Reciter, key: AyahKey) -> Bool {
        FileManager.default.fileExists(atPath: localURL(reciter: reciter, key: key).path)
    }

    /// The local file for an ayah, downloading it first if needed.
    public func file(reciter: Reciter, key: AyahKey) async throws -> URL {
        let local = localURL(reciter: reciter, key: key)
        let files = FileManager.default
        if files.fileExists(atPath: local.path) { return local }

        let (temp, status) = try await fetcher.fetch(reciter.url(for: key))
        defer { try? files.removeItem(at: temp) }
        guard (200..<300).contains(status) else { throw AudioError.badResponse(status: status) }
        let size = (try? files.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw AudioError.emptyFile }

        try files.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: local.path) { return local }
        try files.moveItem(at: temp, to: local)
        // Recordings can be downloaded again, so keep them out of device backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(values)
        return local
    }

    /// Deletes every downloaded recording.
    public func clear() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}
