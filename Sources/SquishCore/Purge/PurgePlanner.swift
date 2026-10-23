import Foundation

/// Finds rebuildable folders in projects nobody has touched for `purgeAfterDays`.
/// Folders outside any project are left alone: with no project around them there
/// is no telling whether anything still needs them.
public struct PurgePlanner {
    let config: SquishConfig
    let openFiles: OpenFileProbe
    let projectBoundary: URL
    let now: Date
    private let exclusions: Exclusions

    public init(
        config: SquishConfig,
        openFiles: OpenFileProbe = LibprocOpenFiles(),
        projectBoundary: URL = Paths.home,
        now: Date = Date()
    ) {
        self.config = config
        self.openFiles = openFiles
        self.projectBoundary = projectBoundary
        self.now = now
        exclusions = Exclusions(config)
    }

    public func plan() -> PurgePlan {
        var plan = PurgePlan()
        let openPaths: Set<String>
        do {
            openPaths = try openFiles.openPaths()
        } catch {
            plan.problems.append("cannot list open files, so nothing was planned: \(error.localizedDescription)")
            return plan
        }
        var seenProjects = Set<String>()
        for location in config.fileLocations {
            let root = Paths.canonical(Paths.expand(location))
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for project in projects(in: root, problems: &plan.problems) where seenProjects.insert(project.path).inserted {
                evaluate(project, within: root, openPaths: openPaths, into: &plan)
            }
        }
        return plan
    }

    /// The outermost projects at or under `root`, or the one enclosing it.
    private func projects(in root: URL, problems: inout [String]) -> [URL] {
        if let enclosing = ProjectActivity.outermostRoot(containing: root, below: projectBoundary) { return [enclosing] }
        var found: [URL] = []
        walkDirectories(under: root, problems: &problems) { directory in
            let name = directory.lastPathComponent
            if name == ".git" || Categories.artifactDirectoryNames.contains(name) || exclusions.contains(directory) {
                return .skip
            }
            guard ProjectActivity.isProjectRoot(directory) else { return .descend }
            found.append(directory)
            return .skip
        }
        return found
    }

    private func evaluate(_ project: URL, within root: URL, openPaths: Set<String>, into plan: inout PurgePlan) {
        guard !exclusions.contains(project) else { return }
        let activity: Date
        do {
            activity = try ProjectActivity.lastActivity(of: project)
        } catch {
            plan.problems.append("\(project.path): project activity unknown, so it was left alone: \(error.localizedDescription)")
            return
        }
        guard now.timeIntervalSince(activity) >= Double(config.purgeAfterDays) * 86_400 else {
            plan.activeProjects += 1
            return
        }
        for (folder, rule) in rebuildableFolders(in: project, problems: &plan.problems) {
            // A location inside the project only covers what is under it.
            guard folder.path == root.path || folder.path.hasPrefix(root.path + "/"), !exclusions.contains(folder) else { continue }
            if openPaths.contains(where: { $0.hasPrefix(folder.path + "/") }) {
                plan.openFolders += 1
                continue
            }
            do {
                let bytes = try DiskUsage.measure(folder).allocatedBytes
                plan.items.append(PurgeItem(url: folder, kind: .folder(lastActivity: activity), bytes: bytes, rebuild: rule.rebuild))
            } catch {
                plan.problems.append("\(folder.path): \(error.localizedDescription)")
            }
        }
    }

    private func rebuildableFolders(in project: URL, problems: inout [String]) -> [(URL, RebuildableFolder)] {
        var found: [(URL, RebuildableFolder)] = []
        walkDirectories(under: project, problems: &problems) { directory in
            if directory.lastPathComponent == ".git" { return .skip }
            if let rule = RebuildableFolder.matching(directory) {
                found.append((directory, rule))
                return .skip
            }
            // Named like build output but without its tool's marker: someone's own folder.
            return Categories.artifactDirectoryNames.contains(directory.lastPathComponent) ? .skip : .descend
        }
        return found
    }

    private enum WalkDecision {
        case descend
        case skip
    }

    private func walkDirectories(under root: URL, problems: inout [String], decide: (URL) -> WalkDecision) {
        var walkErrors: [String] = []
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                walkErrors.append("\(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            problems.append("\(root.path): cannot be listed")
            return
        }
        for case let url as URL in walker {
            let facts: FileFacts
            do {
                facts = try FileFacts.read(url)
            } catch {
                problems.append("\(url.path): \(error.localizedDescription)")
                continue
            }
            if facts.isDirectory, decide(url) == .skip { walker.skipDescendants() }
        }
        problems += walkErrors
    }
}
