# Design: M2-3 — Local Metadata & History

Proposal: `openspec/changes/m2-local-metadata-history/proposal.md` (binding, including the four settled
product decisions and the four confirmed residuals, Engram `#7111`). Umbrella exploration:
`openspec/changes/m2-mutations-installed/explore.md` §5 (placement A), §8 (risks 10), §9. Baseline
`main` @ `8c9bc2a`. Artifact store: hybrid — mirrored in Engram `sdd/m2-local-metadata-history/design`.

## Technical Approach

Four layers, each one the shipped exemplar applied once more:

1. **A new leaf target `Persistence`** in CellarCore holding the SwiftData `VersionedSchema` V1, the
   three `@Model` classes, the container factory and two `@MainActor @Observable` stores. It is the
   outermost node of the package graph — nothing depends back on it — so `Catalog` stays brew-free
   (CS1) and `BrewClient` never links SwiftData.
2. **Value-typed seams in `BrewClient`**: `PackageMetadata` (a `Sendable` struct), a metadata *lookup
   closure* mirroring the existing `catalogLookup:`, and a `HistoryRecording` protocol with a no-op
   default. Every rule — the snooze projection, the favorites filter, the bulk-eligible sets — is a
   pure function over values in `BrewClient`, testable in the `swift test` inner loop with no SwiftData
   in sight.
3. **Retention before history** in `BrewProcess`: `BrewRunner` compacts and then releases terminal
   operation records, with the guarantee expressed by ownership rather than by a timing bet.
4. **Presentational views** in the app target: star toggles, notes editor, snooze control, multi-select
   bar, History section. No rule lives above `Persistence`/`BrewClient`.

```
 View (app target)                       CellarCore
 ─────────────────                       ──────────
 InstalledListView ──reads──▶ InstalledBrowse.entries(…, metadata:)   [BrewClient]
        │                              │  favorites filter, snooze-aware outdated,
        │                              │  bulk-eligible sets — all pure
        │                              ▼
        └──writes──▶ MetadataStore ──▶ ModelContext(main) ──▶ PackageMeta / Snooze   [Persistence]
                          │                                     ▲
 MutationMenu ──submit──▶ OperationCenter ──finish()──▶ HistoryRecording ──▶ HistoryEntry
                               │            (exactly one write per terminal outcome)
                               ▼
                          BrewRunner (FIFO gate, retention D6)             [BrewProcess]
```

## Architecture Decisions

### D1 — `Persistence` depends on `BrewClient`, not on `Catalog` alone

The proposal's approach §1 said "`Catalog` for `PackageID` only". Refined here: the SwiftData
`HistoryRecording` conformance must read `MutationCommand` (verb, package, argv) and `MutationOutcome`,
both of which live in `BrewClient`.

| Option | Verdict |
|---|---|
| `Persistence → BrewClient → {BrewProcess, Catalog}` | **Chosen.** One-directional, nothing depends back; `Catalog` still never sees brew (CS1 intact); the draft→row mapping stays in CellarCore where it is testable |
| `Persistence → Catalog` only, adapter in the app target | Rejected: puts mapping logic in the app target, against `rules.design` ("views, scenes and DI wiring only") and outside `swift test` |
| Move the value types down into `Catalog` | Rejected: favorites/notes/history are not published-catalog concepts; it would pollute the module whose whole point is that it is brew-free derived data |

### D2 — Schema V1: three independent models, primitives only, no relationships

`enum SchemaV1: VersionedSchema` with `Schema.Version(1, 0, 0)`; `enum MetadataMigrationPlan:
SchemaMigrationPlan` with `schemas: [SchemaV1.self]`, `stages: []` — present from day one so M4
`DismissedCVE` and M6 `Settings` are `.lightweight` stages, not a rewrite (proposal risk 1).

| Model | Stored | Key |
|---|---|---|
| `PackageMeta` | `kindRaw: String`, `name: String`, `isFavorite: Bool = false`, `note: String = ""`, `updatedAt: Date` | `#Unique([\.kindRaw, \.name])` |
| `Snooze` | `kindRaw`, `name`, `snoozedVersion: String`, `createdAt: Date` | `#Unique([\.kindRaw, \.name])` — one active snooze per package; re-snoozing updates the version |
| `HistoryEntry` | `id: UUID` (the `ActivityItem` id), `date: Date`, `kindRaw: String`, `name: String`, `verb: String`, `versionFrom: String`, `versionTo: String`, `outcomeRaw: String`, `exitStatus: Int?`, `argv: [String]`, `commandText: String` | `#Unique([\.id])` |

Rules that hold across all three:

- **`PackageKind` persists as its `rawValue`, not as a `Codable` enum.** `#Predicate` stays a string
  comparison, and a future kind cannot break decoding of existing rows.
- **Absence is the empty string, never `Optional`.** A package name can never be empty (`MutationName
  .isSafe` refuses it), so `name == ""` unambiguously means "this entry names no package"
  (`upgradeAll`). This keeps every `#Predicate` non-optional, which is the shape the macro handles best.
- **`MutationOutcome` persists as `outcomeRaw` + `exitStatus`, not as a `Codable` enum.** The domain
  enum carries associated values (`.failed(status:)`, `.abandoned(after: Duration)`) and will grow;
  pinning the on-disk shape to it would make every future outcome a migration.
- **`commandText` is a deliberate denormalisation** of `argv.joined(separator: " ")`. `#Predicate`
  cannot express substring matching across `[String]`, and search must reach the argv (settled R3/R4
  keeps note contents out of search, not the command).
- **No `@Relationship` anywhere in V1.** History must survive both an uninstall and a metadata delete;
  a cascade rule from `PackageMeta` would be exactly wrong, and a nullify rule would buy nothing that
  the joint key does not already give. `@Transient` is unused (so its default-value trap cannot bite).
- Every `@Model` class is `public final`, as option A requires.

### D3 — `@MainActor @Observable` stores over the main context; no `@Query`, no `@ModelActor`

`MetadataStore` and `HistoryStore` are `@MainActor @Observable public final class`, on the shipped
`InstalledStore`/`OperationCenter` exemplar. They own the `ModelContainer` and use its `mainContext`.

- **No `@Query` and no `.modelContainer(…)` scene modifier.** The stores publish plain `Sendable`
  values (`MetadataSnapshot` = `[PackageID: PackageMetadata]`, `[HistoryRecord]`), so `@Model`
  instances never leave `Persistence` and the composition rules can be proven over values in
  `BrewClient`. The container is owned like `CatalogStore` is — `@State` in `cellarApp`, injected
  down. Adding `.modelContainer(store.container)` later remains a one-line option if `@Query` is ever
  wanted.
- **No `@ModelActor` in this slice.** Every M2-3 write is one user-initiated row on the main context.
  The gotchas are carried anyway and are non-negotiable the moment a background path appears: never
  pass a `@Model` instance across an isolation boundary (`PersistentIdentifier` only, it is the
  `Sendable` one), `ModelContext` stays on its creating actor, and any `@ModelActor` method calls
  `save()` explicitly.
- **Writes save explicitly** rather than relying on autosave, so a test can assert durability without
  a run-loop turn, and the snapshot is republished from the store after each save.
- **The metadata snapshot is loaded whole; history is queried.** Favorites/notes/snoozes are a few
  hundred tiny rows. History goes through a `FetchDescriptor` with a predicate and
  `SortDescriptor(\.date, order: .reverse)` — and **no `fetchLimit`**: keep-all retention (settled Q1)
  means an empty search MUST return every entry, and truncating the view would quietly contradict the
  retention promise. Volume is bounded by what the user did *through Cellar*, which is small; if it
  ever measures slow, pagination is an additive change to the query, not to the schema.

### D4 — A degraded store is a state, never a crash

`ModelContainer(for:migrationPlan:configurations:)` throws. Container creation is caught and folded
into `MetadataStore.availability = .unavailable(reason)`, mirroring `InstalledAbsence`/`CatalogStore`.
Consequences: reads return the empty snapshot, writes are no-ops, the star/note/snooze affordances
render disabled with the reason attached, and history reads/writes are skipped. A corrupt or
unwritable store therefore costs local metadata and nothing else — the app still browses, installs and
upgrades. Rationale: this is the same shape as brew being absent, and a `try!` at launch would turn a
recoverable disk problem into a boot loop.

Store location: `Application Support/<bundleID>/Metadata/Metadata.store`, alongside the existing
`…/<bundleID>/Catalog/` directory (`CatalogStore.defaultDirectory()` precedent).

### D5 — Snooze is "different from the snoozed version", not an ordering comparison

The stored fact is the version string the snooze was taken against. The badge rule is a pure function
in `BrewClient`:

```swift
// hidden while the offered version is exactly the one that was snoozed
func isSnoozed(offering candidate: String, snoozedVersion: String?) -> Bool {
    snoozedVersion == candidate
}
```

| Option | Failure mode | Verdict |
|---|---|---|
| String inequality (chosen) | A package that *reverts* to an older version revives the badge | **Chosen** — the failure mode is showing a badge that is honest |
| `compare(_:options:.numeric)` ordering | A comparator that misreads `1.2.3_1`, `2023-10-01`, `r5` or `9e` **suppresses a real update forever, silently** | Rejected: silent suppression is the one outcome this feature must never produce |

**RESOLVED 2026-08-02 (user ruling, Engram `#7117`): inequality it is.** The spec blocks are being
rewritten to equality-based suppression, so the proposal's "strictly newer" wording is superseded and
the rule above stands exactly as written. Gate G5 below is closed.

The rule composes above the inventory exactly as the M2-1 filters do — outdated-state × stored snooze
— so a cold, empty or unavailable metadata store degrades to today's behaviour with no branch.

### D6 — Runner retention: compact on terminal, remove on release (follow-up 4)

Today `BrewRunner.operations` never sheds an entry, and each entry retains a `LaunchedProcess`
(a `Process` and two `Pipe`s), a pump `Task`, a completion `Task` and an `AsyncStream` continuation —
for the process lifetime, for every *read* refresh as well as every mutation. Reads are the higher-
volume producer (one per launch, per activation, per mutation terminal).

Three rules, in order:

| # | Rule |
|---|---|
| R1 | A record that is not terminal, or whose pump/completion has not finished, is **never** touched |
| R2 | On terminal ∧ drained, the record is **compacted**: `process`, `pump`, `completion`, `continuation` and `lines` are released. `id`, `command`, `ordinal`, `resolvedExit` and `fault` survive (~100 bytes), so the record stays enumerable and `exit(of:)`/`fault(of:)` still answer exactly |
| R3 | A compacted record is **removed** only once its handle has been released; released-and-compacted records are additionally capped at 200, oldest ordinal first |

Release is by ownership, not by timing: `BrewOperation` becomes a `final class` (all stored properties
immutable and `Sendable`, so the type stays `Sendable`) whose `deinit` hands the id back to the runner.
`ActivityItem` holds its `BrewOperation` exactly while it is cancellable and drops it in `settle(_:)`.
Therefore **a record can only be removed when no caller can still ask about it** — the constraint
"eviction cannot break `exit(of:)` for an operation still being awaited" is structural, not
probabilistic. The 200-cap is a belt over already-released records; the true bound is
`live handles + 200`.

Rejected: an explicit `runner.retire(id)` call — correctness would depend on every consumer
(`OperationCenter` *and* `InstalledPayloadSource`) remembering it. Rejected: a plain LRU on terminal
records — it evicts by count, which is exactly the timing bet the constraint forbids.

Spec interaction: `brew-execution`'s "identity is stable … while pending, while running, and once
terminal" still holds — a test holding its handle keeps its record by R3. `operation-activity` OA1
("terminal items stay enumerable for the session") is about `OperationCenter.items`, which are never
evicted; durable retention moves to `installation-history`. `OperationCenter.apply(_:)` already writes
a phase only when the snapshot carries that id, so a removed record silently stops updating an item
whose `isTerminal` is decided by its `outcome` anyway — that tolerance is now load-bearing and gets a
test.

**Follow-up 4b** (same file, one line): `apply(_:)` guards the write —
`if item.queuePhase != phase { item.queuePhase = phase }` — killing observation churn on every yield.
`OperationSnapshot.Phase` is already `Equatable` (`isRunning` compares it).

### D7 — History is written at the one terminal funnel, from the transition intended at submission

```swift
@MainActor public protocol HistoryRecording {           // BrewClient
    func record(_ draft: HistoryDraft)
}
public struct NoHistoryRecording: HistoryRecording { public func record(_: HistoryDraft) {} }
```

- **Synchronous, `@MainActor`, non-throwing.** `OperationCenter.finish(_:with:)` is already the single,
  idempotent terminal funnel that pays the gate exactly once; hanging the write there makes "exactly
  one entry per terminal outcome" true by construction. Non-throwing because a failed *write* must
  never change a *mutation's* reported outcome — the store surfaces its own `lastError`.
- **Versions are captured at submission, not observed after.** `submit(_:versions:)` takes an optional
  `VersionTransition(from:to:)`; `submitUpgrades(for:in:)` derives it from the inventory it is already
  handed (`installedVersion` → `catalogVersion`); `MutationMenu`/`PackageDetailView` pass the entry's.
  The entry therefore records the transition Cellar *intended*, and `outcomeRaw` says whether it
  happened. Rejected: diffing an inventory snapshot either side of the operation — it needs a
  re-snapshot to land before the write, makes the entry depend on watcher timing, and is exactly the
  per-package attribution settled decision R1 declines for `upgradeAll`.
- **`upgradeAll` writes one grouped entry** (settled R1): `name == ""`, no versions, `verb ==
  "upgradeAll"`, argv `["upgrade"]`.
- **Only Cellar-submitted mutations are recorded** (settled R2). No FSEvents-driven write exists.
- **Clear history is all-or-nothing behind a confirmation** (settled R3):
  `try context.delete(model: HistoryEntry.self)` — and it touches no other model.
- `HistoryEntry.id` is the `ActivityItem.id`, and `#Unique` on it means a replayed write cannot
  double-log.

### D8 — Bulk selection: one derived set feeds the label, the button and the confirmation (follow-up 1)

Today `InstalledListView` labels the button `outdated.count` (post-dependency-toggle entries) while
`submitUpgradesForOutdated(in:)` submits over the *whole inventory* minus pinned — two different sets.
The fix is structural: `InstalledBrowse` gains one computed projection and both the label and the
submission read it.

```swift
// BrewClient — pure, testable, one definition. Built from the ORDERED selection,
// so both arrays come out in selection order and stay there through submission.
public struct BulkSelection: Sendable {
    public init(selection: [PackageID], entries: [PackageEntry])
    public let upgradable: [PackageID]   // selected ∧ outdated ∧ !pinned ∧ !snoozed
    public let uninstallable: [PackageID]// selected ∧ installed
    public enum Action: CaseIterable { case upgrade, uninstall }  // pin/unpin/snooze absent, assertably
}
```

- `submitUpgradesForOutdated(in:)` is replaced by `submitUpgrades(for: browse.upgradableIDs, in:)`, so
  the pinned exclusion (PM2 — and still no unpin on their behalf) lives in the derivation, once.
- The **outdated section, the outdated count, the badge and the bulk bar all read the same projection**,
  which is what makes the snooze exclusion (proposal §Modified capabilities) consistent by construction
  rather than by four agreeing filters.
- **Fan-out is the M2-2 ruling**: N selected packages → N `.upgrade`/`.uninstall` submissions in
  selection order, each with its own item, log, cancel and outcome. No new argv shape exists, so no new
  brew probe is required.
- **Bulk uninstall confirmation names every selected package.** `ConfirmationRequest` gains a
  multi-command form; the sheet lists each `displayCommand` verbatim. Pin/unpin/snooze expose no bulk
  affordance — `Action` is `CaseIterable` with two cases so the absence is a test assertion, the same
  technique `ActivityItem.Control` uses.
- **Selection model — order-preserving, because `installed-inventory` requires submission in selection
  order.** SwiftUI's `List(selection:)` binding is a `Set`, and a `Set<PackageID>` cannot carry order,
  so the list keeps the native affordance and the *order is recovered beside it*:

  ```swift
  @State private var selected: Set<PackageID> = []   // bound to List(selection:) — native multi-select
  @State private var order: [PackageID] = []         // the ordered truth; the only thing bulk reads

  .onChange(of: selected) { previous, current in
      order.removeAll { !current.contains($0) }                     // deselections keep the rest in place
      let added = entries.map(\.id).filter { current.contains($0) && !order.contains($0) }
      order.append(contentsOf: added)                               // displayed-row order, never Set order
  }
  ```

  The two-step diff is total and deterministic: a single click adds exactly one id, so click order is
  click order; a shift-click or Select All adds many at once, and those are appended **in displayed-row
  order** — never in `Set` iteration order, which is unstable across launches and would make the
  submission sequence non-reproducible. `order` is the only thing `BulkSelection` and the confirmation
  sheet ever read, so what the label counts, what the sheet lists and what `submitUpgrades` fans out
  are one sequence.

  Rejected: a `List(selection:)`-free custom row-tap handler (loses shift/⌘ range selection, VoiceOver
  and Select All for free); rejected: sorting the `Set` by name at submission time (deterministic, but
  it is not the user's order, which is what the spec asks for).

  The detail binding (`PackageID?`) is written only when `order.count == 1`. Browse's single-selection
  contract is untouched.

### D9 — `naming(_:_:)` becomes structurally unnecessary (follow-up 3)

`MutationMenu.swift:27` (`.install(entry.id)`) and `PackageDetailView.swift:69`
(`MutationCommand.install(package.id).displayCommand`) construct package-naming cases directly,
bypassing the name guard. Fixing the two call sites would leave the third one to come.

Instead, the four bare-`PackageID` cases take a proven target:

```swift
public struct PackageTarget: Sendable, Hashable {   // the same technique as FormulaID / CaskID
    public let id: PackageID
    public init?(_ id: PackageID) { guard MutationName.isSafe(id.name) else { return nil }; self.id = id }
}
case install(PackageTarget) | uninstall(PackageTarget) | reinstall(PackageTarget) | upgrade(PackageTarget)
```

`FormulaID`/`CaskID` are re-expressed over it so `isSafe` has one definition. `naming(_:_:)` keeps its
signature and its callers, but the guard is now enforced by the type rather than by remembering to use
it — an unvalidated command becomes unrepresentable, which is what D1/D2 of M2-2 claimed. Cost is
mechanical churn in the existing suites (`.install(Self.wget)` → `.install(PackageTarget(Self.wget)!)`);
accepted, because the alternative — a call-site fix plus a review convention — is discipline, not
construction.

### D10 — Cancel survives a detached or replaced runner (follow-up 2)

`OperationCenter.cancel(_:)` currently reads the centre's *current* `runner` and, when it is `nil`,
calls `finish(item, with: .cancelled)`. Two defects: a repointed brew makes it cancel on the wrong
runner, and a running operation is reported cancelled — **paying the gate early** — while the process
keeps going.

```swift
public func cancel(_ item: ActivityItem) {
    guard item.isCancellable else { return }
    item.isCancelRequested = true
    if let operation = item.operation { Task { await operation.cancel() }; return }  // its own runner
    // No handle yet: if a start is in flight, run(_:for:on:) replays the request
    // (it already guards at entry and after start). Only a submission that never
    // had a runner is terminal here — and the gate is paid exactly once, there.
    if !item.isStartInFlight { finish(item, with: .cancelled) }
}
```

The item holds the `BrewOperation` that its own runner produced (which is also what makes D6's release
rule work), so cancel is always delivered to the process that exists.

### D11 — Test-harness trap becomes a failed expectation (follow-up 5)

`OperationCenterHarness.finish(call:)` does `await launcher.waitForLaunches(atLeast: index + 1)` and
then indexes `launchedProcesses[index]`. `TestPoll.until` returns silently on timeout, so a timing
regression crashes the whole suite instead of failing one test. Fix: `#require` the process is present
(the harness gains `Testing`'s `sourceLocation` passthrough) so the failure names the test.

### D12 — File layout, all under the 400-line SwiftLint precedent

`Persistence`: `SchemaV1.swift` (models + versioned schema), `MetadataMigrationPlan.swift`,
`PersistenceContainer.swift` (on-disk + in-memory factories), `MetadataStore.swift`, `HistoryStore.swift`,
`SwiftDataHistoryRecorder.swift`. `BrewClient` gains `PackageMetadata.swift` (value + lookup + snooze
rule), `HistoryRecording.swift` (protocol + `HistoryDraft` + no-op), `BulkSelection.swift`.

## Data Flow

```
star / note / snooze
   View ──▶ MetadataStore.setFavorite(id:) ──▶ mainContext.insert/update ──▶ save()
                    │                                                         │
                    └──── republish MetadataSnapshot (value) ◀────────────────┘
                                     │
 InstalledBrowse.entries(includingDependencies:catalogLookup:metadata:) ──▶ [PackageEntry]
        favorites filter · snooze-aware isOutdated · BulkSelection      (pure, BrewClient)

mutation
   MutationMenu ──▶ OperationCenter.submit(cmd, versions:) ──▶ BrewRunner ──▶ brew
                              │                                      │
                              │◀──── lines, exit, fault ─────────────┘
                              ▼
                        finish(item, outcome)  ── exactly once ──▶ HistoryRecording.record(draft)
                              │                                          │
                          gate.end()                                     ▼
                                                              HistoryEntry (append-only)
```

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift` | Modify | `Persistence` target + product (deps `BrewClient`), `PersistenceTests` test target |
| `Sources/Persistence/SchemaV1.swift` | Create | `VersionedSchema` V1 + the three `public final class @Model`s (D2) |
| `Sources/Persistence/MetadataMigrationPlan.swift` | Create | `SchemaMigrationPlan`, one schema, zero stages (D2) |
| `Sources/Persistence/PersistenceContainer.swift` | Create | Container factories: on-disk (Application Support) and `isStoredInMemoryOnly` (D3, D4) |
| `Sources/Persistence/MetadataStore.swift` | Create | `@MainActor @Observable` favorites/notes/snooze store + availability (D3, D4) |
| `Sources/Persistence/HistoryStore.swift` | Create | Query projection, search, clear-all (D3, D7) |
| `Sources/Persistence/SwiftDataHistoryRecorder.swift` | Create | `HistoryRecording` conformance, draft → row (D1, D7) |
| `Sources/BrewClient/PackageMetadata.swift` | Create | `PackageMetadata`, `MetadataSnapshot`, lookup seam, snooze rule (D5) |
| `Sources/BrewClient/HistoryRecording.swift` | Create | Protocol, `HistoryDraft`, `VersionTransition`, no-op default (D7) |
| `Sources/BrewClient/BulkSelection.swift` | Create | Bulk-eligible derivations, `Action` (D8) |
| `Sources/BrewClient/InstalledFilterMode.swift` | Modify | `entries(…, metadata:)`, favorites filter, snooze-aware outdated, `upgradableIDs` (D5, D8) |
| `Sources/BrewClient/MutationCommand.swift` | Modify | `PackageTarget`; four cases retyped (D9) |
| `Sources/BrewClient/OperationCenter.swift` | Modify | `HistoryRecording` injection, `submit(_:versions:)`, `submitUpgrades(for:in:)`, multi-command confirmation, cancel fix (D7, D8, D10), `queuePhase` equality guard (D6) |
| `Sources/BrewClient/ActivityItem.swift` | Modify | Holds its `BrewOperation` while cancellable; `isStartInFlight` (D6, D10) |
| `Sources/BrewProcess/BrewOperation.swift` | Modify | `BrewOperation` → `final class` with releasing `deinit`; record compaction fields (D6) |
| `Sources/BrewProcess/BrewRunner.swift` | Modify | R1/R2/R3 retention, `release(_:)` (D6) |
| `Tests/BrewClientTests/Fakes/OperationCenterHarness.swift` | Modify | `#require` instead of an index-after-timeout (D11) |
| `cellar/Installed/*` | Modify + Create | Star toggle, favorites filter chip, multi-select bar, bulk uninstall confirmation |
| `cellar/Browse/PackageDetailView.swift` | Modify | Notes editor, star, snooze control; `PackageTarget` at the copy button (D9) |
| `cellar/History/HistoryView.swift`, `HistoryRow.swift` | Create | Searchable list, clear-history confirmation |
| `cellar/Shell/AppSection.swift`, `ContentView.swift`, `cellarApp.swift` | Modify | `.history` section, store ownership + injection (D3) |
| `cellar.xcodeproj/project.pbxproj` | Modify | One `XCSwiftPackageProductDependency` for `Persistence` (BrewClient precedent); synchronized groups need no edit for new folders |
| `openspec/changes/m2-mutations-installed/explore.md` | Modify | **Absorbed follow-up 11** — the six recorded doc corrections. Docs only, and it must land in this slice: the umbrella exploration is archived after M2-3, so this is the last change that can correct it |

## Interfaces / Contracts

```swift
// BrewClient — the whole surface Persistence has to satisfy
public struct PackageMetadata: Sendable, Hashable {
    public let isFavorite: Bool
    public let note: String
    public let snoozedVersion: String?
}
public typealias MetadataLookup = (PackageID) -> PackageMetadata?   // mirrors catalogLookup:

public struct HistoryDraft: Sendable {
    public let id: UUID, date: Date
    public let packageID: PackageID?           // nil ⇒ upgradeAll (persists as "")
    public let verb: String
    public let versions: VersionTransition?
    public let outcome: MutationOutcome
    public let argv: [String]
}
```

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Spike (phase 0) | The same proof, re-landed on the **real** `Persistence` target: in-memory `ModelConfiguration` + `SchemaV1` + migration plan, insert → save → fetch | Already green outside the repo (G1, `#7116`), so this is a confirmation task, not a risk gate; it still runs first because every later model task builds on it, and it answers G2/G3/G4 in place |
| Unit — Persistence | round-trip, upsert on the joint key, availability degradation, clear-all touches only history, history search + limit | In-memory container, one `PersistenceTests` target |
| Unit — BrewClient rules | snooze projection (equal / different / absent / unavailable store), favorites filter, `upgradableIDs` == the submitted set, bulk `Action` exhaustiveness, one draft per terminal outcome, `upgradeAll` grouped draft | Pure values + a `RecordingHistoryRecorder` fake |
| Unit — BrewProcess retention | R1 (running never compacted), R2 (`exit(of:)` and `fault(of:)` answer after compaction), R3 (record survives while a handle lives; removed after release), enumeration still terminal-stable | `ControllableProcessLauncher`, no real brew |
| Unit — cancel | cancel after `attach(installation: nil)` does not settle a running item early; cancel after repointing reaches the original runner; gate paid exactly once | Center harness |
| Unit — argv | `PackageTarget` refuses empty/`-`-prefixed names; the four retyped cases keep their exact argv | Existing `ArgumentCompositionTests` |
| Integration | none new — **no test mutates a real Homebrew** (M2-2 D12 stands) | — |
| E2E | untested by design: SwiftUI layout, FSEvents adapter | — |

## Threat Matrix

| Row | Applicability | Expected behaviour | RED test |
|---|---|---|---|
| Subprocess argument composition | **Applicable** — bulk fan-out and the retyped cases | argv only, explicit kind flag on every naming command, `PackageTarget` refuses unsafe names, no new argv shape | Exact `ProcessSpec.arguments` per bulk submission, in selection order; unsafe name yields no command |
| User free text reaching a command vector | **Applicable (new)** — notes are the first user-authored persisted strings | A note is stored and rendered verbatim and can reach **no** argv; argv comes only from `MutationCommand` | Note containing `; rm -rf /` and `--force` changes no `ProcessSpec`, survives round-trip byte-identical |
| Persisted argv is display-only | **Applicable (new)** — `HistoryEntry.argv` | One-way, exactly like `displayCommand`: nothing reconstructs a `MutationCommand` from a history row; the view offers copy only | No API accepts a `HistoryEntry` and returns a command; copy text equals `commandText` |
| Irreversible mutation scope | **Applicable** — bulk uninstall | Confirmation names every selected package with its exact command; pin/unpin/snooze have no bulk path | Confirmation lists N commands for N selections; `BulkSelection.Action` has exactly two cases |
| Untrusted payload as classification input | **Applicable (unchanged)** — outcome now also persists | Classification is still the pure M2-2 function over the last 20 stderr lines; the persisted `outcomeRaw` is derived from it, never from raw output | `Password:` in package output persists as the same outcome M2-2 asserts |
| Filesystem write surface | **Applicable (new)** — the store file | Unwritable/corrupt store ⇒ `.unavailable`, disabled affordances, no crash, no data loss elsewhere | Container failure yields empty snapshot, no-op writes, and a rendered reason |
| Privilege boundary | N/A — no change to stdin, no escalation path |  |  |
| VCS/PR automation, executable-file classification | N/A — none in this change |  |  |

## Migration / Rollout

V1 is genesis: there is nothing to migrate *from*, and `SchemaMigrationPlan` exists only so M4/M6 are
`.lightweight` stages. No feature flag. Rollback = revert the branch and delete
`Application Support/<bundleID>/Metadata/`; `HistoryRecording`'s no-op default returns `OperationCenter`
to M2-2 behaviour and nothing else in the app depends on `Persistence`.

## Open Gates

**G1 is CLOSED GREEN — the load-bearing risk of this slice is retired before apply.** The orchestrator
ran the probe on 2026-08-02 (Engram `#7116`): a throwaway SPM package (`swift-tools-version: 6.0`,
`platforms: [.macOS("26.0")]`, `.swiftLanguageMode(.v6)`) exercising an in-memory `ModelContainer` built
from `Schema(versionedSchema:)` **with a migration plan**, one `@Model`, an `@ModelActor` with an
explicit `save()`, a `#Predicate` fetch, and a `PersistentIdentifier` crossing the actor boundary —
**one green test in 0.009 s under headless `swift test`**. Placement A is confirmed empirically, not
assumed. The explore §5 option C Codable store is therefore no longer a plan of record; it survives
only as the historical fallback the proposal named.

| Gate | Question | Status |
|---|---|---|
| **G1** | SwiftData headless in `swift test` with an in-memory `ModelConfiguration` | **CLOSED GREEN** — probed 2026-08-02, 0.009 s, including `@ModelActor` + explicit `save()` + `#Predicate` + `PersistentIdentifier` across the boundary (`#7116`) |
| **G2** | Does `#Unique` compile and upsert (rather than throw) on this toolchain? | **Open, non-blocking, additive.** Fallback: drop `#Unique`; the store API's fetch-or-create is then the only enforcement. Fold the check into the first `PersistenceTests` task |
| **G3** | Can a container be created **on disk** with no app bundle present? | **Open, non-blocking.** Fallback: on-disk coverage moves to the app-target suite (`xcodebuild -only-testing:cellarTests`); package tests stay in-memory |
| **G4** | `@MainActor @Observable` holding a `ModelContainer` under `.swiftLanguageMode(.v6)` in a `nonisolated`-default target | **Effectively closed by the G1 probe** — the probe compiled a `@ModelActor` and a main-actor holder clean in language mode v6. Confirm on the real target; fallback is a small `Sendable` wrapper |
| **G5** | "Strictly newer" (proposal criterion) vs "different from the snoozed version" (D5) | **RESOLVED 2026-08-02** — user ruled **inequality** (Engram `#7117`). D5 stands unchanged; the spec blocks are being rewritten to equality-based suppression and the proposal's wording is superseded |

**No new brew gate.** Bulk operations reuse the M2-2 fan-out and produce no argv shape that was not
already probed on brew 6.0.14 (`#7097`, plus the `pin/unpin --formula` amendment). Stated explicitly so
its absence is a decision, not an oversight.

## Review Budget Forecast

~4.0k–5.4k authored lines (proposal estimate) against the 800-line configured budget, with
`size:exception` already accepted for `single-pr`. Clean cut if the exception is withdrawn: D6 + D10 +
D11 + D9 (retention, cancel, harness, `PackageTarget`) form an independently shippable ~900-line PR #1
that ships no persistence at all; D1–D5 + D7 + D8 + UI as PR #2.
