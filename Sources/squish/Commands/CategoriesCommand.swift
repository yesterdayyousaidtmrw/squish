import Foundation
import SquishCore

enum CategoriesCommand {
    static func run(_ invocation: Invocation) throws {
        let config = try ConfigLoader.load(invocation)
        for category in Categories.all {
            let marker = config.categories.contains(category.id) ? "on " : "off"
            let days = Format.padLeft("\(config.dormantDays(forCategory: category.id))d", 5)
            print("\(marker)  \(Format.pad(category.id, 18))\(days)  \(category.summary)")
        }
    }
}
