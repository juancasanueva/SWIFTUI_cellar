import Catalog

/// Which kinds the Installed list shows.
///
/// A set rather than a single kind, because the chips are toggles: every kind
/// is on by default and any combination is expressible. What is **not**
/// expressible is nothing at all — a list narrowed to no kinds is a dead state
/// that only looks broken, so the last kind refuses to turn off.
public struct InstalledKindSelection: Sendable, Hashable {
    public private(set) var kinds: Set<PackageKind>

    public init(kinds: Set<PackageKind> = Set(PackageKind.allCases)) {
        self.kinds = kinds
    }

    public func contains(_ kind: PackageKind) -> Bool { kinds.contains(kind) }

    /// Flips one kind, refusing to remove the last **visible** one.
    ///
    /// Visible, not selected: with npm off its chip is absent, and a hidden npm
    /// must not count as the kind that keeps the row alive — otherwise both
    /// Homebrew chips can be turned off and the row reads as showing nothing.
    public mutating func toggle(_ kind: PackageKind, npmEnabled: Bool) {
        if kinds.contains(kind) {
            let visible = npmEnabled ? kinds : kinds.subtracting([.npm])
            guard visible.count > 1 else { return }
            kinds.remove(kind)
        } else {
            kinds.insert(kind)
        }
    }

    /// The kinds actually in effect.
    ///
    /// With npm off its chip is absent, so an npm-only selection left over from
    /// before the switch collapses to every kind rather than emptying the list
    /// behind a chip that is no longer on screen — the rule `effectiveSource`
    /// already follows. A mixed selection simply loses npm.
    public func effective(npmEnabled: Bool) -> Set<PackageKind> {
        guard npmEnabled == false else { return kinds }
        let remaining = kinds.subtracting([.npm])
        return remaining.isEmpty ? Set(PackageKind.allCases) : remaining
    }

    /// The one source every effective kind belongs to, or `nil` when they span
    /// both — what the empty state needs to word itself.
    public func effectiveSource(npmEnabled: Bool) -> PackageSource? {
        let sources = Set(effective(npmEnabled: npmEnabled).map(\.source))
        return sources.count == 1 ? sources.first : nil
    }
}
