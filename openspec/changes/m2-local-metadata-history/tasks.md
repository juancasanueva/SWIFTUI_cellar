# Tasks: M2-3 — Local Metadata & History

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 4,000–5,400 authored (phase sums ≈ 4,680; proposal/design forecast 4.0k–5.4k) |
| Default review budget | 400 lines |
| Repo `review_budget_lines` (`openspec/config.yaml`) | 800 lines |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR under the **pre-accepted** `size:exception`; **Phases 1 + 2 + 3** (D6 + D9 + D10 + D11, ≈ 790 lines, zero persistence) are the pre-agreed cut point |
| Delivery strategy | single-pr with a user-ACCEPTED `size:exception` (effective `exception-ok`) |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

**Honest reading, for the orchestrator.** ≈ 5.9× the repo's own `review_budget_lines: 800` and ≈ 12×
the default 400. The `size:exception` was accepted by the user **before** this breakdown was written,
so apply is not blocked and no decision is owed — the number is stated plainly rather than absorbed.

Calibration. M2-2 forecast 4,000–5,000 and landed **4,538** (inside the band) after M2-1 had overrun
1.8×. That accuracy came from pricing tests at **1.2× production** instead of the 0.58× M2-1 assumed;
the same multiplier is applied here to a ≈ 2,130-line non-UI production estimate. Two residuals are
unpriced: (a) `Persistence` is a **new target with a new framework** — SwiftData test scaffolding has
no in-repo precedent to calibrate against, and G1's probe measured feasibility, not volume; (b) D9's
`PackageTarget` retype is 40–60 mechanical edits whose exact count is unknown until the compiler says
so. Treat 5,400 as likely, not as the tail.

Line counts below exclude `openspec/` artifacts. Generated goldens: none in this change.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | `Persistence` target skeleton + headless SwiftData confirmation, G2/G3/G4 answered (Phase 0) | PR 1 | `FAST --filter PersistenceSpike` | N/A — no app surface exists yet; the target is not linked into `cellar` until Phase 8 | Revert the `Package.swift` hunk and delete `Sources/Persistence/` + `Tests/PersistenceTests/`; no shipped file is touched |
| 2 | Runner-record retention + `queuePhase` equality guard (Phase 1) | PR 1 (**or PR 1 if cut**) | `FAST --filter "Retention\|QueueProjection\|Serialization"` | With the app running: submit ~10 mutations/reads, confirm memory does not climb per operation and `exit(of:)` still answers a held handle | Revert the `BrewOperation.swift`/`BrewRunner.swift`/`ActivityItem.swift` hunks; retention is purely additive to M2-2 behaviour |
| 3 | `PackageTarget` — validation with no bypass (Phase 2) | PR 1 (**or PR 1 if cut**) | `FAST --filter "MutationCommand\|ArgumentComposition"` | N/A — pure type-level construction, no process and no I/O | Revert `MutationCommand.swift` and the mechanical `.install(x)` → `.install(PackageTarget(x)!)` edits; argv is unchanged either side |
| 4 | Cancel-after-detach + harness `#require` (Phase 3) | PR 1 (**or PR 1 if cut**) | `FAST --filter "OperationCenter\|Cancel"` | Repoint brew while a mutation runs, then cancel → the process actually stops and the gate opens only at the real terminal | Revert the `OperationCenter.cancel`/`ActivityItem` hunks and the harness hunk; M2-2 cancel semantics return |
| 5 | SwiftData schema, stores, availability degradation (Phase 4) | PR 1 (**or PR 2 if cut**) | `FAST --filter "Schema\|MetadataStore\|HistoryStore"` | Launch the app with `Application Support/<bundleID>/Metadata/` made read-only → affordances disabled with a reason, browse and mutate still work | Delete `Sources/Persistence/*.swift` and `Tests/PersistenceTests/`; nothing outside `Persistence` references them yet |
| 6 | `BrewClient` metadata, snooze, bulk and history seams (Phase 5) | PR 1 (**or PR 2 if cut**) | `FAST --filter "PackageMetadata\|Snooze\|BulkSelection\|InstalledFilter"` | N/A — pure functions over values; the runtime boundary appears at Unit 8 | Delete `Sources/BrewClient/{PackageMetadata,HistoryRecording,BulkSelection}.swift` and revert the `InstalledFilterMode` hunk; `metadata:` defaults to nil so callers compile unchanged |
| 7 | History at the terminal funnel + bulk fan-out + SwiftData recorder (Phases 6–7) | PR 1 (**or PR 2 if cut**) | `FAST --filter "OperationCenter\|HistoryRecorder\|BulkFanOut"` | Uninstall two selected packages from Cellar → two queue items in selection order, two history rows, one confirmation naming both | Revert the `OperationCenter` hunk and delete `SwiftDataHistoryRecorder.swift`; `NoHistoryRecording` restores M2-2 behaviour exactly |
| 8 | Favorites, notes, snooze, multi-select and History UI (Phase 8) | PR 1 (**or PR 2 if cut**) | `FULL` | Star a package, write a note, snooze an outdated one, relaunch → all three survive; History section lists, searches and clears | Revert `cellar/History/**`, the `Installed`/`Browse`/`Shell` hunks and the `project.pbxproj` product dependency |

If cut, PR 1 = Units 2–4 (Phases 1–3, ≈ 790 lines, ships **no persistence at all**); PR 2 = Units 1,
5–8, base = PR 1 branch (feature-branch-chain). This is a clean prefix: Phases 1–3 close four M2-2
follow-ups and touch no file Phases 4–8 create.

### Legend

- Requirement tags: `LPM1..LPM7` (local-package-metadata ADDED, delta order), `IH1..IH7`
  (installation-history ADDED, delta order), `II8` (installed-inventory MODIFIED — filter
  composition), `II12`/`II13`/`II14` (installed-inventory ADDED — snooze exclusion, multi-select,
  label-counts-set), `PM3` (package-mutation MODIFIED — confirmation gate), `PM8`/`PM9`
  (package-mutation ADDED — bulk fan-out, no-bypass construction), `OA1`/`OA4` (operation-activity
  MODIFIED — enumeration, cancel), `OA6` (operation-activity ADDED — one history entry per terminal),
  `BE1` (brew-execution MODIFIED — serialized mutations).
- Design decisions are `D1..D12`; M2-2 decisions are cited as `M2-2 D7`.
- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `openspec/` or `cellar.xcodeproj/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests`.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No
  production line without a red test. Phase 8 (app-target SwiftUI) is xcodebuild-only and sits
  outside the `FAST` inner loop — which is exactly why every rule it needs is a pure function or a
  computed property in `BrewClient` (D3, D5, D8).
- SwiftLint `file_length` warns at 400 and `type_body_length` errors; M2-2 had to split five files
  after the fact. Check `OperationCenter.swift` (313 today) and `InstalledFilterMode.swift` before
  each phase's verify step, not at Phase 9.
- **No test mutates a real Homebrew and no test spawns `brew`** (M2-2 D12 stands). Every runner
  behaviour goes through `FakeProcessLauncher`; every store test uses
  `ModelConfiguration(isStoredInMemoryOnly: true)`.
- **Commit boundaries** (work-unit-commits): one commit per work unit above, tests included with the
  behaviour they verify. Phase 1's `ActivityItem` hunk and Phase 3's `ActivityItem` hunk are
  **separate commits** — one is D6 handle ownership, the other is D10 cancel — so each reviews on its
  own terms.
- **Sequencing.** Phases run in order; tasks inside a phase are sequential (RED strictly before its
  GREEN). Two independent tracks exist after Phase 0: **track A** = Phases 1 → 3 (`BrewProcess` +
  cancel), **track B** = Phase 2 (`MutationCommand`) then Phase 4 (`Persistence`). Phase 5 needs
  Phase 2; Phase 6 joins A and B; Phase 7 needs 4 + 6; Phase 8 needs 5 + 7; Phase 9 needs everything.
  **Do not run parallel writers in separate worktrees** — tracks A and B both edit
  `ActivityItem.swift` and `OperationCenter.swift` from Phase 3 onward.

---

## Phase 0: Baseline and the `Persistence` target (D2, D3, D12 — gates G2/G3/G4) — ≈ 180 lines

Scheduled first because every later model task builds on it. G1 is already **closed green** by the
orchestrator's live probe (Engram `#7116`), so this is a **confirmation on the real target**, not a
risk gate — but it still runs first, and it is where G2/G3/G4 are answered in place.

- [x] 0.1 Record the green baseline on `main` @ `8c9bc2a`: `FAST`, `FULL`, `swiftlint`. Capture the
  `@Test` / suite counts (M2-2 ended at 432 / 56) so Phase 9 can prove nothing was deleted, and the
  source-file `swiftlint` finding count (33 on `main`) so new findings are separable.
- [x] 0.2 `Package.swift`: add `.target(name: "Persistence", dependencies: ["BrewClient"],
  swiftSettings: [.swiftLanguageMode(.v6)])`, the matching `.library` product, and
  `.testTarget(name: "PersistenceTests", dependencies: ["Persistence", "CellarTestSupport"])`.
  `Persistence` is the **outermost** node — assert in 9.3 that nothing depends back on it.
- [x] 0.3 RED `Tests/PersistenceTests/PersistenceSpikeTests.swift` — the `#7116` probe re-landed on
  the real target: an in-memory `ModelContainer(for:migrationPlan:configurations:)` built from
  `Schema(versionedSchema: SchemaV1.self)` with `MetadataMigrationPlan`, one insert, an explicit
  `save()`, and a `#Predicate` fetch on a stored `String` key. **G4** rides here: the test holds the
  container from a `@MainActor` context in a `nonisolated`-default target.
- [x] 0.4 RED, same file — **G2**: two inserts sharing the same `#Unique([\.kindRaw, \.name])` key
  **upsert** rather than throw, leaving exactly one row. If it throws on this toolchain, record the
  fallback in the file header (drop `#Unique`; the store API's fetch-or-create becomes the only
  enforcement) and re-point Phase 4's upsert tasks at it.
- [x] 0.5 RED, same file — **G3**: a container created **on disk** under a temporary directory with
  no app bundle present opens, writes and reopens. If it fails, record the fallback (on-disk coverage
  moves to `xcodebuild -only-testing:cellarTests`; package tests stay in-memory) and mark LPM1 sc1 /
  IH1 sc4 as app-target-verified in Phase 8 instead.
- [x] 0.6 GREEN `Sources/Persistence/SchemaV1.swift` (minimal: `enum SchemaV1: VersionedSchema` and
  one placeholder `@Model`) and `Sources/Persistence/MetadataMigrationPlan.swift` (`schemas:
  [SchemaV1.self]`, `stages: []`) — just enough to turn 0.3–0.5 green. The three real models land in
  Phase 4. Verify: `FAST --filter PersistenceSpike`; record each gate's verdict verbatim.

## Phase 1: Runner-record retention and the phase guard (D6 — BE1, OA1) — ≈ 320 lines — **hard prerequisite for history**

Absorbed follow-up 4. Lands before any history write depends on it (proposal Dependencies).

- [x] 1.1 RED `Tests/BrewProcessTests/RetentionTests.swift` (BE1 sc7) with `FakeProcessLauncher`:
  after N operations have each reached a terminal outcome **and** had their results drained, the
  number of records the runner holds is bounded rather than growing with N.
- [x] 1.2 RED `RetentionTests` (**R1** — BE1 sc9): with one running operation, one pending operation
  and several drained terminal ones, retirement leaves the running and pending operations enumerated
  in their original order, and spawns, cancels or restarts nothing.
- [x] 1.3 RED `RetentionTests` (**R2** — BE1 sc8): a terminal operation whose result has **not** been
  awaited is still answered by `exit(of:)`, and `fault(of:)` still answers, after its `process`,
  `pump`, `completion`, `continuation` and `lines` have been released.
- [x] 1.4 RED `RetentionTests` (**R3** — release by ownership): a record survives while a
  `BrewOperation` handle is alive and is removed only after that handle is released; a retired
  operation is never reported pending or running and is never re-spawned, re-queued or resurrected.
  Also assert the 200-cap over already-released compacted records, oldest ordinal first.
- [x] 1.5 GREEN `Sources/BrewProcess/BrewOperation.swift`: `BrewOperation` becomes a `final class`
  with all stored properties immutable and `Sendable` (so the type stays `Sendable`) whose `deinit`
  hands its id back to the runner. This is what makes "a record can only be removed when no caller
  can still ask about it" **structural, not probabilistic**.
- [x] 1.6 GREEN `Sources/BrewProcess/BrewRunner.swift`: R1/R2/R3 as three ordered rules plus
  `release(_:)`. Rejected alternatives are recorded in the file header — an explicit `retire(id)`
  call (correctness would depend on every consumer remembering it) and a plain LRU on terminal
  records (evicts by count, the exact timing bet the constraint forbids).
- [x] 1.7 RED `Tests/BrewProcessTests/QueueProjectionTests.swift` (BE1 sc10 — follow-up 4b): an
  observer of the runner's queue phase sees **one** change for the transition into a phase and none
  for repeated yields of the same value.
- [x] 1.8 RED `Tests/BrewClientTests/OperationCenterProjectionTests.swift` (OA1 sc5): a terminal,
  fully drained operation whose execution-layer record has been **retired** is still listed by the
  centre with its identity, its argv and its terminal outcome. This makes M2-2's incidental tolerance
  in `apply(_:)` load-bearing and tested.
- [x] 1.9 GREEN `Sources/BrewClient/{OperationCenter,ActivityItem}.swift`: `apply(_:)` guards the
  write with `if item.queuePhase != phase { item.queuePhase = phase }` (`OperationSnapshot.Phase` is
  already `Equatable`), and `ActivityItem` holds its own `BrewOperation` **exactly while it is
  cancellable**, dropping it in `settle(_:)` — the release rule D6 depends on.
  Verify: `FAST --filter "Retention\|QueueProjection\|OperationCenterProjection"`.

## Phase 2: `PackageTarget` — validation with no bypass (D9 — PM9) — ≈ 240 lines

Absorbed follow-up 3. Lands before history, because `HistoryDraft` carries the verb and argv these
cases produce. 40–60 mechanical test edits are expected and accepted.

- [x] 2.1 RED `Tests/BrewClientTests/MutationCommandTests.swift` (PM9 sc1–2) — **threat: subprocess
  argument composition (option injection)**: `PackageTarget(_:)` returns `nil` for a name that is
  empty, whitespace-only, or begins with `-` (`--force`), so **no argv containing it is produced or
  spawned** and nothing is enqueued.
- [x] 2.2 RED `MutationCommandTests` (PM9 sc3) — enumerate every public way to obtain a
  `MutationCommand`: each one applies the same identity validation, and no alternate constructor,
  initializer or convenience overload produces a command from an unvalidated `PackageID`.
- [x] 2.3 RED `MutationCommandTests` — the four retyped cases keep their **exact** argv:
  `install --formula wget`, `uninstall --cask iterm2`, `reinstall --formula git`,
  `upgrade --formula wget`. Retyping is a compile-time change with **zero** argv consequence.
- [x] 2.4 GREEN `Sources/BrewClient/MutationCommand.swift`: `public struct PackageTarget: Sendable,
  Hashable` with `init?(_ id: PackageID)` guarding on `MutationName.isSafe`; `install`, `uninstall`,
  `reinstall`, `upgrade` retyped from `PackageID` to `PackageTarget`. `FormulaID`/`CaskID` are
  re-expressed over it so `isSafe` has **one** definition. `naming(_:_:)` keeps its signature and its
  callers — the guard is now enforced by the type, not by remembering to use it.
- [x] 2.5 Mechanical churn: update every existing use site
  (`.install(Self.wget)` → `.install(PackageTarget(Self.wget)!)`) across `MutationCommandTests`,
  `OperationCenterTests`, `OperationCenterProjectionTests`, `ClassificationTests` and
  `Tests/BrewProcessTests/ArgumentCompositionTests.swift`. Verify the `@Test` count is unchanged.
- [x] 2.6 Close the two known bypasses the retype now makes compile errors:
  `cellar/Activity/MutationMenu.swift:27` (`.install(entry.id)`) and
  `cellar/Browse/PackageDetailView.swift:69` (`MutationCommand.install(package.id).displayCommand`).
  Both become `PackageTarget`-mediated; an unvalidated command is unrepresentable.
  Verify: `FAST --filter "MutationCommand\|ArgumentComposition"` then `xcodebuild build`.

## Phase 3: Cancel survives a detached runner, and the harness stops trapping (D10, D11 — OA4) — ≈ 230 lines

Absorbed follow-ups 2 and 5. Bulk multi-select (Phase 6) multiplies the exposure, so this precedes it.

- [x] 3.1 RED `Tests/BrewClientTests/OperationCenterTests.swift` (OA4 sc4): a running mutation whose
  queue has been detached (`attach(installation: nil)`) is, on cancel, **signalled through the
  ordinary cancellation escalation** and reported cancelled **only once the process has stopped** —
  not settled immediately.
- [x] 3.2 RED `OperationCenterTests` (OA4 sc5): with the same detached running mutation and another
  pending behind it, cancelling before the process stops starts **nothing** and forces **no**
  inventory re-snapshot; both happen exactly once when the real terminal outcome arrives. The gate is
  paid exactly once.
- [x] 3.3 RED `OperationCenterTests`: repointing brew mid-flight and then cancelling reaches the
  **original** runner — the one that produced the item's `BrewOperation` — not the centre's current
  one.
- [x] 3.4 GREEN `Sources/BrewClient/{OperationCenter,ActivityItem}.swift` (D10): `cancel(_:)` sets
  `isCancelRequested`, delivers to `item.operation` when it exists, and otherwise finishes as
  cancelled **only** when `!item.isStartInFlight` — a start in flight is replayed by `run(_:for:on:)`,
  which already guards at entry and after start. Keep this hunk in a **separate commit** from 1.9.
- [x] 3.5 RED `Tests/BrewClientTests/Fakes/OperationCenterHarness.swift` (D11): drive
  `finish(call:)` past a poll timeout and assert the harness reports a **named failed expectation**
  rather than crashing the whole suite by indexing `launchedProcesses[index]`.
- [x] 3.6 GREEN the harness: `try #require(...)` the process is present, with `Testing`'s
  `sourceLocation` passed through so the failure names the calling test.
  Verify: `FAST --filter "OperationCenter\|Cancellation"`.

## Phase 4: `Persistence` — schema, stores, degradation (D2, D3, D4 — LPM1–LPM4, LPM6, LPM7, IH4–IH6) — ≈ 1,150 lines

- [x] 4.1 RED `Tests/PersistenceTests/SchemaTests.swift` (LPM1 sc1–3): a favorite, a note and a
  snooze recorded for the **formula** `wget` are readable after the store is closed and reopened
  against the same location; the **cask** `docker` and the **formula** `docker` are different keys;
  metadata for a package absent from the inventory is unchanged and still readable.
- [x] 4.2 GREEN `Sources/Persistence/SchemaV1.swift`: the three `public final class @Model`s —
  `PackageMeta`, `Snooze`, `HistoryEntry` — with the exact stored shapes from D2. `PackageKind`
  persists as `kindRaw: String`; **absence is `""`, never `Optional`**; `MutationOutcome` persists as
  `outcomeRaw` + `exitStatus`; `commandText` is the deliberate denormalisation of
  `argv.joined(separator: " ")`. **No `@Relationship` and no `@Transient` anywhere in V1** — record
  the reasons (history must survive both an uninstall and a metadata delete) in the file header.
- [x] 4.3 RED `Tests/PersistenceTests/MetadataStoreTests.swift` (LPM2 sc1, sc3): the favorite flag
  round-trips (mark → read → unmark → read); a package for which nothing was ever stored reports
  **not favorite** and throws nothing.
- [x] 4.4 RED `MetadataStoreTests` (LPM2 sc2): with a recording process launcher in scope, marking
  and unmarking favorite records **no brew invocation** and submits **no operation** to the queue.
- [x] 4.5 RED `MetadataStoreTests` (LPM3 sc1–2) — **threat: user free text reaching a command
  vector.** A note containing `line one\n\n  # not a heading  \nline two`, and separately one
  containing `; rm -rf /` and `--force`, is stored and returned **byte-identical** with no markup
  interpreted or stripped, no length cap applied, and **changes no `ProcessSpec`** — assert no argv
  anywhere in the recorded launches contains any fragment of the note text. Setting a note to `""`
  reports no note.
- [x] 4.6 RED `MetadataStoreTests` (LPM4 sc1–3): snoozing stores the exact offered version `1.2.3`
  and nothing else; the stored fields carry **no duration, no expiry and no timestamp that governs
  when the snooze ends**; re-snoozing at `1.3.0` leaves exactly one snooze, naming `1.3.0`.
  Unsnoozing removes it entirely.
- [x] 4.7 GREEN `Sources/Persistence/MetadataStore.swift`: `@MainActor @Observable public final
  class` over the container's `mainContext`, on the shipped `InstalledStore` exemplar. Fetch-or-create
  upsert on the joint key; **writes `save()` explicitly** rather than relying on autosave, and the
  `MetadataSnapshot` value is republished from the store after each save. No `@Query`, no
  `.modelContainer(…)` modifier, no `@ModelActor`.
- [x] 4.8 RED `MetadataStoreTests` (LPM6 sc2) — **threat: filesystem write surface**: a container
  that fails to open yields `availability == .unavailable(reason)`, an **empty** snapshot, **no-op**
  writes that throw nothing, and a reason string available for rendering. Nothing else in the app is
  affected.
- [x] 4.9 GREEN `Sources/Persistence/PersistenceContainer.swift`: on-disk factory at
  `Application Support/<bundleID>/Metadata/Metadata.store` (the `CatalogStore.defaultDirectory()`
  precedent) and an `isStoredInMemoryOnly` factory. Container creation `throw`s are **caught and
  folded** into `.unavailable(reason)` — a `try!` at launch would turn a recoverable disk problem
  into a boot loop (D4).
- [x] 4.10 RED `Tests/PersistenceTests/HistoryStoreTests.swift` (IH5 sc1–4): three entries read with
  an empty search return **all three, newest first**; searching `WGET` returns only the `wget` entry
  (case-insensitive over name, verb and argv); searching `uninstall` returns only the uninstall entry;
  a term matching nothing returns empty and a later empty search still returns all three.
- [x] 4.11 GREEN `Sources/Persistence/HistoryStore.swift`: `FetchDescriptor` with a `#Predicate` over
  `name`/`verb`/`commandText` and `SortDescriptor(\.date, order: .reverse)`, and **no `fetchLimit`** —
  keep-all retention (IH4) means an empty search MUST return every entry, and truncating the view
  would quietly contradict the retention promise. Pagination stays an additive future change.
- [x] 4.12 RED `HistoryStoreTests` (IH4 sc1–2): a large number of appended entries across several
  sessions are all still present, none removed by age or by count; an uninstall of `wget` after an
  install of `wget` produces **two** entries with the first one's fields unchanged.
- [x] 4.13 RED `HistoryStoreTests` (IH6 sc1, sc3–4): a confirmed clear empties the history; every
  favorite, note and snooze is **still readable with its original value** afterwards; and the
  projection exposes **no per-entry delete or remove control**.
- [x] 4.14 GREEN `HistoryStore.clearAll()`: `try context.delete(model: HistoryEntry.self)` and
  nothing else — it touches no other model. No selective or per-entry deletion exists (settled R3).
- [x] 4.15 RED/GREEN `Tests/PersistenceTests/MigrationTests.swift` (LPM7 sc1–2): the stored
  configuration and public surface declare **no sync, cloud or remote destination** and make no
  network request; and a store written at V1 holding a favorite, a note and a snooze is still
  readable with its original values when opened by a schema version that adds a field (exercise
  `MetadataMigrationPlan` with a throwaway V2 carrying one additional optional property, proving the
  stage is `.lightweight`).
  Verify: `FAST --filter "Schema\|MetadataStore\|HistoryStore\|Migration"`.

## Phase 5: `BrewClient` value seams and pure rules (D5, D7, D8 — LPM5, LPM6, II8, II12, II13, II14) — ≈ 800 lines

Every rule here is a pure function over values, testable in the `FAST` loop with no SwiftData in
sight. This is what keeps Phase 8's views rule-free.

- [ ] 5.1 RED `Tests/BrewClientTests/SnoozeProjectionTests.swift` (LPM5 sc1–2): a package snoozed at
  `1.2.3` and still outdated toward `1.2.3` shows **no** badge; when the offered version becomes
  `1.3.0` the badge is shown again, **with no user action** required to clear the snooze.
- [ ] 5.2 RED `SnoozeProjectionTests` (LPM5 sc3 — the G5 ruling, Engram `#7117`): an offered
  `1.2.3_1` **and separately an older `1.2.2`** each revive the badge — the accepted, visible false
  positive of an equality rule — and assert structurally that **no ordering comparison of version
  strings was performed** to reach either result. No comparator exists in this capability.
- [ ] 5.3 RED `SnoozeProjectionTests` (LPM5 sc4–5): removing the snooze shows the badge on the next
  read with **no inventory refresh required**; a snoozed, outdated package is still listed with its
  installed version under default filters.
- [ ] 5.4 GREEN `Sources/BrewClient/PackageMetadata.swift`: `PackageMetadata` (`isFavorite`, `note`,
  `snoozedVersion`), `MetadataSnapshot = [PackageID: PackageMetadata]`, `MetadataLookup` mirroring the
  existing `catalogLookup:`, and `func isSnoozed(offering:snoozedVersion:) -> Bool { snoozedVersion
  == candidate }`. Record the D5 rejection in the header: an ordering comparator's failure mode is
  **silent suppression of a real update**, the one outcome this feature must never produce.
- [ ] 5.5 RED `Tests/BrewClientTests/InstalledFilterTests.swift` (II8 sc8–10): the favorites filter
  narrows the list to `wget`; it **composes** with the outdated filter rather than replacing it
  (leaving only the outdated favorite); with no metadata it renders **disabled** and the results are
  identical to the same query with no favorites filtering.
- [ ] 5.6 RED `InstalledFilterTests` (II8 sc5 + LPM3 sc3): the catalog query's declared filter set
  contains **no** installed, not-installed, outdated **or favorite** predicate; and a package named
  `wget` whose note contains `zeppelin`, with nothing else matching, returns **no results** when the
  Installed list is searched for `zeppelin` — note text enters no search index.
- [ ] 5.7 RED `Tests/BrewClientTests/SnoozeProjectionTests.swift` (II12 sc1–4): a snoozed outdated
  formula is absent from the outdated **set** and the **count** is 1; a changed offered version
  (`1.3.0`, and separately `1.2.3_1`) returns it to both without user action; the outdated **browse
  filter** agrees with the outdated list exactly; and the snooze never hides the package from the
  Installed list.
- [ ] 5.8 GREEN `Sources/BrewClient/InstalledFilterMode.swift`: `entries(…, metadata:)` and
  `rows(…, metadata:)` take an optional `MetadataLookup`; the favorites filter is answered by
  intersecting with the favorite membership set on **exactly** the terms the installed-state filters
  already use; snooze-aware outdated is a **projection** over (inventory outdated state × stored
  snooze), never a mutation of the inventory's own derivation — so a cold, empty or unavailable store
  degrades to today's behaviour with no branch (LPM6 sc1).
- [ ] 5.9 RED `Tests/BrewClientTests/BulkSelectionTests.swift` (II13 sc1–3): selecting `wget`, then
  `iterm2`, then `git` reports the selection in **that order**; deselecting the second leaves the
  other two in their original relative order; a package that leaves the inventory leaves the selection
  at the next refresh.
- [ ] 5.10 RED `BulkSelectionTests` (II13 sc4–5) — **threat: irreversible mutation scope**:
  `BulkSelection.Action` is `CaseIterable` with **exactly two** cases, `.upgrade` and `.uninstall`, so
  the absence of a bulk pin, unpin, snooze, favorite or note affordance is a **test assertion**, not a
  convention; and an empty selection reports every bulk control unavailable rather than inert.
- [ ] 5.11 RED `BulkSelectionTests` (II14 sc1–3 — absorbed follow-up 1): the announced count equals
  the number of operations submitted under the default filters; toggling the dependency filter moves
  both together; and with three outdated packages, one snoozed, the announced count is **2** and
  exactly two operations are submitted, **neither naming the snoozed package**.
- [ ] 5.12 GREEN `Sources/BrewClient/BulkSelection.swift`: `init(selection: [PackageID], entries:
  [PackageEntry])` producing `upgradable` (selected ∧ outdated ∧ !pinned ∧ !snoozed) and
  `uninstallable` (selected ∧ installed), both **in selection order**, plus `Action`. Add
  `InstalledBrowse.upgradableIDs` as the **one** projection the label, the outdated section, the
  outdated count, the badge and the submission all read — which is what makes agreement structural
  rather than four filters happening to concur.
- [ ] 5.13 RED `Tests/BrewClientTests/HistoryRecordingTests.swift`: `NoHistoryRecording` accepts a
  draft and does nothing; `HistoryDraft` carries `packageID: PackageID?` (nil ⇒ `upgradeAll`), verb,
  `VersionTransition?`, `MutationOutcome` and argv; the protocol is `@MainActor`, **synchronous and
  non-throwing** so a failed write can never change a mutation's outcome.
- [ ] 5.14 GREEN `Sources/BrewClient/HistoryRecording.swift`: the protocol, `HistoryDraft`,
  `VersionTransition(from:to:)` and the `NoHistoryRecording` default.
  Verify: `FAST --filter "SnoozeProjection\|InstalledFilter\|BulkSelection\|HistoryRecording"`.

## Phase 6: `OperationCenter` — history funnel, bulk fan-out, one derived set (D7, D8 — OA6, PM3, PM8, IH1–IH2, IH7, II14) — ≈ 650 lines

- [ ] 6.1 RED `Tests/BrewClientTests/OperationCenterHistoryTests.swift` (OA6 sc1–2; IH1 sc1–2): an
  install for the cask `iterm2` exiting 0 submits **exactly one** draft carrying the cask identity,
  the install verb, the successful outcome and the argv `install --cask iterm2`; a mutation exiting
  non-zero, one ending in the typed **busy** failure and one **cancelled** while running each submit
  exactly one draft **naming its own outcome**, not a generic one.
- [ ] 6.2 RED `OperationCenterHistoryTests` (OA6 sc3; IH1 sc3): a pending mutation and a running
  mutation each have **no** draft submitted; nothing is written before the terminal outcome.
- [ ] 6.3 RED `OperationCenterHistoryTests` (OA6 sc4; IH7 sc1–2): with **no** recorder configured,
  and separately with a recorder that **fails on every write**, the operation's reported outcome and
  log are identical to a working-recorder run, **exactly one** inventory re-snapshot is forced, and
  nothing is thrown into the operation's path.
- [ ] 6.4 GREEN `Sources/BrewClient/OperationCenter.swift`: a `HistoryRecording` injection defaulting
  to `NoHistoryRecording`, with `record(_:)` called from `finish(_:with:)` — already the single,
  idempotent terminal funnel that pays the gate exactly once, which makes "exactly one entry per
  terminal outcome" true **by construction** rather than by discipline.
- [ ] 6.5 RED `OperationCenterHistoryTests` (IH1 argv/versions; IH2 sc1): `submit(_:versions:)`
  records the transition Cellar **intended at submission** (`installedVersion` → `catalogVersion`),
  never one observed after; and `upgradeAll` writes **one grouped entry** with `name == ""`, no
  versions, verb `upgradeAll`, argv `["upgrade"]` — with **no** inventory-snapshot diffing anywhere.
- [ ] 6.6 GREEN `submit(_:versions:)` and `submitUpgrades(for:in:)` deriving `VersionTransition` from
  the inventory they are already handed. Record the rejected alternative: diffing an inventory
  snapshot either side needs a re-snapshot to land before the write, makes the entry depend on watcher
  timing, and is exactly the per-package attribution settled decision R1 declines.
- [ ] 6.7 RED `Tests/BrewClientTests/BulkFanOutTests.swift` (PM8 sc1; IH2 sc2) — **threat: subprocess
  argument composition**: a confirmed bulk uninstall over formulae `wget`, `git` and cask `iterm2`,
  **in that order**, enqueues exactly three operations with argvs `uninstall --formula wget`,
  `uninstall --formula git`, `uninstall --cask iterm2` in that order; **no argv names more than one
  package**; and exactly three history drafts result, one naming each package.
- [ ] 6.8 RED `BulkFanOutTests` (PM8 sc2–4): a mid-batch non-zero exit attributes to the **second
  package only** and the third still runs; cancelling the second of three leaves the first running and
  the third queued; and asking the mutation surface to build **pin, unpin or reinstall** for a
  selection yields no such bulk mutation.
- [ ] 6.9 RED `BulkFanOutTests` (PM3 sc5–6) — **threat: irreversible mutation scope**: a bulk
  uninstall over three packages requests **exactly one** confirmation before anything is submitted,
  and its text **names all three** — not a count, not an elided subset; declining submits **none** of
  it and spawns nothing, never a partial subset.
- [ ] 6.10 GREEN `OperationCenter`: `ConfirmationRequest` gains a **multi-command** form carrying the
  typed commands (so confirming submits exactly what was shown), and bulk submission fans out into
  N `.upgrade`/`.uninstall` submissions in selection order — the M2-2 ruling `#7101` applied to
  uninstall. **No new argv shape exists, so no new brew probe is required.**
- [ ] 6.11 RED `BulkFanOutTests` (II14 — absorbed follow-up 1, centre side): the count
  `InstalledBrowse.upgradableIDs` announces equals the number of operations
  `submitUpgrades(for:in:)` submits, for every combination of dependency toggle and snooze state.
- [ ] 6.12 GREEN: delete `submitUpgradesForOutdated(in:)` and replace its one call site with
  `submitUpgrades(for: browse.upgradableIDs, in:)`, so the pinned exclusion (PM2 — and still **no
  unpin submitted on their behalf**) and the snooze exclusion live in the derivation, once.
  Verify: `FAST --filter "OperationCenterHistory\|BulkFanOut\|OperationCenter"`.

## Phase 7: The SwiftData recorder (D1, D7 — IH1, IH3, IH4) — ≈ 350 lines

- [ ] 7.1 RED `Tests/PersistenceTests/HistoryRecorderTests.swift` (IH1 sc1, sc4): a `HistoryDraft`
  maps to a `HistoryEntry` row with every field preserved — date, `kindRaw`, `name`, verb,
  `versionFrom`/`versionTo`, `outcomeRaw`, `exitStatus`, `argv`, `commandText` — and three recorded
  entries survive a close/reopen against the same location with their original fields.
- [ ] 7.2 RED `HistoryRecorderTests` — replay safety: recording the **same** draft id twice leaves
  exactly one row, because `HistoryEntry.id` is the `ActivityItem.id` and `#Unique` on it means a
  replayed write cannot double-log.
- [ ] 7.3 RED `HistoryRecorderTests` — **threat: untrusted payload as classification input**: a
  successful run whose package output contains `Password:` persists the **same** outcome M2-2 asserts
  (`.succeeded`, not `.needsPrivileges`). `outcomeRaw` is derived from the pure classifier, never from
  raw output.
- [ ] 7.4 RED `HistoryRecorderTests` — **threat: persisted argv is display-only**: enumerate the
  public surface and assert **no API accepts a `HistoryEntry` (or its projected record) and returns a
  `MutationCommand`** — the mapping is one-way, exactly like `displayCommand`. The view offers copy
  only, and the copy text equals `commandText` character for character.
- [ ] 7.5 GREEN `Sources/Persistence/SwiftDataHistoryRecorder.swift`: the `HistoryRecording`
  conformance, draft → row, `nil` package identity persisting as `""`. Non-throwing; a write failure
  surfaces on the store's own `lastError` and never reaches the operation.
- [ ] 7.6 RED `Tests/BrewClientTests/OperationCenterHistoryTests.swift` (IH3 sc1–2): with a running
  inventory and a change source under test control, an **externally** added package appears in the
  inventory after the quiet window but produces **no** history entry; and an inventory refresh, a
  catalog sync and a brew detection all completing leave the history empty. **No FSEvents-driven write
  exists** (settled R2).
- [ ] 7.7 RED `Tests/PersistenceTests/HistoryRecorderTests.swift` (IH4 sc3): an entry whose
  operation's execution-layer record has been **retired** by Phase 1 is still present with all of its
  fields — durable retention is independent of the runner's bounded records.
- [ ] 7.8 GREEN wiring: no production change expected for 7.6–7.7. A failure means a non-mutation path
  gained a write, or retention reached into the store.
  Verify: `FAST --filter "HistoryRecorder\|OperationCenterHistory"`.

## Phase 8: App-target UI (D3, D8, D12 — xcodebuild only, outside the `FAST` loop) — ≈ 900 lines

Views own **no rules**: everything they read is a pure function or a computed property proven in
Phases 5–7.

- [ ] 8.1 `cellar.xcodeproj/project.pbxproj`: add one `XCSwiftPackageProductDependency` for
  `Persistence` (the `BrewClient` precedent). New source folders need **no** edit — objectVersion 77
  synchronized groups, verified in M2-2 task 8.1. Verify: `xcodebuild build`.
- [ ] 8.2 `cellar/cellarApp.swift` + `cellar/ContentView.swift`: own `MetadataStore` and
  `HistoryStore` as `@State` (the `CatalogStore` precedent) and inject them down. **No
  `.modelContainer(…)` scene modifier and no `@Query`** — adding the modifier later stays a one-line
  option if `@Query` is ever wanted (D3).
- [ ] 8.3 `cellar/Shell/AppSection.swift` + `ContentView.swift`: add the `.history` sidebar section.
  Favorites is a **filter bar entry, not a sidebar section** (settled Q4).
- [ ] 8.4 `cellar/Installed/InstalledRow.swift`: star toggle reading `PackageMetadata.isFavorite`,
  writing through `MetadataStore.setFavorite(id:)`. Disabled with the reason attached when
  availability is `.unavailable` (D4).
- [ ] 8.5 `cellar/Installed/InstalledFilterBar.swift`: the favorites filter chip, disabled when no
  metadata is available; the outdated count reads `InstalledBrowse.upgradableIDs` — **the same
  projection the bulk action submits** (II14).
- [ ] 8.6 `cellar/Installed/InstalledListView.swift`: multi-select. Keep the native
  `List(selection:)` `Set<PackageID>` binding for shift/⌘ range selection, VoiceOver and Select All,
  and recover order **beside** it in `@State private var order: [PackageID]` maintained in
  `.onChange(of: selected)` — remove deselected ids in place, then append newly added ids **in
  displayed-row order**, never in `Set` iteration order (which is unstable across launches and would
  make the submission sequence non-reproducible). `order` is the **only** thing `BulkSelection` and
  the confirmation sheet read. The detail binding is written only when `order.count == 1`.
- [ ] 8.7 `cellar/Installed/BulkActionBar.swift` (create): upgrade and uninstall only, labelled from
  `BulkSelection`, unavailable rather than inert for an empty or ineligible selection.
- [ ] 8.8 `cellar/Activity/MutationConfirmation.swift`: render the multi-command form — one sheet
  listing **every** selected package's `displayCommand` verbatim (PM3 sc5).
- [ ] 8.9 `cellar/Browse/PackageDetailView.swift`: notes editor (plain `TextEditor`, **no Markdown
  rendering, no length cap**), star toggle, and the snooze control that stores the currently offered
  version. Unsnooze restores the badge on the next read.
- [ ] 8.10 Create `cellar/History/HistoryView.swift` and `cellar/History/HistoryRow.swift`: the
  searchable newest-first list over `HistoryStore`, per-row copy of `commandText`, **no per-entry
  delete control** (IH6 sc4), and a single confirmed all-or-nothing **Clear history** action.
  Verify: `FULL` — builds, links, and the History section renders empty with no store.

## Phase 9: Docs, gate and manual verification

- [ ] 9.1 **Absorbed follow-up 11** — `openspec/changes/m2-mutations-installed/explore.md`, the six
  recorded doc corrections: the over-generalised `installed_as_dependency` claim, the unmarked pin
  read path, the Defer/Prelude verdict conflict, the stale `project.pbxproj` line numbers, the
  present-tense superseded facts needing an as-of anchor, and the six-slice arithmetic slip. Docs
  only — and it **must** land here: the umbrella exploration is archived after M2-3, so this is the
  last change that can correct it.
- [ ] 9.2 **Manual verification (for the surfaces that are untested by design). Left unchecked for
  the orchestrator.** With the app running and brew present:
  (a) star a package, write a multi-line note, snooze an outdated one → **quit and relaunch** → all
  three survive against the **real on-disk SwiftData store** under
  `Application Support/<bundleID>/Metadata/`, keyed by (kind, name);
  (b) snooze a genuinely outdated package against **live brew data** → the badge and the outdated
  count both drop it, and the outdated browse filter agrees; then confirm it is still listed in
  Installed with its installed version;
  (c) multi-select two packages in the real UI, in a deliberate order → the bulk label counts exactly
  what is submitted, the uninstall confirmation **names both**, and the two operations run **in
  selection order** with two history rows;
  (d) History section: search by name, by verb and by argv fragment; then Clear history confirmed →
  history empty, favorites/notes/snoozes intact.
  Record each observation verbatim in the apply report. Do **not** exercise sudo-requiring casks or a
  real lock conflict — both are covered by probe `#7097`'s captured strings.
- [ ] 9.3 Full gate: `FAST` green with the Phase 0 `@Test` count intact plus the new suites (none
  deleted), `FULL` green, `swiftlint` on changed files with new findings separated from the 33
  pre-existing source findings. Every changed file **under 400 lines** — check `OperationCenter.swift`,
  `InstalledFilterMode.swift`, `BrewRunner.swift` and the new `Persistence` files explicitly, and
  watch `type_body_length` on the new suites (it errors, and it bit M2-2). Record every command and
  its exact result.
- [ ] 9.4 Scope guard: `git diff --stat main` touches only the files in design "File Changes" (plus
  any file a task above mandates by name — list each with its reason); `Persistence` is the outermost
  node and **nothing depends back on it**; `Catalog` still declares no `BrewProcess` dependency
  (`PackageGraphTests` green); `BrewClient` **never links SwiftData**; no `@unchecked Sendable` in
  `Sources/Persistence/` or `Sources/BrewClient/`; no `@Model` instance crosses an isolation boundary
  anywhere. Then record the actual authored line count against the 4,000–5,400 forecast and the
  pre-accepted `size:exception`.
