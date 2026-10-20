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
