import Foundation
import SquishCore

enum CompressCommand {
    static func run(_ invocation: Invocation) throws {
        try invocation.rejectPositionals()
        let config = try ConfigLoader.load(invocation)
        let compressor = AfsctoolCompressor(executable: try AfsctoolCompressor.locate(), config: config)
        let result = ScanCommand.scan(config)
        ScanPrinter(limit: 10).printSummary(result, config: config)
        guard !result.candidates.isEmpty else {
            print("Nothing to compress.")
            return try failIfProblems(result.problems.count)
        }
        guard invocation.flags.contains("--yes") || Console.confirm("Compress \(result.candidates.count) item(s) in place?") else {
            return print("Cancelled.")
        }

        let report = CompressionRun(compressor: compressor, progress: Console.status).execute(result.candidates)
        print("Saved \(Format.bytes(report.savedBytes)) on disk across \(report.compressedCount) of \(report.outcomes.count) item(s).")
        for outcome in report.outcomes.sorted(by: { $0.savedBytes > $1.savedBytes }).prefix(10) where outcome.savedBytes > 0 {
            print("  " + Format.padLeft(Format.bytes(outcome.savedBytes), 10) + "  " + Paths.abbreviate(outcome.candidate.url))
        }
        ScanPrinter.printProblems(report.problems)
        try failIfProblems(result.problems.count + report.problems.count)
    }

    /// Scan problems count too: an unreadable folder is work that silently did not happen.
    private static func failIfProblems(_ count: Int) throws {
        if count > 0 { throw RunError.partialFailure(count) }
    }
}

enum RunError: LocalizedError {
    case partialFailure(Int)

    var errorDescription: String? {
        switch self {
        case .partialFailure(let count): return "\(count) problem(s), listed above"
        }
    }
}
