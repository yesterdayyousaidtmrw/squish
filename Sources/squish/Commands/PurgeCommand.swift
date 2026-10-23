import Foundation
import SquishCore

enum PurgeCommand {
    static func run(_ invocation: Invocation) throws {
        guard geteuid() != 0 else { throw UsageError("run purge without sudo: it moves your own folders to your own Trash") }
        try invocation.rejectPositionals()
        var config = try ConfigLoader.load(invocation)
        if let days = try invocation.intOption("--days") { config.purgeAfterDays = days }

        Console.status("Looking for rebuildable files…")
        var plan = PurgePlanner(config: config).plan()
        // --in limits the run to one folder; the caches live elsewhere.
        if invocation.options["--in"] == nil {
            plan.items += ToolCacheFinder().find(problems: &plan.problems)
        }
        PurgePrinter.printPlan(plan, days: config.purgeAfterDays)
        guard !plan.items.isEmpty else {
            print("Nothing to purge.")
            return try failIfProblems(plan.problems.count)
        }
        guard invocation.flags.contains("--yes") else {
            let hasCaches = plan.items.contains { if case .toolCache = $0.kind { return true } else { return false } }
            print("Dry run: nothing was changed. Add --yes to move the folders to the Trash\(hasCaches ? " and clear the caches" : "").")
            return try failIfProblems(plan.problems.count)
        }

        let report = PurgeRun(progress: Console.status).execute(plan.items)
        PurgePrinter.printReport(report)
        try failIfProblems(plan.problems.count + report.problems.count)
    }

    private static func failIfProblems(_ count: Int) throws {
        if count > 0 { throw RunError.partialFailure(count) }
    }
}
