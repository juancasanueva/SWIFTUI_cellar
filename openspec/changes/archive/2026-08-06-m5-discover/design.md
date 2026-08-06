# Design: M5 Discover

Derived from `proposal.md` (decisions **D1–D5**, user-approved and binding) and the mechanism
correction in Engram obs 7493. Slice 2 of 5; slice 1 archived at `163edd5`. Written against the
shipped code, not against the milestone exploration: where `explore.md` says "diff via revision
ordinals", the proposal already superseded it and this document implements the replacement.

## Technical Approach

No new target, no new product, no new dependency edge, no new protocol. The slice adds **three pure
projections** in `Catalog` (ranked ladders, curated resolution, arrivals) plus **two sidecar files**
owned by `CatalogFileStore`, and one presentation-only section tree in the app target.

Four rules govern every type below:

1. **`CatalogPackage` and `CatalogSnapshot` are frozen.** No field, no `CodingKeys` entry, no
   `currentSchemaVersion` move. `CatalogFootprintTests` is re-run unchanged, never re-based — 1.56×
   against a 1.6× bound is 2.4% headroom, and one persisted per-record date crosses it over ~16k
   records. Newness lives in files the footprint suite does not measure, by construction.
2. **Newness is a seen-set, not an ordinal and not a date on a record.**
   `CatalogSnapshotRevision` is process-local and never persisted (`CatalogModels.swift`); it keeps
   its existing job in `adopt` and gains none.
3. **Absent is not zero.** An unranked package is excluded from a ladder, never appended to it.
   `installCount365d: Int?` survives end to end.
4. **Discovery I/O is never fatal.** A roster read or write that fails costs newness for one sync;
   it must not fail a sync that produced a catalog.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| **Two sidecars, `catalog-roster.json` (undated seen-set) + `catalog-arrivals.json` (dated, 30-day)** | One combined file; a `firstSeenAt` on `CatalogPackage` | Only a few hundred entries need a timestamp; ~16k need only membership. Splitting keeps dating cheap and lets a corrupt arrivals log cost arrivals without costing the roster. A per-record field breaks rule 1. |
| **The sidecars carry their own `DiscoverySchema.currentVersion = 1`**, gated by the exact CS6 idiom (missing, corrupt, mismatched = absent) | Reusing `CatalogSnapshot.currentSchemaVersion` | Tying newness to the snapshot's version silently erases the user's 30-day history every time an unrelated package field changes. The gate idiom is the requirement; sharing the constant is not. `currentSchemaVersion` stays **2**. |
| **An absent roster seeds and records zero arrivals** | Treating an empty seen-set as "everything is new" | This is D5's first-run contract *and* the corruption-recovery path. The dangerous failure mode is a lost roster reporting 16,214 arrivals; the design makes it structurally unreachable — the empty-roster branch never writes an arrival. |
| **Write arrivals first, then the roster** | Roster first | Mirrors the shipped snapshot→sidecar ordering rule (D3): pick the crash order that costs a redundant repeat, not a wrong answer. A crash between the two re-records the same arrival next sync, deduplicated earliest-`firstSeenAt`-wins. The reverse order loses the arrival permanently. |
| **The roster is a monotone union; it never removes names** | Replacing the roster with the current catalog each sync | A package removed from Homebrew and re-published is not new *to you*. Subtraction would resurrect newness on a name you have already seen. Cost is ~14 B per dead name, policed by the size bound. |
| **Diff runs only on the path that materialized a new snapshot; expiry is enforced at *read* time too** | Diffing on every sync incl. the 304 path | On a fully revalidated sync the packages are identical, so the diff is a guaranteed no-op costing a roster read and a 16k set compare. Read-time pruning is what makes the 30-day rule true regardless of sync cadence; write-time pruning is only what bounds the file. |
| **Arrivals retention: 30 days, then a hard cap of 1,000 entries, oldest dropped first** | Unbounded retention | An entry dropped by the cap is by construction the closest to expiry, so the cap and the window agree. Bounds a file whose size is otherwise decided by an upstream publisher. |
| **Discover state is projected inside `CatalogStore.adopt`, not by a new store** | A second `@MainActor @Observable` `DiscoverStore` | `CatalogSyncEngine.events` supports **exactly one iterator** (documented, enforced by `isRunning`), so a second store cannot observe snapshots; one fed by `CatalogStore` would be indirection with no boundary. All logic stays in nonisolated pure `Catalog` types — the store gains one `private(set)` property, not behaviour. It also inherits the revision-ordinal dedup for free. |
| **Curated list as `resources: [.copy("Discovery")]` on the existing `Catalog` target** | A loose JSON under `cellar/`; `.process` | Both reach the built `.app`; only the target resource keeps the decoder and its skip accounting testable under `swift test`, which the "all logic in CellarCore" rule requires. `.copy` matches the repo's shipped `.copy("Fixtures")` convention and gives a stable bundle path. Rollback = delete one line and one directory. |
| **Two distinct skip counters: `skippedRecordCount` (malformed file entry) and `unresolvedEntryCount` (valid entry, no catalog match)** | One combined count | They are different facts with different owners — a shipping bug versus catalog drift — and slice 1 already paid for conflating a remainder with `skippedRecordCount`. |
| **Ladders exclude unranked, deprecated and disabled records; they do not reuse `PackageSearchIndex.defaultOrder`** | Reusing the empty-query search order | That order sorts absent counts *last* (`absentCount`), which is right for search and wrong for a ranking: "unmeasured" must not appear on a most-installed ladder at all. |
| **Clock seam is the shipped `CatalogTimeSource`; pure projections take `now:` explicitly** | A new date-provider protocol; `Date()` inside logic | `CatalogSyncEngine` already holds `any CatalogTimeSource` (`SystemTimeSource`). Adding a second protocol for the same question duplicates vocabulary the project already settled. Every pruning function is `nonisolated` and pure over an injected `now`. |

## Interfaces

```swift
// Sources/Catalog/DiscoveryRoster.swift — sidecar shapes. All Codable, Sendable, Hashable.
public enum DiscoverySchema { public static let currentVersion = 1 }

public struct KnownPackageRoster: Codable, Sendable, Hashable {
    public let schemaVersion: Int            // gated exactly: != current means "seen nothing"
    public let formulae: [String]            // sorted, names only, no dates
    public let casks: [String]
    public func contains(_ id: PackageID) -> Bool
}

public struct PackageArrival: Codable, Sendable, Hashable {
    public let kind: PackageKind
    public let name: String
    /// First observation **by this machine**. Never a publication date.
    public let firstSeenAt: Date
}

public struct PackageArrivalsLog: Codable, Sendable, Hashable {
    public static let retentionWindow: TimeInterval = 30 * 24 * 60 * 60
    public static let retentionLimit = 1_000
    public let schemaVersion: Int
    public let arrivals: [PackageArrival]
    public func pruned(now: Date) -> Self          // window, then cap, oldest dropped first
}

// Sources/Catalog/DiscoveryRosterDiff.swift — pure, nonisolated.
public enum DiscoveryRosterDiff {
    /// `roster == nil` is the seeding pass: the roster is written, **no arrival is recorded**.
    public static func advance(
        roster: KnownPackageRoster?,
        arrivals: PackageArrivalsLog?,
        observing packages: [CatalogPackage],
        now: Date
    ) -> (roster: KnownPackageRoster, arrivals: PackageArrivalsLog)
}

// Sources/Catalog/DiscoverRanking.swift
public struct RankedPackage: Sendable, Hashable, Identifiable {
    public var id: PackageID { package.id }
    public let rank: Int                 // 1-based, within its own ladder
    public let package: CatalogPackage
    public let installs: InstallCount    // carries `.metric` and `isLowerBound`
}
public enum DiscoverRanking {
    public static let ladderDepth = 50
    /// Eligible = matching kind, not deprecated, not disabled, `installCount365d != nil`.
    /// Order: count desc, then name asc — total, because `(name, kind)` is unique.
    public static func ladder(_ kind: PackageKind, in: [CatalogPackage], depth: Int = ladderDepth)
        -> [RankedPackage]
}

// Sources/Catalog/CuratedDiscovery.swift
public struct CuratedEntry: Codable, Sendable, Hashable { let kind: PackageKind, token, blurb: String }
public struct CuratedCategory: Codable, Sendable, Hashable { let id, title: String; let entries: [CuratedEntry] }
public struct CuratedDiscoveryList: Sendable, Hashable {
    public let categories: [CuratedCategory]
    public let skippedRecordCount: Int              // entries the file published, unreadable here
    @concurrent
    public static func decode(_ data: Data) throws -> Self
    /// The list shipped in this build's resource bundle.
    public static func shipped(from bundle: Bundle = .module) throws -> Self
}

// Sources/Catalog/DiscoverContent.swift — what the UI renders; no SwiftUI in sight.
public struct DiscoverContent: Sendable, Hashable {
    public let topFormulae, topCasks: [RankedPackage]
    public let curated: [ResolvedCuratedCategory]
    public let curatedSkippedRecordCount, curatedUnresolvedCount: Int
    public let newToYou: [ArrivalRow]               // newest first, then name
    public let hiddenArrivalCount: Int              // beyond the display cap; "and N more"
    public static let empty: Self
}
public struct ArrivalRow: Sendable, Hashable, Identifiable {
    public var id: PackageID { package.id }
    public let package: CatalogPackage
    public let firstSeenAt: Date
}
public enum DiscoverProjection {
    public static func content(
        snapshot: CatalogSnapshot, curated: CuratedDiscoveryList?,
        arrivals: PackageArrivalsLog?, now: Date, arrivalDisplayLimit: Int = 30
    ) -> DiscoverContent
}
```

`CatalogFileStore` gains `rosterURL`/`arrivalsURL`, `loadRoster()`, `loadArrivals()` and
`persistDiscovery(roster:arrivals:)` — the same `publish(_:to:stagedAs:)` atomic-replace path the
snapshot and sidecar already use, and the same `schemaVersion(of:)` probe, generalised to take an
expected version. `CatalogSyncEngine` gains `arrivals()` (mirroring `cachedSnapshot()`) and one
never-fatal `recordArrivals(in:at:)` call after a successful `persist`.

**A curated entry or arrival whose token is not in the snapshot is dropped, never rendered.** The
curated case is counted (`curatedUnresolvedCount`, D1); the arrival case is not — the log expires it
within 30 days and a counter for it would be noise, not honesty.

## Data Flow

```text
catalog.json ──▶ CatalogSnapshot ──┬──▶ DiscoverRanking.ladder(.formula) ─┐
   (already in memory, no I/O)     ├──▶ DiscoverRanking.ladder(.cask) ────┤
                                   └──▶ curated/arrival resolution ───────┤
Bundle.module/Discovery/                                                  │
  curated-discovery.json ──▶ CuratedDiscoveryList.decode  [@concurrent]───┤
catalog-arrivals.json ────▶ engine.arrivals() ──▶ pruned(now:) ───────────┤
                                                                          ▼
                                                            DiscoverProjection.content
                                                                          │  (off main, inside
                                                                          │   the adoption Task)
                                                       CatalogStore.discover  [@MainActor]
                                                                          │
                                                       cellar/Discover/DiscoverView
                                     no brew ── no HTTP ── no new file read on the UI path

sync (only when a NEW snapshot materialized):
  persist(snapshot, state) ──▶ DiscoveryRosterDiff.advance(now: timeSource.now)
                                       │
                                       ├─▶ catalog-arrivals.json   (written FIRST)
                                       └─▶ catalog-roster.json     (written SECOND)
                              roster == nil ⇒ seed only, zero arrivals
```

## File Changes

| Files | Action |
|---|---|
| `Sources/Catalog/DiscoveryRoster.swift`, `DiscoveryRosterDiff.swift` | Create — sidecar shapes, gate, prune, diff. |
| `Sources/Catalog/DiscoverRanking.swift`, `CuratedDiscovery.swift`, `DiscoverContent.swift` | Create — the three projections and their value types. |
| `Sources/Catalog/Discovery/curated-discovery.json` | Create — v1 seed, ~20–30 entries in 3–5 categories (D1). |
| `Sources/Catalog/CatalogFileStore.swift` | Modify — two URLs, two loads, one `persistDiscovery`; `schemaVersion(of:)` takes an expected version. |
| `Sources/Catalog/CatalogSyncEngine.swift` | Modify — `arrivals()`, and one never-fatal `recordArrivals` after `persist`. |
| `Sources/Catalog/CatalogStore.swift` | Modify — `private(set) var discover: DiscoverContent`, projected inside the existing adoption `Task`. |
| `Packages/CellarCore/Package.swift` | Modify — **one line**: `resources: [.copy("Discovery")]` on the existing `Catalog` target. No new target/product/dependency. |
| `cellar/Shell/AppSection.swift` | Modify — `.discover` between `.home` and `.browse`; `title` "Discover", `systemImage` `sparkles`. |
| `cellar/ContentView.swift` | Modify — content column case; detail column joins the existing `case .browse, .installed`. |
| `cellar/Discover/DiscoverView.swift`, `DiscoverLadderSection.swift`, `DiscoverCuratedSection.swift`, `DiscoverNewToYouSection.swift` | Create — presentation only, under a `PBXFileSystemSynchronizedRootGroup` (slice 1 confirmed: **no pbxproj edit**). |
| `Tests/CatalogTests/{DiscoverRankingTests,CuratedDiscoveryTests,DiscoveryRosterTests,DiscoverProjectionTests,DiscoverySidecarFootprintTests}.swift` | Create. |
| `Tests/CatalogTests/Fixtures/Discovery/` + `Fixtures/README.md` | Create/update — curated fixtures to the shipped fixture standard. |
| `cellarTests/DiscoverCompositionTests.swift` | Create — shipped-bundle accessor + copy-vocabulary scan. |

`cellarApp.swift` needs **no** change: `catalog` is already constructed and injected, and Discover
reads it. That is a scope reduction against the proposal's file table, recorded here rather than
absorbed silently.

## Concurrency and Isolation

- Every new public type is a struct/enum of `String`/`Int`/`Date`/`PackageKind`/arrays, so `Sendable`
  is trivially satisfiable and is **declared explicitly** on each, per project convention.
- `DiscoveryRosterDiff`, `DiscoverRanking` and `DiscoverProjection` are `enum` namespaces of
  `nonisolated static` pure functions — no actor, no `await`, sync-testable (slice-1 lesson).
- `CuratedDiscoveryList.decode` is `@concurrent` **on its own line, before `public static func`**
  (the other order does not compile; recorded as having cost an apply cycle in M1).
- `CatalogFileStore` stays a `Sendable` struct with synchronous throwing methods; the new reads and
  the new write use the existing `CatalogFileSystem` seam, so persistence remains fully faked in
  tests. `CatalogSyncEngine` stays the only actor; `arrivals()` is actor-isolated and returns a
  `Sendable` value.
- `DiscoverContent` crosses from the off-main adoption `Task` into `@MainActor CatalogStore` in the
  **same single assignment** the index already makes — no new isolation domain, no new crossing, and
  the "the store is never between indexes" guarantee is preserved because both land together.
- No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `#available`.

## Testing Strategy

Strict TDD, RED before GREEN, in this order. `swift test --package-path Packages/CellarCore` is the
inner loop; the two app-target cases run under `xcodebuild`.

| # | Layer | What / how |
|---|---|---|
| 1 | Unit — ladders | Top-50 depth; a 51st eligible record is absent; unranked (`nil` count) is **absent, not last**; deprecated and disabled are ineligible; formula and cask ladders are independent and each row's `installs.metric` matches its kind; equal counts break by name, deterministically across runs; a catalog with <50 eligible yields a short ladder, not padding. |
| 2 | Unit — curated decode | A well-formed file decodes 3–5 categories; a malformed entry (missing token/kind/blurb, blank blurb, unknown kind string) is skipped and counted; one bad entry never costs the file; `skippedRecordCount` is distinct from `unresolvedEntryCount`. |
| 3 | Unit — shipped resource | `CuratedDiscoveryList.shipped()` resolves under `swift test` and yields ≥20 entries in 3–5 categories with `skippedRecordCount == 0` — the seed list must not ship already-broken. |
| 4 | Unit — roster gate | Missing, corrupt, and version-mismatched roster and arrivals files each read as **absent**, independently of each other; a recording `FakeCatalogFileSystem` proves a read wrote and removed nothing. |
| 5 | Unit — diff | Seeding: absent roster + 16k packages ⇒ full roster, **zero arrivals**. Second pass: only genuinely unseen IDs arrive. A name removed then re-published does **not** re-arrive. Re-recording the same arrival keeps the earliest `firstSeenAt` (crash-window dedup). |
| 6 | Unit — retention | With an injected `now`, an entry at 29d 23h is listed and at 30d 1h is gone; a 1,001-entry log caps to 1,000 with the **oldest** dropped; pruning is idempotent; read-time pruning alone is sufficient when no sync ran. |
| 7 | Unit — projection | First run: rankings and curated present, `newToYou` empty (D5). An arrival whose package left the catalog is dropped, not rendered. A curated token missing from the catalog is dropped **and counted**. `hiddenArrivalCount` is exact beyond the display cap. |
| 8 | Unit — size bound | New `DiscoverySidecarFootprintTests` over the shipped synthetic corpus (7,684 casks + 8,530 formulae): encoded roster **≤ 0.06× the encoded snapshot and ≤ 512 KB**; a full 1,000-entry arrivals log **≤ 64 KB**. Ratios, not absolutes, for the same machine-independence reason slice 1 recorded. |
| 9 | Regression — footprint | `CatalogFootprintTests` runs **unchanged** and passes. Plus a structural scan asserting `CatalogPackage`'s stored-property set is unchanged and that no `firstSeen`/`arrival`/`roster` identifier appears in `CatalogModels.swift`. |
| 10 | Integration — sync | A sync that materializes a new snapshot writes both sidecars, **arrivals before roster**; a fully revalidated (304) sync writes neither and leaves both files byte-identical; a `FakeCatalogFileSystem` that throws on the sidecar write leaves the sync **successful** and the snapshot published. |
| 11 | Integration — zero egress | A recording `FakeCatalogSource` plus a recording process launcher: projecting Discover issues **zero** requests and **zero** process spawns; the catalog directory holds exactly `catalog.json`, `catalog-state.json`, `catalog-roster.json`, `catalog-arrivals.json`. |
| 12 | App target | `CuratedDiscoveryList.shipped()` resolves from the **built `.app`** (proves the SwiftPM resource bundle is embedded); a source scan of `cellar/Discover/` and the Catalog discovery sources finds none of `published`, `release date`, `added to Homebrew`, `new on Homebrew`, `recently added` — the honest-phrasing rule is a test, not a review note (comments stripped first, per the shipped `SecurityCompositionSupport` idiom). |
| 13 | E2E (XCUITest) | `.discover` appears between Home and Browse; selecting it shows all three sections; a first-run profile shows the "new to you" explanation rather than a spinner or an empty screen. |

## Threat Matrix

| Boundary | Applicability | Response / RED |
|---|---|---|
| Network egress | **Applicable — by prohibition** | Discover adds no endpoint, no fetch, no consent surface. Rankings come from the shipped analytics join; the curated list is in-bundle. RED: test 11. |
| Filesystem write during a read | **Applicable — by prohibition** | Reading a missing, corrupt or mismatched sidecar must not delete or rewrite it. RED: test 4 (recording fake). |
| Untrusted on-disk input | **Applicable** | Both sidecars are attacker-writable by a local process and are decoded, never trusted: exact schema gate, `try?` throughout, retention cap bounds the entry count, and a failed decode degrades to "seen nothing" (which, by the seeding rule, produces zero arrivals rather than 16k). RED: tests 4, 6. |
| Catalog-published text into UI | **Applicable** | Package names and descriptions render as `Text`, exactly as Browse already does. No `Link`, no URL construction, no shell interpolation anywhere in `cellar/Discover/`. RED: test 12's source scan. |
| Subprocess / process integration | **Applicable — by prohibition** | Discover never invokes `brew`. RED: test 11's recording launcher. |
| Routing, VCS/PR automation, executable-file classification | N/A — no such boundary | None. |

## Migration / Rollout

**No migration.** `CatalogSnapshot`, `CatalogState` and `currentSchemaVersion` are untouched, so no
cache is invalidated in either direction and no re-download occurs. The two sidecars are created on
the first sync after this slice ships; that first sync is the seeding pass, so "new to you" is
correctly empty and explained on first run (D5).

**Rollback** is `git revert` of the slice PR. The `Package.swift` change is one `resources:` line
plus one directory. `cellar/Discover/` is a synchronized root group, so there is no target-membership,
build-setting or scheme edit to unwind. A reverted build never reads the sidecars; the orphaned files
are inert and are re-adopted intact if the slice is re-applied — because the sidecars carry their own
schema version, a re-applied slice resumes the user's existing 30-day history rather than reseeding.

## Apply-Time Amendments

Recorded, not absorbed. Each of these is a place where the implementation had to
differ from the interface block above; none changes a spec requirement, and the
first is a case where the **spec governed over this document**.

1. **Typed per-section state replaces the flat field list (task 7.4).** The
   `DiscoverContent` sketched above exposes `topFormulae`, `topCasks`, `curated`
   and `newToYou` as bare collections. `package-discovery` **PD-R6** requires each
   section's availability to be a *typed value that names why it is empty*, and a
   bare collection cannot distinguish "nothing is eligible" from "the catalog has
   not loaded" from "everything was unresolvable". The spec wins. Shipped shape:

   ```swift
   public enum DiscoverEmptyReason: Sendable, Hashable {
       case newnessMeasuredFromThisSyncOnward
       case noEligibleRankedPackage
       case everyCuratedEntryUnresolved
   }
   public enum DiscoverSectionState<Content: Sendable & Hashable>: Sendable, Hashable {
       case populated(Content), empty(DiscoverEmptyReason), awaitingCatalog
   }
   ```

   Each of the four fields is a `DiscoverSectionState<…>`; the three counts
   (`curatedSkippedRecordCount`, `curatedUnresolvedCount`, `hiddenArrivalCount`)
   are unchanged. `snapshot:` also became **optional**, because PD-R6's
   awaiting-catalog scenario is "no adopted snapshot" and `DiscoverContent.empty`
   is now exactly the all-awaiting value.

2. **`shipped(from bundle: Bundle = .module)` became two overloads.** SwiftPM
   generates `Bundle.module` as **internal**, and an internal value cannot be the
   default argument of a `public` function. Shipped as `shipped()` and
   `shipped(from:)`, with the default living in a body — the only place this
   module may name it. Compiler-forced, no behavioural change.

3. **`CuratedDiscoveryList` and its value types are `Decodable`, not `Codable`.**
   Per task 3.3; the interface block above said `Codable`. Nothing encodes a
   curated list, and `Encodable` would be a conformance no call site uses.

4. **`loadRoster()` and `loadArrivals()` are non-throwing.** `catalog-sync`
   CS-A1/CS-A2 require classification to never be reported as an error; a
   non-throwing signature makes that unrepresentable rather than merely intended.
   `recordArrivals(in:at:)` is non-throwing for the same reason — it runs inside
   `performSync`'s `do` block, whose `catch` would otherwise convert a failed
   roster write into a discarded 47 MB catalog.

5. **`DiscoverProjection.build` was added beside `content`.** `content` is the
   pure `nonisolated` function the design specifies and is what every unit test
   calls; `build` is a thin `@concurrent` wrapper so `CatalogStore` can project
   off the main actor, mirroring `PackageSearchIndex.build`.

6. **`CatalogSyncEngine` gained `now`.** The store must prune arrivals against
   the *same* clock the sync dated them with. Exposing the engine's
   `timeSource.now` avoids introducing a second, untestable notion of "now" in
   the app layer, and keeps the shipped `CatalogTimeSource` the single seam.

7. **`cellarApp.swift` changed after all — one line, and not for wiring.** The
   scope reduction recorded above still holds for *composition*: `catalog` was
   already constructed and injected, and Discover needed no wiring change. The
   one edit is a **test seam**: the catalog directory now comes from
   `AppTestFixtures.catalogDirectory`, which returns the ordinary location unless
   `--ui-testing-m5-discover` is present, in which case it is an empty per-launch
   temporary directory. Without it a UI test cannot reach a genuine first run on a
   developer machine whose catalog directory is already populated. This follows
   the fixture convention the app target already established for M3 and M4.

8. **Sidebar rows gained accessibility identifiers.** The sidebar label and the
   navigation title carry the same words, so a UI test querying by text matched
   two elements and could assert on neither.

## Open Questions

- [x] **Curated seed content is authored at apply time.** D1 fixes the shape (~20–30 entries, 3–5
      named categories, blurbs in Cellar's voice saying *why you might want this*, never the package's
      own `desc`). The actual tokens and prose are a content decision the user may want to review;
      test 3 only proves the file is well-formed and complete, not that the picks are good.
      **Closed at apply time (task 10.3): the user reviewed and approved the picks** — 25 entries in
      5 categories (Command line essentials, Developer workflow, Apps worth having, Media and files,
      Keeping an eye on your Mac), every token verified against the live catalog via
      `brew info --json=v2` as present and neither deprecated nor disabled.
- [ ] **Arrival display cap of 30 rows** is a judgment, not a decision from D1–D5. If a real sync
      routinely produces more, the "and N more" affordance may need to become a disclosure instead.

*Size note: this document exceeds the 800-word skill budget, as every design in this project does.
The project convention — a design dense enough that apply needs no re-derivation — wins.*
