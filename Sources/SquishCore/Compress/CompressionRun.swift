import Foundation

public struct CandidateOutcome {
    public let candidate: Candidate
    public let allocatedAfter: Int64
    public var savedBytes: Int64 { candidate.allocatedBytes - allocatedAfter }
}

public struct RunReport {
    public let outcomes: [CandidateOutcome]
    public let problems: [String]

    public init(outcomes: [CandidateOutcome], problems: [String]) {
        self.outcomes = outcomes
        self.problems = problems
    }
    public var savedBytes: Int64 { outcomes.reduce(0) { $0 + $1.savedBytes } }
    public var compressedCount: Int { outcomes.filter { $0.savedBytes > 0 }.count }
}

public struct CompressionRun {
    let compressor: Compressor
    let batchSize: Int
    let progress: (String) -> Void
    let runningApps: () -> (URL) -> Bool

    public init(
        compressor: Compressor,
        batchSize: Int = 200,
        progress: @escaping (String) -> Void = { _ in },
        runningApps: @escaping () -> (URL) -> Bool = RunningApps.snapshot
    ) {
        self.compressor = compressor
        self.batchSize = batchSize
        self.progress = progress
        self.runningApps = runningApps
    }

    /// Savings are measured from disk afterwards, not taken from afsctool's word.
    public func execute(_ candidates: [Candidate]) -> RunReport {
        var problems: [String] = []
        let work = batches(candidates)
        for (index, batch) in work.enumerated() {
            progress("[\(index + 1)/\(work.count)] \(label(batch))")
            // The scan's snapshot is minutes old by now (confirm prompt, earlier
            // batches), so ask again right before touching an app.
            if batch[0].kind == .app, runningApps()(batch[0].url) {
                progress("  skipped: \(label(batch)) is running now")
                continue
            }
            do {
                try compressor.compress(batch.map(\.url))
            } catch {
                problems.append("\(label(batch)): \(error.localizedDescription)")
            }
        }
        let outcomes = candidates.map { candidate -> CandidateOutcome in
            do {
                return CandidateOutcome(candidate: candidate, allocatedAfter: try DiskUsage.measure(candidate.url).allocatedBytes)
            } catch {
                problems.append("\(candidate.url.path): re-measure failed: \(error.localizedDescription)")
                return CandidateOutcome(candidate: candidate, allocatedAfter: candidate.allocatedBytes)
            }
        }
        return RunReport(outcomes: outcomes, problems: problems)
    }

    /// One call per app (afsctool walks the bundle), loose files in chunks.
    func batches(_ candidates: [Candidate]) -> [[Candidate]] {
        let apps = candidates.filter { $0.kind == .app }.map { [$0] }
        let files = candidates.filter { $0.kind == .file }
        let fileBatches = stride(from: 0, to: files.count, by: batchSize).map {
            Array(files[$0..<min($0 + batchSize, files.count)])
        }
        return apps + fileBatches
    }

    private func label(_ batch: [Candidate]) -> String {
        batch.count == 1 ? batch[0].url.lastPathComponent : "\(batch.count) files"
    }
}
