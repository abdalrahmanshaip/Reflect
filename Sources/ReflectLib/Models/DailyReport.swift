import Foundation

/// An editable daily reflection report. Answers and edits are user content, kept distinct
/// from generated drafts and from imported evidence.
public struct DailyReport: Codable, Identifiable, Hashable {
    public var id: String { day }
    public let day: String
    public var narrative: String
    public var narrativeGeneratedAt: Date?
    public var answers: [String: AnswerEntry]
    public var analysisResult: String?
    public var analysisGeneratedAt: Date?
    public var updatedAt: Date

    public init(
        day: String,
        narrative: String,
        narrativeGeneratedAt: Date?,
        answers: [String: AnswerEntry],
        analysisResult: String?,
        analysisGeneratedAt: Date?,
        updatedAt: Date
    ) {
        self.day = day
        self.narrative = narrative
        self.narrativeGeneratedAt = narrativeGeneratedAt
        self.answers = answers
        self.analysisResult = analysisResult
        self.analysisGeneratedAt = analysisGeneratedAt
        self.updatedAt = updatedAt
    }
}

public struct AnswerEntry: Codable, Hashable {
    public var text: String
    public var updatedAt: Date

    public init(text: String, updatedAt: Date) {
        self.text = text
        self.updatedAt = updatedAt
    }
}
