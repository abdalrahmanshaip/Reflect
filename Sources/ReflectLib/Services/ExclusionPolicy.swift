import Foundation

/// Privacy exclusions: any path containing one of the user's tokens is never imported.
struct ExclusionPolicy: Equatable {
    let substrings: [String]

    init(_ substrings: [String]) {
        self.substrings = substrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func isExcluded(path: String) -> Bool {
        substrings.contains { path.range(of: $0, options: .caseInsensitive) != nil }
    }
}
