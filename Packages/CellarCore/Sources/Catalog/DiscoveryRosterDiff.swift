import Foundation

/// Advances the seen-set and the arrivals log by one observation.
///
/// A namespace of pure functions over an injected `now`: no actor, no clock, no
/// file system, no `Date()`. That is what makes a thirty-day retention rule
/// testable in milliseconds instead of once a month.
public enum DiscoveryRosterDiff {
    /// The roster and arrivals log as they should be after observing `packages`.
    ///
    /// **`roster == nil` is the seeding pass**: the roster is written in full and
    /// *no arrival is recorded*. That branch is the whole first-run contract
    /// (D5) and the corruption-recovery path at once — a missing, corrupt or
    /// version-mismatched roster reads as "seen nothing", and if "seen nothing"
    /// meant "everything is new" a lost file would announce 16,000 arrivals.
    /// Here it is structurally unable to: the seeding branch never appends.
    ///
    /// The roster **unions and never removes**. A package pulled from Homebrew
    /// and later re-published is not new to you, and subtracting would resurrect
    /// newness on a name you have already seen. The cost is a few bytes per dead
    /// name, policed by the roster's own size bound.
    ///
    /// Arrivals do **not** inherit the ladders' deprecated/disabled exclusion:
    /// that rule exists so Cellar does not *recommend* an abandoned package, and
    /// this projection makes no recommendation — it reports an observation.
    public nonisolated static func advance(
        roster: KnownPackageRoster?,
        arrivals: PackageArrivalsLog?,
        observing packages: [CatalogPackage],
        now: Date
    ) -> (roster: KnownPackageRoster, arrivals: PackageArrivalsLog) {
        let observed = union(roster, with: packages)

        guard let roster else {
            // Seeding: record what is here, claim nothing about newness. There is
            // deliberately no path from this branch to an appended arrival.
            return (observed, (arrivals ?? .empty).pruned(now: now))
        }

        // An identity already in the log keeps its original date and gains no
        // second entry, however often it is observed again. This is what makes
        // the arrivals-before-roster crash window cost a redundant repeat rather
        // than a wrong date.
        let previous = arrivals ?? .empty
        var logged = Set(previous.arrivals.map(\.id))
        var recorded = previous.arrivals

        // The source guard is not redundant with `roster.contains`, it is the
        // reason it cannot be trusted alone. `contains` answers `false` for every
        // npm identity by construction, so "not in the roster" would read as
        // "new to this machine" and an npm global would be announced as a
        // freshly published Homebrew package. The roster's union already skips
        // npm; the arrivals log has to skip it for the same reason.
        for package in packages
        where package.kind.source == .homebrew && !roster.contains(package.id) {
            guard logged.insert(package.id).inserted else { continue }
            recorded.append(
                PackageArrival(kind: package.kind, name: package.name, firstSeenAt: now)
            )
        }

        return (observed, PackageArrivalsLog(arrivals: recorded).pruned(now: now))
    }

    /// The seen-set plus everything just observed. Never subtracts.
    private static func union(
        _ roster: KnownPackageRoster?,
        with packages: [CatalogPackage]
    ) -> KnownPackageRoster {
        var formulae = Set(roster?.formulae ?? [])
        var casks = Set(roster?.casks ?? [])

        for package in packages {
            switch package.kind {
            case .formula: formulae.insert(package.name)
            case .cask: casks.insert(package.name)
            // Nothing to record. The roster has two namespaces because the
            // catalog has two, and an npm package cannot arrive in either. It is
            // skipped here rather than given a third set, so a "new package"
            // badge can never appear for something Homebrew never published.
            case .npm: break
            }
        }

        return KnownPackageRoster(formulae: Array(formulae), casks: Array(casks))
    }
}

extension PackageArrivalsLog {
    /// The log with expired and surplus entries removed, newest first.
    ///
    /// Window **then** cap, oldest dropped first. Applied at *both* read and
    /// write, for two different reasons: read-time pruning is what makes the
    /// thirty-day rule true regardless of sync cadence — a machine that has not
    /// synced in six weeks must not still be showing arrivals from before the
    /// window — and write-time pruning is what bounds a file whose size is
    /// otherwise decided by an upstream publisher.
    ///
    /// `now` is a parameter, never `Date()`: pruning is a pure function of the
    /// log and the instant it is asked about.
    public nonisolated func pruned(now: Date) -> Self {
        let cutoff = now.addingTimeInterval(-Self.retentionWindow)
        let retained = arrivals
            .filter { $0.firstSeenAt > cutoff }
            // Newest first, so the cap below drops the oldest — which is by
            // construction the entry closest to expiry anyway.
            .sorted { left, right in
                left.firstSeenAt == right.firstSeenAt
                    ? left.name < right.name
                    : left.firstSeenAt > right.firstSeenAt
            }
            .prefix(Self.retentionLimit)

        return PackageArrivalsLog(schemaVersion: schemaVersion, arrivals: Array(retained))
    }
}
