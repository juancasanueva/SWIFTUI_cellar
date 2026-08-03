# Design: M3-0 — Hardening Prelude

Ten defect fixes, no feature. Proposal: `openspec/changes/m3-hardening-prelude/proposal.md`
(Engram `sdd/m3-hardening-prelude/proposal`, decisions `#7130`). Umbrella: `m3-services-cleanup-taps/explore.md`
§5 (bundle) and §6 (M3-1 decisions this slice must **not** pre-build and must not contradict).

## Technical Approach

Three rules govern every item.

1. **Fix at the funnel, never beside it.** W1 routes into the existing `finish(_:with:)` rather than
   adding a second settle site. #1 replaces an arrival-ordered guard with a revision-ordered one at the
   same line, so the dedup assignment below it becomes unreachable for an older snapshot — one guard
   closes both halves the proposal named.
2. **Every rule lands in a package type; views keep layout only.** #3, #4, #5 and #7 are observable in
   the app target today. Each moves its decision into `CellarCore` (`NoteDraft`, `LocalStores`,
   `InstalledSections`, an injected clear seam), so `swift test` proves the rule and the manual check
   is reduced to *wiring*, not behaviour. Same discipline as `PackageMetadata.isSnoozed`.
3. **No type grows a case the spine must re-switch.** #6 adds one `BrewExit.Reason` case (nothing in
   `Sources/` switches over `Reason` — verified) and maps it to the **existing** `MutationOutcome
   .launchFailed`, whose doc already reads "the process never started". Zero new outcome, zero message
   churn, no `throws` (30 callers via `BrewOperation.exit()` keep their signature).

Out of scope, restated as a gate: no `BrewMutating`, no `InvalidationScope`, no PM6 edit, no new SPM
target, no `Package.swift` or `project.pbxproj` edit.

## Architecture Decisions

| # | Decision | Rejected | Rationale |
|---|---|---|---|
| D1 | #1 guard is `snapshot.revision.ordinal > adopted.ordinal`, older joins the in-flight adoption then returns | separate "is-older" branch beside the dedup guard | One guard makes the `adoptedRevision =` assignment at `:183` unreachable for an older snapshot, so the record cannot regress. Equal ordinal keeps today's join-a-duplicate contract byte-for-byte. `ordinal` is `internal`, `CatalogStore` is same-module — no API widens |
| D2 | `adoptionSequence`/`installedSequence` stay | delete them as redundant | They guard out-of-order **build completion** of two in-order snapshots; D1 guards arrival. Different failures |
| D3 | #2 hoists `gate?.begin()` **above** `guard let runner`, then the branch calls `finish(item, with: .launchFailed)` | call `finish` without a matching `begin` | `end()` yields a terminal unconditionally, so an unpaired end is safe but leaves depth accounting dishonest. One begin per submit / one end per finish is the invariant M3-1 inherits when it generalizes `submit` |
| D4 | #3 rebuilds the projection **first**, applies the failure **after** | set availability before `reload()` (today's bug), or skip `reload()` on failure | `reload()` sets `.available` on a successful fetch and would erase the reason. Reloading after `rollback()` is what proves every entry survived. `lastError` set exactly as `append` does; inline surface only, no alert (settled Q1) |
| D5 | #3 gets an internal injected clear closure (`init(container:clearing:)`) | force a real SwiftData failure (read-only dir, corrupt file) | The failure branch is otherwise unprovable in the `swift test` loop and would be flaky if faked with filesystem permissions. Seam discipline already used for `ProcessLaunching`, `CatalogSource`, `InstalledPayloadSourcing` |
| D6 | #4 adds `LocalStores` in `Persistence`: opens **one** container and injects it into both stores, folding an open failure into both stores' `.unavailable(reason:)` | build the container inline in `cellarApp` | Keeps the error→reason fold inside the package that owns it, makes the one-container rule headlessly testable, and gives M3-1's services store a place to join instead of opening a third container. `cellarApp` shrinks to three lines. `init(at:)` convenience initializers stay for tests |
| D7 | #5 extracts `NoteDraft` (pure value) into `Persistence`; the view commits **against the old id** in `onChange(of: entry.id)` before resetting | prompt/discard affordance | A switch is navigation, not cancel (settled Q2). The closure's `oldValue` is the only place the departing package's identity still exists — `stored` already reads the new one |
| D8 | #6 adds `BrewExit.Reason.unknownOperation` + `BrewExit.unknownOperation` (`status: -1`) and one `classify` branch → `.launchFailed` | new `MutationOutcome` case; `BrewExit?`; a thrown error | `isSuccess` requires `.exited && status == 0`, so the fabricated success becomes unrepresentable by construction. `-1` cannot collide with a real wait status (0–255) or a signalled `128+n`. Terminal flows unchanged, so the entry is recorded like any other (settled Q4) |
| D9 | #7 extracts `InstalledSections` (outdated / selfUpdating / rest + `displayed`) into `BrewClient`; both the three `Section`s and `reconcileOrder` read it | fix `:117` in place with `outdated + selfUpdating + rest` inline | One projection read twice — the `upgradableIDs` precedent (II14). Rendering and selection order cannot drift again, and the order becomes headlessly assertable |

**Correction for `sdd-spec` (item #7).** The proposal's "outdated → on-request → dependencies" does not
match the site. `InstalledListView` renders **Outdated → Updates itself → All packages / Installed on
request** (`:56-77`); dependency rows live inside the third section only when `includeDependencies` is
on. The ruling is unchanged (displayed order wins); the scenario must say *"in the order the list
displays them"* and must not name three sections that do not exist.

## Data Flow

    submit(command)
      │  gate.begin()                      ← hoisted above the runner guard (D3)
      ├─ no runner ─────────────────┐
      └─ run(...) ─ exit/fault ─────┤
                                    ▼
                          finish(item, with:)   ← the only settle site
                          settle → gate.end() → history.record()

    adopt(snapshot)  →  revision.ordinal > adopted?  ─no→ join in-flight, discard
                                   │yes
                                   ▼  adoptedRevision = revision  (unreachable for older)

## File Changes

| File | Action | Change |
|---|---|---|
| `Sources/Catalog/CatalogStore.swift` | Modify | D1/D2 guard at `:179-183` |
| `Sources/BrewClient/OperationCenter.swift` | Modify | D3: hoist `begin()`, no-runner branch → `finish` |
| `Sources/Persistence/HistoryStore.swift` | Modify | D4 `clearAll`; D5 clear seam; internal `init(unavailable:)` |
| `Sources/Persistence/LocalStores.swift` | **Create** | D6 one container, two stores |
| `Sources/Persistence/NoteDraft.swift` | **Create** | D7 commit rule |
| `Sources/Persistence/MetadataStore.swift` | Modify | `init(unavailable:)` `private` → internal (for D6) |
| `Sources/BrewProcess/BrewExit.swift` | Modify | D8 `.unknownOperation` + static factory |
| `Sources/BrewProcess/BrewRunner.swift` | Modify | D8 `exit(of:)` both fabricated returns (`:286`, `:291`) |
| `Sources/BrewClient/MutationOutcome.swift` | Modify | D8 classify branch after the fault switch |
| `Sources/BrewClient/InstalledSections.swift` | **Create** | D9 |
| `cellar/cellarApp.swift` | Modify | D6 wiring (`:50`, `:63`) |
| `cellar/Browse/PackageMetadataSection.swift` | Modify | D7 wiring; **doc comment corrected** — a multiline `TextEditor` has no `onSubmit`; the triggers are focus loss and a package change |
| `cellar/Installed/InstalledListView.swift` | Modify | D9 wiring (`:56-77`, `:117`) |
| `Tests/{CatalogTests,BrewClientTests,BrewProcessTests,PersistenceTests}` | Modify/Create | RED tests below |
| `openspec/config.yaml` | Modify | `:7` `800 → 2000`; `:59` prose `800 → 2,000` |
| `openspec/specs/installed-inventory/spec.md` | Modify | `:547` cites `changes/m2-mutations-installed/explore.md` — repoint to the archive path. **Path text only; not part of any delta** |
| `openspec/changes/m2-mutations-installed/` | Move | `git mv` → `archive/2026-08-03-m2-mutations-installed/` |

## Interfaces

```swift
// Persistence — D6, D7
@MainActor public struct LocalStores {
    public let metadata: MetadataStore
    public let history: HistoryStore
    public init(at url: URL = PersistenceContainer.defaultURL())   // one container, or one shared reason
}

public struct NoteDraft: Sendable, Equatable {
    public init(_ text: String)
    public static func starting(from stored: String?) -> NoteDraft   // what a newly shown package starts with
    public func pendingWrite(against stored: String?) -> String?     // nil = owes nothing; "" clears the note
}

// BrewProcess — D8
// NOTE: Swift cannot declare enum cases in an extension — add the case INSIDE the
// `BrewExit.Reason` declaration (BrewExit.swift:7-14). Nothing in Sources/ switches over Reason,
// so the addition is exhaustiveness-safe.
//   enum Reason { …existing cases…; case unknownOperation }
extension BrewExit { public static let unknownOperation = BrewExit(status: -1, reason: .unknownOperation) }

// BrewClient — D9
public struct InstalledSections: Sendable, Equatable {
    public init(entries: [PackageEntry], outdatedIDs: Set<PackageID>)
    public let outdated, selfUpdating, rest: [PackageEntry]
    public var displayed: [PackageEntry] { outdated + selfUpdating + rest }
}
```

## Testing Strategy — RED test per item

| # | Suite | RED test | Proves |
|---|---|---|---|
| 1 | `CatalogTests/CatalogAdoptionTests` | `anOlderSnapshotArrivingAfterANewerOneIsDiscarded` | `packageCount` stays the newer one; `indexBuildCount == 1` |
| 1 | same | `theAdoptedRevisionDoesNotRegressAfterDiscardingAnOlderSnapshot` | re-adopting the newer snapshot still dedups (no rebuild) |
| 2 | `BrewClientTests/OperationCenterTests` | `aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry` | outcome `.launchFailed`, spy drafts `== 1`, gate terminals `== 1` |
| 3 | `PersistenceTests/HistoryStoreTests` | `aFailedClearKeepsEveryEntryAndReportsTheReason` | records unchanged, `availability` unavailable **after** reload, `lastError` set |
| 3 | same | `aSuccessfulClearLeavesNoStaleFailureReason` | `lastError == nil`, `.available` |
| 4 | `PersistenceTests/LocalStoresTests` | `oneContainerServesBothStores` | a row written through one store is visible to the other; identical container |
| 4 | same | `aStoreThatCannotBeOpenedGivesBothStoresTheSameReason` | blocked path (regular file where the directory must go) folds, no throw |
| 5 | `PersistenceTests/NoteDraftTests` | `anEditedDraftOwesAWriteWhenTheShownPackageChanges` / `anUnchangedDraftOwesNoWrite` / `anEmptiedDraftOwesAWriteThatClearsTheNote` | the commit rule, headless |
| 6 | `BrewProcessTests/ExitTests` | `anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess` | `reason == .unknownOperation`, `isSuccess == false`, no `isReleased` involvement |
| 6 | `BrewClientTests/ClassificationTests` | `anUnknownOperationClassifiesAsLaunchFailedNotSucceeded` | `.launchFailed` → `isFailure`, entry recorded |
| 7 | `BrewClientTests/InstalledSectionsTests` | `theDisplayedOrderIsOutdatedThenSelfUpdatingThenTheRest` / `bulkAddEntersTheSelectionInDisplayedOrderNotInventoryOrder` | order fidelity |
| 8 | `PersistenceTests/HistoryRecorderTests` | `aStoredRowCannotBecomeACommand` (amended) | per-file **positive anchor** (`source.contains("HistoryEntry")`) before the four negative assertions, so an unresolved path or an over-eager comment strip fails instead of passing |
| 9 | `CatalogTests/CatalogAdoptionTests` | suite trait `.timeLimit(.minutes(1))` | **gotcha**: `TimeLimitTrait` requires whole minutes — `.seconds(30)` traps at runtime |

**Manual evidence (plan in `sdd-tasks`, not at verify).** (a) App launches with one container: notes,
favorites and history all read/write in the same session — item #4's wiring, since a package test
cannot see `cellarApp`. A cross-target source scan from `PersistenceTests` was rejected: it would
couple the package's tests to the app target's file layout. (b) Type a note, switch package in Browse,
switch back — the note is there (item #5 wiring). (c) Select All in Installed with an outdated package
low in inventory order — the bulk bar submits in displayed order (item #7 wiring).

## Threat Matrix

| Boundary | Applicability | Design response | RED test |
|---|---|---|---|
| Documentation-like paths | N/A — no file is classified or executed | — | — |
| Git repository selection | N/A — no `git -C`/cwd authority in product code; the archive move is a one-off `git mv` by a human | — | — |
| Commit state / Push state / PR commands | N/A — no VCS or PR automation in scope | — | — |
| **Subprocess terminal-result fidelity** (project row) | **Applicable** — #6 and #2 both decide what a terminal result *is* when no process exists | An identity with no record yields a typed non-success value; a submission with no runner settles through the same funnel. No argv is composed, no signal sent, no prose parsed | `anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess`, `aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry` |

## Migration / Rollout

No migration. No schema version, no `VersionedSchema` change, no `MetadataMigrationPlan` stage: #4
changes **how many** containers open `PersistenceContainer.defaultURL()`, not the file, the schema or
its contents. Revert = revert the branch.

## Size forecast

| Bucket | Lines |
|---|---|
| src (#1 ~10, #2 ~12, #3 ~25, #4 ~55, #5 ~50, #6 ~30, #7 ~55, #8–#10 ~12) | ~250 |
| tests | ~450–650 |
| spec deltas (5 whole-block MODIFIED, 6 scenarios) | **331 measured** (was forecast ~260 — whole-block carry-forward floor) |
| SDD markdown (proposal + this + tasks + verify) | ~450–700 |
| **Candidate** | **~1,480–1,930 / 2,000** (validator-corrected with measured deltas) |

`Decision needed before apply: No`
`Chained PRs recommended: No`
`400-line budget risk: High` (against the default 400; **Low–Medium** against this project's declared 2,000)

Drop-first order if the candidate approaches 2,000: **#7, then #8**. Never #4 — it carries the
data-integrity tail. D6 and D9 add ~90 src lines over the proposal's estimate; that is bought back by
tests landing under the proposal's ~650, and both are the reason #3/#4/#5/#7 are provable at all.

## Open Questions

None. All six proposal decisions are settled (`#7130`); no probe gate blocks this slice; every fix is
in-repo, so no external-behaviour gate exists.
