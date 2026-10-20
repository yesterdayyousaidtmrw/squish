import Foundation
@testable import SquishCore

/// A throwaway folder under the temp dir, removed when the test releases it.
final class TestTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("squish-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// 64 KB by default: a file of 4 KB or less never shrinks on disk, so smaller
    /// fixtures would be skipped for too little gain and test nothing else.
    @discardableResult
    func file(_ path: String, bytes: Int = 65_536) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: UInt8(ascii: "a"), count: bytes).write(to: url)
        return url
    }

    /// Word-like text that compresses about as well as real source or logs.
    /// A fixed LCG keeps it identical on every run.
    @discardableResult
    func textFile(_ path: String, bytes: Int) throws -> URL {
        var state: UInt64 = 42
        var words: [String] = []
        for _ in 0..<2000 {
            var word = ""
            state = state &* 6364136223846793005 &+ 1442695040888963407
            for _ in 0..<(2 + Int(state >> 61)) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                word.append(Character(UnicodeScalar(UInt8(97 + (state >> 33) % 26))))
            }
            words.append(word)
        }
        var text = ""
        while text.utf8.count < bytes {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            text += words[Int((state >> 33) % 2000)] + " "
        }
        return try write(Data(text.utf8.prefix(bytes)), to: path)
    }

    /// Random bytes: nothing to gain from compressing them.
    @discardableResult
    func randomFile(_ path: String, bytes: Int) throws -> URL {
        var generator = SystemRandomNumberGenerator()
        return try write(Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &generator) }), to: path)
    }

    private func write(_ data: Data, to path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    /// Children before parents, so dating a child cannot leave its folder looking fresh.
    func ageEverything(to date: Date) throws {
        let paths = (FileManager.default.subpaths(atPath: root.path) ?? []).sorted { $0.count > $1.count }
        for path in paths {
            try setTimes(root.appendingPathComponent(path), to: date)
        }
    }

    func setTimes(_ url: URL, to date: Date) throws {
        let seconds = Int(date.timeIntervalSince1970)
        var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
        guard utimes(url.path, &times) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

struct FakeProbe: ActivityProbe {
    var dates: [String: Date] = [:]

    func spotlightActivity(of url: URL) -> Date? {
        dates[url.lastPathComponent]
    }
}

func daysAgo(_ days: Double, from now: Date) -> Date {
    now.addingTimeInterval(-days * 86_400)
}
