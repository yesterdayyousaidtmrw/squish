import Foundation

/// What Squish compressed, so it can tell when something keeps rewriting a file.
/// Each rewrite doubles that file's dormancy window, so a file another program
/// regenerates every few weeks stops being compressed and undone on repeat.
public struct ChurnLedger: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var inode: UInt64
        public var size: Int64
        public var modified: Double
        public var rewrites: Int
        /// False once the file has been seen rewritten, until Squish compresses it again.
        public var compressed: Bool
    }

    /// 2^5: a 30-day window grows to at most 960 days.
    public static let maxRewrites = 5

    public var files: [String: Entry] = [:]

    public init() {}

    /// Rewrites so far, counting this one if the file is uncompressed again with
    /// new content. Same inode, size and mtime means it was decompressed in place
    /// (squish restore), which is not churn.
    public func rewrites(for path: String, facts: FileFacts) -> (count: Int, isNew: Bool) {
        guard let entry = files[path] else { return (0, false) }
        let changed = entry.inode != facts.inode
            || entry.size != facts.logicalBytes
            || entry.modified != facts.modified.timeIntervalSince1970
        let isNew = entry.compressed && !facts.isCompressed && changed
        return (min(Self.maxRewrites, entry.rewrites + (isNew ? 1 : 0)), isNew)
    }

    public mutating func recordCompressed(_ path: String, facts: FileFacts) {
        files[path] = Entry(
            inode: facts.inode, size: facts.logicalBytes, modified: facts.modified.timeIntervalSince1970,
            rewrites: files[path]?.rewrites ?? 0, compressed: true
        )
    }

    public mutating func recordRewrite(_ path: String) {
        var entry = files[path] ?? Entry(inode: 0, size: 0, modified: 0, rewrites: 0, compressed: false)
        entry.rewrites = min(Self.maxRewrites, entry.rewrites + 1)
        entry.compressed = false
        files[path] = entry
    }

    /// Records the rewrites the scan found and the files the run left compressed,
    /// and forgets paths that no longer exist.
    public mutating func update(after report: RunReport, rewritten: [String]) throws {
        for path in rewritten { recordRewrite(path) }
        // A file deleted since it was compressed has nothing left to record; reading
        // it would throw and lose the whole run's history.
        for outcome in report.outcomes where outcome.candidate.kind == .file
            && FileManager.default.fileExists(atPath: outcome.candidate.url.path) {
            let facts = try FileFacts.read(outcome.candidate.url)
            if facts.isCompressed { recordCompressed(outcome.candidate.url.path, facts: facts) }
        }
        files = files.filter { FileManager.default.fileExists(atPath: $0.key) }
    }
}

public struct LedgerStore {
    public let url: URL

    /// Lives beside the config file, so --config keeps a separate history.
    public init(configURL: URL) {
        url = configURL.deletingLastPathComponent().appendingPathComponent("state.json")
    }

    public func load() throws -> ChurnLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return ChurnLedger() }
        return try JSONDecoder().decode(ChurnLedger.self, from: Data(contentsOf: url))
    }

    public func save(_ ledger: ChurnLedger) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
        try giveBackToSudoUser([folder, url])
    }

    /// A `sudo squish compress` writes this as root; without handing it back, every
    /// later run as the user fails to save.
    private func giveBackToSudoUser(_ urls: [URL]) throws {
        let env = ProcessInfo.processInfo.environment
        guard geteuid() == 0, let uid = env["SUDO_UID"].flatMap(UInt32.init), let gid = env["SUDO_GID"].flatMap(UInt32.init) else {
            return
        }
        for url in urls where chown(url.path, uid, gid) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
    }
}
