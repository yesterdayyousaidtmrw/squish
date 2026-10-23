import Foundation

struct Invocation {
    static let valueOptions: Set<String> = ["--config", "--days", "--algorithm", "--only", "--in", "--hour"]
    static let knownFlags: Set<String> = ["--yes", "--all", "--force", "--help", "-h", "--version"]

    let command: String
    let positionals: [String]
    let flags: Set<String>
    let options: [String: String]

    init(arguments: [String]) throws {
        var positionals: [String] = []
        var flags: Set<String> = []
        var options: [String: String] = [:]
        var remaining = arguments.makeIterator()
        while let argument = remaining.next() {
            if Self.valueOptions.contains(argument) {
                guard let value = remaining.next() else { throw UsageError("\(argument) needs a value") }
                options[argument] = value
            } else if argument.hasPrefix("-") {
                // Rejecting unknowns stops `--days=60` from being dropped in favour of the default.
                guard Self.knownFlags.contains(argument) else {
                    throw UsageError("unknown option \(argument); see `squish help`")
                }
                flags.insert(argument)
            } else {
                positionals.append(argument)
            }
        }
        let wantsHelp = flags.contains("--help") || flags.contains("-h")
        command = wantsHelp ? "help" : flags.contains("--version") ? "version" : positionals.first ?? "help"
        self.positionals = Array(positionals.dropFirst())
        self.flags = flags
        self.options = options
    }

    /// scan and compress work on configured locations; a stray path would otherwise
    /// be ignored and every location processed instead.
    func rejectPositionals() throws {
        if let stray = positionals.first {
            throw UsageError("unexpected argument \"\(stray)\"; use --in <folder> to limit the scan")
        }
    }

    func intOption(_ name: String) throws -> Int? {
        guard let raw = options[name] else { return nil }
        guard let value = Int(raw) else { throw UsageError("\(name) must be a whole number, got \"\(raw)\"") }
        return value
    }
}

struct UsageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
