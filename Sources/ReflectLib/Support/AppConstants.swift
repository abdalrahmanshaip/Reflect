import Foundation

enum AppConstants {
    static let appSupportFolderName = "Reflect"
    static let keychainService = "Reflect.provider"
    static let keychainAccount = "apiKey"

    /// A daily report needs at least this many events before a coaching question is offered.
    static let minimumEventsForQuestion = 3
    /// Growth readings need at least this many events across at least this many days.
    static let minimumEventsForGrowth = 10
    static let minimumDistinctDaysForGrowth = 3
    static let maxGitCommits = 2000
}

enum JSONParsing {
    static func object(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    static func cappedPreview(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// Collects readable text from the many "content" shapes these formats use.
    static func text(from content: Any?, limit: Int) -> String {
        var parts: [String] = []
        switch content {
        case let text as String:
            parts.append(text)
        case let blocks as [[String: Any]]:
            for block in blocks {
                if let text = block["text"] as? String {
                    parts.append(text)
                } else if let input = block["input_text"] as? String {
                    parts.append(input)
                }
            }
        default:
            break
        }
        return cappedPreview(parts.joined(separator: " "), limit: limit)
    }
}
