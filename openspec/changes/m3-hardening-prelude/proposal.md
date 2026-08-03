# Proposal: M3-0 — Hardening Prelude

PRD milestone **M3** (§3.3, §3.6, §3.8, §4.1–4.2, §7), slice **M3-0** — the first of five, and the
only one forecast to fit the review budget. Umbrella exploration:
`openspec/changes/m3-services-cleanup-taps/explore.md` (§4.2 slice table, §4.3 ordering, §5 fold-in
register). Artifact store: hybrid — mirrored in Engram `sdd/m3-hardening-prelude/proposal`.
Baseline: `main` @ `3562cd1` (M2 fully archived; 555 tests / 73 suites; 10 main specs, 80
requirements, 263 scenarios).

## Intent

M3 adds four capabilities on top of the mutation spine, the runner, the composition root and the
adoption discipline that M2 built. Ten known defects sit in exactly those places. Three of them are
**live spec violations** (a terminal outcome that writes no history entry, a runner that answers an
unknown operation with a fabricated *success*, a catalog that lets an older snapshot install over a
newer one); one has a **data-integrity tail** (two `ModelContainer`s over one store file); the rest
are silent-failure and order-fidelity bugs the user cannot see but would be blamed for.

Every one of them is cheaper to fix now than after M3-1 restructures the same methods, and three of
them are shapes M3-1..4 are about to replicate — a fabricated success gets worse with every new
submitter, and a third `ModelContainer` is one services store away. This slice closes them, makes the
review budget in the config match the one the session actually uses, and leaves M2 with no artifact
outside `archive/`.

**It ships no feature.** That is the point: it is the only M3 slice that merges without a
`size:exception` negotiation, so the correctness work does not wait behind one.

## Scope

### In Scope

| # | Item | Fix | Spec |
|---|---|---|---|
| 1 | **Catalog adoption ordinal** (`Catalog/CatalogStore.swift:185-186`) | `adoptionSequence` stamps on *call arrival*, so a later-entering older snapshot wins. Order by `snapshot.revision.ordinal` (already monotonic, minted at materialization) and stop `adoptedRevision` from regressing to an older revision | `catalog-sync` |
| 2 | **W1 — terminal outcome without a history entry** (`BrewClient/OperationCenter.swift:159-163`) | The no-runner submit path settles `.launchFailed` inline, bypassing `finish(_:with:)`. Route it through the single idempotent funnel so the entry is written **by construction**, not by a second call site | `operation-activity` |
| 3 | **W2 — failed Clear History rendered as success** (`Persistence/HistoryStore.swift:181-190`) | `clearAll()` sets `availability` in the `catch`, then an unconditional `reload()` overwrites it to `.available`; `lastError` is never set. Preserve the failure, set `lastError`, keep the all-or-nothing rollback | `installation-history` |
| 4 | **W3 — two `ModelContainer`s over one store file** (`cellar/cellarApp.swift:50`, `:63`) | One container built once at the composition root and injected into `MetadataStore` and `HistoryStore` — design D3's stated intent | — (design) |
| 5 | **W4 — uncommitted note draft lost on package switch** (`cellar/Browse/PackageMetadataSection.swift:56`) | `onChange(entry.id)` resets `draft` with no commit; the doc comment claims an `onSubmit` commit that a multiline `TextEditor` cannot have. Commit **before** the reset, and correct the comment to the behaviour that exists | — (design) |
| 6 | **S1 — fabricated success for an unknown operation** (`BrewProcess/BrewRunner.swift:284-292`) | `exit(of:)` returns `BrewExit(status: 0, reason: .exited)` for an id it does not know; only the `isReleased` gate keeps it unobserved. Return a typed unknown-operation result instead | `brew-execution` |
| 7 | **S2 — bulk multi-add order** (`cellar/Installed/InstalledListView.swift:117`) | Appends in flat inventory order, not the displayed three-section order its own comment claims. M2-3's design ruled **displayed-row order**; make the code match and make the ruling durable | `installed-inventory` |
| 8 | **VS1 — vacuous structural scan** (`PersistenceTests/HistoryRecorderTests.swift`) | `aStoredRowCannotBecomeACommand` is pure-negative and passes on an empty set. Add the positive anchor the G5 scan already uses | — (tests) |
| 9 | **M2-0 #4 — unbounded watcher loop** (`CatalogTests/CatalogAdoptionTests.swift:182`) | Suite carries no `.timeLimit`. M3-1 adds a poll loop and M3-3 a cancellable traversal; establish the habit before, not after | — (tests) |
| 10 | **Housekeeping** | `openspec/config.yaml` `review_budget_lines: 800 → 2000` **and** the `rules.tasks` line that still says "the 800-line review budget"; move `openspec/changes/m2-mutations-installed/` to `openspec/changes/archive/2026-08-03-m2-mutations-installed/` (milestone-close date, matching the sibling convention) | — |

### Out of Scope

Held deliberately — every line below is an M3-1..4 or later concern, and this slice fits the budget
only because none of it enters:

- **`BrewMutating` generalization** and the `ServiceCommand` / `TapCommand` / `CleanupCommand`
  families (explore §6-A) — M3-1. The no-runner fix (#2) restructures the *same method* M3-1 will
  generalize; that is why it lands first, not why it grows here.
- **`InvalidationScope`** and any change to `MutationOutcome.forcesReSnapshot` / the unconditional
  `gate?.begin()` (explore §6-B) — M3-1. `package-mutation` PM6 is **not** touched by this slice.
- **Services, taps, disk usage, cleanup** — any store, decoder, probe, view, poll loop or new SPM
  target. No new capability is created here.
- **The catalog hardening bundle** (register item M2-2 #13: M2-0 #5–#7, M1 #4/#5 — poisoned-snapshot
  recovery gated on staleness, engine-side zero-package guard, latency test via the synchronous
  initialiser, payload size cap, unwired `payloadByteLimit`). Deferred to a catalog slice or M5. Item
  #1 above is the *adoption ordinal only*.
- **VS2, M2-2 #6/#7/#9, VS4** — absorbed into M3-1 by the approved plan. **VS3** (UI-test harness),
  **M2-2 #8/#10**, **M2-1 #8/#9** — deferred.
- **Probe gates U1–U8.** None blocks this slice; all eight run before M3-1's propose.

## Capabilities

### New Capabilities

None. This slice creates no capability and adds no requirement to a capability that does not already
own the behaviour.

### Modified Capabilities

Five, each a **whole-block MODIFIED superset** of one existing requirement — zero REMOVED, zero
RENAMED, zero destructive deltas. Each restates its requirement with one added clause and keeps every
existing scenario byte-identical.

| Capability | Requirement | Added clause | New scenarios |
|---|---|---|---|
| `catalog-sync` | *A snapshot is adopted exactly once, in order* | "Newer" is the snapshot's own revision, not the order adoption was **called**; an older snapshot entering after a newer one has been installed MUST be discarded, and the adopted-revision record MUST NOT regress | 1 |
| `operation-activity` | *Every terminal outcome records exactly one history entry* | An operation that reaches a terminal outcome **without ever spawning** — no runner configured, or a launch that fails before the process exists — is a terminal outcome like any other and MUST record exactly one entry | 1 |
| `installation-history` | *Clear history is a single confirmed all-or-nothing action* | A clear that fails MUST be observable and MUST NOT be presented as an emptied or healthy history; the failure reason MUST survive the projection reload that follows it; every entry MUST still be present | 2 |
| `brew-execution` | *Terminal result and exit handling* | An identity the runner does not know MUST yield a typed unknown-operation result, never a fabricated successful `BrewExit` | 1 |
| `installed-inventory` | *Multi-select is explicit, ordered, and offered only for bulk-eligible verbs* | A selection added in bulk (select-all / multi-add) MUST enter the selection in the order the list **displays**, so submission order matches what the user sees | 1 |

**Trap for `sdd-spec`**: `installed-inventory` sc4 asserts exhaustively over
`BulkSelection.Action.allCases` (exactly two cases). The MODIFIED block must carry all five existing
scenarios forward unchanged — this slice adds no bulk verb.

## Approach

1. **Strict TDD, one item per RED→GREEN pair.** Every item is a defect with an observable symptom, so
   each starts with a test that reproduces it. Items #1, #2, #3, #6, #7 get their failing test written
   against the new spec scenario, so the assertion outlives the fix.
2. **Fix through the existing funnel, never beside it.** #2 is deleted code, not added: the inline
   settle disappears and the path calls `finish(_:with:)`, which already pays `gate?.end()` and writes
   the entry idempotently. This is the shape M3-1 inherits when it generalizes `submit`.
3. **#1 is bookkeeping, not one line.** The register called it a one-line guard; `adoptedRevision` is
   assigned unconditionally at `:183`, so the fix must also stop an older snapshot from clobbering the
   dedup record. `CatalogSnapshotRevision.ordinal` is `internal` and `CatalogStore` is in the same
   module, so no API widens.
4. **#6 changes a return type, so its blast radius is the real cost.** `exit(of:)` is `internal` and
   reached through `BrewOperation.exit()`; the typed result must not leak a *new error* into a path
   the spec says never throws for a non-zero exit. Prefer a distinguishable value (an unknown reason)
   over a thrown error — `brew-execution` already rules that a terminal result is a value.
5. **#5's rule moves out of the view.** `PackageMetadataSection` is app-target SwiftUI and untestable
   in the `swift test` loop. Extract the draft/commit decision into a small pure type in the package
   (given a stored note, a draft and an identity change, does it commit and with what?), leave the
   view holding layout only, and test the type. Same discipline as `PackageMetadata.isSnoozed`.
6. **#4 is composition-root only.** One `ModelContainer` created in `cellarApp`, passed to both
   stores' `init(container:)` — which already exists. `PersistenceContainer.defaultURL()` stays the
   single source of the path; no schema, model or migration changes.
7. **Nothing else moves.** No new target, no new source folder, no `Package.swift` edit, no
   `project.pbxproj` edit expected (a new file inside an existing synchronized folder needs none —
   objectVersion 77, verified in M2-2 task 8.1).

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Sources/Catalog/CatalogStore.swift` | Modified | Revision-ordered adoption guard; non-regressing `adoptedRevision` |
| `Packages/CellarCore/Sources/BrewProcess/BrewRunner.swift` | Modified | Typed unknown-operation result from `exit(of:)`; callers in `BrewOperation.swift` |
| `Packages/CellarCore/Sources/BrewClient/OperationCenter.swift` | Modified | No-runner path routed through `finish(_:with:)` |
| `Packages/CellarCore/Sources/Persistence/HistoryStore.swift` | Modified | Clear failure preserved through `reload()`; `lastError` set |
| `Packages/CellarCore/Sources/Persistence/` (new small type) | New | Note-draft commit rule extracted from the view |
| `cellar/cellarApp.swift` | Modified | One `ModelContainer`, injected into both stores |
| `cellar/Browse/PackageMetadataSection.swift` | Modified | Commit before draft reset; doc comment corrected |
| `cellar/Installed/InstalledListView.swift` | Modified | Bulk multi-add in displayed section order |
| `Packages/CellarCore/Tests/` (Catalog, BrewProcess, BrewClient, Persistence) | Modified | RED tests per item; positive scan anchor; `.timeLimit` on the watcher suite |
| `openspec/config.yaml`, `openspec/changes/m2-mutations-installed/` | Modified / Moved | Budget reconcile; last M2 artifact into `archive/` |

## Size forecast vs the 2,000-line budget

| Bucket | Forecast |
|---|---|
| Items #1–#7 (src) | ~210 |
| Items #1–#7 (tests, ~1.2× familiar layers) | ~650 |
| Items #8–#10 | ~40 |
| Spec deltas (5 whole-block MODIFIED + 6 scenarios) | ~260 |
| SDD markdown (proposal, design, tasks, verify report) | ~450–800 |
| **Total candidate lines** | **~1,610–1,960** |

Authored src+tests land at **~900** — inside the explore's 900–1,500 band. The **review candidate**
is the number that matters, and it counts SDD markdown too: M2-3 forecast 6,425 src+tests and its
review candidate was **9,018 lines across 68 files**. Applying that ratio here is what puts the top of
the band at ~1,960, i.e. **fitting, but with no headroom**. See risk 1.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Candidate exceeds 2,000 once spec + SDD markdown is counted (M2-3 precedent: +40% over src+tests) | **Med-High** | Whole-block MODIFIED deltas only, no new requirement; short design; if the candidate approaches 2,000 the drop-first order is **#7 then #8** (both defer cleanly to M3-1) — **never #4**, which carries the data-integrity tail |
| Scope creep: "while we're in `OperationCenter`, start the `BrewMutating` protocol" | **High** | M2-0 overran its band by 1.67× and was the worst ratio of the four M2 slices, precisely as a small prelude. The Out-of-Scope list above is a hard gate; any generalization is an M3-1 task, and a `size:exception` request is the signal that scope leaked |
| #6's typed result ripples further than expected (`exit(of:)` has 30 callers via `BrewRunner`) | Med | Keep it a **value**, not a thrown error, so no `throws` annotation propagates; the existing `ExitTests` suite is the regression net |
| #4 changes container ownership and could break store availability at launch | Med | Both stores already accept `init(container:)`; the on-disk failure path folds to `.unavailable(reason:)` unchanged. Manual launch check is mandatory evidence (see success criteria) |
| #3, #4, #5 are only observable in the app target, where automated coverage is thin (VS3 is deferred) | Med | Put every rule in a package-level testable type (#5) or assert on store state (#3); plan the manual checks in `sdd-tasks` rather than at verify — M2-3's IH6 CRITICAL is the precedent for what unplanned manual evidence costs |
| Archiving `m2-mutations-installed/` breaks a path some artifact still cites | Low | Grep for the path before moving; the M3 umbrella explore references it by name only |

## Rollback Plan

Revert the feature branch. Every change is a behaviour correction inside an existing file — no new
target, no new SPM product, no `project.pbxproj` or target-membership edit, no schema version and
no migration, so there is **nothing to undo outside git**. #4 is the only item touching persisted
data's *access path*: it changes how many `ModelContainer`s open `PersistenceContainer.defaultURL()`,
not the file, the schema or its contents, so reverting restores the previous wiring against the same
store with no data loss. The `openspec/config.yaml` budget line and the archive folder move revert
with the branch.

## Dependencies

- M2 archived at `3562cd1` — done.
- No probe gate blocks this slice (U1–U8 are M3-1..4 concerns).
- **No `size:exception` expected.** If the candidate crosses 2,000, drop #7 and #8 rather than
  request one.

## Success Criteria

- [ ] An older catalog snapshot arriving after a newer one has installed is discarded, and the
      catalog still serves the newer one.
- [ ] A submit with no runner reaches its terminal outcome **and** writes exactly one history entry,
      through the same funnel as every other outcome.
- [ ] A failed Clear History leaves every entry present, reports the failure reason, and is never
      shown as an emptied or healthy history.
- [ ] The app opens exactly one `ModelContainer` over the store file, injected into both stores.
- [ ] An uncommitted note survives switching packages; the doc comment describes the commit triggers
      that actually exist.
- [ ] `exit(of:)` answers an unknown operation with a typed unknown result — a fabricated
      `status: 0` is unreachable, proven by a test rather than by the `isReleased` gate.
- [ ] Bulk multi-add enters the selection in displayed order, asserted by a scenario, not a comment.
- [ ] `HistoryRecorderTests`' structural scan cannot pass vacuously; `CatalogAdoptionTests` carries a
      `.timeLimit`.
- [ ] `openspec/config.yaml` declares `review_budget_lines: 2000` (and its `rules.tasks` line agrees);
      `openspec/changes/` holds no M2 artifact outside `archive/`.
- [ ] `swift test --package-path Packages/CellarCore` green (555 + new tests) and the app scheme
      builds; zero new SwiftLint findings; zero concurrency warnings.
- [ ] Every fix landed RED-first, and each of the five spec deltas has at least one scenario that
      failed before it.

## Open decisions (assumed below; correct at spec or design)

1. **Failed Clear History** — assumed: entries stay visible, the reason is surfaced inline via the
   existing availability/`lastError` surface, the clear stays all-or-nothing (`rollback()` already
   holds), no blocking alert and no retry affordance.
2. **Note draft on package switch** — assumed: commit silently, no prompt and no discard affordance;
   a switch is not a cancel. Window close / app quit stays out of scope.
3. **Bulk multi-add order** — assumed: the displayed three-section order (outdated → on-request →
   dependencies) as rendered, becoming a durable `installed-inventory` scenario rather than a code
   comment.
4. **Unknown operation (#6)** — assumed: a *value* carrying an unknown reason, surfaced as a failed
   operation, and it records a history entry like any other terminal outcome.
5. **"Newer" for a catalog snapshot** — assumed: materialization order (`revision.ordinal`), not a
   fetched-at timestamp. No new state; matches what the shipped requirement already implies.
6. **Archive folder name** — assumed `archive/2026-08-03-m2-mutations-installed/`, dated to the
   milestone close so the umbrella sorts beside its last slice.
