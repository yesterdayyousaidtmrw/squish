import Foundation
import SquishCore

enum ConfigLoader {
    static func store(_ invocation: Invocation) -> ConfigStore {
        invocation.options["--config"].map { ConfigStore(url: Paths.expand($0)) } ?? ConfigStore()
    }

    static func ledgerStore(_ invocation: Invocation) -> LedgerStore {
        LedgerStore(configURL: store(invocation).url)
    }

    /// The saved config with this run's command-line overrides applied on top.
    static func load(_ invocation: Invocation) throws -> SquishConfig {
        var config = try store(invocation).load()
        if let days = try invocation.intOption("--days") {
            config.dormantDays = days
            config.dormantDaysByCategory = [:]
        }
        if let name = invocation.options["--algorithm"] {
            guard let algorithm = CompressionAlgorithm(rawValue: name.lowercased()) else {
                throw UsageError("--algorithm must be one of: \(CompressionAlgorithm.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            config.algorithm = algorithm
        }
        if let only = invocation.options["--only"] {
            config.categories = only.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if let folder = invocation.options["--in"] {
            config.appLocations = [folder]
            config.fileLocations = [folder]
        }
        try config.validate()
        return config
    }
}
