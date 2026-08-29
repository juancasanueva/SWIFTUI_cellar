import Foundation

/// The version the newness sidecars are gated against.
///
/// **Its own constant, deliberately not `CatalogSnapshot.currentSchemaVersion`.**
/// What the persistence rule mandates is the gate *idiom* — exact in both
/// directions, absence-not-error, never mutating the file it rejects — not a
/// shared number. Keying these files to the snapshot's version would mean that
/// every unrelated widening of the persisted projection silently erased the
/// user's retained 30-day arrivals history, for a reason the user never caused
/// and cannot see. The snapshot's shape and this schema change for different
/// reasons, so they carry different versions (catalog-sync CS-A1, CS-A2).
public enum DiscoverySchema {
    public static let currentVersion = 1
}

/// Every package identity this machine has already observed.
///
/// Names only: ~16k identities need membership, and only the few hundred in the
/// arrivals log need a date. Splitting them is what keeps dating cheap and lets
/// a corrupt arrivals log cost arrivals without costing the seen-set.
///
/// A **monotone union** — it never removes a name. A package pulled from
/// Homebrew and later re-published is not new *to you*, and subtracting would
/// resurrect newness on a name you have already seen.
public struct KnownPackageRoster: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    /// Sorted, so the same seen-set always encodes to the same bytes.
    public let formulae: [String]
    public let casks: [String]

    /// Outside `CodingKeys`: membership is asked ~16k times per diff, and a
    /// linear scan of the arrays would make that quadratic. Adds no key to the
    /// persisted JSON and no reason of its own to move `schemaVersion`.
    private let formulaSet: Set<String>
    private let caskSet: Set<String>

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case formulae
        case casks
    }

    public init(
        schemaVersion: Int = DiscoverySchema.currentVersion,
        formulae: [String],
        casks: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.formulae = formulae.sorted()
        self.casks = casks.sorted()
        formulaSet = Set(formulae)
        caskSet = Set(casks)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let formulae = try container.decode([String].self, forKey: .formulae)
        let casks = try container.decode([String].self, forKey: .casks)
        self.formulae = formulae
        self.casks = casks
        formulaSet = Set(formulae)
        caskSet = Set(casks)
    }

    /// Whether this machine has observed that identity before.
    ///
    /// Keyed on the pair and never on the name: Homebrew publishes the same
    /// token in both namespaces, and they are two different packages.
    public func contains(_ id: PackageID) -> Bool {
        switch id.kind {
        case .formula: formulaSet.contains(id.name)
        case .cask: caskSet.contains(id.name)
        // The roster is the set of identities *the Homebrew catalog* has
        // published to this machine. npm publishes into no catalog Cellar syncs,
        // so an npm identity has never been observed here and never will be —
        // and `false` is the honest answer rather than a gap.
        case .npm: false
        }
    }

    public var isEmpty: Bool { formulae.isEmpty && casks.isEmpty }

    public static let empty = KnownPackageRoster(formulae: [], casks: [])
}

/// One package, and when **this installation** first observed it.
public struct PackageArrival: Codable, Sendable, Hashable {
    public let kind: PackageKind
    public let name: String
    /// First observation **by this machine**.
    ///
    /// Never a publication or release date: the catalog does not carry one, and
    /// presenting this value as one would be a claim Cellar cannot support.
    public let firstSeenAt: Date

    public var id: PackageID { PackageID(kind: kind, name: name) }

    public init(kind: PackageKind, name: String, firstSeenAt: Date) {
        self.kind = kind
        self.name = name
        self.firstSeenAt = firstSeenAt
    }
}

/// The small dated companion to the roster.
///
/// Bounded twice over: a 30-day window, then a hard cap with the oldest dropped
/// first. An entry the cap drops is by construction the one closest to expiry,
/// so the two rules agree rather than compete — which is what lets a file whose
/// size is otherwise decided by an upstream publisher stay bounded.
public struct PackageArrivalsLog: Codable, Sendable, Hashable {
    public static let retentionWindow: TimeInterval = 30 * 24 * 60 * 60
    public static let retentionLimit = 1_000

    public let schemaVersion: Int
    public let arrivals: [PackageArrival]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case arrivals
    }

    public init(
        schemaVersion: Int = DiscoverySchema.currentVersion,
        arrivals: [PackageArrival]
    ) {
        self.schemaVersion = schemaVersion
        self.arrivals = arrivals
    }

    /// Lossy per **entry**, not per file.
    ///
    /// An entry whose date is missing or unreadable is dropped rather than
    /// failing the read: one bad byte in a locally-writable file must not erase
    /// the user's whole 30-day window (catalog-sync CS-A2).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        arrivals = try container
            .decode([TolerantArrival].self, forKey: .arrivals)
            .compactMap(\.arrival)
    }

    public var isEmpty: Bool { arrivals.isEmpty }

    public static let empty = PackageArrivalsLog(arrivals: [])
}

/// An arrival that never fails its container: decoding an array of these always
/// advances, so an undatable entry is `nil` here rather than an error costing
/// every sibling.
private struct TolerantArrival: Decodable {
    let arrival: PackageArrival?

    init(from decoder: any Decoder) throws {
        arrival = try? PackageArrival(from: decoder)
    }
}
