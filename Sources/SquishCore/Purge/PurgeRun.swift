import Foundation

public protocol Trasher {
    func trash(_ url: URL) throws
}

/// The Finder's Trash: purged folders can be put back until it is emptied.
public struct FinderTrash: Trasher {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

public struct PurgeReport {
    public let done: [PurgeItem]
    public let problems: [String]

    /// In the Trash: the space comes back once the Trash is emptied.
    public var trashedBytes: Int64 {
        done.filter { if case .folder = $0.kind { return true } else { return false } }.reduce(0) { $0 + $1.bytes }
    }

    public var clearedBytes: Int64 {
        done.filter { if case .toolCache = $0.kind { return true } else { return false } }.reduce(0) { $0 + $1.bytes }
    }
}

public struct PurgeRun {
    let trash: Trasher
    let openFiles: OpenFileProbe
    let run: (URL, [String]) throws -> ProcessOutcome
    let progress: (String) -> Void

    public init(
        trash: Trasher = FinderTrash(),
        openFiles: OpenFileProbe = LibprocOpenFiles(),
        run: @escaping (URL, [String]) throws -> ProcessOutcome = ProcessRunner.run,
        progress: @escaping (String) -> Void = { _ in }
    ) {
        self.trash = trash
        self.openFiles = openFiles
        self.run = run
        self.progress = progress
    }

    public func execute(_ items: [PurgeItem]) -> PurgeReport {
        // Fresh snapshot: something may have started using a folder since the plan.
        let openPaths: Set<String>
        do {
            openPaths = try openFiles.openPaths()
        } catch {
            return PurgeReport(done: [], problems: ["cannot list open files, so nothing was purged: \(error.localizedDescription)"])
        }
        var done: [PurgeItem] = []
        var problems: [String] = []
        for item in items {
            switch item.kind {
            case .folder:
                if openPaths.contains(where: { $0.hasPrefix(item.url.path + "/") }) {
                    progress("  skipped: \(item.url.path) is in use now")
                    continue
                }
                do {
                    try trash.trash(item.url)
                    done.append(item)
                } catch {
                    problems.append("\(item.url.path): \(error.localizedDescription)")
                }
            case .toolCache(let command):
                guard let executable = command.first else { continue }
                progress("  running \(command.joined(separator: " "))")
                do {
                    let outcome = try run(URL(fileURLWithPath: executable), Array(command.dropFirst()))
                    guard outcome.status == 0 else {
                        problems.append("\(command.joined(separator: " ")): exited \(outcome.status): \(outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                        continue
                    }
                    done.append(item)
                } catch {
                    problems.append("\(command.joined(separator: " ")): \(error.localizedDescription)")
                }
            }
        }
        return PurgeReport(done: done, problems: problems)
    }
}
