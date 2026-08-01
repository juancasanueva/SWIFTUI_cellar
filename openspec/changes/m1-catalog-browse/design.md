# Design: M1 — Catalog sync, package search, Browse UI

## Technical Approach

A new `Catalog` library target in `Packages/CellarCore`, independent of `BrewProcess`. It owns
acquisition (HTTPS behind `CatalogSource`), a slim on-disk projection, an in-memory byte-scan search
index, and a `@MainActor @Observable CatalogStore`. The app target keeps views and DI wiring only.
SwiftPM's default `nonisolated` isolation puts decode and index building off-main *by construction*;
`CatalogStore` is the single main-isolated crossing point.

Pipeline: `CatalogSource` → staging dir → `CatalogDecoder` (mapped `Data` → slim projection) →
`CatalogFileStore` (atomic swap) → `PackageSearchIndex` (Sendable value) → `CatalogStore` (MainActor).

## Architecture Decisions

### D1 — `CatalogStore` lives in the `Catalog` target, not the app target

| Option | Tradeoff |
|---|---|
| App target | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` silently main-isolates every helper written beside it; only reachable from `xcodebuild test`, not `swift test` |
| **`Catalog` target (chosen)** | Explicit `@MainActor` opt-in inside a `nonisolated` module; testable in the fast `swift test` inner loop; mirrors the shipped `BrewDetectionStore` precedent (public, in `BrewProcess`, consumed by the app) |

### D2 — Actor for coordination, `@concurrent` free functions for CPU work

`CatalogSyncEngine` is an `actor` holding only coordination state (in-flight task, sidecar, current
phase). Decode/projection/index building are `nonisolated` value-type functions marked `@concurrent`
so a multi-second CPU burst never occupies the actor's executor (which would stall `state`, `cancel`
and manual-refresh joins). Rejected: decoding inside the actor (head-of-line blocking); `Task.detached`
(loses priority propagation and cancellation). **Apply-time check**: if `@concurrent` is unavailable
in the pinned toolchain, fall back to `Task.detached(priority: .utility)` and record it.

### D3 — Sidecar written *after* the snapshot

Write order is `catalog.json` (atomic replace) → then `catalog-state.json`. A crash between them
leaves a fresh catalog with stale validators, costing one redundant download. The reverse order would
advertise a stale snapshot as fresh — the only failure mode that serves wrong data.

### D4 — Search runs synchronously on `@MainActor`

An 8 ms budget is cheaper than an async hop, and it eliminates out-of-order as-you-type results and
per-keystroke cancellation logic. The p95 test *is* the licence for this decision: if the assertion
breaks, escalate to the char-bitmask pre-gate, then trigrams, then an off-main hop — in that order.

**Measured at apply time** (`swift test -c release --filter SearchLatency`, 15,500 records,
1,000 samples): **p95 = 1.02 ms**, median 0.96 ms, max 1.70 ms — roughly 8× headroom under the
ceiling. No escalation step was needed (task 5.9 discharged without action).

### D5 — Poll-and-compare scheduling, not a 24 h sleep

The refresh loop sleeps `pollGranularity` (15 min) on an injected `any Clock<Duration>` and compares
`CatalogTimeSource.now` against the persisted `lastSuccessAt`. A monotonic 24 h sleep drifts across
system sleep; wall-clock comparison syncs correctly after a laptop wakes from a 30 h sleep. Both seams
are injectable, so the whole schedule is exercised with `TestClock` (already in the repo) and a fake
time source, in microseconds.

### D6 — Tolerant decoding never throws on a record

Only an unreadable envelope or a **zero usable records** result throws. Individual malformed records
increment `skippedRecordCount`. `emptyCatalog` is a hard guard: a good snapshot is never replaced by
an empty one.

### D7 — Cache defeat is belt *and* braces

`configuration.urlCache = nil` **and** `request.cachePolicy = .reloadIgnoringLocalCacheData`, with
`If-None-Match`/`If-Modified-Since` set manually. `Last-Modified` is persisted and echoed as the
**raw header string** — never round-tripped through a `DateFormatter`. `statusCode == 304` is checked
before the temp file is touched (a 304 from `download(for:)` yields an empty file).

### D8 — Decode memory (the 40 MB risk), concretely

1. `URLSession.download(for:)` streams to disk — network peak ≈ 0.
2. `Data(contentsOf:options: .mappedIfSafe)` — pages, not a 40 MB heap copy.
3. Formula and cask are decoded **sequentially**, each inside its own scope + `autoreleasepool`, so
   the mapped payload and its wire array are released before the next resource starts (halves peak).
4. Wire types declare only the ~18 keys the projection needs; raw downloads are deleted immediately
   after projection.
5. **Measurable expectation**: `CatalogMemoryTests` generates a synthetic 40 MB `formula.json` into a
   temp dir (no repo cost), records `phys_footprint` via `task_info(TASK_VM_INFO)` around the decode,
   and asserts **peak delta ≤ 300 MB** and **post-decode retained delta ≤ 40 MB**.

**Live measurement (task 10.3, 2026-08-01)** — a real cold sync against `formulae.brew.sh` through
`HTTPCatalogSource`, sampled every 3 ms: **peak `phys_footprint` delta 177.2 MB** for the full
47.8 MB of payload (16,200 records, 0 skipped) in **2.56 s**, staging purged, `catalog.json`
7,114,578 B. The immediately following revalidation sync completed in **0.158 s** with no body
transferred. Note the origin emits **weak** ETags (`W/"6a6e37f1-fff2a7"`); replaying them verbatim
still produced 304s.

## Data Flow

    CatalogSource ──download(for:)──▶ staging/*.json ──mappedIfSafe──▶ CatalogDecoder
         │ 304                                                              │ slim projection
         ▼                                                                  ▼
    sidecar bump ◀── CatalogFileStore (replaceItemAt) ◀── CatalogSnapshot + AnalyticsIndex
                              │ load
                              ▼
                     PackageSearchIndex (Sendable value)
                              │ handoff
                              ▼
        @MainActor CatalogStore ──▶ BrowseView / PackageDetailView (NavigationSplitView)

## Interfaces / Contracts

```swift
// Identity & domain
public enum PackageKind: String, Codable, Sendable, Hashable { case formula, cask }
public struct PackageID: Hashable, Sendable, Codable { public let kind: PackageKind; public let name: String }

public struct CatalogPackage: Codable, Sendable, Hashable, Identifiable {
    public var id: PackageID { .init(kind: kind, name: name) }
    public let kind: PackageKind, name: String, displayName: String   // cask: token / name[0]
    public let desc: String?, homepage: URL?, license: String?
    public let version: String, tap: String
    public let dependencies: [String], buildDependencies: [String], dependents: [String]
    public let caveats: String?
    public let deprecated: Bool, deprecationReason: String?
    public let disabled: Bool, disableReason: String?
    public let autoUpdates: Bool                 // casks only
    public let installCount365d: Int?            // nil ⇒ render "not reported"
}

// Persistence
public struct CatalogSnapshot: Codable, Sendable {   // catalog.json
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int, generatedAt: Date, packages: [CatalogPackage]
}
public struct SourceState: Codable, Sendable { public var etag: String?, lastModified: String?, fetchedAt: Date, byteCount: Int }
public struct CatalogState: Codable, Sendable {      // catalog-state.json
    public var schemaVersion: Int
    public var sources: [String: SourceState]        // "formula" | "cask" | "analytics-formula" | "analytics-cask"
    public var lastSuccessAt: Date, recordCount: Int, skippedRecordCount: Int
}

// Seams (config rule: a protocol boundary per external dependency)
public enum CatalogResource: Sendable, Hashable { case formulae, casks, analytics(PackageKind) }
public struct ConditionalValidators: Sendable, Equatable { public var etag: String?; public var lastModified: String? }
public struct FetchedPayload: Sendable { public let fileURL: URL, validators: ConditionalValidators, byteCount: Int }
public enum CatalogFetchOutcome: Sendable { case notModified, downloaded(FetchedPayload) }

public protocol CatalogSource: Sendable {
    func fetch(_ resource: CatalogResource, validators: ConditionalValidators?) async throws -> CatalogFetchOutcome
}
public protocol CatalogFileSystem: Sendable {          // FileManager seam
    func createDirectory(at: URL) throws
    func fileExists(at: URL) -> Bool
    func contentsMappedIfSafe(of: URL) throws -> Data
    func write(_ data: Data, to: URL) throws
    func replaceItem(at destination: URL, withItemAt staged: URL) throws
    func moveItem(at: URL, to: URL) throws
    func removeItem(at: URL) throws
}
public protocol CatalogTimeSource: Sendable { var now: Date { get } }

// Sync state machine
public enum CatalogSyncPhase: Sendable, Equatable { case checking, downloading(Double?), decoding, indexing, persisting }
public enum CatalogSyncState: Sendable, Equatable {
    case idle(lastSuccessAt: Date?, isStale: Bool)
    case syncing(CatalogSyncPhase)
    case failed(CatalogError, at: Date)     // last-good snapshot stays loaded and searchable
}

// Errors — closed taxonomy
public enum CatalogError: Error, Sendable, Equatable { case network(CatalogNetworkError), decode(CatalogDecodeError), persistence(CatalogPersistenceError), cancelled }
public enum CatalogNetworkError: Error, Sendable, Equatable { case offline, timedOut, http(status: Int), invalidResponse, payloadTooLarge(bytes: Int, limit: Int) }
public enum CatalogDecodeError: Error, Sendable, Equatable { case malformedEnvelope(resource: String), emptyCatalog(resource: String) }
public enum CatalogPersistenceError: Error, Sendable, Equatable { case directoryUnavailable(String), writeFailed(String), snapshotUnreadable(String), schemaVersionMismatch(found: Int, expected: Int) }

// Search
public enum MatchRank: Int, Comparable, Sendable { case exactToken = 0, namePrefix, nameSubstring, descriptionSubstring }
public struct SearchFilters: Sendable, Equatable { public var kinds: Set<PackageKind> = [.formula, .cask]; public var includeDeprecated = true; public var includeDisabled = true }
public struct SearchHit: Sendable, Hashable, Identifiable { public let id: PackageID; public let rank: MatchRank }

public struct PackageSearchIndex: Sendable {          // struct-of-arrays; Sendable by composition, no @unchecked
    public func search(_ query: String, filters: SearchFilters, limit: Int = 200) -> [SearchHit]
    public func package(_ id: PackageID) -> CatalogPackage?
}

@MainActor @Observable public final class CatalogStore {
    public private(set) var syncState: CatalogSyncState
    public private(set) var isReady: Bool
    public private(set) var results: [CatalogPackage]
    public var query: String { didSet { rerank() } }
    public var filters: SearchFilters { didSet { rerank() } }
    public func start() async        // load cached snapshot, then run the refresh loop
    public func refreshNow() async   // manual; joins an in-flight sync (single-flight, as BrewDetectionStore)
    public func package(_ id: PackageID) -> CatalogPackage?
}
```

**Index layout** — one contiguous `names: [UInt8]` + `nameRanges: [Range<Int>]`, same for `descs`,
plus `installCounts: [Int32]`, `kinds: [UInt8]`, `flags: [UInt8]` (deprecated/disabled bits). ~15.5k
records ≈ 1–2 MB, zero per-record heap allocation. `PackageText.normalize` (lowercase, diacritic-fold,
non-alphanumeric → single `0x20`) is applied identically to record text at build time and to the query
at search time.

**Ranking scan** — one pass; each record lands in one of four rank buckets (name checks first,
`continue` on a name hit so the desc scan is skipped). Buckets are then sorted lazily, best rank
first, stopping once `limit` is filled — so a one-character query never sorts the huge
`descriptionSubstring` bucket. Ordering key: `(rank asc, installCount desc, name asc)` — fully
deterministic for tests. Empty query ⇒ filtered list by install count desc.

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift` | Modify | `Catalog` product + target + `CatalogTests` target (`.swiftLanguageMode(.v6)`, no `BrewProcess` dependency) |
| `Sources/Catalog/CatalogModels.swift` | Create | `PackageKind`, `PackageID`, `CatalogPackage`, `CatalogSnapshot`, `CatalogState` |
| `Sources/Catalog/Wire/{Formula,Cask,Analytics}Wire.swift`, `Wire/Lossy.swift` | Create | `Decodable`-only wire shapes; `LossyArray`, `UsesFromMacOS` either-type, `decodeIfPresent` throughout |
| `Sources/Catalog/CatalogSource.swift` | Create | Protocol + `HTTPCatalogSource` (download/conditional/retry/backoff) |
| `Sources/Catalog/CatalogFileSystem.swift` | Create | Protocol + `DefaultCatalogFileSystem` |
| `Sources/Catalog/CatalogFileStore.swift` | Create | Atomic snapshot swap, sidecar read/write, schema-version gate |
| `Sources/Catalog/CatalogDecoder.swift` | Create | `@concurrent` decode + projection + dependent inversion + analytics join |
| `Sources/Catalog/AnalyticsIndex.swift` | Create | Flat ranked endpoints; comma-grouped counts parsed by stripping `,` (no `NumberFormatter`) |
| `Sources/Catalog/PackageSearchIndex.swift`, `PackageText.swift` | Create | Byte-scan index + normalizer |
| `Sources/Catalog/CatalogSyncEngine.swift` | Create | `actor`; state machine, single-flight, staging lifecycle |
| `Sources/Catalog/CatalogRefreshPolicy.swift` | Create | Interval/poll/backoff values |
| `Sources/Catalog/CatalogErrors.swift` | Create | Closed error enums |
| `Sources/Catalog/CatalogStore.swift` | Create | `@MainActor @Observable` façade |
| `Tests/CatalogTests/**` | Create | Fixtures, fakes, decode/sync/index/ranking/latency/memory suites |
| `cellar/ContentView.swift` | Modify | Rewritten as the `NavigationSplitView` shell (sidebar → Browse list → detail) |
| `cellar/Shell/AppSection.swift`, `Home/HomeView.swift`, `Home/BrewDetectionSummary.swift` | Create | Sections enum; detection summary extracted verbatim from the old `ContentView` |
| `cellar/Browse/{BrowseView,PackageRow,PackageDetailView,CatalogFilterBar,SyncBanner}.swift` | Create | Browse UI |
| `cellar/cellarApp.swift` | Modify | Drop `Schema([Item.self])` and the `ModelContainer`; own `CatalogStore`, `.task { await catalog.start() }` |
| `cellar/Item.swift` | Delete | Template dead code |
| `cellar.xcodeproj/project.pbxproj` | Modify | `Catalog` product dependency (4 hunks) |
| `cellar.xcodeproj/xcshareddata/xcschemes/CellarCore.xcscheme` | Modify | Build entry for `Catalog`, testable for `CatalogTests` |
| `openspec/specs/brew-{execution,detection}/spec.md` | Modify | Two editorial reconciliations |

### Xcode project changes and rollback boundary

The app target uses `PBXFileSystemSynchronizedRootGroup`, so **adding or deleting Swift files under
`cellar/` — including new subdirectories — requires no `project.pbxproj` edit at all.** The only
pbxproj change is linking the product, in four hunks that must land as **one atomic unit**; reverting
any subset leaves a dangling `productRef` and an unbuildable project:

| # | Section | Edit | Reserved ID |
|---|---|---|---|
| 1 | `PBXBuildFile` | `Catalog in Frameworks` | `BC0000010000000000000004` |
| 2 | `PBXFrameworksBuildPhase` (`BCDBE978…`) | append hunk 1's ID to `files` | — |
| 3 | target `cellar` `packageProductDependencies` | append hunk 4's ID | — |
| 4 | `XCSwiftPackageProductDependency` | `productName = Catalog` | `BC0000010000000000000005` |

IDs continue the repo's hand-authored `BC000001…` convention so the diff stays reviewable and
hand-revertable. No new `XCLocalSwiftPackageReference` (CellarCore is already referenced).
**Rollback**: `git checkout main -- cellar.xcodeproj/project.pbxproj` (and the same for the
`.xcscheme`) — all-or-nothing, never split across PR slices. Scheme edits are cosmetic for CI
(`swift test --package-path` runs `CatalogTests` regardless) but keep the shared scheme honest in
Xcode.

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit — decode | Nullable `desc`/`caveats`, cask `name: [String]`, `uses_from_macos` String\|Object, unknown keys, one malformed record among many, zero-record guard | Real captured excerpts in `Tests/CatalogTests/Fixtures/` (a full `wget`/`git`/`iterm2` record each + a ~50-record slice + a mutated unknown-key variant) |
| Unit — analytics | `"2,808,879"` → `2808879`; `formula` vs `cask` item keys; missing package ⇒ `nil` count | Captured flat 365d excerpts |
| Unit — sync | 200→persist; 304→sidecar bump only, snapshot untouched; 503/offline/malformed ⇒ `.failed` with last-good intact; retry skips 4xx except 429; cancellation | `FakeCatalogSource` (scripted outcomes) + `FakeCatalogFileSystem` (injectable write/replace failures) |
| Unit — persistence | Atomic replace, sidecar-last ordering, schema-version mismatch ⇒ rebuild not crash | Real temp directory via `DefaultCatalogFileSystem` |
| Unit — search | Ranking order across all four ranks, tie-break by install count then name, filters, empty query, diacritic/case folding | Small hand-written index |
| Perf — latency | **p95 < 8 ms** | 1,000 samples = 50 as-you-type prefixes (progressive 1–5 char prefixes of 10 real names) × 20 runs, after 5 warm-up passes; `ContinuousClock` deltas; index built from a seeded generator sized to 15.5k records with the length distribution measured from the live capture. **Release-only** (`@Test(.enabled(if: BuildConfiguration.isRelease))`) — a `-Onone` byte scan is 5–20× slower and would make the assertion meaningless; verify runs `swift test -c release --filter SearchLatency` |
| Perf — memory | Peak delta ≤ 300 MB, retained ≤ 40 MB | Synthetic 40 MB JSON generated into a temp dir; `task_info(TASK_VM_INFO).phys_footprint` around decode |
| Scheduler | 24 h staleness, poll granularity, wake-from-sleep, manual refresh joins in-flight | `TestClock` + `FakeTimeSource`; zero wall-clock waiting |
| Integration (manual, apply-time) | Live `curl -sI` to confirm `ETag`; real cold sync; peak RSS | Documented as an apply checklist item, not a CI test |

Fixture capture is a one-time scripted step recorded in the tasks; committed fixtures are excerpts
(kilobytes), never the 40 MB dumps.

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary. `Catalog` deliberately does not depend on `BrewProcess`. File handling
safeguards are still specified: downloads land only in the app-owned Application Support subtree, a
`payloadTooLarge` cap (128 MB per resource) bounds disk use, payloads are parsed as JSON only and
never executed, and the staging directory is purged on every sync completion or failure.

## Migration / Rollout

No data migration. `CatalogSnapshot.schemaVersion` mismatch discards the cached snapshot and triggers
a full re-sync — the catalog is derived data, always re-acquirable. Removing `Item` from the SwiftData
schema drops the `ModelContainer` entirely for this milestone; a stale local dev store is disposable
(no shipped users). On-disk state is removed by deleting
`~/Library/Application Support/com.juancasanueva.cellar/Catalog/`.

## Open Questions

- [x] **`ETag`/`If-None-Match` on formulae.brew.sh — CONFIRMED (task 0.3, 2026-08-01).** `curl -sI`
      on `formula.json`, `cask.json`, `analytics/install-on-request/365d.json` and
      `analytics/cask-install/365d.json` returns **both** `ETag` (`"6a6e2a26-1d95bbf"` style,
      Varnish-fronted) and `Last-Modified`. Replaying either `If-None-Match` or
      `If-Modified-Since` answers `HTTP/2 304`. Both validators ship; no CS2 re-scoping needed.
- [x] **`@concurrent` under Swift 6.3.3 / tools-version 6.0 — CONFIRMED (task 0.2).** It compiles in
      the `Catalog` target with `.swiftLanguageMode(.v6)`. One syntax constraint: the attribute must
      precede the modifier — `@concurrent nonisolated func` compiles, `nonisolated @concurrent func`
      is a parse error. The `Task.detached(priority: .utility)` fallback is **not** used.
- [x] **Slim-projection size ratio — MEASURED (Unit 1 gate).** Live inputs captured 2026-08-01:
      `formula.json` 31,022,015 B (8,529 records) + `cask.json` 16,773,799 B (7,671 records)
      = 47,795,814 B for 16,200 records, 0 skipped. The persisted `catalog.json` is
      **6,862,330 B (6.54 MB)** — a **7.0× reduction**, slightly above the estimated 4–6 MB band.
      The overhead is the analytics join (16,191 of 16,200 records carry a count) plus the
      per-edge `PackageDependency` objects that make PD2's unresolvable marking possible. Well
      inside the D8 retained budget; no action taken.
