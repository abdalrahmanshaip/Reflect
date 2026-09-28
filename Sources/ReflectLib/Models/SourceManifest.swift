import Foundation

/// Per-source import bookkeeping shown in the Sources view.
public struct SourceManifest: Codable, Hashable {
    public var lastImport: Date?
    public var importedEventCount: Int
    public var filesScanned: Int
    public var note: String?

    public init(lastImport: Date?, importedEventCount: Int, filesScanned: Int, note: String?) {
        self.lastImport = lastImport
        self.importedEventCount = importedEventCount
        self.filesScanned = filesScanned
        self.note = note
    }
}

/// Availability metadata gathered without reading any file contents.
public struct SourceAvailability: Codable, Hashable {
    public enum Status: String, Codable, Hashable {
        case detected
        case detectedUnverified
        case missing
        case manual
    }

    public var status: Status
    public var fileCount: Int
    public var rootPath: String?
    public var lastModified: Date?
    public var note: String?

    public init(status: Status, fileCount: Int, rootPath: String?, lastModified: Date?, note: String?) {
        self.status = status
        self.fileCount = fileCount
        self.rootPath = rootPath
        self.lastModified = lastModified
        self.note = note
    }

    public var displayText: String {
        switch status {
        case .detected:
            return "Detected (\(fileCount) file\(fileCount == 1 ? "" : "s"))"
        case .detectedUnverified:
            return "Detected; format not yet verified (\(fileCount) file\(fileCount == 1 ? "" : "s"))"
        case .missing:
            return "Not detected"
        case .manual:
            return "Selected by user"
        }
    }
}
