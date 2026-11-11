import XCTest
@testable import NasuhaCore

final class ReciterCatalogTests: XCTestCase {
    private let json = """
    {
      "defaultReciter": "one",
      "reciters": [
        { "id": "one", "name": "Reciter One", "riwayah": "Hafs", "baseURL": "https://example.org/one/", "licenceCleared": false },
        { "id": "two", "name": "Reciter Two", "riwayah": "Hafs", "baseURL": "https://example.org/two/", "licenceCleared": true }
      ]
    }
    """

    func testUnclearedReciterIsNeverPlayable() throws {
        let catalog = try ReciterCatalog(data: Data(json.utf8))
        XCTAssertEqual(catalog.playable().map(\.id), ["two"])
        XCTAssertEqual(catalog.reciter(preferred: "one")?.id, "two", "an uncleared choice falls back to a cleared one")
        XCTAssertEqual(catalog.reciter(preferred: nil)?.id, "two")
    }

    func testNoClearedReciterHidesAudio() throws {
        let only = ReciterCatalog(defaultReciter: "one", reciters: [
            Reciter(id: "one", name: "Reciter One", riwayah: "Hafs",
                    baseURL: URL(string: "https://example.org/one/")!, licenceCleared: false),
        ])
        XCTAssertNil(only.reciter(preferred: "one"))
        XCTAssertTrue(only.playable().isEmpty)
        XCTAssertNil(ReciterCatalog.empty.reciter(preferred: nil))
    }

    func testPreviewIncludesUnclearedAndPrefersTheDefault() throws {
        let catalog = try ReciterCatalog(data: Data(json.utf8))
        XCTAssertEqual(catalog.reciter(preferred: nil, includeUncleared: true)?.id, "one")
        XCTAssertEqual(catalog.reciter(preferred: "two", includeUncleared: true)?.id, "two")
    }

    func testFileAddressUsesThreeDigitSurahAndAyah() throws {
        let catalog = try ReciterCatalog(data: Data(json.utf8))
        let url = catalog.reciters[1].url(for: AyahKey(surah: 93, ayah: 3))
        XCTAssertEqual(url.absoluteString, "https://example.org/two/093003.mp3")
    }

    func testBadFileGivesAnEmptyCatalog() {
        XCTAssertThrowsError(try ReciterCatalog(data: Data("not json".utf8)))
        XCTAssertEqual(ReciterCatalog.bundled(in: Bundle(for: Self.self)), .empty)
    }
}

final class PlaybackPlanTests: XCTestCase {
    func testSingleAyahRepeatedThreeTimes() {
        let key = AyahKey(surah: 93, ayah: 3)
        let plan = PlaybackPlan(keys: [key], repeatCount: PlaybackPlan.repeatChoice)
        XCTAssertEqual(plan.sequence, [key, key, key])
    }

    func testRangeKeepsOrder() {
        let keys = (1...5).map { AyahKey(surah: 93, ayah: $0) }
        XCTAssertEqual(PlaybackPlan(keys: keys).sequence, keys)
        XCTAssertEqual(PlaybackPlan(keys: keys, repeatCount: 0).repeatCount, 1, "never fewer than once")
    }

    func testWholeSurah() {
        let plan = PlaybackPlan(surah: 93, ayahCount: 11)
        XCTAssertEqual(plan.keys.count, 11)
        XCTAssertEqual(plan.keys.first, AyahKey(surah: 93, ayah: 1))
        XCTAssertEqual(plan.keys.last, AyahKey(surah: 93, ayah: 11))
        XCTAssertEqual(PlaybackPlan(surah: 93, ayahCount: 11, from: 9).keys.map(\.ayah), [9, 10, 11])
        XCTAssertTrue(PlaybackPlan(surah: 93, ayahCount: 11, from: 12).isEmpty)
    }

    func testPlansCompareByContent() {
        let a = PlaybackPlan(keys: [AyahKey(surah: 1, ayah: 1)])
        XCTAssertEqual(a, PlaybackPlan(keys: [AyahKey(surah: 1, ayah: 1)]))
        XCTAssertNotEqual(a, PlaybackPlan(keys: [AyahKey(surah: 1, ayah: 1)], repeatCount: 3))
    }
}

final class AudioCacheTests: XCTestCase {
    private final class FakeFetcher: AudioFetching, @unchecked Sendable {
        var status = 200
        var body = Data("mp3".utf8)
        private(set) var requests: [URL] = []

        func fetch(_ url: URL) async throws -> (file: URL, status: Int) {
            requests.append(url)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try body.write(to: temp)
            return (temp, status)
        }
    }

    private var root: URL!
    private let reciter = Reciter(id: "two", name: "Reciter Two", riwayah: "Hafs",
                                  baseURL: URL(string: "https://example.org/two/")!, licenceCleared: true)
    private let key = AyahKey(surah: 2, ayah: 255)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nasuha-audio-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testDownloadsOnceThenReadsFromDisk() async throws {
        let fetcher = FakeFetcher()
        let cache = AudioCache(root: root, fetcher: fetcher)
        XCTAssertFalse(cache.isCached(reciter: reciter, key: key))

        let first = try await cache.file(reciter: reciter, key: key)
        XCTAssertEqual(first.lastPathComponent, "002255.mp3")
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "two", "one folder per reciter")
        XCTAssertTrue(cache.isCached(reciter: reciter, key: key))
        XCTAssertEqual(try Data(contentsOf: first), Data("mp3".utf8))

        _ = try await cache.file(reciter: reciter, key: key)
        XCTAssertEqual(fetcher.requests.map(\.absoluteString), ["https://example.org/two/002255.mp3"])
    }

    func testMissingFileIsNotCached() async {
        let fetcher = FakeFetcher()
        fetcher.status = 404
        let cache = AudioCache(root: root, fetcher: fetcher)
        do {
            _ = try await cache.file(reciter: reciter, key: key)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AudioError, .badResponse(status: 404))
        }
        XCTAssertFalse(cache.isCached(reciter: reciter, key: key))
    }

    func testEmptyFileIsRejected() async {
        let fetcher = FakeFetcher()
        fetcher.body = Data()
        let cache = AudioCache(root: root, fetcher: fetcher)
        do {
            _ = try await cache.file(reciter: reciter, key: key)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AudioError, .emptyFile)
        }
        XCTAssertFalse(cache.isCached(reciter: reciter, key: key))
    }

    func testClearRemovesEverything() async throws {
        let cache = AudioCache(root: root, fetcher: FakeFetcher())
        _ = try await cache.file(reciter: reciter, key: key)
        try cache.clear()
        XCTAssertFalse(cache.isCached(reciter: reciter, key: key))
    }
}
