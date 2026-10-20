import Foundation

enum Console {
    /// Progress and errors go to stderr so stdout stays the report.
    static func status(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Anything but y/yes, including a closed stdin, is a no.
    static func confirm(_ question: String) -> Bool {
        print("\(question) [y/N] ", terminator: "")
        fflush(stdout)
        guard let answer = readLine()?.lowercased() else { return false }
        return answer == "y" || answer == "yes"
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func idleDays(since date: Date, now: Date = Date()) -> String {
        "\(Int(now.timeIntervalSince(date) / 86_400))d idle"
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func padLeft(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }
}
