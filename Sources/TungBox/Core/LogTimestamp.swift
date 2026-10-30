import Foundation

@MainActor
enum LogTimestamp {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    private static let timestamp = try! NSRegularExpression(pattern: #"^(?:[+-]\d{4}\s+)?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}"#)
    private static let ansi = try! NSRegularExpression(pattern: "\\u001B\\[[0-9;]*m")

    /// Capture arrival time once, before either persistence or presentation.
    /// Existing Core timestamps and blank lines are preserved.
    static func addingMissing(to text: String, at date: Date = Date()) -> String {
        formatter.timeZone = .current
        let prefix = formatter.string(from: date) + " "
        return text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let plain = ansi.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "")
            guard timestamp.firstMatch(in: plain, range: NSRange(location: 0, length: (plain as NSString).length)) == nil else { return line }
            return prefix + line
        }.joined(separator: "\n")
    }
}
