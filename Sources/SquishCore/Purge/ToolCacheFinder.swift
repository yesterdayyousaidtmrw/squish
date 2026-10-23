import Foundation

/// A package manager's download cache, emptied with the tool's own command so the
/// tool's bookkeeping stays consistent. Everything in it is downloaded again on demand.
struct ToolCache {
    let tool: String
    let cacheQuery: [String]
    let cacheSubfolder: String?
    let clean: [String]
    let rebuild: String

    static let known: [ToolCache] = [
        ToolCache(tool: "brew", cacheQuery: ["--cache"], cacheSubfolder: nil, clean: ["cleanup", "--prune=all"],
                  rebuild: "downloaded again when needed; also removes old versions of installed formulae"),
        ToolCache(tool: "npm", cacheQuery: ["config", "get", "cache"], cacheSubfolder: "_cacache", clean: ["cache", "clean", "--force"],
                  rebuild: "downloaded again on the next install"),
        ToolCache(tool: "pip3", cacheQuery: ["cache", "dir"], cacheSubfolder: nil, clean: ["cache", "purge"],
                  rebuild: "downloaded again on the next install"),
    ]
}

public struct ToolCacheFinder {
    let searchPath: String
    let run: (URL, [String]) throws -> ProcessOutcome

    public init(
        searchPath: String = ToolCacheFinder.defaultSearchPath,
        run: @escaping (URL, [String]) throws -> ProcessOutcome = ProcessRunner.run
    ) {
        self.searchPath = searchPath
        self.run = run
    }

    /// PATH plus Homebrew's folders, which a LaunchAgent's minimal PATH leaves out.
    public static var defaultSearchPath: String {
        (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
    }

    /// Caches of tools that are installed and have something cached; a missing
    /// tool is simply not listed.
    public func find(problems: inout [String]) -> [PurgeItem] {
        ToolCache.known.compactMap { cache in
            guard let executable = locate(cache.tool) else { return nil }
            do {
                let outcome = try run(executable, cache.cacheQuery)
                let reported = outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard outcome.status == 0, reported.hasPrefix("/") else {
                    throw CompressorError.failed(status: outcome.status, output: outcome.stderr.isEmpty ? reported : outcome.stderr)
                }
                var folder = URL(fileURLWithPath: reported)
                if let subfolder = cache.cacheSubfolder { folder.appendPathComponent(subfolder) }
                guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
                let bytes = try DiskUsage.measure(folder).allocatedBytes
                guard bytes > 0 else { return nil }
                return PurgeItem(url: folder, kind: .toolCache(command: [executable.path] + cache.clean), bytes: bytes, rebuild: cache.rebuild)
            } catch {
                problems.append("\(cache.tool): cannot read its cache: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func locate(_ tool: String) -> URL? {
        searchPath.split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
