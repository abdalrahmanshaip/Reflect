import Foundation

/// The versioned JSON envelope wrapping each store payload on disk.
///
/// - `store` pins stable store identity, so a file can never be read as, or
///   replaced by, another store's data.
/// - `schemaVersion` pins the payload schema generation. Version 0 is the
///   legacy bare payload written before envelopes existed; version 1 is the
///   first enveloped generation, matching `StoreName.schemaVersion`.
/// - `payload` keeps each store's existing Codable shape unchanged.
struct StoreEnvelope<Payload: Codable>: Codable {
    let store: StoreName
    let schemaVersion: Int
    let payload: Payload

    private enum CodingKeys: String, CodingKey {
        case store
        case schemaVersion
        case payload
    }

    init(store: StoreName, schemaVersion: Int, payload: Payload) {
        self.store = store
        self.schemaVersion = schemaVersion
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decode(String.self, forKey: .store)
        guard let parsedStore = StoreName(rawValue: identity) else {
            throw DecodingError.dataCorruptedError(
                forKey: .store,
                in: container,
                debugDescription: "Unknown store identity."
            )
        }
        store = parsedStore
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        payload = try container.decode(Payload.self, forKey: .payload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(store.rawValue, forKey: .store)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(payload, forKey: .payload)
    }
}

/// Typed reasons an existing store file is rejected before it may be read as
/// data or replaced by an ordinary save. Carries only structural facts — never
/// payload bytes, transcript content, or file paths.
enum StoreFileRejection: Error, Equatable {
    /// Not decodable JSON, a broken envelope, or a payload that does not match
    /// the store's Codable shape.
    case malformed
    /// An envelope whose store identity belongs to a different store.
    case wrongStore(found: String)
    /// A schema version newer than this build supports.
    case unsupportedSchema(found: Int)
    /// A schema version that is present but not a usable version integer.
    case invalidVersion
    /// A readable legacy bare payload that must not be replaced by an ordinary
    /// save: the original would be destroyed before the explicit migration
    /// path (with its protected backup and manifest) exists.
    case legacyNeedsMigration
    /// A migration or rollback is in progress, so the on-disk set is a mixed
    /// generation: reads and ordinary saves pause until it finishes or is
    /// explicitly rolled back.
    case migrationInProgress

    /// Safe English message for the store health surface. It names the store
    /// only — never payload bytes, transcript content, or private paths.
    func userMessage(for store: StoreName) -> String {
        switch self {
        case .malformed:
            return StoreHealthMessages.loadFailed(store)
        case .wrongStore:
            return StoreHealthMessages.wrongStoreContent(store)
        case .unsupportedSchema:
            return StoreHealthMessages.unsupportedSchemaVersion(store)
        case .invalidVersion:
            return StoreHealthMessages.invalidSchemaVersion(store)
        case .legacyNeedsMigration:
            return StoreHealthMessages.legacyNeedsMigration(store)
        case .migrationInProgress:
            return StoreHealthMessages.migrationInProgress(store)
        }
    }
}

/// The on-disk generation of a readable store file.
enum StoreFileGeneration: Equatable {
    /// The bare payload written before envelopes existed (schema version 0).
    /// Legacy reads are read-only: the file stays untouched until the explicit
    /// migration path exists.
    case legacy
    /// A valid current-version envelope (`StoreName.schemaVersion`).
    case current
}

/// A decoded store payload together with the on-disk generation it came from.
struct StoreFileContents<T> {
    let payload: T
    let generation: StoreFileGeneration
}

/// Classifies and decodes existing store file bytes. Two generations are
/// readable: the legacy bare payload (schema version 0, read transparently
/// without changing any bytes — reads are read-only until the store is
/// migrated) and the current version-1 envelope. Everything else — malformed
/// payloads or envelopes, wrong-store envelopes, missing or invalid versions,
/// and newer unsupported schemas — is a typed rejection that must never be
/// silently defaulted.
enum StoreFileReader {
    /// Marker keys that make a top-level JSON object envelope-shaped. Any
    /// object carrying one of these is treated as an envelope attempt: it must
    /// decode as a valid, matching, current-version envelope — it is never
    /// reinterpreted as a legacy bare payload.
    private static let envelopeMarkerKeys: Set<String> = ["store", "schemaVersion", "payload"]

    static func read<T: Codable>(_ data: Data, store: StoreName, as type: T.Type) throws -> T {
        try readWithGeneration(data, store: store, as: type).payload
    }

    static func readWithGeneration<T: Codable>(
        _ data: Data,
        store: StoreName,
        as type: T.Type
    ) throws -> StoreFileContents<T> {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StoreFileRejection.malformed
        }

        if let topLevelObject = object as? [String: Any],
           !envelopeMarkerKeys.isDisjoint(with: topLevelObject.keys) {
            let payload = try readEnvelope(topLevelObject, from: data, store: store, as: type)
            return StoreFileContents(payload: payload, generation: .current)
        }

        // Legacy bare payload (schema version 0): decode as-is, change nothing.
        do {
            let payload = try decodePayload(type, from: data)
            return StoreFileContents(payload: payload, generation: .legacy)
        } catch {
            throw StoreFileRejection.malformed
        }
    }

    private static func readEnvelope<T: Codable>(
        _ object: [String: Any],
        from data: Data,
        store: StoreName,
        as type: T.Type
    ) throws -> T {
        guard let foundStore = object["store"] as? String else {
            throw StoreFileRejection.malformed
        }
        guard foundStore == store.rawValue else {
            throw StoreFileRejection.wrongStore(found: foundStore)
        }
        guard object["schemaVersion"] != nil else {
            throw StoreFileRejection.malformed
        }
        guard let version = object["schemaVersion"] as? Int else {
            throw StoreFileRejection.invalidVersion
        }
        guard version >= 1 else {
            throw StoreFileRejection.invalidVersion
        }
        guard version == store.schemaVersion else {
            throw StoreFileRejection.unsupportedSchema(found: version)
        }

        do {
            let envelope = try decodePayload(StoreEnvelope<T>.self, from: data)
            guard envelope.store == store, envelope.schemaVersion == store.schemaVersion else {
                throw StoreFileRejection.malformed
            }
            return envelope.payload
        } catch let rejection as StoreFileRejection {
            throw rejection
        } catch {
            throw StoreFileRejection.malformed
        }
    }

    private static func decodePayload<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

/// Encodes store payloads as deterministic version-1 envelopes: pretty-printed
/// JSON with sorted keys and ISO-8601 dates, so equal payloads always yield
/// equal bytes.
enum StoreFileWriter {
    static func envelopeData<T: Codable>(payload: T, store: StoreName) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            StoreEnvelope(store: store, schemaVersion: store.schemaVersion, payload: payload)
        )
    }
}
