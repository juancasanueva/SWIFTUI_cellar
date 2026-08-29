import Catalog
import Foundation

/// The reduced detail an installed package gets when the catalog does not carry
/// it (installed-inventory II15).
///
/// A **total, pure derivation over one decoded receipt**: no catalog value, no
/// store, no clock, no `Process`, no SwiftUI. That is what lets the whole
/// requirement be asserted in the `swift test` inner loop, and what makes the
/// pane that renders it cost no brew invocation at all.
///
/// Two facts II15 lists as install state are deliberately *not* here — size on
/// disk and installed-on-request. Both are already owned for the same
/// `PackageID` by stores whose answers change between renders, so folding them
/// into a `Hashable` value would make that value stale by construction. The
/// presenting surface joins them (design DD-7).
///
/// `nonisolated` by module default and `Sendable` by composition, exactly like
/// `InstalledPackage` itself (design DD-10).
public struct InstalledDetailProjection: Sendable, Hashable {

    /// One labelled fact. `value` is **never empty**: absence is omission, not a
    /// sentinel (design DD-3).
    public struct Fact: Sendable, Hashable {
        /// How the value reads, not how it is styled: `mono` marks an
        /// identifier, `link` carries the URL a consumer opens.
        public enum Style: Sendable, Hashable {
            case plain
            case mono
            case link(URL)
        }

        public let label: String
        public let value: String
        public let style: Style

        public init(label: String, value: String, style: Style = .plain) {
            self.label = label
            self.value = value
            self.style = style
        }
    }

    /// Formula-only state. A cask value has no place to put any of it, which is
    /// what makes II15's "a fact only for the kind that can publish it" a
    /// property of the type rather than of a `switch` somebody has to remember
    /// (design DD-2).
    public struct FormulaState: Sendable, Hashable {
        /// Linkage alone. The version lives on `primaryKegVersion` for **both**
        /// cases, because II15 requires the primary keg to be named whether or
        /// not brew has linked it — an associated value here would lose it in
        /// the unlinked case.
        public enum LinkState: Sendable, Hashable {
            case linked
            case unlinked
        }

        /// Two facts, not a double optional: pinned-without-a-version is a state
        /// brew really reports, and `String??` would encode it unreadably.
        public enum Pin: Sendable, Hashable {
            case notPinned
            case pinned(version: String?)
        }

        /// The linked keg's version, or the newest install's when nothing is
        /// linked. Never absent — a formula always has a primary keg.
        public let primaryKegVersion: String
        public let linkState: LinkState
        /// `0` for a single-keg formula, which emits no fact at all.
        public let otherKegCount: Int
        public let pin: Pin

        public init(
            primaryKegVersion: String,
            linkState: LinkState,
            otherKegCount: Int,
            pin: Pin
        ) {
            self.primaryKegVersion = primaryKegVersion
            self.linkState = linkState
            self.otherKegCount = otherKegCount
            self.pin = pin
        }
    }

    /// Cask-only state. `autoUpdates` is the receipt's tri-state verbatim: `nil`
    /// is "the payload declared nothing", which is not "declared `false`"
    /// (installed-inventory II2).
    public struct CaskState: Sendable, Hashable {
        public let autoUpdates: Bool?

        public init(autoUpdates: Bool?) {
            self.autoUpdates = autoUpdates
        }
    }

    /// npm-only state, and deliberately almost empty.
    ///
    /// A global npm package has one installed version and nothing else this pane
    /// can state as a fact: no keg list, no link state, no pin, no tap and no
    /// auto-updates declaration. Giving it its own case rather than borrowing
    /// `FormulaState` is what keeps those four absent members unrepresentable
    /// instead of set to plausible defaults nobody would notice were wrong.
    public struct NpmState: Sendable, Hashable {
        public let installedVersion: String

        public init(installedVersion: String) {
            self.installedVersion = installedVersion
        }
    }

    public enum KindState: Sendable, Hashable {
        case formula(FormulaState)
        case cask(CaskState)
        case npm(NpmState)
    }

    /// The published description, absence preserved. Presented as its own block
    /// rather than as a labelled fact row.
    public let description: String?
    /// Group 1 — the kind, and the homepage when the receipt publishes one.
    public let identity: [Fact]
    /// Group 2 — the tap of origin, and the seam the per-package grant marker
    /// attaches to at presentation.
    ///
    /// Its own member rather than a row inside a group, so the presenting
    /// surface can address it without matching the label string. The marker is
    /// **not** a field here and never will be: `nil` yields no fact *and* no
    /// marker from the one guard (package-detail PD8, design DD-4).
    public let tapOfOrigin: Fact?
    public let kindState: KindState
    /// When the primary keg was installed, or `nil` when its receipt does not
    /// say. A **value rather than a fact**: locale belongs to the presenting
    /// surface, and this type consults no calendar. Never derived from the
    /// Unix epoch — the decoder preserves a missing timestamp as `nil`, which
    /// is what lets this fact exist at all (installed-inventory II15).
    public let installedAt: Date?

    /// Group 3 — derived from `kindState` rather than stored, so the structured
    /// value a test asserts and the copy a pane renders cannot drift.
    ///
    /// Note what is absent and stays absent: no "latest", "current" or
    /// "published" version (the receipt's current-version value falls back to
    /// the installed keg's own, so such a row would assert a claim the receipt
    /// never made — design DD-5). The install date is not a row here either:
    /// it is `installedAt`, a value the surface formats in its own locale.
    public var installStateFacts: [Fact] {
        switch kindState {
        case .formula(let state):
            var facts = [
                Fact(label: "Version", value: state.primaryKegVersion, style: .mono),
                Fact(label: "Link state", value: Self.copy(state.linkState))
            ]
            if let others = Self.otherVersionsCopy(state.otherKegCount) {
                facts.append(Fact(label: "Other versions", value: others))
            }
            if let pin = Self.copy(state.pin) {
                facts.append(Fact(label: "Pin state", value: pin))
            }
            return facts
        case .cask(let state):
            // Three answers, and the third is no row (II2).
            guard let autoUpdates = state.autoUpdates else { return [] }
            return [
                Fact(
                    label: "Updates",
                    value: autoUpdates ? "Updates itself" : "Updated by Homebrew"
                )
            ]
        case .npm(let state):
            // One row, and no "latest": the same rule the formula branch follows
            // (DD-5). The offered version is the Installed row's business, not
            // this pane's, and asserting it here would restate a claim the npm
            // listing on its own never makes.
            return [Fact(label: "Version", value: state.installedVersion, style: .mono)]
        }
    }

    /// Every fact in II15's group order: identity, then origin, then install
    /// state.
    ///
    /// The order is a property of this value rather than something each consumer
    /// assembles, which is what makes "in that group order" assertable at all.
    public var orderedFacts: [Fact] {
        identity + (tapOfOrigin.map { [$0] } ?? []) + installStateFacts
    }

    public init(_ package: InstalledPackage) {
        description = Self.present(package.desc)

        var identity = [
            Fact(label: "Type", value: Self.typeCopy(package.kind))
        ]
        if let homepage = package.homepage {
            identity.append(
                Fact(label: "Homepage", value: homepage.absoluteString, style: .link(homepage))
            )
        }
        self.identity = identity

        tapOfOrigin = Self.present(package.tap).map {
            Fact(label: "Tap", value: $0, style: .mono)
        }
        installedAt = package.installedAt

        switch package.kind {
        case .formula:
            // `linkedKeg` is read directly rather than through
            // `formulaLinkState`: that projection answers `.notApplicable` for
            // casks — a runtime guard `KindState` makes unnecessary — and
            // reading it would pull `DiskUsage` into a type that needs nothing
            // from it.
            kindState = .formula(FormulaState(
                primaryKegVersion: package.primaryKeg.version,
                linkState: package.linkedKeg == nil ? .unlinked : .linked,
                otherKegCount: max(package.kegs.count - 1, 0),
                pin: package.isPinned
                    ? .pinned(version: Self.present(package.pinnedVersion))
                    : .notPinned
            ))
        case .cask:
            kindState = .cask(CaskState(autoUpdates: package.declaresAutoUpdates))
        case .npm:
            // The single keg the npm projection synthesises. Its version is the
            // whole install state an npm global has.
            kindState = .npm(NpmState(installedVersion: package.primaryKeg.version))
        }
    }

    // MARK: - Copy

    /// A switch rather than the two-way ternary this used to be: with three
    /// kinds a ternary would have labelled every npm package "Cask (GUI app)",
    /// and it would have compiled.
    ///
    /// `public` so the detail header renders the same sentence this pane does:
    /// the two sat beside each other with the same ternary written twice, and
    /// one copy of the rule is what stops them disagreeing.
    public static func typeCopy(_ kind: PackageKind) -> String {
        switch kind {
        case .formula: "Formula (CLI)"
        case .cask: "Cask (GUI app)"
        case .npm: "npm package"
        }
    }

    private static func copy(_ state: FormulaState.LinkState) -> String {
        switch state {
        case .linked: "Linked"
        case .unlinked: "Not linked"
        }
    }

    /// The row's copy, or `nil` when there is no row. Matches the Installed
    /// list's shipped pin copy, so the two surfaces say the same thing.
    private static func copy(_ pin: FormulaState.Pin) -> String? {
        switch pin {
        case .notPinned: nil
        case .pinned(let version): version.map { "Pinned at \($0)" } ?? "Pinned"
        }
    }

    /// `nil` for a single-keg formula: II15 forbids the fact outright rather
    /// than rendering a zero.
    private static func otherVersionsCopy(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 other version installed" : "\(count) other versions installed"
    }

    /// An empty published string is absence, not a value.
    ///
    /// The decoder already preserves a withheld tap as `nil` rather than `""`;
    /// this keeps a payload that publishes the empty string from re-collapsing
    /// that distinction at the last hop (design DD-3).
    private static func present(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
