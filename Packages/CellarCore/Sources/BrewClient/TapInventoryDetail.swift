import Catalog

/// Everything Cellar can honestly say about a package one installed third-party
/// tap publishes and this Mac has **not** installed (`package-search` PS8 round
/// 6, `package-detail` PD6, `tap-management` TM5).
///
/// ## Why it carries so little
///
/// The tap inventory publishes a name, a kind and the tap that declared it —
/// and nothing else. A description, a version, a homepage, a licence, a
/// dependency list, an install count, a deprecation flag or a size would each
/// require reading the tap's own formula or cask source, which TM5 forbids
/// **unconditionally**, for this capability's surfaces and every outside
/// consumer alike. An installed package gets all of that from its receipt, on
/// the pane `installed-inventory` owns. A package this Mac does not have has no
/// receipt, so the absence is presented as an absence rather than filled from a
/// source that may not be read.
///
/// The two sentences are stored here rather than worded by the pane, for the
/// same reason `TapSearchHit.stateNote` and `collisionNote` are: one projection
/// answers one fact, and a `unit` test can read these bytes without rendering
/// anything (PS8's copy-ownership clause, design DD-22).
///
/// `kind` is **computed** off `id`. Unlike `TapSearchHit.nextVersion` it is not
/// invisible to `Mirror` — `id` is enumerated and carries it — so storing a
/// second copy would give one fact two homes and one chance to disagree.
public struct TapInventoryDetail: Sendable, Hashable {
    /// The bare token brew installs by, and the identity a detail is selected
    /// with. Never `/`-qualified (`package-mutation` PM10).
    public let id: PackageID
    /// The name to draw, as the tap projection already projects it.
    public let displayName: String
    /// The one tap that publishes this identity.
    public let tapName: String
    /// TM5's exact shipped string, reused byte-for-byte rather than reworded, so
    /// this Mac's install state cannot read one way on Taps and another here.
    ///
    /// Honest by construction: `resolve(_:in:installed:)` answers `nil` for any
    /// identity this Mac holds a receipt for, so no value carrying this sentence
    /// can describe an installed package.
    public let stateCopy: String
    /// The pane's own boundary, stated plainly rather than implied by an empty
    /// pane: this is what Cellar knows, and why there is no more of it.
    public let footerCopy: String

    public var kind: PackageKind { id.kind }

    public init(id: PackageID, displayName: String, tapName: String) {
        self.id = id
        self.displayName = displayName
        self.tapName = tapName
        stateCopy = Self.notInstalledCopy
        footerCopy = Self.footer
    }

    /// TM5's string, character for character.
    private static let notInstalledCopy = "Not installed."
    private static let footer = "Cellar knows this package by name only until it is installed."

    /// The detail for `id`, or `nil` when there is nothing honest to answer.
    ///
    /// Three conditions, and all three are refusals rather than guesses:
    ///
    /// 1. **This Mac holds no receipt for it.** The same question the
    ///    receipt-backed branch asks, asked here so the two can never both
    ///    answer — and so `stateCopy` can never be a false statement. The
    ///    withheld-tap case is why this is keyed on the receipt rather than on
    ///    the tap projection's install state: Homebrew withholds the tap, so the
    ///    record's `tap` is absent, but the record exists and it decides.
    /// 2. **Exactly one installed third-party tap publishes it.** Zero has no
    ///    origin to name; several have no *single* origin to name, and picking
    ///    one would put a wrong tap on the pane. Official taps are excluded by
    ///    `TapProjection.thirdPartyTaps` — the catalog owns those packages.
    /// 3. **That tap really projects this identity.** `packages(for:installed:)`
    ///    is the shipped projection, so the display name here is the one the tap
    ///    rows already show rather than a second normalisation of the same
    ///    published token.
    ///
    /// Pure, `nonisolated` by the module default, and `Sendable` by
    /// composition: its whole input is two already-resident inventories, so
    /// there is nothing to inject and composing it costs no brew invocation.
    public static func resolve(
        _ id: PackageID,
        in inventory: TapInventory,
        installed: InstalledInventory
    ) -> TapInventoryDetail? {
        guard installed.package(id) == nil else { return nil }

        let publishers = TapProjection(inventory: inventory).thirdPartyTaps
            .filter { TapProjection.publishes(id, in: $0) }
        guard publishers.count == 1, let tap = publishers.first else { return nil }
        guard
            let package = TapProjection.packages(for: tap, installed: installed)
                .first(where: { $0.id == id })
        else { return nil }

        return TapInventoryDetail(
            id: package.id,
            displayName: package.displayName,
            tapName: tap.name
        )
    }
}
