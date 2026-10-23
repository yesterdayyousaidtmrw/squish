import Foundation
import SquishCore

enum ScheduleCommand {
    static func run(_ invocation: Invocation) throws {
        guard geteuid() != 0 else { throw UsageError("run schedule without sudo; it installs a per-user LaunchAgent") }
        let agent = LaunchAgent()
        switch invocation.positionals.first {
        case nil, "show":
            print(agent.isInstalled ? "Installed: \(agent.plistURL.path)\nLog: \(agent.logURL.path)" : "Not installed.")
        case "install":
            let hour = try invocation.intOption("--hour") ?? 3
            guard (0...23).contains(hour) else { throw UsageError("--hour must be 0-23") }
            guard let binary = Bundle.main.executableURL else {
                throw UsageError("cannot work out where the squish binary lives")
            }
            let executable = ExecutablePath.stable(
                executable: binary, searchPath: ProcessInfo.processInfo.environment["PATH"] ?? ""
            )
            if executable.path.contains("/.build/") {
                Console.status("warning: scheduling a binary inside .build; a clean or rebuild will break the job. Copy it somewhere stable first.")
            }
            _ = try AfsctoolCompressor.locate()
            try agent.install(executable: executable, hour: hour)
            print("Installed: `\(executable.path) compress --yes` runs daily at \(hour):00.\nLog: \(agent.logURL.path)")
        case "uninstall":
            try agent.uninstall()
            print("Removed.")
        default:
            throw UsageError("usage: squish schedule [show | install [--hour N] | uninstall]")
        }
    }
}
