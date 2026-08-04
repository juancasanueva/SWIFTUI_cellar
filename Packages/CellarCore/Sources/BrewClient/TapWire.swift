import Foundation

public struct TapRecord: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let user: String?
    public let repository: String
    public let remote: URL?
    public let formulaNames: [String]
    public let caskTokens: [String]
    public let lastCommit: String?

    public init(
        name: String,
        user: String? = nil,
        repository: String,
        remote: URL? = nil,
        formulaNames: [String] = [],
        caskTokens: [String] = [],
        lastCommit: String? = nil
    ) {
        self.name = name
        self.user = user
        self.repository = repository
        self.remote = remote
        self.formulaNames = formulaNames
        self.caskTokens = caskTokens
        self.lastCommit = lastCommit
    }
}

public struct TapInventory: Sendable, Equatable {
    public let taps: [TapRecord]
    public let skippedRecordCount: Int

    public init(taps: [TapRecord], skippedRecordCount: Int = 0) {
        self.taps = taps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.skippedRecordCount = skippedRecordCount
    }

    public static let empty = TapInventory(taps: [])
}

private struct TapWire: Decodable {
    let name: String
    let user: String?
    let repository: String
    let remote: String?
    let formulaNames: [String]
    let caskTokens: [String]
    let lastCommit: String?

    enum CodingKeys: String, CodingKey {
        case name, user, repo, repository, remote
        case formulaNames = "formula_names"
        case caskTokens = "cask_tokens"
        case lastCommit = "last_commit"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        if let primary = try container.decodeIfPresent(String.self, forKey: .repo) {
            repository = primary
        } else {
            repository = try container.decode(String.self, forKey: .repository)
        }
        remote = try container.decodeIfPresent(String.self, forKey: .remote)
        formulaNames = try container.decodeIfPresent([String].self, forKey: .formulaNames) ?? []
        caskTokens = try container.decodeIfPresent([String].self, forKey: .caskTokens) ?? []
        lastCommit = try container.decodeIfPresent(String.self, forKey: .lastCommit)
    }
}

public enum TapDecoder {
    @concurrent
    public static func decode(_ data: Data) async throws(TapInventoryError) -> TapInventory {
        try inventory(from: data)
    }

    static func inventory(from data: Data) throws(TapInventoryError) -> TapInventory {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .malformedJSON
        }
        guard object is [Any] else { throw .nonArrayEnvelope }

        let decoded: LossyArray<TapWire>
        do {
            decoded = try JSONDecoder().decode(LossyArray<TapWire>.self, from: data)
        } catch {
            throw .malformedJSON
        }
        return TapInventory(
            taps: decoded.elements.map { wire in
                TapRecord(
                    name: wire.name,
                    user: wire.user,
                    repository: wire.repository,
                    remote: redactedURL(wire.remote),
                    formulaNames: wire.formulaNames,
                    caskTokens: wire.caskTokens,
                    lastCommit: wire.lastCommit
                )
            },
            skippedRecordCount: decoded.skippedCount
        )
    }

    private static func redactedURL(_ raw: String?) -> URL? {
        guard let raw, var components = URLComponents(string: raw) else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }
}
