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
}

/// Every package the metadata store knows about, keyed by the identity the
/// catalog and the inventory already use.
public typealias MetadataSnapshot = [PackageID: PackageMetadata]
