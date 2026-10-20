import Foundation

public struct LaunchAgent {
    public static let label = "local.squish.compress"

    public let plistURL: URL
    public let logURL: URL
    private var domain: String { "gui/\(getuid())" }

    public init(home: URL = Paths.home) {
        plistURL = home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        logURL = home.appendingPathComponent("Library/Logs/squish.log")
    }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public func definition(executable: URL, hour: Int) -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": [executable.path, "compress", "--yes"],
            "StartCalendarInterval": ["Hour": hour, "Minute": 0],
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
        ]
    }

    public func install(executable: URL, hour: Int) throws {
        try uninstall()
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: definition(executable: executable, hour: hour), format: .xml, options: 0
        )
        try data.write(to: plistURL, options: .atomic)
        try launchctl(["bootstrap", domain, plistURL.path])
    }

    public func uninstall() throws {
        if try isLoaded() { try launchctl(["bootout", "\(domain)/\(Self.label)"]) }
        if isInstalled { try FileManager.default.removeItem(at: plistURL) }
    }

    private func isLoaded() throws -> Bool {
        try ProcessRunner.run(Self.launchctlURL, arguments: ["print", "\(domain)/\(Self.label)"]).status == 0
    }

    private static let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")

    private func launchctl(_ arguments: [String]) throws {
        let outcome = try ProcessRunner.run(Self.launchctlURL, arguments: arguments)
        guard outcome.status == 0 else {
            throw CompressorError.failed(status: outcome.status, output: "launchctl \(arguments.first ?? ""): \(outcome.stderr)")
        }
    }
}
