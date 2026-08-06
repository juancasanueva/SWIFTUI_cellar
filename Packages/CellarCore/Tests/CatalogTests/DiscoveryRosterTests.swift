import Foundation
import Testing

@testable import Catalog

/// The two newness sidecars: the undated seen-set and the dated arrivals log
/// (catalog-sync CS-A1 and CS-A2).
///
/// Newness is a **seen-set**, not an ordinal and not a date on a record.
/// `CatalogSnapshotRevision` is process-local and restarts at 1 every launch, so
/// a diff keyed on it would report the whole catalog as new on the second
/// launch; and a per-record `firstSeenAt` would cross the snapshot's encoded
/// footprint bound across ~16k records. Both mistakes are structurally excluded
/// by putting newness in files of its own.
@Suite("Discovery roster and arrivals log")
struct DiscoveryRosterTests {
    // MARK: - The roster carries identities only (CS-A1)

    @Test("An encoded roster carries identities only — no date, no count, no payload")
    func encodedRosterCarriesIdentitiesOnly() throws {
        let roster = KnownPackageRoster(
            formulae: ["git", "wget"],
            casks: ["firefox", "iterm2"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(roster)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // The whole file, exhaustively: three keys and nothing else. A
        // hand-written "does not contain firstSeenAt" check would keep passing
        // the day someone adds `lastSeenAt` instead.
        #expect(Set(object.keys) == ["schemaVersion", "formulae", "casks"])
        #expect(object["formulae"] as? [String] == ["git", "wget"])
        #expect(object["casks"] as? [String] == ["firefox", "iterm2"])
        #expect(object["schemaVersion"] as? Int == DiscoverySchema.currentVersion)

        // ...and no per-record structure anywhere in the bytes: the roster is a
        // list of names, so nothing in it can be a date or a measurement.
        let text = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["firstSeenAt", "downloadedAt", "installCount", "recordCount", "desc"] {
            #expect(text.contains(forbidden) == false, "the roster carried \(forbidden)")
        }
    }

    @Test("The roster answers membership per kind, never by name alone")
    func rosterAnswersMembershipPerKind() {
        // Homebrew publishes the same token in both namespaces, so a roster that
        // answered by name would call a brand-new cask "already seen" the moment
        // a formula of that name existed.
        let roster = KnownPackageRoster(formulae: ["wget"], casks: ["iterm2"])

        #expect(roster.contains(PackageID(kind: .formula, name: "wget")))
        #expect(roster.contains(PackageID(kind: .cask, name: "iterm2")))
        #expect(roster.contains(PackageID(kind: .cask, name: "wget")) == false)
        #expect(roster.contains(PackageID(kind: .formula, name: "iterm2")) == false)
        #expect(roster.contains(PackageID(kind: .formula, name: "neverseen")) == false)
    }

    @Test("A roster round-trips through its own schema version")
    func rosterRoundTrips() throws {
        let roster = KnownPackageRoster(formulae: ["git"], casks: ["iterm2"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        let reloaded = try JSONDecoder().decode(
            KnownPackageRoster.self,
            from: try encoder.encode(roster)
        )

        #expect(reloaded == roster)
        #expect(reloaded.contains(PackageID(kind: .formula, name: "git")))
        #expect(reloaded.contains(PackageID(kind: .cask, name: "iterm2")))
    }

    @Test("The discovery schema is versioned independently of the snapshot's")
    func discoverySchemaIsIndependentOfTheSnapshot() {
        // The constant that stops an unrelated projection bump from erasing a
        // user's retained 30-day history. It is deliberately its own number,
        // not an alias of `CatalogSnapshot.currentSchemaVersion`.
        #expect(DiscoverySchema.currentVersion == 1)
        #expect(CatalogSnapshot.currentSchemaVersion == 2)
    }

    // MARK: - The gate (CS-A1 sc3, CS-A2 sc4, TM3)

    @Test("A missing, corrupt or mismatched roster all mean 'seen nothing'")
    func hostileRosterReadsAsSeenNothing() throws {
        // Both sidecars are writable by any local process, so every shape here is
        // untrusted input (TM3). All three answer the same thing, and — by the
        // seeding rule — that answer produces zero arrivals rather than 16,000.
        for shape in try Self.hostileRosterShapes() {
            let fileSystem = FakeCatalogFileSystem()
            let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
            if let bytes = shape.bytes { fileSystem.seed(bytes, at: store.rosterURL) }

            // Non-throwing by signature: "MUST NOT be reported as an error" is
            // stronger as a type than as an assertion.
            #expect(store.loadRoster() == nil, "\(shape.label) was not read as 'seen nothing'")
        }
    }

    @Test("A missing, corrupt or mismatched arrivals log all mean 'no arrivals'")
    func hostileArrivalsReadAsNoArrivals() throws {
        for shape in try Self.hostileArrivalsShapes() {
            let fileSystem = FakeCatalogFileSystem()
            let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
            if let bytes = shape.bytes { fileSystem.seed(bytes, at: store.arrivalsURL) }

            #expect(store.loadArrivals() == nil, "\(shape.label) was not read as 'no arrivals'")
        }
    }

    @Test("The roster and the arrivals log are gated independently of each other")
    func sidecarsAreGatedIndependently() throws {
        // A corrupt arrivals log must cost arrivals, not the seen-set — which is
        // the whole reason they are two files rather than one.
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        fileSystem.seed(
            try encoder.encode(KnownPackageRoster(formulae: ["wget"], casks: [])),
            at: store.rosterURL
        )
        fileSystem.seed(try Fixture.discovery("arrivals-corrupt"), at: store.arrivalsURL)

        #expect(store.loadArrivals() == nil)
        let roster = try #require(store.loadRoster())
        #expect(roster.contains(PackageID(kind: .formula, name: "wget")))
    }

    @Test("An undatable arrival is dropped while its well-formed siblings survive")
    func undatableArrivalIsDroppedNotFatal() throws {
        // Lossy per **entry**, not per file: one unreadable date must not cost
        // the other two arrivals, or a single bad byte would erase the window.
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        fileSystem.seed(try Fixture.discovery("arrivals-undatable"), at: store.arrivalsURL)

        let log = try #require(store.loadArrivals())

        #expect(log.arrivals.map(\.name) == ["first-good", "second-good"])
        #expect(log.arrivals.contains { $0.name == "undatable" } == false)
        #expect(log.arrivals.first?.firstSeenAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: - A read never mutates the file it rejects (TM2)

    @Test("Rejecting a sidecar writes, replaces and removes nothing")
    func rejectingASidecarMutatesNothing() throws {
        for shape in try Self.hostileRosterShapes() + Self.hostileArrivalsShapes() {
            let fileSystem = FakeCatalogFileSystem()
            let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
            let url = shape.isRoster ? store.rosterURL : store.arrivalsURL
            if let bytes = shape.bytes { fileSystem.seed(bytes, at: url) }

            _ = store.loadRoster()
            _ = store.loadArrivals()

            // A read that "repaired" a rejected file would destroy the evidence
            // and, on a hostile file, do it on an attacker's schedule.
            #expect(
                fileSystem.operations.isEmpty,
                "reading \(shape.label) touched the file system: \(fileSystem.operations)"
            )
            #expect(fileSystem.contents(at: url) == shape.bytes, "\(shape.label) was rewritten")
        }
    }

    // MARK: - Seeding (CS-A1 sc1, D5)

    @Test("An absent roster seeds and records no arrival at all")
    func absentRosterSeedsWithZeroArrivals() {
        let packages = [
            Self.package("wget"),
            Self.package("git"),
            Self.package("iterm2", .cask)
        ]

        let advanced = DiscoveryRosterDiff.advance(
            roster: nil,
            arrivals: nil,
            observing: packages,
            now: Self.now
        )

        // The roster records everything the snapshot holds...
        #expect(advanced.roster.formulae == ["git", "wget"])
        #expect(advanced.roster.casks == ["iterm2"])
        #expect(advanced.roster.contains(PackageID(kind: .cask, name: "iterm2")))
        // ...and not one package is called an arrival. This is D5's first-run
        // contract and the whole reason "empty on first run" is a designed state
        // rather than a bug.
        #expect(advanced.arrivals.arrivals.isEmpty)
    }

    @Test("A lost roster re-seeds against a full catalog and still reports zero arrivals")
    func lostRosterDoesNotReportTheWholeCatalogAsNew() {
        // The dangerous failure mode, made structurally unreachable: a corrupt
        // or deleted roster reads as "seen nothing", and the seeding branch
        // never writes an arrival — so the answer is 0, not 15,000.
        let packages = (1..<15_000).map { Self.package("pkg\($0)") }

        let advanced = DiscoveryRosterDiff.advance(
            roster: nil,
            arrivals: nil,
            observing: packages,
            now: Self.now
        )

        #expect(advanced.roster.formulae.count == 14_999)
        #expect(advanced.arrivals.arrivals.isEmpty)
        #expect(advanced.arrivals.arrivals.count == 0)
    }

    // MARK: - The second pass (CS-A1 sc2, CS-A2 sc2)

    @Test("A second sync records exactly the identity the roster did not hold")
    func secondSyncRecordsOnlyGenuinelyUnseenPackages() throws {
        let seeded = KnownPackageRoster(formulae: ["git", "wget"], casks: ["iterm2"])
        let packages = [
            Self.package("wget"),
            Self.package("git"),
            Self.package("iterm2", .cask),
            Self.package("newpkg")
        ]

        let advanced = DiscoveryRosterDiff.advance(
            roster: seeded,
            arrivals: .empty,
            observing: packages,
            now: Self.now
        )

        #expect(advanced.arrivals.arrivals.map(\.name) == ["newpkg"])
        let arrival = try #require(advanced.arrivals.arrivals.first)
        #expect(arrival.kind == .formula)
        #expect(arrival.firstSeenAt == Self.now)
        // The roster afterwards holds every identity in the new snapshot.
        #expect(advanced.roster.formulae == ["git", "newpkg", "wget"])
        for package in packages {
            #expect(advanced.roster.contains(package.id), "\(package.name) missing from the roster")
        }
    }

    @Test("A package removed from the catalog and re-published does not arrive twice")
    func republishedPackageDoesNotReArrive() {
        // The roster is a monotone union. Replacing it with the current catalog
        // each sync would subtract `oldpkg` when it vanished, and then resurrect
        // newness on a name the user has already seen.
        let seeded = KnownPackageRoster(formulae: ["oldpkg", "wget"], casks: [])

        // Sync 2: `oldpkg` is gone from the catalog.
        let withoutOld = DiscoveryRosterDiff.advance(
            roster: seeded,
            arrivals: .empty,
            observing: [Self.package("wget")],
            now: Self.now
        )
        #expect(withoutOld.arrivals.arrivals.isEmpty)
        // Never subtracted, which costs ~14 bytes and is what makes sync 3 correct.
        #expect(withoutOld.roster.formulae == ["oldpkg", "wget"])

        // Sync 3: it is published again.
        let republished = DiscoveryRosterDiff.advance(
            roster: withoutOld.roster,
            arrivals: withoutOld.arrivals,
            observing: [Self.package("wget"), Self.package("oldpkg")],
            now: Self.now.addingTimeInterval(86_400)
        )

        #expect(republished.arrivals.arrivals.isEmpty)
    }

    @Test("Re-observing a logged arrival keeps the earliest date and adds no second entry")
    func reObservedArrivalKeepsItsEarliestDate() throws {
        // The crash window: arrivals is written before the roster, so a crash
        // between the two leaves an arrival logged whose identity the roster
        // does not yet hold. The next sync observes it as unseen again — and
        // earliest-`firstSeenAt` wins, which is what makes that crash order cost
        // a redundant repeat rather than a wrong date.
        let tenDaysAgo = Self.now.addingTimeInterval(-10 * 24 * 60 * 60)
        let logged = PackageArrivalsLog(arrivals: [
            PackageArrival(kind: .formula, name: "newpkg", firstSeenAt: tenDaysAgo)
        ])

        let advanced = DiscoveryRosterDiff.advance(
            roster: KnownPackageRoster(formulae: ["wget"], casks: []),
            arrivals: logged,
            observing: [Self.package("wget"), Self.package("newpkg")],
            now: Self.now
        )

        #expect(advanced.arrivals.arrivals.count == 1)
        let arrival = try #require(advanced.arrivals.arrivals.first)
        #expect(arrival.name == "newpkg")
        #expect(arrival.firstSeenAt == tenDaysAgo)
        #expect(arrival.firstSeenAt != Self.now)
    }

    @Test("A newly arrived deprecated package is still new to you")
    func arrivalsDoNotInheritTheLadderExclusion() {
        // The deprecated/disabled exclusion is **ladder-scoped**: it exists so
        // Cellar does not *recommend* an abandoned package. "New to you" makes
        // no recommendation — it reports an observation — so a package that
        // arrived deprecated still arrived.
        let advanced = DiscoveryRosterDiff.advance(
            roster: KnownPackageRoster(formulae: ["wget"], casks: []),
            arrivals: .empty,
            observing: [
                Self.package("wget"),
                CatalogPackage.stub(kind: .formula, name: "newdeprecated", deprecated: true),
                CatalogPackage.stub(kind: .cask, name: "newdisabled", disabled: true)
            ],
            now: Self.now
        )

        #expect(advanced.arrivals.arrivals.map(\.name).sorted() == ["newdeprecated", "newdisabled"])
    }

    // MARK: - Retention, over an injected clock (CS-A2 sc3)

    @Test("The window keeps an entry at 29d 23h and drops one at 30d 1h")
    func retentionWindowIsThirtyDays() {
        let log = PackageArrivalsLog(arrivals: [
            Self.arrival("justinside", hoursAgo: 29 * 24 + 23),
            Self.arrival("justoutside", hoursAgo: 30 * 24 + 1)
        ])

        let pruned = log.pruned(now: Self.now)

        #expect(pruned.arrivals.map(\.name) == ["justinside"])
    }

    @Test("The cap keeps a thousand entries and drops the oldest first")
    func retentionCapDropsTheOldestFirst() throws {
        // 1,001 entries, each a minute older than the last, so every one of them
        // is comfortably **inside** the 30-day window and the cap is the only
        // rule doing any work. (Spacing them by hours would put the oldest 41
        // days back, and the window would drop them before the cap was reached —
        // which would test the window twice and the cap not at all.)
        let log = PackageArrivalsLog(
            arrivals: (0...1_000).map { Self.arrival("pkg\($0)", minutesAgo: $0) }
        )

        let pruned = log.pruned(now: Self.now)

        #expect(pruned.arrivals.count == PackageArrivalsLog.retentionLimit)
        #expect(pruned.arrivals.count == 1_000)
        // `pkg1000` is the oldest and is the one that falls off.
        #expect(pruned.arrivals.contains { $0.name == "pkg1000" } == false)
        #expect(pruned.arrivals.contains { $0.name == "pkg0" })
        #expect(pruned.arrivals.contains { $0.name == "pkg999" })
    }

    @Test("Pruning is idempotent")
    func pruningIsIdempotent() {
        let log = PackageArrivalsLog(arrivals: [
            Self.arrival("keep", hoursAgo: 2),
            Self.arrival("drop", hoursAgo: 40 * 24)
        ])

        let once = log.pruned(now: Self.now)
        let twice = once.pruned(now: Self.now)

        #expect(once == twice)
        #expect(twice.arrivals.map(\.name) == ["keep"])
    }

    @Test("Read-time pruning alone gives the thirty-day answer with no sync having run")
    func readTimePruningIsSufficientWithoutASync() throws {
        // What makes the 30-day rule true regardless of sync cadence: a machine
        // that has not synced in six weeks must not still be showing arrivals
        // from before the window. Write-time pruning only bounds the file.
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        fileSystem.seed(
            try encoder.encode(
                PackageArrivalsLog(arrivals: [
                    Self.arrival("stale", hoursAgo: 31 * 24),
                    Self.arrival("fresh", hoursAgo: 2 * 24)
                ])
            ),
            at: store.arrivalsURL
        )

        let log = try #require(store.loadArrivals())

        // Read straight off disk, with no sync in between.
        #expect(log.pruned(now: Self.now).arrivals.map(\.name) == ["fresh"])
    }

    // MARK: - Hostile shapes

    struct HostileShape {
        let label: String
        /// `nil` is the missing-file case, which is a shape in its own right.
        let bytes: Data?
        let isRoster: Bool
    }

    static func hostileRosterShapes() throws -> [HostileShape] {
        [
            HostileShape(label: "a missing roster", bytes: nil, isRoster: true),
            HostileShape(
                label: "a corrupt roster",
                bytes: try Fixture.discovery("roster-corrupt"),
                isRoster: true
            ),
            HostileShape(
                label: "a version-mismatched roster",
                bytes: try Fixture.discovery("roster-wrong-version"),
                isRoster: true
            )
        ]
    }

    static func hostileArrivalsShapes() throws -> [HostileShape] {
        [
            HostileShape(label: "a missing arrivals log", bytes: nil, isRoster: false),
            HostileShape(
                label: "a corrupt arrivals log",
                bytes: try Fixture.discovery("arrivals-corrupt"),
                isRoster: false
            ),
            HostileShape(
                label: "a version-mismatched arrivals log",
                bytes: try Fixture.discovery("arrivals-wrong-version"),
                isRoster: false
            )
        ]
    }

    static let root = URL(fileURLWithPath: "/tmp/cellar-fake/Discovery", isDirectory: true)

    /// Every date in this suite is derived from this instant and injected. No
    /// pruning or diffing function reads `Date()` — a retention rule tested
    /// against the wall clock is a retention rule tested once a month.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func package(_ name: String, _ kind: PackageKind = .formula) -> CatalogPackage {
        CatalogPackage.stub(kind: kind, name: name)
    }

    static func arrival(
        _ name: String,
        hoursAgo: Int,
        kind: PackageKind = .formula
    ) -> PackageArrival {
        PackageArrival(
            kind: kind,
            name: name,
            firstSeenAt: now.addingTimeInterval(-Double(hoursAgo) * 3_600)
        )
    }

    static func arrival(
        _ name: String,
        minutesAgo: Int,
        kind: PackageKind = .formula
    ) -> PackageArrival {
        PackageArrival(
            kind: kind,
            name: name,
            firstSeenAt: now.addingTimeInterval(-Double(minutesAgo) * 60)
        )
    }

    @Test("An arrival is dated by first observation and carries nothing else")
    func arrivalCarriesKindNameAndFirstSeenOnly() throws {
        let arrival = PackageArrival(
            kind: .formula,
            name: "newpkg",
            firstSeenAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let log = PackageArrivalsLog(arrivals: [arrival])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let object = try #require(
            try JSONSerialization.jsonObject(with: try encoder.encode(log)) as? [String: Any]
        )

        #expect(Set(object.keys) == ["schemaVersion", "arrivals"])
        let entries = try #require(object["arrivals"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(Set(entries[0].keys) == ["kind", "name", "firstSeenAt"])
        #expect(entries[0]["firstSeenAt"] as? Double == 1_800_000_000)
        #expect(PackageArrivalsLog.retentionWindow == 30 * 24 * 60 * 60)
        #expect(PackageArrivalsLog.retentionLimit == 1_000)
    }
}
