import Foundation
import CryptoKit

/// Stable evidence identity. The same source record always produces the same id,
/// which is what makes repeated imports idempotent.
enum EvidenceIdentity {
    static func stableID(source: SourceKind, path: String, line: Int?, recordType: String) -> String {
        let key = stableKey(source: source, path: path, line: line, recordType: recordType)
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func stableKey(source: SourceKind, path: String, line: Int?, recordType: String) -> String {
        let linePart = line.map(String.init) ?? "-"
        return "\(source.rawValue)|\(path)|\(linePart)|\(recordType)"
    }
}
