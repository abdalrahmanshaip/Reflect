import Foundation
@testable import ReflectLib

struct BoundedContextTests {
    static let suiteName = "BoundedContextTests"

    // MARK: Synthetic helpers (never real activity)

    /// Encodes with sorted keys so the JSON text is deterministic, then decodes back.
    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func jsonString<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
    }

    private func syntheticBudget(
        maxItemCount: Int = 4,
        maxByteCount: Int = 256,
        maxTurnCount: Int = 8
    ) throws -> BoundedContextBudget {
        try BoundedContextBudget(maxItemCount: maxItemCount, maxByteCount: maxByteCount, maxTurnCount: maxTurnCount)
    }

    private func syntheticCoverage(
        includedItemCount: Int = 2,
        omittedItemCount: Int = 1,
        truncatedItemCount: Int = 0,
        includedByteCount: Int = 96,
        includedTurnCount: Int = 3,
        state: SourceCoverageState = .partial
    ) throws -> BoundedContextCoverage {
        try BoundedContextCoverage(
            includedItemCount: includedItemCount,
            omittedItemCount: omittedItemCount,
            truncatedItemCount: truncatedItemCount,
            includedByteCount: includedByteCount,
            includedTurnCount: includedTurnCount,
            state: state
        )
    }

    private func syntheticDescriptor(
        budget: BoundedContextBudget? = nil,
        coverage: BoundedContextCoverage? = nil
    ) throws -> BoundedContextDescriptor {
        try BoundedContextDescriptor(
            budget: try budget ?? syntheticBudget(),
            coverage: try coverage ?? syntheticCoverage()
        )
    }

    private func descriptorJSON(
        maxItemCount: Int,
        maxByteCount: Int,
        maxTurnCount: Int,
        includedItemCount: Int,
        omittedItemCount: Int,
        truncatedItemCount: Int,
        includedByteCount: Int,
        includedTurnCount: Int,
        state: String
    ) -> Data {
        Data("""
        {"budget":{"maxByteCount":\(maxByteCount),"maxItemCount":\(maxItemCount),"maxTurnCount":\(maxTurnCount)},"coverage":{"includedByteCount":\(includedByteCount),"includedItemCount":\(includedItemCount),"includedTurnCount":\(includedTurnCount),"omittedItemCount":\(omittedItemCount),"state":"\(state)","truncatedItemCount":\(truncatedItemCount)}}
        """.utf8)
    }

    private func budgetJSON(maxItemCount: Int, maxByteCount: Int, maxTurnCount: Int) -> Data {
        Data("""
        {"maxByteCount":\(maxByteCount),"maxItemCount":\(maxItemCount),"maxTurnCount":\(maxTurnCount)}
        """.utf8)
    }

    private func coverageJSON(
        includedItemCount: Int,
        omittedItemCount: Int,
        truncatedItemCount: Int,
        includedByteCount: Int,
        includedTurnCount: Int,
        state: String
    ) -> Data {
        Data("""
        {"includedByteCount":\(includedByteCount),"includedItemCount":\(includedItemCount),"includedTurnCount":\(includedTurnCount),"omittedItemCount":\(omittedItemCount),"state":"\(state)","truncatedItemCount":\(truncatedItemCount)}
        """.utf8)
    }

    private func expectValidationThrows(
        _ expected: BoundedContextValidationError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ build: () throws -> Void
    ) throws {
        do {
            try build()
            throw TestFailure("\(file):\(line): expected init to throw \(expected) \(message)")
        } catch let error as BoundedContextValidationError {
            try expectEqual(error, expected, message, file: file, line: line)
        } catch {
            throw TestFailure("\(file):\(line): expected BoundedContextValidationError \(expected), got \(error) \(message)")
        }
    }

    private func expectDecodeThrows<Value: Decodable>(
        _ type: Value.Type,
        _ data: Data,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        do {
            _ = try JSONDecoder().decode(type, from: data)
            throw TestFailure("\(file):\(line): expected decoding to fail — \(message)")
        } catch is DecodingError {
            // Expected: corrupt persisted metadata must be rejected as a decoding error.
        } catch {
            throw TestFailure("\(file):\(line): expected DecodingError, got \(error) — \(message)")
        }
    }

    // MARK: Exact Codable round trip

    func descriptorRoundTripsExactlyAcrossEveryCoverageState() throws {
        try expectEqual(SourceCoverageState.allCases.count, 4, "source coverage has exactly four states")
        let expectedRawValues: [SourceCoverageState: String] = [
            .complete: "complete",
            .partial: "partial",
            .unavailable: "unavailable",
            .unknown: "unknown"
        ]
        for (state, rawValue) in expectedRawValues {
            let coverage: BoundedContextCoverage
            switch state {
            case .complete:
                coverage = try syntheticCoverage(
                    includedItemCount: 2, omittedItemCount: 0, truncatedItemCount: 0,
                    includedByteCount: 96, includedTurnCount: 3, state: .complete
                )
            case .partial:
                coverage = try syntheticCoverage(
                    includedItemCount: 2, omittedItemCount: 1, truncatedItemCount: 1,
                    includedByteCount: 96, includedTurnCount: 3, state: .partial
                )
            case .unavailable:
                coverage = try syntheticCoverage(
                    includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
                    includedByteCount: 0, includedTurnCount: 0, state: .unavailable
                )
            case .unknown:
                coverage = try syntheticCoverage(
                    includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
                    includedByteCount: 0, includedTurnCount: 0, state: .unknown
                )
            }
            let descriptor = try syntheticDescriptor(coverage: coverage)
            let decoded = try roundTrip(descriptor)
            try expectEqual(decoded, descriptor, "\(rawValue) coverage must survive a Codable round trip unchanged")
            try expectEqual(decoded.coverage.state, state)
            try expectEqual(decoded.budget, descriptor.budget)
            try expectTrue(
                try jsonString(descriptor).contains("\"\(rawValue)\""),
                "encoded JSON must use the exact state raw value \(rawValue)"
            )
        }
    }

    // MARK: At-boundary metadata

    func atBoundaryMetadataIsAccepted() throws {
        // A budget of exactly 1 in every dimension is positive and therefore valid.
        let minimalBudget = try BoundedContextBudget(maxItemCount: 1, maxByteCount: 1, maxTurnCount: 1)
        try expectEqual(minimalBudget.maxItemCount, 1)

        // Coverage counts of exactly zero are nonnegative and therefore valid.
        let emptyCoverage = try BoundedContextCoverage(
            includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
            includedByteCount: 0, includedTurnCount: 0, state: .unavailable
        )
        try expectEqual(emptyCoverage.includedItemCount, 0)

        // Included equal to the maximum in every dimension is exactly at budget.
        // With nothing omitted or truncated the honest state is `.complete`.
        let atBoundary = try BoundedContextDescriptor(
            budget: minimalBudget,
            coverage: try BoundedContextCoverage(
                includedItemCount: 1, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 1, includedTurnCount: 1, state: .complete
            )
        )
        try expectEqual(atBoundary.coverage.includedItemCount, minimalBudget.maxItemCount)
        try expectEqual(atBoundary.coverage.includedByteCount, minimalBudget.maxByteCount)
        try expectEqual(atBoundary.coverage.includedTurnCount, minimalBudget.maxTurnCount)

        // The same boundary metadata must also decode: an at-budget descriptor is
        // not rejected by the persistence path either.
        let decoded = try roundTrip(atBoundary)
        try expectEqual(decoded, atBoundary, "at-boundary metadata must survive a Codable round trip unchanged")

        // `partial` needs only one of the two counts positive: truncation alone is valid.
        let truncatedOnly = try BoundedContextCoverage(
            includedItemCount: 1, omittedItemCount: 0, truncatedItemCount: 1,
            includedByteCount: 1, includedTurnCount: 1, state: .partial
        )
        try expectEqual(truncatedOnly.state, SourceCoverageState.partial)

        // `unknown` carries no count relation: counts of any size stay valid.
        let unassessedWithCounts = try BoundedContextCoverage(
            includedItemCount: 1, omittedItemCount: 2, truncatedItemCount: 0,
            includedByteCount: 1, includedTurnCount: 1, state: .unknown
        )
        try expectEqual(unassessedWithCounts.state, SourceCoverageState.unknown)

        // Byte counts mean UTF-8 encoded bytes: a multibyte fixture whose UTF-8
        // byte total equals the byte maximum must be accepted.
        let text = "café ☕ — Reflection"
        let utf8Bytes = text.utf8.count
        try expectTrue(utf8Bytes > text.count, "the fixture must actually contain multibyte characters")
        let utf8Descriptor = try BoundedContextDescriptor(
            budget: try BoundedContextBudget(maxItemCount: 1, maxByteCount: utf8Bytes, maxTurnCount: 1),
            coverage: try BoundedContextCoverage(
                includedItemCount: 1, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: utf8Bytes, includedTurnCount: 1, state: .complete
            )
        )
        try expectEqual(utf8Descriptor.coverage.includedByteCount, text.utf8.count)
    }

    // MARK: Rejected values in direct initialization

    func invalidValuesAreRejectedByThrowingInitializers() throws {
        // Budget maxima must be strictly positive: zero and negative are rejected.
        try expectValidationThrows(.nonPositiveMaximum(.itemCount)) {
            _ = try BoundedContextBudget(maxItemCount: 0, maxByteCount: 64, maxTurnCount: 8)
        }
        try expectValidationThrows(.nonPositiveMaximum(.itemCount)) {
            _ = try BoundedContextBudget(maxItemCount: -1, maxByteCount: 64, maxTurnCount: 8)
        }
        try expectValidationThrows(.nonPositiveMaximum(.byteCount)) {
            _ = try BoundedContextBudget(maxItemCount: 4, maxByteCount: 0, maxTurnCount: 8)
        }
        try expectValidationThrows(.nonPositiveMaximum(.turnCount)) {
            _ = try BoundedContextBudget(maxItemCount: 4, maxByteCount: 64, maxTurnCount: -3)
        }

        // Coverage counts must be nonnegative: every negative count is rejected.
        try expectValidationThrows(.negativeCount(.includedItemCount)) {
            _ = try BoundedContextCoverage(
                includedItemCount: -1, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 0, includedTurnCount: 0, state: .complete
            )
        }
        try expectValidationThrows(.negativeCount(.omittedItemCount)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 0, omittedItemCount: -2, truncatedItemCount: 0,
                includedByteCount: 0, includedTurnCount: 0, state: .complete
            )
        }
        try expectValidationThrows(.negativeCount(.truncatedItemCount)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: -1,
                includedByteCount: 0, includedTurnCount: 0, state: .complete
            )
        }
        try expectValidationThrows(.negativeCount(.includedByteCount)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: -8, includedTurnCount: 0, state: .complete
            )
        }
        try expectValidationThrows(.negativeCount(.includedTurnCount)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 0, includedTurnCount: -1, state: .complete
            )
        }

        // Included totals may never exceed the paired budget's maxima.
        try expectValidationThrows(.includedExceedsMaximum(.includedItemCount, included: 5, maximum: 4)) {
            _ = try BoundedContextDescriptor(
                budget: try self.syntheticBudget(),
                coverage: try self.syntheticCoverage(includedItemCount: 5, includedByteCount: 64, includedTurnCount: 3)
            )
        }
        try expectValidationThrows(.includedExceedsMaximum(.includedByteCount, included: 257, maximum: 256)) {
            _ = try BoundedContextDescriptor(
                budget: try self.syntheticBudget(),
                coverage: try self.syntheticCoverage(includedItemCount: 4, includedByteCount: 257, includedTurnCount: 3)
            )
        }
        try expectValidationThrows(.includedExceedsMaximum(.includedTurnCount, included: 9, maximum: 8)) {
            _ = try BoundedContextDescriptor(
                budget: try self.syntheticBudget(),
                coverage: try self.syntheticCoverage(includedItemCount: 4, includedByteCount: 64, includedTurnCount: 9)
            )
        }

        // The coverage state must agree with the counts.
        try expectValidationThrows(.stateInconsistentWithCounts(.complete)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 2, omittedItemCount: 1, truncatedItemCount: 0,
                includedByteCount: 64, includedTurnCount: 3, state: .complete
            )
        }
        try expectValidationThrows(.stateInconsistentWithCounts(.complete)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 2, omittedItemCount: 0, truncatedItemCount: 1,
                includedByteCount: 64, includedTurnCount: 3, state: .complete
            )
        }
        try expectValidationThrows(.stateInconsistentWithCounts(.partial)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 2, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 64, includedTurnCount: 3, state: .partial
            )
        }
        try expectValidationThrows(.stateInconsistentWithCounts(.unavailable)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 1, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 0, includedTurnCount: 0, state: .unavailable
            )
        }
        try expectValidationThrows(.stateInconsistentWithCounts(.unavailable)) {
            _ = try BoundedContextCoverage(
                includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 0, includedTurnCount: 4, state: .unavailable
            )
        }
    }

    // MARK: Rejected corrupt persisted values

    func corruptPersistedValuesAreRejectedByDecoding() throws {
        // A persisted budget with a zero or negative maximum must not decode.
        try expectDecodeThrows(BoundedContextBudget.self, budgetJSON(maxItemCount: 0, maxByteCount: 64, maxTurnCount: 8), "a zero maximum is not a positive budget")
        try expectDecodeThrows(BoundedContextBudget.self, budgetJSON(maxItemCount: -1, maxByteCount: 64, maxTurnCount: 8), "a negative maximum is not a positive budget")
        try expectDecodeThrows(BoundedContextBudget.self, budgetJSON(maxItemCount: 4, maxByteCount: 0, maxTurnCount: 8), "a zero byte maximum is not a positive budget")
        try expectDecodeThrows(BoundedContextBudget.self, budgetJSON(maxItemCount: 4, maxByteCount: 64, maxTurnCount: 0), "a zero turn maximum is not a positive budget")

        // A persisted coverage with a negative count must not decode.
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: -1, omittedItemCount: 0, truncatedItemCount: 0, includedByteCount: 0, includedTurnCount: 0, state: "complete"),
            "a negative item count must not decode"
        )
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0, includedByteCount: -8, includedTurnCount: 0, state: "complete"),
            "a negative byte count must not decode"
        )

        // A persisted state outside the agreed four-state vocabulary must not decode.
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: 0, omittedItemCount: 0, truncatedItemCount: 0, includedByteCount: 0, includedTurnCount: 0, state: "everything"),
            "an unknown state raw value must not decode"
        )

        // A persisted coverage whose state contradicts its counts must not decode.
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: 2, omittedItemCount: 1, truncatedItemCount: 0, includedByteCount: 64, includedTurnCount: 3, state: "complete"),
            "complete coverage with omitted items must not decode"
        )
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: 2, omittedItemCount: 0, truncatedItemCount: 0, includedByteCount: 64, includedTurnCount: 3, state: "partial"),
            "partial coverage with nothing omitted or truncated must not decode"
        )
        try expectDecodeThrows(
            BoundedContextCoverage.self,
            coverageJSON(includedItemCount: 1, omittedItemCount: 0, truncatedItemCount: 0, includedByteCount: 0, includedTurnCount: 0, state: "unavailable"),
            "unavailable coverage with included items must not decode"
        )

        // The same consistency rules are inherited by descriptor decoding:
        // an individually well-formed coverage is rejected inside a descriptor.
        try expectDecodeThrows(
            BoundedContextDescriptor.self,
            descriptorJSON(
                maxItemCount: 4, maxByteCount: 256, maxTurnCount: 8,
                includedItemCount: 2, omittedItemCount: 1, truncatedItemCount: 0,
                includedByteCount: 64, includedTurnCount: 3, state: "complete"
            ),
            "a descriptor holding complete coverage with omitted items must not decode"
        )

        // A descriptor whose individually valid coverage exceeds its own budget
        // must not decode on any dimension.
        try expectDecodeThrows(
            BoundedContextDescriptor.self,
            descriptorJSON(
                maxItemCount: 4, maxByteCount: 256, maxTurnCount: 8,
                includedItemCount: 5, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 64, includedTurnCount: 3, state: "partial"
            ),
            "included items above the budget maximum must not decode"
        )
        try expectDecodeThrows(
            BoundedContextDescriptor.self,
            descriptorJSON(
                maxItemCount: 4, maxByteCount: 256, maxTurnCount: 8,
                includedItemCount: 4, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 300, includedTurnCount: 3, state: "partial"
            ),
            "included bytes above the budget maximum must not decode"
        )
        try expectDecodeThrows(
            BoundedContextDescriptor.self,
            descriptorJSON(
                maxItemCount: 4, maxByteCount: 256, maxTurnCount: 8,
                includedItemCount: 4, omittedItemCount: 0, truncatedItemCount: 0,
                includedByteCount: 64, includedTurnCount: 9, state: "partial"
            ),
            "included turns above the budget maximum must not decode"
        )

        // Valid persisted JSON still decodes exactly.
        let descriptor = try syntheticDescriptor()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(descriptor)
        let decoded = try JSONDecoder().decode(BoundedContextDescriptor.self, from: data)
        try expectEqual(decoded, descriptor, "valid persisted metadata must decode unchanged")
    }

    // MARK: Deterministic JSON

    func encodedJSONIsDeterministicWithExactSortedFields() throws {
        let descriptor = try syntheticDescriptor()
        let first = try jsonString(descriptor)
        let second = try jsonString(descriptor)
        try expectEqual(first, second, "the same metadata must encode to byte-identical JSON every time")

        let expected = """
        {"budget":{"maxByteCount":256,"maxItemCount":4,"maxTurnCount":8},"coverage":{"includedByteCount":96,"includedItemCount":2,"includedTurnCount":3,"omittedItemCount":1,"state":"partial","truncatedItemCount":0}}
        """
        try expectEqual(first, expected, "JSON keys must be sorted and raw values exact")

        // The exact deterministic text must decode back to the same descriptor.
        let decoded = try JSONDecoder().decode(BoundedContextDescriptor.self, from: Data(expected.utf8))
        try expectEqual(decoded, descriptor)
    }
}

extension BoundedContextTests {
    static var entries: [TestEntry] {
        let tests = BoundedContextTests()
        return [
            TestEntry(suite: suiteName, name: "descriptorRoundTripsExactlyAcrossEveryCoverageState") {
                try tests.descriptorRoundTripsExactlyAcrossEveryCoverageState()
            },
            TestEntry(suite: suiteName, name: "atBoundaryMetadataIsAccepted") {
                try tests.atBoundaryMetadataIsAccepted()
            },
            TestEntry(suite: suiteName, name: "invalidValuesAreRejectedByThrowingInitializers") {
                try tests.invalidValuesAreRejectedByThrowingInitializers()
            },
            TestEntry(suite: suiteName, name: "corruptPersistedValuesAreRejectedByDecoding") {
                try tests.corruptPersistedValuesAreRejectedByDecoding()
            },
            TestEntry(suite: suiteName, name: "encodedJSONIsDeterministicWithExactSortedFields") {
                try tests.encodedJSONIsDeterministicWithExactSortedFields()
            }
        ]
    }
}
