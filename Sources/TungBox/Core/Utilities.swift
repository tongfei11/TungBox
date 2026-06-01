import Foundation

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension DateFormatter {
    static var short: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}


extension NSError {
    static func user(_ message: String) -> NSError {
        NSError(domain: "TungBox", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
