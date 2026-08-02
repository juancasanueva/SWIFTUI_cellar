import Catalog
import Foundation

/// Everything locally stored about one package, as a plain value.
///
/// A `Sendable` struct rather than a `@Model` instance on purpose (design D3):
/// `Persistence` publishes values, so a SwiftData object never crosses a module
/// or an isolation boundary, and every rule that composes metadata into the
/// inventory can be proven over values in the `swift test` inner loop.
public struct PackageMetadata: Sendable, Hashable {
    public let isFavorite: Bool
    /// Verbatim, and empty when there is no note. Never `Optional`, so callers
    /// do not have to distinguish "no row" from "row with an empty note" — they
    /// are the same thing (local-package-metadata LPM3).
    public let note: String
    /// The exact version string a snooze was taken against, when there is one.
    public let snoozedVersion: String?

    public init(isFavorite: Bool = false, note: String = "", snoozedVersion: String? = nil) {
        self.isFavorite = isFavorite
        self.note = note
        self.snoozedVersion = snoozedVersion
    }

    /// What a package with nothing stored for it reports. Not an absent value
    /// and not an error: "not favorite, no note, not snoozed" is the answer.
    public static let none = PackageMetadata()

    public var isEmpty: Bool { self == .none }

    // MARK: - The snooze rule (design D5, local-package-metadata LPM5)

    /// Whether the outdated badge is suppressed for a package currently offered
    /// at `candidate`.
    ///
    /// The whole rule is **string equality**, and that was a ruling rather than
    /// a default. An ordering comparator — `compare(_:options: .numeric)` or
    /// anything like it — misreads `1.2.3_1`, `2023-10-01`, `r5` and `9e`, and
    /// its failure mode is **silent suppression of a real update, forever**:
    /// the one outcome this feature must never produce. Equality fails the other
    /// way, visibly: a package republished at an older version shows a badge
    /// again. That false positive is accepted on purpose.
    ///
    /// **No Homebrew version comparator exists in this capability**, and the
    /// suite asserts structurally that none has been added.
    public static func isSnoozed(offering candidate: String, snoozedVersion: String?) -> Bool {
        snoozedVersion == candidate
    }

    public func isSnoozed(offering candidate: String) -> Bool {
        Self.isSnoozed(offering: candidate, snoozedVersion: snoozedVersion)
    }
}

/// Every package the metadata store knows about, keyed by the identity the
/// catalog and the inventory already use.
public typealias MetadataSnapshot = [PackageID: PackageMetadata]

/// How a composition rule reaches stored metadata, mirroring the existing
/// `catalogLookup:` seam.
///
/// A closure rather than a store reference, so every rule stays a pure function
/// over values and `BrewClient` never links SwiftData (design D1, D5).
public typealias MetadataLookup = (PackageID) -> PackageMetadata?

extension Dictionary where Key == PackageID, Value == PackageMetadata {
    /// The snapshot as a lookup.
    public var lookup: MetadataLookup { { self[$0] } }
}
