import Foundation

do {
    let invocation = try Invocation(arguments: Array(CommandLine.arguments.dropFirst()))
    switch invocation.command {
    case "scan": try ScanCommand.run(invocation)
    case "compress": try CompressCommand.run(invocation)
    case "status": try StatusCommand.run(invocation)
    case "restore": try RestoreCommand.run(invocation)
    case "config": try ConfigCommand.run(invocation)
    case "categories": try CategoriesCommand.run(invocation)
    case "schedule": try ScheduleCommand.run(invocation)
    case "help": HelpCommand.run()
    default: throw UsageError("unknown command \"\(invocation.command)\"; see `squish help`")
    }
} catch {
    Console.status("squish: \(error.localizedDescription)")
    exit(1)
}
