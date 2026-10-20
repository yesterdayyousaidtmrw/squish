import Foundation
import SquishCore

struct ScanPrinter {
    let limit: Int

    func printSummary(_ result: ScanResult, config: SquishConfig) {
        print(settingsLine(config))
        let apps = result.candidates.filter { $0.kind == .app }
        let files = result.candidates.filter { $0.kind == .file }
        print("Candidates: \(apps.count) apps (\(Format.bytes(total(apps)))), \(files.count) files (\(Format.bytes(total(files)))); sizes are before compression")
        let estimated = result.candidates.reduce(Int64(0)) { $0 + $1.estimatedSavedBytes }
        let caveat = config.algorithm == .lzfse ? "" : " (sampled with LZFSE; \(config.algorithm.rawValue) will differ)"
        print("Estimated saving: ≈\(Format.bytes(estimated)) on disk\(caveat)")
        let ranked = result.candidates.sorted { $0.estimatedSavedBytes > $1.estimatedSavedBytes }
        for candidate in ranked.prefix(limit) {
            print(row(candidate))
        }
        if ranked.count > limit { print("  … \(ranked.count - limit) more (--all lists every one)") }
        if !result.skips.isEmpty {
            let counts = SkipReason.allCases.compactMap { reason in result.skips[reason].map { "\(reason.rawValue) \($0)" } }
            print("Skipped: " + counts.joined(separator: " · "))
        }
        if let needsAdmin = result.skips[.needsAdmin] {
            print("  \(needsAdmin) item(s) are owned by root; run with sudo to include them.")
        }
        Self.printProblems(result.problems)
    }

    static func printProblems(_ problems: [String], limit: Int = 10) {
        guard !problems.isEmpty else { return }
        print("Problems (\(problems.count)):")
        for problem in problems.prefix(limit) { print("  " + problem) }
        if problems.count > limit { print("  … \(problems.count - limit) more") }
    }

    private func settingsLine(_ config: SquishConfig) -> String {
        let overrides = config.dormantDaysByCategory.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)d" }
        let dormancy = "dormant ≥ \(config.dormantDays)d" + (overrides.isEmpty ? "" : " (\(overrides.joined(separator: ", ")))")
        let algorithm = config.algorithm == .zlib ? "zlib-\(config.zlibLevel)" : config.algorithm.rawValue
        return "Settings: \(dormancy) · categories: \(config.categories.joined(separator: ", ")) · \(algorithm)"
    }

    private func row(_ candidate: Candidate) -> String {
        "  " + Format.pad(candidate.kind.rawValue, 5)
            + Format.padLeft(Format.bytes(candidate.compressibleBytes), 10)
            + Format.padLeft("≈−" + Format.bytes(candidate.estimatedSavedBytes), 12) + "  "
            + Format.padLeft(Format.idleDays(since: candidate.lastActivity), 10) + "  "
            + Format.pad(candidate.categoryID, 18)
            + Paths.abbreviate(candidate.url)
    }

    private func total(_ candidates: [Candidate]) -> Int64 {
        candidates.reduce(0) { $0 + $1.compressibleBytes }
    }
}
