import Foundation
import CryptoKit

/// Stable identity for normalized session/turn records in the `sessions`
/// store. This ID space is independent from `EvidenceIdentity`: the same
/// source file produces both event IDs and session IDs without collision.
///
/// Rules (per the M2 normalization contract):
/// - Source-provided session/turn identifiers are preferred and preserved
///   verbatim in the record; they are scoped by session so identifiers from
///   different sources cannot collide.
/// - When a source identifier is absent or invalid, identity derives from the
///   source identity and the record coordinates (file path and line), which
///   stay stable across appends and identical re-imports.
/// - Revision identity digests canonical record content, so an amended
///   record yields a new revision linked to the unchanged stable turn ID.
/// IDs are opaque: the first 16 SHA-256 digest bytes as 32 lowercase hex
/// characters. Readable source/path/locator parts never appear in the ID.
enum SessionIdentity {
    static func digest(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// A source identifier is valid when it is a non-empty string after
    /// trimming whitespace; anything else counts as absent.
    static func normalizedID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// The session scope: the source session ID when valid, otherwise the
    /// source file identity. Turns and sessions of one file share this scope,
    /// so a file without source IDs keeps one stable session across imports.
    static func sessionKey(source: SourceKind, sourceSessionID: String?, filePath: String) -> String {
        if let id = normalizedID(sourceSessionID) {
            return "\(source.rawValue)|session|\(id)"
        }
        return "\(source.rawValue)|file|\(filePath)"
    }

    static func sessionID(source: SourceKind, sourceSessionID: String?, filePath: String) -> String {
        digest("reflect-sessions/v1|session|\(sessionKey(source: source, sourceSessionID: sourceSessionID, filePath: filePath))")
    }

    static func turnID(
        source: SourceKind,
        sourceSessionID: String?,
        filePath: String,
        line: Int?,
        sourceTurnID: String?
    ) -> String {
        let key = sessionKey(source: source, sourceSessionID: sourceSessionID, filePath: filePath)
        if let turnID = normalizedID(sourceTurnID) {
            return digest("reflect-sessions/v1|turn|\(key)|src|\(turnID)")
        }
        let linePart = line.map(String.init) ?? "-"
        return digest("reflect-sessions/v1|turn|\(key)|loc|\(filePath)|\(linePart)")
    }

    static func revisionID(
        role: ConversationRole,
        sourceTurnID: String?,
        timestamp: Date?,
        timestampApproximate: Bool,
        retainedText: String
    ) -> String {
        let timePart = timestamp.map { String($0.timeIntervalSince1970) } ?? "-"
        let sourcePart = normalizedID(sourceTurnID) ?? "-"
        return digest(
            "reflect-sessions/v1|revision|\(role.rawValue)|\(sourcePart)|\(timePart)|\(timestampApproximate ? 1 : 0)|\(retainedText)"
        )
    }
}
