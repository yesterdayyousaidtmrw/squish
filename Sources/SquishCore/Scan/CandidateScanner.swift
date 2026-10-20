import Foundation

public struct CandidateScanner {
    /// Git objects and packs are zlib-compressed already.
    static let skippedDirectoryNames: Set<String> = [".git"]

    let config: SquishConfig
    let probe: ActivityProbe
    let isAppRunning: (URL) -> Bool
    let canModify: (URL) -> Bool
    let sampler: CompressibilityProbe
    let now: Date
    private let excludedRoots: [String]
    private let excludedExtensions: Set<String>

    public init(
        config: SquishConfig,
        probe: ActivityProbe = SpotlightActivityProbe(),
        isAppRunning: @escaping (URL) -> Bool = RunningApps.snapshot(),
        canModify: @escaping (URL) -> Bool = CandidateScanner.canModify,
        sampler: CompressibilityProbe = LZFSESampler(),
        now: Date = Date()
    ) {
        self.config = config
        self.probe = probe
        self.isAppRunning = isAppRunning
        self.canModify = canModify
        self.sampler = sampler
        self.now = now
        excludedRoots = config.excludedPaths.map { Paths.canonical(Paths.expand($0)).path }
        excludedExtensions = Set(config.excludedExtensions)
    }

    public static func canModify(_ url: URL) -> Bool {
        geteuid() == 0 || FileManager.default.isWritableFile(atPath: url.path)
    }

    public func scan() -> ScanResult {
        var result = ScanResult()
        let enabled = config.enabledCategories
        if enabled.contains(where: { $0.id == Categories.appsID }) {
            for location in config.appLocations {
                scanApps(in: Paths.expand(location), into: &result)
            }
        }
        let fileCategories = enabled.filter { $0.id != Categories.appsID }
        if !fileCategories.isEmpty {
            for location in config.fileLocations {
                scanFiles(in: Paths.expand(location), categories: fileCategories, into: &result)
            }
        }
        return result
    }

    // MARK: Dormancy

    /// nil when the item was used inside its dormancy window. Spotlight is slow per
    /// file, so it is only asked once the cheap filesystem date already looks dormant.
    private func dormantSince(_ url: URL, filesystemDate: Date, categoryID: String) -> Date? {
        guard isDormant(since: filesystemDate, categoryID: categoryID) else { return nil }
        let last = max(filesystemDate, probe.spotlightActivity(of: url) ?? filesystemDate)
        return isDormant(since: last, categoryID: categoryID) ? last : nil
    }

    private func isDormant(since last: Date, categoryID: String) -> Bool {
        now.timeIntervalSince(last) >= Double(config.dormantDays(forCategory: categoryID)) * 86_400
    }

    private func isExcluded(_ url: URL) -> Bool {
        let path = url.path
        return excludedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    // MARK: Apps

    private func scanApps(in location: URL, into result: inout ScanResult) {
        let root = Paths.canonical(location)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for app in appBundles(in: root, depth: 2, problems: &result.problems) {
            evaluateApp(app, into: &result)
        }
    }

    /// .app bundles in `folder`, plus those one plain subfolder down (/Applications/Utilities).
    /// Symlinked apps are skipped: what they point at is not ours to rewrite.
    private func appBundles(in folder: URL, depth: Int, problems: inout [String]) -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            problems.append("\(folder.path): \(error.localizedDescription)")
            return []
        }
        var apps: [URL] = []
        for entry in entries {
            let facts: FileFacts
            do {
                facts = try FileFacts.read(entry)
            } catch {
                problems.append("\(entry.path): \(error.localizedDescription)")
                continue
            }
            guard facts.isDirectory else { continue }
            if entry.pathExtension == "app" {
                apps.append(entry)
            } else if depth > 1, !isExcluded(entry) {
                apps += appBundles(in: entry, depth: depth - 1, problems: &problems)
            }
        }
        return apps
    }

    private func evaluateApp(_ app: URL, into result: inout ScanResult) {
        if isExcluded(app) { return result.skip(.excludedPath) }
        if isAppRunning(app) { return result.skip(.running) }
        let usage: DiskUsage
        let bundleDate: Date
        var uncompressedFiles: [(url: URL, facts: FileFacts)] = []
        do {
            usage = try DiskUsage.measure(app) { url, facts in
                if !facts.isCompressed { uncompressedFiles.append((url, facts)) }
            }
            bundleDate = try appFilesystemDate(app)
        } catch {
            result.problems.append("\(app.path): \(error.localizedDescription)")
            return result.skip(.unreadable)
        }
        guard let last = dormantSince(app, filesystemDate: bundleDate, categoryID: Categories.appsID) else {
            return result.skip(.recentlyUsed)
        }
        guard usage.uncompressedLogicalBytes > 0 else { return result.skip(.alreadyCompressed) }
        guard canModify(app.appendingPathComponent("Contents")) else { return result.skip(.needsAdmin) }
        let ratio: Double
        do {
            ratio = try bundleRatio(uncompressedFiles)
        } catch {
            result.problems.append("\(app.path): \(error.localizedDescription)")
            return result.skip(.unreadable)
        }
        guard meetsMinimumSavings(ratio) else { return result.skip(.incompressible) }
        var candidate = Candidate(
            url: app, kind: .app, categoryID: Categories.appsID, lastActivity: last,
            compressibleBytes: usage.uncompressedLogicalBytes, allocatedBytes: usage.allocatedBytes
        )
        candidate.estimatedSavedBytes = uncompressedFiles.reduce(0) { total, file in
            total + max(0, SavingsEstimate.savedBytes(
                allocatedBefore: file.facts.allocatedBytes, logicalBytes: file.facts.logicalBytes, ratio: ratio
            ))
        }
        result.candidates.append(candidate)
    }

    /// Sampling every file of a large app would read most of it, so sample the 64
    /// largest, which hold most of the bytes, and weight each by what was read.
    private func bundleRatio(_ files: [(url: URL, facts: FileFacts)]) throws -> Double {
        var sampledBytes = 0.0
        var compressedBytes = 0.0
        for file in files.sorted(by: { $0.facts.logicalBytes > $1.facts.logicalBytes }).prefix(64) {
            let weight = Double(min(file.facts.logicalBytes, Int64(LZFSESampler.sampleBytes)))
            compressedBytes += weight * (try sampler.compressedRatio(of: file.url, accessed: file.facts.accessed))
            sampledBytes += weight
        }
        return sampledBytes > 0 ? compressedBytes / sampledBytes : 1
    }

    /// The same bar afsctool applies with -s, checked before anything is written.
    private func meetsMinimumSavings(_ ratio: Double) -> Bool {
        (1 - ratio) * 100 >= Double(config.minSavingsPercent)
    }

    /// Updates rewrite Info.plist, so its mtime marks the last install or update.
    /// Access times are ignored for apps: merely listing a bundle bumps them.
    private func appFilesystemDate(_ app: URL) throws -> Date {
        let bundle = try FileFacts.read(app).modified
        let infoPlist = app.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist.path) else { return bundle }
        return max(bundle, try FileFacts.read(infoPlist).modified)
    }

    // MARK: Files

    /// The outermost project the walk is inside. Only the outermost matters: its
    /// activity already covers every nested project's own files.
    private struct ProjectScope {
        let rootPath: String
        let activity: Date
    }

    private func projectScope(at directory: URL, into result: inout ScanResult) -> ProjectScope {
        do {
            return ProjectScope(rootPath: directory.path, activity: try ProjectActivity.lastActivity(of: directory))
        } catch {
            // Better to leave a project alone than compress one that may be in use.
            result.problems.append("\(directory.path): project activity unknown, treated as active: \(error.localizedDescription)")
            return ProjectScope(rootPath: directory.path, activity: now)
        }
    }

    private func scanFiles(in location: URL, categories: [FileCategory], into result: inout ScanResult) {
        let root = Paths.canonical(location)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        var walkErrors: [String] = []
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                walkErrors.append("\(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            result.problems.append("\(root.path): cannot be listed")
            return
        }
        let rootDepth = root.pathComponents.count
        var project = ProjectActivity.isProjectRoot(root) ? projectScope(at: root, into: &result) : nil
        for case let url as URL in walker {
            if let current = project, !url.path.hasPrefix(current.rootPath + "/") { project = nil }
            let facts: FileFacts
            do {
                facts = try FileFacts.read(url)
            } catch {
                result.problems.append("\(url.path): \(error.localizedDescription)")
                result.skip(.unreadable)
                continue
            }
            let directories = Array(url.deletingLastPathComponent().pathComponents.dropFirst(rootDepth))
            if facts.isDirectory {
                if isExcluded(url) {
                    result.skip(.excludedPath)
                    walker.skipDescendants()
                } else if Self.skippedDirectoryNames.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                } else if project == nil,
                          !(directories + [url.lastPathComponent]).contains(where: Categories.artifactDirectoryNames.contains),
                          ProjectActivity.isProjectRoot(url) {
                    // A package.json inside node_modules is a dependency, not the user's project.
                    project = projectScope(at: url, into: &result)
                }
                continue
            }
            guard facts.isRegularFile else { continue }
            if isExcluded(url) {
                result.skip(.excludedPath)
                continue
            }
            evaluateFile(url, facts: facts, directories: directories, projectActivity: project?.activity, categories: categories, into: &result)
        }
        result.problems += walkErrors
    }

    private func evaluateFile(
        _ url: URL, facts: FileFacts, directories: [String], projectActivity: Date?,
        categories: [FileCategory], into result: inout ScanResult
    ) {
        if facts.isCompressed { return result.skip(.alreadyCompressed) }
        if facts.linkCount > 1 { return result.skip(.hardLinked) }
        if facts.logicalBytes == 0 || facts.logicalBytes < config.minFileBytes { return result.skip(.tooSmall) }
        let ext = url.pathExtension.lowercased()
        if excludedExtensions.contains(ext) { return result.skip(.excludedType) }
        guard let category = categories.first(where: { $0.matches(fileExtension: ext, directories: directories) }) else {
            return result.skip(.noMatchingCategory)
        }
        let filesystemDate = max(facts.modified, facts.accessed, projectActivity ?? .distantPast)
        guard let last = dormantSince(url, filesystemDate: filesystemDate, categoryID: category.id) else {
            return result.skip(.recentlyUsed)
        }
        guard canModify(url) else { return result.skip(.needsAdmin) }
        let ratio: Double
        do {
            ratio = try sampler.compressedRatio(of: url, accessed: facts.accessed)
        } catch {
            result.problems.append("\(url.path): \(error.localizedDescription)")
            return result.skip(.unreadable)
        }
        guard meetsMinimumSavings(ratio) else { return result.skip(.incompressible) }
        var candidate = Candidate(
            url: url, kind: .file, categoryID: category.id, lastActivity: last,
            compressibleBytes: facts.logicalBytes, allocatedBytes: facts.allocatedBytes
        )
        candidate.estimatedSavedBytes = SavingsEstimate.savedBytes(
            allocatedBefore: facts.allocatedBytes, logicalBytes: facts.logicalBytes, ratio: ratio
        )
        result.candidates.append(candidate)
    }
}
