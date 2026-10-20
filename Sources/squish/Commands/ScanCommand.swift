import Foundation
import SquishCore

enum ScanCommand {
    static func run(_ invocation: Invocation) throws {
        try invocation.rejectPositionals()
        let config = try ConfigLoader.load(invocation)
        let result = scan(config)
        ScanPrinter(limit: invocation.flags.contains("--all") ? .max : 25).printSummary(result, config: config)
    }

    static func scan(_ config: SquishConfig) -> ScanResult {
        Console.status("Scanning…")
        return CandidateScanner(config: config).scan()
    }
}
