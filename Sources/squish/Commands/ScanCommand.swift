import Foundation
import SquishCore

enum ScanCommand {
    static func run(_ invocation: Invocation) throws {
        try invocation.rejectPositionals()
        let config = try ConfigLoader.load(invocation)
        // Read only: a dry run reports rewrites but leaves recording them to compress.
        let ledger = try ConfigLoader.ledgerStore(invocation).load()
        let result = scan(config, ledger: ledger)
        ScanPrinter(limit: invocation.flags.contains("--all") ? .max : 25).printSummary(result, config: config)
    }

    static func scan(_ config: SquishConfig, ledger: ChurnLedger) -> ScanResult {
        Console.status("Scanning…")
        return CandidateScanner(config: config, ledger: ledger).scan()
    }
}
