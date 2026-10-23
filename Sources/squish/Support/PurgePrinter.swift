import Foundation
import SquishCore

enum PurgePrinter {
    static let limit = 25

    static func printPlan(_ plan: PurgePlan, days: Int) {
        let folders = plan.items.filter(isFolder)
        let caches = plan.items.filter { !isFolder($0) }
        print("Projects untouched for \(days)+ days: \(folders.count) rebuildable folder(s), \(Format.bytes(total(folders)))")
        for item in folders.sorted(by: { $0.bytes > $1.bytes }).prefix(limit) {
            print(row(item, detail: "rebuild: \(item.rebuild)"))
        }
        if folders.count > limit { print("  … \(folders.count - limit) more") }
        if !caches.isEmpty {
            print("Package manager caches: \(Format.bytes(total(caches)))")
            for item in caches {
                if case .toolCache(let command) = item.kind {
                    print(row(item, detail: "`\(command.joined(separator: " "))`; \(item.rebuild)"))
                }
            }
        }
        var kept: [String] = []
        if plan.activeProjects > 0 { kept.append("\(plan.activeProjects) project(s) in use") }
        if plan.openFolders > 0 { kept.append("\(plan.openFolders) folder(s) open in another program") }
        if !kept.isEmpty { print("Kept: " + kept.joined(separator: " · ")) }
        ScanPrinter.printProblems(plan.problems)
    }

    static func printReport(_ report: PurgeReport) {
        print("Moved \(Format.bytes(report.trashedBytes)) to the Trash; empty the Trash to get the space back.")
        if report.clearedBytes > 0 { print("Cleared \(Format.bytes(report.clearedBytes)) of package manager caches.") }
        ScanPrinter.printProblems(report.problems)
    }

    private static func row(_ item: PurgeItem, detail: String) -> String {
        "  " + Format.padLeft(Format.bytes(item.bytes), 10) + "  " + Paths.abbreviate(item.url) + "  (" + detail + ")"
    }

    private static func isFolder(_ item: PurgeItem) -> Bool {
        if case .folder = item.kind { return true }
        return false
    }

    private static func total(_ items: [PurgeItem]) -> Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }
}
