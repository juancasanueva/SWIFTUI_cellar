# Proposal: M2-3 — Local Metadata & History

PRD milestone **M2** (§3.2, §4.1, §4.2, §7), slice **M2-3** — the **last** M2 slice. Umbrella
exploration: `openspec/changes/m2-mutations-installed/explore.md` (§5 SwiftData placement, §7 slicing,
§9 approach). Artifact store: hybrid — mirrored in Engram `sdd/m2-local-metadata-history/proposal`.
Baseline: `main` @ `8c9bc2a` (M2-2 archived, 432 tests / 56 suites, 8 main specs).

## Intent

Cellar can now read and mutate Homebrew, but it forgets everything. Nothing the *user* knows about a
package survives a relaunch: no favorite, no note, no "stop nagging me about this version", no record
of what Cellar itself installed or removed. There is **zero SwiftData in the repo** and no
`Persistence` target, so M2's exit criterion — full daily package management without Terminal — is
met for actions but not for the local knowledge that makes those actions repeatable. This slice adds
the persistence spine (once, versioned) and the four surfaces PRD §3.2 hangs off it.

It is also the last chance to close the follow-ups that only became reachable once mutations shipped:
runner records are **never evicted** today, which is a hard prerequisite for an honest history.

## Scope

### In Scope

- **`Persistence` target** in CellarCore: SwiftData `VersionedSchema` V1 + `SchemaMigrationPlan` from
  day one, models `PackageMeta` (favorite, note), `Snooze`, `HistoryEntry`. Joint key is
  `PackageID` (kind + name), reused from M1 — not a second identity.
- **Favorites**: star toggle on Installed rows and package detail; **Favorites filter in the Installed
  filter bar**. No separate sidebar section (settled Q4).
- **Per-package notes**: free-text, edited from package detail, persisted locally.
- **Snooze — "until next version" only** (settled Q2): stores the version it applies to; the outdated
  badge stays hidden while the offered version **equals** the snoozed one and revives on **any
  different** offered version (G5 ruling, user-confirmed — no version ordering, no comparator).
  No durations, no clock dependency.
- **Installation history**: one durable entry per mutation Cellar performed (date, package, verb,
  version from→to, outcome, exact argv), a History sidebar section with search, **keep-all retention**
  and a manual **Clear history** action (settled Q1).
- **Bulk multi-select**: upgrade + uninstall only, **per-package brew invocation fan-out** (M2-2
  ruling `#7101`); bulk uninstall confirmation lists every selected package. Pin/unpin/snooze are
  **not** bulk-eligible (settled Q3).
- **Absorbed follow-ups** 1, 2, 3, 4, 5, 11 — see the register below.

### Out of Scope

- Time-based snooze durations (PRD §3.2 also lists 1 day / 1 week / 1 month). Deliberately narrowed to
  the version-relative rule; durations need a clock seam and buy nothing M2 needs.
- `DismissedCVE` (M4) and `Settings` (M6) models — V1 carries three models; those land as later
  lightweight migration stages.
- CloudKit / sync of any kind (PRD §4.2: data is machine-specific).
- Release notes, adopt-existing-apps, size on disk, last-used heuristics (PRD §7 assigns these to M5).
- History of **externally** performed brew changes — the log is "performed through the app" (PRD §3.2).
- Follow-ups 6–10, 12, 13 (see dispositions).

## Capabilities

### New Capabilities

- `local-package-metadata`: locally persisted per-package metadata keyed by (kind, name) — favorite
  flag, note, and version-scoped snooze — plus the rule by which a snooze suppresses the outdated
  badge and how any different offered version revives it (G5 ruling: equality, not ordering).
- `installation-history`: a durable, append-only record of every mutation Cellar performed, its
  searchable projection, keep-all retention, and the manual clear action.

### Modified Capabilities

- `installed-inventory`: favorites composed as a filter alongside the existing installed-state filters
  (never pushed into the search index); snoozed packages excluded from the outdated section **and its
  count**; multi-select selection model; the bulk-upgrade label counts exactly the set it submits
  (follow-up 1).
- `package-mutation`: bulk selection fans out into one invocation per selected package; bulk uninstall
  confirmation names every package it will remove; the two `naming(_:_:)` bypasses closed so
  construction-time validation is true at every call site (follow-up 3).
- `operation-activity`: cancel stays effective when the runner is detached and the gate is not paid
  early (follow-up 2); every terminal outcome writes exactly one history entry.
- `brew-execution`: bounded retention for terminal operation records — `exit(of:)` stays answerable
  for any operation still being awaited, while records stop accumulating for the process lifetime
  (follow-up 4). Durable retention moves to `installation-history`.

## Approach

1. **`Persistence` target inside CellarCore** (explore §5 option A), not the app target: it keeps the
   models in the fast headless `swift test` loop with
   `ModelConfiguration(isStoredInMemoryOnly: true)` and escapes the app target's
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Depends on `Catalog` for `PackageID` only —
   one-directional, so `Catalog` stays brew-free (CS1).
2. **Persist primitives, expose types.** `@Model` classes store `kind` + `name` as primitives so
   `#Predicate` stays simple and migration-safe; the store API takes and returns `PackageID`.
3. **Seams, not framework leakage.** `OperationCenter` records history through a `HistoryRecording`
   protocol; the SwiftData implementation lives in `Persistence`, so `BrewClient` never links
   SwiftData and its suite keeps a fake. Mirrors `ProcessLaunching` / `CatalogSource` / `InstalledChangeObserving`.
4. **`@MainActor @Observable` metadata store**, on the shipped `InstalledStore` / `OperationCenter`
   exemplar. Every M2-3 write is a single user-initiated row on the main context; `@ModelActor` is
   introduced only if a measured write blocks. Carry the gotchas regardless: never pass `@Model`
   instances across actors, `PersistentIdentifier` only, explicit `save()` in any actor path.
5. **Snooze and favorites compose above the inventory**, exactly as the M2-1 installed-state filters
   do — the badge rule is a projection over (inventory outdated state × stored snooze version), so a
   cold or empty metadata store degrades to today's behaviour.
6. **Retention before history.** Evict a runner record only once it is terminal *and* drained; land it
   with tests before any history write depends on it.

## Follow-up register dispositions (13 items, `archive/2026-08-02-m2-mutations-activity`)

| # | Item | Disposition | Rationale (one line) |
|---|---|---|---|
| 1 | Bulk-upgrade label/set mismatch (`InstalledListView.swift:83`) | **Absorb** | This slice rewrites that filter bar for favorites and multi-select; the label must count what it submits |
| 2 | Cancel after runner detach (`OperationCenter.swift:239`) | **Absorb** | Bulk multi-select multiplies the exposure of an uncancellable running operation |
| 3 | `naming(_:_:)` bypass (`MutationMenu.swift:27`, `PackageDetailView.swift:69`) | **Absorb** | Both views gain favorite/note/bulk affordances here; fixing the bypass makes the by-construction claim true |
| 4 | Runner records never evicted + `queuePhase` equality guard | **Absorb** | Retention is a **hard prerequisite** for history; the guard is one line in the same file |
| 5 | `OperationCenterHarness.swift:53` indexes after a silent poll timeout | **Absorb** | ~5 lines in the harness this slice extends for history assertions; a trap should be a failed expectation |
| 11 | `explore.md` doc corrections (6 items) | **Absorb** | Last M2 slice — the umbrella exploration is archived after this; docs-only |
| 6 | Post-terminal FSEvents echo grace window | **Defer** | Verify ruling 2 confirmed it conforming; a new timing policy needs its own probe for one redundant probe |
| 7 | Duplicate-submission dedup | **Defer** | Permitted by design (verify ruling 3); a product nicety, not a correctness fix |
| 8 | Carry `standardInput` through `ProcessSpec` | **Defer** | Observability of already-correct behaviour, in a seam this slice does not otherwise touch |
| 9 | Sudo signature set unprobed | **Defer** | Needs a live sudo-requiring cask; safe by construction (a miss degrades to `.failed` with the log) |
| 10 | `skippedRecordCount` never surfaced | **Defer** | Inventory decode-tolerance UX, no coupling to metadata or history |
| 12 | M2-0 #1 catalog adoption ordinal | **Defer** | The archive report explicitly asks that the project's oldest defect be closed on its own, not carried into a fourth slice |
| 13 | M2-0 #4–#7, M1 #4/#5 | **Defer** | Catalog/watcher hardening bundle; unrelated surface |

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Sources/Persistence/` | **New** | `VersionedSchema` V1, three `@Model` classes, migration plan, metadata store, SwiftData history recorder |
| `Packages/CellarCore/Package.swift` | Modified | New `Persistence` target + product, new `PersistenceTests` target |
| `Packages/CellarCore/Sources/BrewClient/OperationCenter.swift` | Modified | `HistoryRecording` seam, cancel-after-detach fix, one history write per terminal outcome |
| `Packages/CellarCore/Sources/BrewClient/` (browse/entries, `MutationCommand`) | Modified | Favorites + snooze composition, bulk selection projection, bulk uninstall confirmation |
| `Packages/CellarCore/Sources/BrewProcess/BrewRunner.swift` | Modified | Bounded terminal-record retention, `queuePhase` equality guard |
| `cellar/Installed/`, `cellar/Browse/`, `cellar/History/` (new) | New + Modified | Star toggles, favorites filter, notes editor, snooze control, multi-select, history view + search |
| `cellar/cellarApp.swift`, `cellar/ContentView.swift` | Modified | `ModelContainer` wiring, History sidebar section |
| `cellar.xcodeproj/project.pbxproj` | Modified | One `XCSwiftPackageProductDependency` for `Persistence` (precedent: `BrewClient`). New source folders need no edit — objectVersion 77 synchronized groups |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| V1 schema shape wrong; M4/M6 additions force a heavy migration | Med | `VersionedSchema` + `SchemaMigrationPlan` from day one even at V1; V1 carries only the three M2 models; additive optional properties stay lightweight |
| SwiftData does not run headless in the `swift test` inner loop | Med | Prove it in the first phase with an in-memory `ModelConfiguration` spike before any model work; fall back to a Codable store only if it genuinely cannot (explore §5 option C) |
| `ModelContext` is not `Sendable`; app target is MainActor-default | Med | All M2-3 writes are single-row on the main context; never pass `@Model` across actors; `PersistentIdentifier` only; explicit `save()` in any actor path |
| Record eviction breaks `exit(of:)` for a live operation | Med | Evict only when terminal **and** drained; land retention first with RED tests, before history depends on it |
| Size exceeds the 2,000-line review budget | **High** | ~4.0k–5.4k authored forecast → **`size:exception` required before apply** (M2-2 precedent: 4,538 accepted) |
| History fidelity for `upgradeAll` (names no package) | Med | Open question below; default is one entry per submitted operation, no snapshot diffing |
| Notes/snoozes accumulate for packages long uninstalled | Low | Rows are tiny and keyed by (kind, name); a favorite/note surviving a reinstall is the desirable behaviour |

## Rollback Plan

Revert the feature branch. Nothing else in the app depends on `Persistence`, and the
`HistoryRecording` seam has a no-op default, so `OperationCenter` returns to its M2-2 behaviour. There
is **no migration to undo**: V1 is the first schema, so deleting the store file under Application
Support is a complete data rollback. The two project-file touches — the `Persistence` product
dependency in `project.pbxproj` and the `Package.swift` target — revert with the branch; no target
membership is edited by hand for new source folders (objectVersion 77 synchronized groups, verified in
M2-2 task 8.1). Cost of rollback: local favorites/notes/snoozes/history created on a Debug build are
lost, which is acceptable because none of that data existed before this change.

## Dependencies

- M2-2 `m2-mutations-activity` archived at `8c9bc2a` (mutation vocabulary, `OperationCenter`,
  `InstalledMutationGate`) — done.
- An accepted **`size:exception`** before apply.
- Runner-record retention (follow-up 4) must land before any history write depends on it.

## Success Criteria

- [ ] Favorites, notes and snoozes survive a relaunch and are keyed by (kind, name).
- [ ] A snoozed package shows no outdated badge and is absent from the outdated count while the
      offered version equals the snoozed one; **any different** offered version returns it
      automatically (G5 ruling supersedes the original "strictly newer" wording).
- [ ] Every mutation Cellar performs writes exactly one history entry with date, package, verb,
      version from→to, outcome and the exact argv; history is searchable and never auto-evicted;
      Clear history removes all entries and nothing else.
- [ ] Multi-select upgrade and uninstall each fan out into one brew invocation per selected package,
      in selection order; bulk uninstall confirms by naming every selected package; pin/unpin offer no
      bulk affordance.
- [ ] Terminal runner records stop accumulating, and `exit(of:)` still answers for any operation still
      being awaited.
- [ ] Absorbed follow-ups 1–5 each closed with a test that reproduced them first (strict TDD).
- [ ] `swift test --package-path Packages/CellarCore` and the app scheme both green; zero new SwiftLint
      findings; zero concurrency warnings.

## Open product questions carried to design (not blocking)

1. **`upgradeAll` history fidelity**: one entry for the whole grouped operation (default), or per-package
   entries derived by diffing the inventory snapshot either side of it?
2. **History scope confirmation**: entries record only mutations submitted through Cellar; externally
   detected changes are deliberately not logged. Assumed from PRD §3.2 wording.
3. **Clear history**: single confirmed all-or-nothing action (default), or selective deletion?
4. **Note constraints**: plain text with no length cap and no Markdown rendering (default); notes are
   searchable in the Installed list or not?
