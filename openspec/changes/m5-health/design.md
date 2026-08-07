# Design: Health Dashboard, `brew doctor` & Bulk Pin/Snooze (`m5-health`)

Derives from proposal obs 7533 (Binding Invariants 1–4 and D1–D7 binding), decisions obs 7532
(design proposes the weights; `size:exception` pre-accepted), probes obs 7531 (U10/U11/U12/U14),
explore §2.5/§3.4/§4/§5/§8. Every repository claim below was re-verified at `main` `7d48779`.

## Technical Approach

Four independent pieces, composed only in the app target.

1. **Doctor** — `BrewClient`: `DoctorCommand` (constant `.read` argv) → `DoctorSource` (a
   **non-throwing** seam) → `DoctorParser` (`@concurrent`, over `Data`) → `DoctorOutcome` carrying
   `DoctorEvidence` in the `CleanupEvidence` idiom.
2. **Last update** — `DiskUsage`: a new `FileMetadataAccess` seam plus `HomebrewRepositoryLocator`
   (probe order) and `HomebrewUpdateReader`, which **composes** `HomebrewRoots` and touches nothing
   persisted. Zero brew invocations.
3. **Score** — `Catalog`: `HealthInputs` → `HealthScoring.score(_:) -> HealthScoreState`. A pure
   function over scalars and Catalog-local enums, in the only dependency-free library target.
4. **Section** — `cellar/Health/`: a `HealthProjection` render plus the two acquisitions, wired in
   `cellarApp`/`ContentView`. Plus the bulk pin/unpin widening in `BrewClient` and an app-side bulk
   snooze that never enters `BulkSelection.Action`.

`Package.swift`, `project.pbxproj`, `CatalogFootprintTests.swift` and `brew-execution/spec.md` are
untouched — all four are 0-line diffs.

## Architecture Decisions

### HD1 — `DoctorSourcing` is non-throwing; non-zero is an ordinary outcome

| Option | Tradeoff | Decision |
|---|---|---|
| `CleanupPreviewError`-shaped throwing source (7a-A) | Encodes "warnings found" as an error; the score would read a failure where there is none | Rejected |
| `throws(DoctorError)` with `.issues` returned normally | Non-zero-as-error remains *expressible*; a later "simplification" back onto the trio's rule compiles | Rejected |
| **`func run(using:) async -> DoctorOutcome`, no `throws` at all** (7a-B) | New vocabulary needing requirement text | **Chosen** |

Classification, in order: `exit.isCancelled → .unavailable(.cancelled)`; `exit.isSuccess →
.clean(evidence)`; otherwise `.issues(evidence)`. A non-zero status can reach `.unavailable` only
through a *spawn* failure (`BrewProcessError`), never through a completed run. Because the seam
cannot throw, the inversion is enforced by the signature rather than by a comment. Licensed verbatim
by `brew-execution` BE "a non-zero status MUST NOT be raised as a thrown error, because `brew` uses
exit codes semantically" — recorded in the new capability's Provenance (D7). `BrewCommand.read(["doctor"])`
per U14; argv is a compile-time constant with no parameter, interpolation or joining.

### HD2 — The parser reads stderr as the document and records where it actually arrived

U10 measured the whole 622-byte payload on **stderr** and 1 byte (a bare newline) on stdout.
`DoctorParser.parse` therefore walks stderr as the document, but also walks stdout and admits any
`Warning:` block it finds there. Which streams contributed is recorded in
`DoctorParserProvenance.documentStream ∈ {stdout, stderr, both, neither}`, so a future brew that
moves the payload is *visible in the evidence* rather than silently parsed as clean. `rawStdout` and
`rawStderr` stay separate `Data` fields and are **never concatenated** anywhere.

Grammar, per line, over `Data` (the `CleanupParser.lines(in:)` byte splitter, reused):

| Line | Outcome |
|---|---|
| non-empty, before the first `Warning: ` | preamble, in order (U10's "just used to help the Homebrew maintainers…") |
| `Warning: <headline>` | opens a new `DoctorWarning`; `headline` is the remainder |
| any other non-empty line while a block is open | appended to that block's `detail`, in order |
| `Warning: ` with an empty remainder | block still recorded; issue `.emptyWarningHeadline` |
| non-empty detail-shaped line with no open block and after the preamble | `unknownLines`; issue `.orphanDetailLine` |
| bytes that are not valid UTF-8 | `unknownLines` (as `Data`); issue `.undecodableLine` |

`warningCount` is `0`, never absent, on a clean run. `isPartial == !issues.isEmpty`.
`parserVersion: Int = 1` travels with every value.

### HD3 — The quarantine proof is behavioural, over all three JSON sources

`DoctorPayloadQuarantineTests.swift` (`BrewClientTests`) asserts, for each of
`InstalledPayload.payload`, `ServicesPayload.payload` and `TapPayload.payload`, in both directions:

- a **non-zero** exit carrying a well-formed JSON document on stdout still throws
  `.commandFailed(status:message:)` — the doctor rule did not leak;
- an **exit-0** run with a blank stdout and the document on **stderr** still throws
  `.malformedPayload`/`.blankOutput` — stderr still never enters a JSON document.

A behavioural proof, not a text scan: it holds even if the three files are refactored, and it fails
loudly if anyone "unifies" doctor with the trio. `brew-execution/spec.md` stays a 0-line diff.

### HD4 — Compose, do **not** widen `DiskRootsIdentity` (explore §8's open question, resolved)

Widening `HomebrewRoots.identity` would invalidate the disk-usage cache. Verified, not assumed:

- `DiskRootsIdentity` (`HomebrewRoots.swift:34–45`) is `Codable` with four non-optional stored
  properties and is persisted verbatim as `DiskUsageSnapshot.roots` (`DiskUsageModels.swift:90`).
- `DiskUsageCache.load()` (`DiskUsageCache.swift:15–20`) **throws** on a decode failure; it returns
  `nil` only for a missing file or `schemaVersion != 1`. A new non-optional key makes every
  previously written cache file throw `keyNotFound` rather than degrade to `nil`.
- Even on a successful decode, `CleanupParser.currentlyOnDiskBytes` (`:292–296`) gates on
  `context.snapshot.roots == context.expectedRoots`; widening changes `==` and the orphan byte
  attribution silently becomes `nil`.

So: a new value composes `HomebrewRoots` instead. `HomebrewRepositoryLocator.repository(for:)` probes
`<prefix>/Homebrew/.git` then `<prefix>/.git` (U11: correct on both install shapes, `/opt/homebrew`
and the `/usr/local` shape PRD §3.9 supports), and returns a typed location. `HomebrewRoots`,
`DiskRootsIdentity`, `DiskUsageSnapshot` and the cache are all **unchanged**.

### HD5 — `FileMetadataAccess`: one protocol, three operations' worth of honesty

`CatalogFileSystem` and `ReleaseNotesFileAccess` both lack any attribute operation. The new seam is
`ReleaseNotesFileAccess`-sized and lives in `DiskUsage` (which already owns `HomebrewRoots` and the
filesystem domain, and which `Persistence` never needs to see):

```swift
public protocol FileMetadataAccess: Sendable {
    func modificationDate(at url: URL) -> FileModificationDate
}
public enum FileModificationDate: Sendable, Hashable { case read(Date), absent, unreadable }
public struct SystemFileMetadataAccess: FileMetadataAccess { /* FileManager.attributesOfItem */ }
```

`HomebrewUpdateReader.lastUpdate(roots:now:access:) -> HomebrewLastUpdate` with
`case read(Date) | absent | unreadable | futureDated(Date)`. `.absent` covers both "never fetched"
and "not a git checkout" (the API-only future); `.futureDated` carries the real mtime rather than a
negative age; **no `Date` is ever invented** and `Date.distantPast` appears nowhere. Every case is
reachable from a test with no disk.

### HD6 — The score lives in `Catalog`, over a re-declared scalar vocabulary

No core target may see both `BrewClient` and `SecurityKit` except `Persistence`, and no new SwiftPM
target is in scope. `Catalog` is the only dependency-free library target, and it already hosts the
pure-projection idiom (`DiscoverProjection`, `DiscoverSectionState`). Placing the score there makes
"the score can see neither brew nor advisories" a **fact of the build graph**, exactly the argument
`Package.swift` already makes for `ReleaseNotes`.

`HealthInputs` therefore names no foreign type. Each of the eight inputs is a
`HealthSignal { case answered(Double), unknown(HealthUnknownReason) }` over a normalised 0…1 health,
and the **app target** performs every mapping (`DoctorOutcome`, `CoverageTotals`,
`SecurityScanState`, `CleanupOrphans`, `DiskUsageSnapshot`, `InstalledBrowse`, `HomebrewLastUpdate` →
`HealthSignal`). Same "re-declare rather than import" discipline `ReleaseNotes` uses for its consent
and credential seams. The score is testable in `CatalogTests`, in the `swift test` inner loop, with
no store, clock, filesystem or process anywhere in its signature.

### HD7 — The proposed weights, each defended in one line

`value = round(100 × Σ_answered wᵢ·hᵢ / Σ_answered wᵢ)`. Unknown inputs leave **both** sums, so they
neither flatter nor punish — they are disclosed instead (HD8). Weights sum to 100 for readability and
live as named constants in `HealthWeights`, each rendered in the breakdown.

| Input | w | Defense |
|---|---|---|
| `vulnerable` | 25 | The only input describing harm already present rather than housekeeping. |
| `outdated` | 20 | The app's primary verb, and the largest actionable non-harmful signal. |
| `advisoryCoverage` | 15 | The M4 lesson given its own weight: an unanswered inventory costs points instead of being invisible. |
| `lastUpdate` | 15 | A stale Homebrew makes every other answer stale, including the outdated count. |
| `orphans` | 8 | Real waste, fully remediable in one click, harmless if left. |
| `duplicateVersions` | 7 | Same class as orphans, smaller, and more often deliberate (a kept old version). |
| `cache` | 5 | Pure disk, zero risk, and the one row a user may intentionally keep large. |
| `doctor` | 5 | Homebrew itself says these warnings are "just used to help the maintainers with debugging"; weighting them like a vulnerability would overstate what brew declines to. |

Normalisation, linear between the two ends, every threshold a documented constant in
`HealthThresholds`: `outdated` 1.0 at zero → 0.0 at 25% of installed; `vulnerable` 1.0 at zero → 0.0
at 5% of **answered** packages; `advisoryCoverage` 1.0 when every package was answered → 0.0 at 50%;
`lastUpdate` 1.0 within 1 day (brew's own `HOMEBREW_AUTO_UPDATE_SECS` default of 86400) → 0.0 at 30
days; `orphans` and `duplicateVersions` 1.0 at 0 → 0.0 at 20; `cache` 1.0 at ≤1 GiB → 0.0 at 20 GiB;
`doctor` 1.0 at 0 warnings → 0.0 at 10.

### HD8 — `unknownInputs` is structurally inseparable, and "nothing answered" has no number

```swift
public struct HealthScore: Sendable, Hashable {
    public let value: Int                            // 0...100
    public let contributions: [HealthContribution]   // input, weight, h, points — the breakdown
    public let unknownInputs: [HealthUnknown]        // input + typed reason
    public let answeredWeight: Int                   // the visible denominator
    fileprivate init(...)                            // reachable only through HealthScoring
}
public enum HealthScoreState: Sendable, Hashable {
    case scored(HealthScore)
    case unscorable(unknownInputs: [HealthUnknown])  // nothing was answered — no number exists
}
```

The memberwise initialiser is not public, so no caller can mint a score whose `unknownInputs`
disagrees with its `contributions`; and the surface reads `value` and `unknownInputs` off **one
value**, never two views, so the caveat cannot be dropped in the view layer. `.unscorable` is the
`DiscoverSectionState` technique: a number nobody could compute is a case, not a `0` and not a `100`.
`notCovered`, `unavailable`, `.partial`, `.failed`, `.cancelled`, `CleanupOrphans.unknown`,
`CleanupReportedTotal.unknown`, `DiskRootState.failed` and `isComplete == false` all map to
`.unknown(reason)` — never to `answered(1.0)`.

### HD9 — `.health` is a tenth case; Home stays; the `AppSection` TODO resolves as "keep"

`AppSection.swift:17–20` defers the Home question to this slice by name; D4 resolves it as **keep**,
and the TODO text is replaced by the recorded resolution. `.health` is inserted **after `.cleanup`
and before `.security`** — which satisfies PRD §5's "between Services and Security" while sitting
adjacent to Cleanup, whose shipped verbs three of Health's rows remediate through. Case order defines
sidebar order and `sidebar-health` is its identifier. `ContentView` gains a `.health` arm in both
switches: content = `HealthView`, detail = `HealthBreakdownPanel` (the weights table — the surface
that makes the number arguable). No new `@State` selection. `HomeView` is not touched.

`HealthProjection.build(inputs:now:) -> HealthContent` is `@concurrent static`, pure, in the
`DiscoverProjection` idiom: **rendering triggers no request, no subprocess and no sync.** Rows carry a
Catalog-local `HealthRemediation { upgradeAll, autoremove, cleanupCache, runDoctor, none }`; the app
target is the only place that maps one to `MutationCommand.upgradeAll`, `CleanupCommand(.autoremove)`,
`CleanupCommand(.global)` or a doctor re-run. The "Run doctor" copy states it **re-measures and fixes
nothing** — no `brew doctor --fix` exists, and `brew update` is a `.mutate` §3.4 does not list.
Health owns only the two new acquisitions; the other six inputs are read from resident state.

### HD10 — Bulk pin and unpin: two verbs, own eligibility, unavailable-not-inert

`BulkSelection` gains two stored id lists beside `upgradable`/`uninstallable`:

- `pinnable` = selected ∧ still installed ∧ `kind == .formula` ∧ **not** currently pinned;
- `unpinnable` = selected ∧ still installed ∧ `kind == .formula` ∧ currently pinned.

Formula-only because `MutationCommand.pin(formula:)`/`.unpin(formula:)` take a `FormulaID` by
construction. Derived independently, so a mixed pinned/unpinned selection offers **both** verbs with
honest counts and neither guesses — which is what II13 sc5 forbids. `ids(for:)`, `isAvailable(_:)`
and `label(for:)` extend by two arms each and need no other change; `BulkActionBar` iterates
`allCases`, so both buttons appear with zero structural edit. `commands(for:over:)` gains
`case .pin: MutationCommand.naming(id, MutationCommand.pin)` and the `.unpin` twin, and its doc
comment's "exactly two cases" reasoning is rewritten. No confirmation: `request(_:)` already returns
`nil` for pin and unpin, so `submitBulk` submits directly and DD1's `first.disclosure` fix is
untouched.

**The two test rewrites** (rewritten, never deleted):

- `BulkSelectionTests.swift:70–79` — the count becomes `allCases == [.upgrade, .uninstall, .pin, .unpin]`
  / `count == 4`, and the title scan keeps the three verbs still prohibited:
  `["snooze", "favorite", "note"]`. The assertion's intent is preserved exactly where it survives.
- `ServiceSubmissionTests.swift:213–231` — only the two `allCases ==` / `count ==` lines change.
  Its load-bearing half (`:225–228`, iterating `allCases` against `ServiceCommand.allVerbs` to prove
  no *service* verb entered the package vocabulary) and `ServiceRowControl.allCases.count == 5`
  survive **verbatim**. The SM4 sc5 intent is the point of the test and is kept.
- `BulkSelectionTests:83–95` (`anEmptySelectionOffersNothing`) already loops `allCases` and needs no
  edit — pin and unpin must report unavailable on an empty selection, which they do.

### HD11 — Bulk snooze travels its own app-side path

Snooze produces no `MutationCommand`, so a fifth `Action` case would need a `case snooze: []` arm in
`commands(for:over:) -> [MutationCommand]` — a silent no-op the type system cannot catch — and
`MetadataStore` lives in `Persistence` while `BulkSelection` lives in `BrewClient`, which must not
link SwiftData. So the affordance is a separate button in `BulkActionBar`, beside (not inside) the
`ForEach(BulkSelection.Action.allCases)`, calling `MetadataStore.snooze(id, offering:)` once per
package with **that package's own** `installed.catalogVersion`. It appears nowhere in
`BulkSelection.Action` or `OperationCenter`, submits no operation, writes no history entry, and
spawns nothing. Its eligibility is derived app-side from the same entries the bar already holds:
outdated ∧ not already snoozed at the offered version. Copy names the count and **never a duration**
(`createdAt` is provenance, never policy). `PackageMetadata.isSnoozed`'s string equality and the
structural test proving no comparator is reachable from it both stay untouched.

## Data Flow

    DOCTOR (.read, no mutation gate — U14)
    DoctorCommand.command ─argv["doctor"]→ BrewRunner ─LogLine*→ DoctorSource (cannot throw)
        └→ DoctorParser.parse(rawStdout:rawStderr:exit:) @concurrent
             └→ DoctorOutcome{ .clean(E) | .issues(E) | .unavailable(reason) }
                  E = DoctorEvidence{ rawStdout, rawStderr (separate, verbatim, never joined),
                                      preamble, warnings[], unknownLines:[Data], issues, provenance }

    LAST UPDATE (zero brew invocations — U11/U12)
    HomebrewRoots.prefix → HomebrewRepositoryLocator: <prefix>/Homebrew/.git ?? <prefix>/.git
        └→ FileMetadataAccess.modificationDate(<repo>/.git/FETCH_HEAD)
             └→ HomebrewLastUpdate{ read(Date) | absent | unreadable | futureDated(Date) }

    SCORE + SECTION (app target composes; Catalog computes; nothing is acquired by rendering)
    InstalledBrowse ┐  CoverageTotals ┐  CleanupOrphans ┐  DiskUsageSnapshot ┐  Doctor ┐  LastUpdate ┐
                    └──────────── app-target mapping → HealthInputs (8 × HealthSignal) ─────────────┘
        └→ HealthScoring.score → .scored(HealthScore{value, contributions, unknownInputs}) | .unscorable
             └→ HealthProjection.build → HealthContent{rows[HealthRemediation], score}
                  └→ HealthView / HealthBreakdownPanel → app maps a verb → OperationCenter

## File Changes

| File | Action | Description |
|---|---|---|
| `Sources/BrewClient/DoctorCommand.swift` | Create | Constant `.read` argv; no parameter, no interpolation |
| `Sources/BrewClient/DoctorEvidence.swift` | Create | `DoctorEvidence`, `DoctorWarning`, `DoctorParseIssue`, `DoctorParserProvenance`, `DoctorOutcome`, `DoctorUnavailableReason` |
| `Sources/BrewClient/DoctorParser.swift` | Create | `@concurrent static parse`; HD2 grammar over `Data` |
| `Sources/BrewClient/DoctorSource.swift` | Create | Non-throwing `DoctorSourcing` + `BrewDoctorSource` (`BrewInfoPayloadSource` glue shape) |
| `Sources/BrewClient/BulkSelection.swift` | Modify | `.pin`/`.unpin` cases, `pinnable`/`unpinnable`, three switch arms, doc-comment rewrite |
| `Sources/BrewClient/OperationCenterBulk.swift` | Modify | Two `commands(for:over:)` arms; doc comment rewritten |
| `Sources/DiskUsage/FileMetadataAccess.swift` | Create | The seam + `FileModificationDate` + `SystemFileMetadataAccess` |
| `Sources/DiskUsage/HomebrewUpdateReader.swift` | Create | `HomebrewRepositoryLocator` (probe order) + `HomebrewLastUpdate` |
| `Sources/DiskUsage/HomebrewRoots.swift` | Unchanged | **Deliberately not widened** (HD4) |
| `Sources/Catalog/HealthInputs.swift` | Create | Eight inputs, `HealthSignal`, `HealthUnknownReason`, `HealthRemediation` |
| `Sources/Catalog/HealthScore.swift` | Create | `HealthWeights`, `HealthThresholds`, `HealthScore`, `HealthScoreState`, `HealthScoring` |
| `Sources/Catalog/HealthProjection.swift` | Create | `@concurrent build`, `HealthContent`, `HealthRow` |
| `cellar/Shell/AppSection.swift` | Modify | `.health` case, title, `heart.text.square`; TODO replaced by the D4 resolution |
| `cellar/ContentView.swift` | Modify | Two `.health` switch arms |
| `cellar/cellarApp.swift` | Modify | Doctor source + update reader composition |
| `cellar/Health/HealthView.swift`, `HealthRowView.swift`, `HealthBreakdownPanel.swift`, `HealthStore.swift`, `HealthComposition.swift` | Create | New **synchronized root group** → 0-line pbxproj diff |
| `cellar/Installed/BulkActionBar.swift` | Modify | Bulk-snooze button beside the `allCases` `ForEach`; `BulkActionBarPresentation` value |
| `cellar/Installed/InstalledListView.swift` | Modify | Passes `metadata` and the snooze handler to the bar |
| `Tests/BrewClientTests/Fixtures/Doctor/` | Create | Captured + hand-authored streams, README, manifest |

`HealthStore` is a thin `@MainActor @Observable` holder for the **two new acquisitions only** (last
doctor outcome, last update reading) with explicit `refresh()` — it polls nothing and no view `.task`
triggers it. It is not a health store in the polling sense the proposal forbids.

## Interfaces / Contracts

```swift
public enum DoctorOutcome: Sendable, Hashable {
    case clean(DoctorEvidence)
    case issues(DoctorEvidence)                    // non-zero exit — ordinary, carries the document
    case unavailable(DoctorUnavailableReason)      // spawn failure or cancellation only
}
public protocol DoctorSourcing: Sendable {         // no `throws`, by design (HD1)
    func run(using installation: BrewInstallation) async -> DoctorOutcome
}
public enum HealthInput: String, Sendable, Hashable, CaseIterable {
    case outdated, vulnerable, advisoryCoverage, lastUpdate
    case orphans, duplicateVersions, cache, doctor
}
public enum HealthSignal: Sendable, Hashable {
    case answered(Double)                          // 0.0...1.0, already normalised
    case unknown(HealthUnknownReason)
}
```

## Testing Strategy

Strict TDD — RED before GREEN for every behavioural task, with a recorded cycle-evidence table
(slice 4's 21-row bar). Inner loop: `swift test --package-path Packages/CellarCore`.

| Layer | What | Approach |
|---|---|---|
| Unit — doctor parser | Every HD2 grammar row; the captured 622-byte stderr; the hand-authored clean run; the hostile odd-grouping fixture; non-UTF-8 bytes survive in `unknownLines`; `warningCount == 0` (not absent) when clean | Pure `Data` in, `DoctorEvidence` out — **no process** |
| Unit — doctor source | Exit 1 → `.issues` carrying evidence; exit 0 → `.clean`; cancelled → `.unavailable(.cancelled)`; spawn failure → `.unavailable`; both raw streams preserved separately and unconcatenated; argv is exactly `["doctor"]` and `.read` | `RecordingProcessLauncher`, per-instance |
| Structural — quarantine | HD3, both directions, over all three JSON payload sources | Behavioural over the shipped functions |
| Unit — update reader | Probe order on both install shapes; `.absent`, `.unreadable`, `.futureDated`; **zero** launcher invocations | Fake `FileMetadataAccess`, no disk |
| Regression — HD4 | `DiskRootsIdentity`, `DiskUsageSnapshot` encoding and `currentlyOnDiskBytes` unchanged; an existing cache file still loads | Existing `StoreCacheTests`/`CleanupParserTests` run unedited |
| Unit — score | Each weight readable from `contributions`; every unknown reason lands in `unknownInputs`; `notCovered`/`unavailable`/`.partial` never score as clean; all-unknown → `.unscorable`; monotonicity per input; no store/clock/process in the signature | `CatalogTests`, pure values |
| Unit — projection | Rendering acquires nothing; rows carry the right `HealthRemediation`; the score and its caveat come from one value | `CatalogTests` |
| Unit — bulk | `allCases == [.upgrade, .uninstall, .pin, .unpin]`; pin/unpin eligibility independent on a mixed selection; casks never pinnable; empty selection unavailable-not-inert; no confirmation requested; the two rewritten tests keep their original intent | `BulkSelectionTests`, `BulkFanOutTests`, `ConfirmationDisclosureTests`, `ServiceSubmissionTests` |
| App — bulk snooze | N packages record N different offered versions; nothing submitted; no history row; `BulkSelection.Action` and `OperationCenter` never named on the path; copy implies no duration | `cellarTests`, `BulkActionBarPresentation` as a plain value (the `PackageInspectionRow` idiom) |
| App — `BulkActionBar` (**no covering tests today**) | Two-part strategy: (a) extract `BulkActionBarPresentation` so labels, counts, roles and enablement are provable without rendering; (b) a `TapShippingProofTests`-style bounded-control guard over `BulkActionBar.swift` enumerating the expected button labels and asserting no unbulked verb string appears | `cellarTests/BulkActionBarTests.swift` — new |
| App composition | Health composes SecurityKit; doctor source and update reader injected once in `cellarApp` | `cellarTests/HealthCompositionTests.swift` with a **per-instance UUID-tagged ledger** under `Mutex`. **Do not** add a call site to `SecurityCompositionSupport.swift:181`'s `CompositionRequestSpy` — its `nonisolated(unsafe) static var count` + `install()` reset is the shipped false-zero shape |
| UI | Sidebar shows `sidebar-health`; the score renders beside its `unknownInputs`; "Run doctor" copy claims no fix | `cellarUITests`, identifiers on leaf views (never a container root — A9) |

**Fixtures** — `Tests/BrewClientTests/Fixtures/Doctor/`, to the `Fixtures/Bundle` standard exactly
(`README.md` with capture date, Homebrew version, binary path, exact argv excluding `brew`, exit
status, per-stream byte counts and provenance; `probe-manifest.txt` with SHA-256 per stream;
`DoctorFixtureManifestTests`):

1. `warnings-run/` — **captured** on this machine 2026-08-07 (exit 1, stdout 1 B, stderr 622 B),
   both streams byte-exact.
2. `clean-run/` — **hand-authored and visibly marked as such** in its own directory and in the README
   (this machine has real warnings, so exit 0 could not be captured — U10).
3. `odd-grouping/` — **hand-authored hostile**: an empty `Warning: ` headline, an indented detail line
   before any warning, two adjacent warnings with no detail, and a non-UTF-8 byte run.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Subprocess integration (`brew doctor`) | **Applicable** | `.read` (U14: FETCH_HEAD mtime identical before/after under `HOMEBREW_NO_AUTO_UPDATE=1`), so it bypasses the mutation gate and mutates nothing | `.read` + argv pinning; a doctor run submits no operation and writes no history |
| Argument composition | **Applicable** | `BrewCommand.read(["doctor"])` is a compile-time constant; no package name, selection or user string can reach it; argv-only, never `/bin/sh -c` | Structural: the doctor argv contains exactly one element and no stored `String` |
| Untrusted subprocess payload | **Applicable** | Parser is a pure function over synthesised `Data`; hostile shapes (non-UTF-8, orphan detail lines, empty headlines, a payload on the "wrong" stream) are reachable with no process; raw streams verbatim and separate | The odd-grouping fixture; the HD3 quarantine suite both directions |
| Filesystem path resolution | **Applicable** | Probe order is a closed two-element list under `HomebrewRoots.prefix`; no user-supplied path, no env var read, no symlink following into an unknown root; failure is a typed case, never an invented `Date` | `.absent`/`.unreadable`/`.futureDated` reachable; zero launcher invocations |
| Irreversible mutation scope (bulk widening) | **Applicable** | Pin and unpin are reversible and require no confirmation; the destructive verb set is unchanged; snooze writes one local row per package and submits nothing | Mixed-selection eligibility; no confirmation raised; snooze spawns no process |
| Executable-file classification / VCS / PR automation | **N/A** | This change performs no VCS operation, opens no PR and classifies no file as executable | None |

## Concurrency (Swift 6 strict)

`CellarCore` uses SwiftPM nonisolated defaults; the app defaults to `MainActor`. Every doctor, health
and update model is a `Sendable` value type, so results cross back to the main actor with no lock and
no `@unchecked`. `DoctorParser.parse` and `HealthProjection.build` are `@concurrent` with the
attribute **before** the modifier (M1 convention), matching `DiscoverProjection.build` and
`PackageSearchIndex.build`. `DoctorSource` is a nonisolated `Sendable` struct over
`any ProcessLaunching` using `withTaskCancellationHandler`, like `CleanupPreviewSource`.
`FileMetadataAccess` is a synchronous `Sendable` protocol (an `attributesOfItem` call, not I/O worth
suspending). `HealthStore` is `@MainActor @Observable` and only assigns awaited results. No new
actor, no `nonisolated(unsafe)`, no `@preconcurrency`, no `#available`.

## Migration / Rollout

No migration. No cache file, schema version, `UserDefaults` key or Keychain item is introduced; no
`CatalogPackage` field is added, so S4's ~2.4% headroom is untouched. Bulk snooze writes only
existing `Snooze` rows through the shipped API, so reverting the UI leaves them valid and
individually unsnoozable.

## Rollback

One `git revert` of the merge restores `main`. The new `cellar/Health/` files revert as deletions
with **zero** `project.pbxproj` objects to remove (existing synchronized-root-group pattern, proven
by `cellar/Discover/`). The one exception is the II13 reversal, which reverts as spec-text
restoration plus the two rewritten tests — the byte-sliced replaced ranges are recorded in the delta
for exactly this. A partial revert that restores the spec text without restoring
`BulkSelectionTests` and `ServiceSubmissionTests` leaves the suite red; a partial revert of
`BulkSelection.swift` without `OperationCenterBulk.swift` leaves `commands(for:over:)`
non-exhaustive and uncompilable. Those two pairs revert together or not at all.

## Open Questions

- [x] **Both resolved at apply (13.4).** (1) The HD7 weights **stand as proposed** — the maintainer
      reviewed them with this design and made no change; the `cache`/`doctor` tie at 5 is deliberate
      and is now asserted explicitly rather than left implicit (see F7 below). (2) `.health` ships
      **after `.cleanup` and before `.security`**, which is what "between Services and Security"
      means in the shipped sidebar order; the alternative placement directly after `.services` was
      not taken.

## Apply-Time Amendments

Recorded rather than absorbed. Each of these is a place where the evidence forced a change to what
this document specified, and each one is a change the code actually made.

### HD2 gains one document-level rule its per-line table cannot express (F4)

The per-line grammar table is complete for a document that opens at least one `Warning:` block. It is
not complete for one that opens none, and two spec scenarios are jointly unsatisfiable without a
rule about that case: a clean run must report **zero** unknown lines, and a wholly unrecognised
report must carry **the whole document** among its unknown lines and be flagged partial. Both have
zero blocks, so the per-line table files both entirely as preamble — and an unrecognised report then
reads exactly like a healthy machine.

Shipped with one added rule: **if no block opened and the document carries no ready statement, the
accumulated preamble is reclassified into `unknownLines` with a new `.unrecognisedReport` issue.**
Recognising Homebrew's own clean sentence is what makes that decidable, so `DoctorParser.readyStatement`
is a named constant and `DoctorEvidence.reportsReady` records it — the only way to tell "no warnings"
from "no idea" from the bytes alone.

### HD8 gains `HealthMeasurement`, so a row can state what it does not know (F9)

`HealthInputs` as designed carries only a normalised `Double` per input. A row built from that alone
could never render "3 vulnerable", so "never renders 0 vulnerable for an unanswered scan" would have
been **vacuously** true — the strongest-sounding guarantee in the delta, satisfied by having nothing
to render at all.

Added a Catalog-local `HealthMeasurement { summary, unanswered }`, supplied by the app beside the
signals and returned **only where the signal was answered**, so a count can never outlive the answer
it came from. `Catalog` still names no foreign type and learns nothing about bytes, kegs or CVEs: the
summary is app-authored text, and `HealthComposition` is the only thing that writes one.

### `DiskUsageSnapshot` encodes non-deterministically — pre-existing, not fixed here (F12)

`[DiskArea: DiskRootState]` encodes as a flat JSON **array** (`DiskArea` is not
`CodingKeyRepresentable`), and `.sortedKeys` does not sort array elements, so element order follows
dictionary iteration order and varies between runs. Harmless for the cache, which round-trips, but it
means a whole-snapshot byte golden is flaky.

Not caused by this change and deliberately not fixed here: the fix would touch `DiskUsageModels.swift`,
one of the seven binding zero-line-diff files. The HD4 golden was narrowed to `roots` alone, which is
deterministic and is the only part HD4 is about. **Recorded as a follow-up.**

### The LPM5 guard is re-rooted at the repository, and the app caller is named (11.6)

`SnoozeGuardTests`' reader stopped at `Packages/CellarCore`, so it could not open
`cellar/Installed/BulkActionBar.swift` at all — and a scan that cannot open a file does not fail, it
reads an empty string and passes. It is now rooted at the **repository**, and every existing path is
prefixed rather than any existing assertion being relaxed.

**Of LPM5's two admissible options, the chosen one is: name the app surface in `capabilitySources`.**
The alternative — proving the surface writes only through `Sources/Persistence/MetadataStore.swift` —
is a claim about what a file does *not* reach, and it would hold vacuously the day a second write
path is added. Naming the file puts its real bytes under the same forbidden-comparator and
security-token scans as the rule itself. A new test,
`noSnoozeCallerOutsideThisPackageCanEvadeTheGuard`, holds it to **both** token sets, and the per-file
anchor assertion is kept precisely because the re-rooting is what makes it satisfiable.

### `HD7`'s weights: the `cache`/`doctor` tie stands, and `tasks.md` 6.5 was the error (F7)

`tasks.md` 6.5 asked for "doctor is **strictly the lowest** weight". HD7's own table proposes
`cache 5` and `doctor 5` — a tie at the bottom. The **spec** (SH10) requires only that doctor be lower
than the weight applied to the user's own outdated packages, which 5 < 20 satisfies.

Ruled by the maintainer: the **tie stands** and the task text was wrong. 6.5 is reworded to
"doctor < outdated". `HealthWeightsTests` asserts `doctor == min(all weights)`, asserts `doctor <`
every signal describing the user's own packages, and asserts the `cache` tie **explicitly and
visibly** rather than leaving it to be discovered.

### Four more, smaller, each recorded where it happened

- **F3** — HD10's `MutationCommand.naming(id, MutationCommand.pin)` does not typecheck, and the
  obvious repair (`MutationCommand.pin(formula: id.name)`) is *wrong*: the name-based factory rebuilds
  the identity as a formula, so a cask would silently produce `pin --formula iterm2`. Shipped as
  `FormulaID(id).map(MutationCommand.pin)`, which checks the kind and returns `nil` for a cask.
- **F10** — `DoctorOutcome`/`DoctorUnavailableReason` are `Equatable`, not `Hashable` as specified:
  `BrewProcessError`, carried verbatim rather than re-described, is `Equatable` only. The new types
  were narrowed rather than a shipped `BrewProcess` type widened to satisfy a new consumer.
- **F11** — `DoctorParser.parse` takes no `exit`, contrary to the Data Flow sketch. An `exit` in the
  parser's signature would let two byte-identical captures produce unequal evidence, which SH3
  forbids. `BrewDoctorSource` classifies; the parser reads bytes.
- **F13** — **`ContentView` has never landed on Home.** `tasks.md` 9.1 and 12.1 both ask for "Home is
  still the landing section, asserted over the shell's default selection". The shipped value is
  `@State private var section: AppSection = .browse`, and has been since M1. Changing it would be a
  user-visible behaviour change no requirement in this delta asks for, and HD9 rules it out ("No new
  `@State` selection"). What this change owes is asserted instead — **Health did not take the landing
  spot, and this change moved nothing** — with the literal `browse` pinned so a future silent move
  fails the test. **Open for the maintainer**: if Home *should* be the landing section, that is a
  one-line change and its own decision.
- **10.2, narrowed honestly** — the task asks that "no view `.task` calls `HealthStore.refresh()`".
  The Health section carries exactly one `.task`, and it rebuilds the **pure** projection when the
  inputs change; `HealthProjection.build` takes one value and a date, so there is no seam in its
  scope to reach. The test forbids a `.task` that *acquires* (`runDoctor`, `readLastUpdate`,
  `startPreview`, `refresh`, a scan, a measurement, a sync) rather than forbidding `.task` outright,
  and it carries both an anchor and a violation control. Per SH7's own wording, only the **doctor
  run** must be user-initiated; the invocation-free last-update reading joins the app's existing
  launch-and-activation refresh in `cellarApp`, which never calls `runDoctor`.
- **UI fixture determinism** — `--ui-testing-m5-health` redirects the disk-usage and advisory cache
  files to per-launch temporary paths. Without that, `DiskUsageStore` and `SecurityStore.start()`
  adopt the **developer's own machine's** cached measurements with no consent and no network, and the
  "nothing could be scored" launch scored 63 out of a machine nobody measured — a UI test that passes
  on a fresh CI box and fails on every real one.
- **Verify remediation (post-verify, bounded)** — verify returned FAIL on one CRITICAL:
  `HealthComposition.command(for:)` was referenced by no test, so SH11 sc3 ("a remediation keeps its
  owner's confirmation") had no covering test and sc1's second half was partial. Closed with
  `cellarTests/HealthRemediationTests.swift` (5 tests, **no production change**): the five
  remediation→command mappings pinned to their exact shipped values over `allCases`; each cleanup
  remediation asserted to carry **Cleanup's own** `requiresConfirmation` and `disclosure` and
  upgrade-all **Installed's own** gate — ownership, not a re-issued copy; plus a comment-stripped
  guard over `cellar/Health/` (anchor on the shipped routing, sweep for eight bypass tokens,
  violation control). Proven non-vacuous by a temporary mutation of `HealthComposition`/`HealthView`
  that failed all three real-code tests, then reverted byte-for-byte. WARNING 1 closed with it: the
  D4 note said "Home keeps the landing spot", which F13 disproved, and `AppSectionPlacementTests`
  pinned that wrong string while `:75` pinned `landing == "browse"`; the comment now records what
  shipped and the assertion pins the correction. WARNING 2 (`cellarApp.swift` initializer length) is
  untouched and remains open.
- **SH4 sc3 closed by observation, not by assertion (verify-2 precedent)** — verify rev 2 returned FAIL
  with zero CRITICAL on one PARTIAL scenario: "running doctor does not move the fetch marker" had no
  test that runs doctor and re-reads the marker, because no argv-level assertion can prove what `brew
  doctor` does inside itself. Offered as two exits — a maintainer ruling that probe U14 discharges it
  as manual verification, or one integration test — and the maintainer chose the test. Added as
  `Packages/CellarCore/Tests/BrewClientTests/DoctorIntegrationTests.swift` (1 test, **no production
  change**), in the integration layer `openspec/config.yaml` already declares against the real binary
  and under `BrewIntegrationTests`' established `.enabled(if:)` skip idiom and `.realBrew` tag. It
  resolves the marker through the shipped `HomebrewRepositoryLocator`/`HomebrewUpdateReader` rather
  than a literal path, asserts `HOMEBREW_NO_AUTO_UPDATE=1` is in effect from `BrewEnvironment.pinned`
  instead of setting it, and refuses three vacuous passes: an unresolved marker, an `.unavailable`
  doctor outcome, and a run that wrote no bytes.
