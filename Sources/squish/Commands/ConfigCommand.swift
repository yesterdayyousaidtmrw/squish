import Foundation
import SquishCore

enum ConfigCommand {
    static func run(_ invocation: Invocation) throws {
        let store = ConfigLoader.store(invocation)
        switch invocation.positionals.first {
        case nil, "show":
            let note = store.exists ? "" : " (not created yet; these are the defaults)"
            print("# \(store.url.path)\(note)")
            print(String(decoding: try ConfigStore.encode(try store.load()), as: UTF8.self))
        case "path":
            print(store.url.path)
        case "init":
            if store.exists && !invocation.flags.contains("--force") {
                throw UsageError("\(store.url.path) already exists (--force overwrites it with the defaults)")
            }
            try store.save(.standard)
            print("Wrote defaults to \(store.url.path)")
        default:
            throw UsageError("usage: squish config [show | path | init [--force]]")
        }
    }
}
