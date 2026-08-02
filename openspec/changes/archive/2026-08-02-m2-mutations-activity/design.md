# Design: M2-2 — Mutations & Activity

## Technical Approach

Three layers, each one already implied by shipped code:

1. **A typed command vocabulary** (`MutationCommand`) in `BrewClient`, which is the only target that
   sees both `PackageID` and `BrewCommand`. It projects to argv and to nothing else.
2. **A read-only projection over `BrewRunner`'s existing `operations` dictionary.** The runner already
   stores everything a queue view needs — `process` (spawned yet?), `resolvedExit` (terminal?), `fault`,
   `isCancelling`. Phase is *derived* from those fields, never stored a second time. The FIFO gate (I2),
   the SIGINT→SIGTERM policy and the SIGKILL ban (M1 D4) are untouched.
3. **An `@MainActor @Observable OperationCenter`** built on the `InstalledStore` exemplar, which finally
   drives `InstalledMutationGate.begin()/end()` — the seam M2-1 shipped with zero callers.

The unifying idea is **the runner already knows; nobody else should re-derive it**. The activity UI is
presentational over rules unit-tested in the `swift test` inner loop.

Decisions are `D1…D12`; earlier ones are cited as `M1 D4`, `M2-1 D6`, `M2-1 D9`.

    UI intent ──▶ OperationCenter.submit(MutationCommand)
                       │ argv, never a string
                       ▼
                 BrewCommand.mutate([…]) ──▶ BrewRunner (FIFO gate, I2)
                       │                          │
                       │           queue: AsyncStream<QueueSnapshot> (derived phase)
                       ▼                          ▼
                 ActivityItem ◀── lines ──── BrewOperation
                  (log ring)  ◀── exit() ──▶ MutationOutcome.classify(exit, fault, stderr tail)
                       │
                       ├──▶ InstalledMutationGate.begin()/end()  (depth-counted)
                       │              │ terminals
                       │              ▼
                       │       InstalledRefreshCoordinator ──▶ InstalledStore.refresh
                       ▼
                 ActivityBar / ActivityDrawer (thin, app target)

## Architecture Decisions

### D1 — `MutationCommand` lives in `BrewClient`, and the package graph is what forces it

`BrewProcess` owns argv (`BrewCommand`) and must never learn what a package *is*: `PackageKind` lives in
`Catalog`, and `BrewProcess → Catalog` is the edge M2-1 D1 exists to forbid. So the typed vocabulary
lives in `BrewClient` — the only target that sees both — and lowers to `BrewCommand.mutate([…])`.

```swift
public enum MutationCommand: Sendable, Equatable {
    case install(PackageID), uninstall(PackageID), reinstall(PackageID), upgrade(PackageID)
    case zap(CaskID)                 // `--zap` is cask-only; a formula cannot spell it
    case upgradeAll                  // plain `brew upgrade`, brew defaults (product Q3)
    case pin(FormulaID), unpin(FormulaID)   // pinning is a formula concept in this slice
}
```

`FormulaID` / `CaskID` are thin wrappers with `init?(_ id: PackageID)` that fail on the wrong kind, so
"pin a cask" and "zap a formula" are **unrepresentable**, not validated at runtime — the same technique
`CatalogFilterBar.KindSelection` already uses for "neither kind selected".

| Case | argv |
|---|---|
| `install/uninstall/reinstall/upgrade(id)` | `[verb, "--formula"\|"--cask", id.name]` |
| `zap(cask)` | `["uninstall", "--cask", "--zap", cask.name]` |
| `upgradeAll` | `["upgrade"]` |
| `pin/unpin(f)` | `[verb, "--formula", f.name]` |

The `--formula`/`--cask` flag is **always explicit** on every command that names a package, so a name
existing in both namespaces can never resolve to the wrong one. There is **no exception**: `brew pin`
and `brew unpin` both document and accept `--formula`/`--cask` (live probe, brew 6.0.14), so one argv
composition rule covers all six verbs. `upgradeAll` carries no flag only because it names no package.

The typed `FormulaID` wrapper therefore does no argv work — it encodes the *product* decision that this
slice pins formulae only. Cask pinning is available in brew 6.0.14 and is deliberately out of scope
here; the wrapper is what makes adding it later a new case rather than a new validation path.

**Settled (user ruling, 2026-08-02): "upgrade selected" expands to one operation per selected package**
— `upgrade --formula wget`, `upgrade --formula git`, `upgrade --cask iterm2` — and the spec delta is
amended to match. There is no `upgradeSelected` case: the selection fans out into N ordinary
`.upgrade(id)` commands at submission, so the queue, the log, the copy-command affordance and cancel
all work on it with no special path.

| Option | Tradeoff | Decision |
|---|---|---|
| Kind-grouped multi-name argv (`upgrade --formula wget git`) | Fewer brew starts, but all-or-nothing cancel, one interleaved log for the group, and a single exit status that cannot attribute a mid-batch failure to a package | Rejected |
| **One operation per selected package** | One brew start each; per-item attribution, cancel, log and copy-command, and a mid-batch failure names exactly which package failed | **Chosen** |

"Upgrade all" remains the one bare invocation — no name, no kind flag — because product Q3 defines it
as literally `brew upgrade` with brew's own defaults.

### D2 — Names are argv-hardened at construction

Every name reaching argv comes from brew's own snapshot or the catalog, never from free text. Even so,
a token beginning with `-` would be parsed by brew as an option wherever it sits. `MutationCommand`'s
factories are failable and reject an empty name or one beginning with `-`. This is a threat-matrix
requirement (below), not a style choice: it is the one place option injection could enter.

### D3 — Queue observability is a derived projection plus one stored field

`OperationRecord` gains exactly two stored fields — `let command: BrewCommand` (so the snapshot can
carry verbatim argv) and `let ordinal: Int` (so a `[UUID: …]` dictionary can be rendered in submission
order). **No phase is stored**, because storing it would create a second source of truth that can drift
from `process`/`resolvedExit`:

```swift
public struct OperationSnapshot: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let command: BrewCommand              // argv verbatim — "copy command" reads this
    public enum Phase: Sendable, Equatable {
        case pending                             // gated; nothing spawned, cancel costs nothing
        case running
        case terminal(BrewExit, fault: BrewProcessError?)
    }
    public let phase: Phase                      // resolvedExit != nil ? .terminal : process != nil ? .running : .pending
}
public struct QueueSnapshot: Sendable, Equatable { public let operations: [OperationSnapshot] }
```

| Option | Tradeoff | Decision |
|---|---|---|
| Polled `snapshot()` only | Zero bookkeeping, but the UI needs a timer and shows stale phases | Kept as a *pull* companion, not the primary |
| Per-observer broadcast stream | Multi-consumer bookkeeping inside the actor, for one consumer | Rejected |
| **One `AsyncStream<QueueSnapshot>` made in `init`, `.bufferingNewest(1)`** | One stored continuation; yielded at the five sites where phase already changes (enqueue, install, spawn, terminal, cancel) | **Chosen** |

`.bufferingNewest(1)` is correct rather than merely cheap: these are *state snapshots*, so dropping an
intermediate one is lossless, and a slow UI can never back-pressure the actor. `queue` is a
`nonisolated let` of `Sendable` elements, so no isolation is crossed by reading it.

Accepted constraint: `operations` entries are never evicted (pre-existing — `exit(of:)` must stay
answerable after termination). Retention of what is *displayed* is `OperationCenter`'s job (D6), and
each record is small once its log stream drains. Recorded as a follow-up, not fixed here.

### D4 — `OperationCenter`: one `@MainActor @Observable` store, `InstalledStore`'s shape

Per submission it holds an `ActivityItem` (id, command, display string, phase, bounded log, outcome),
starts one task draining `operation.lines` into a **2,000-line ring** with a truncation marker, awaits
`exit()`, classifies (D5) and settles the gate. The runner arrives after detection, so
`attach(installation:)` builds it; a submission with no runner is refused as a terminal item rather
than a silent no-op, and repointing `brew` builds a new runner while in-flight items keep the old one
alive until they settle.

### D5 — Outcome classification is a pure function over untrusted output

```swift
static func classify(exit: BrewExit, fault: BrewProcessError?, stderrTail: [String]) -> MutationOutcome
```

Order: `fault` → `.launchFailed` / `.abandoned(after:)`; `exit.isCancelled` → `.cancelled`;
`exit.isSuccess` → `.succeeded`; then signature matching on the **last 20 `.stderr` lines only**:

| Outcome | Signature | Confidence |
|---|---|---|
| `.busy` | `"has already locked"` **or** `"Please wait for it to finish or terminate it to continue"` | **Verified live** (probe #7097, exit 1) |
| `.needsPrivileges` | `"sudo: no tty present"`, `"sudo: a password is required"`, `"Password:"` | Heuristic, **unprobed** |
| `.failed(status:)` | everything else | — |

Two safety properties make the heuristic acceptable. First, classification **only ever changes the
sentence shown** — never a retry, never an escalation, never an argv — so a false positive is a wrong
message, not a wrong action, and a false negative degrades to `.failed` with the full streamed log
already on screen (product Q1). Second, per probe #7097 brew names the blocking process after *its own*
invocation, not the real holder, so the busy message is rendered from Cellar's own command and brew's
guessed command name is **never parsed or displayed**. Both are RED tests.

### D6 — Confirmation, copy, cancel

`requiresConfirmation` is `true` for `.uninstall` and `.zap` and false for everything else (product Q2).
The sheet and the "copy command" affordance both render `"brew " + arguments.joined(separator: " ")`.
That string is **display only**: there is no path that parses it back into argv, which is what keeps the
rendering incapable of changing what runs.

Cancel keeps the shipped semantics: a `.pending` item resolves without ever spawning; a `.running` item
gets SIGINT→SIGTERM and never SIGKILL (M1 D4). Every cancelled item shows one generic line (product Q5)
— *"Cancelled. Homebrew may have left a partial change; refreshing now."* — and the forced re-snapshot
follows from D7 for free. The one case that gets its own sentence is `.abandoned`, mapped from the
existing `.cancelledUnresponsive` fault: brew ignored both signals and is still running outside Cellar,
which is a materially different fact and already carried by the runner. Queue control is cancel-only;
nothing reorders or removes (product Q6, and I2 stays immutable).

### D7 — The gate becomes depth-counted; every terminal forces a re-snapshot

`InstalledMutationGate` keeps its API and gains a depth: `begin()` increments, `end()` decrements with a
floor of zero and **always** yields one terminal. So `isMutating` covers the whole batch — a quiet
window between two queued mutations no longer wastes a refresh — while N terminals still produce N
re-snapshots, which is the success criterion stated verbatim. Overlapping refreshes are absorbed by
`InstalledStore`'s existing single-flight slot and ordinal guard (M2-1 D6).

### D8 — The four absorbed M2-1 defects, with mechanics

| # | Defect | Fix |
|---|---|---|
| a | Coordinator checks `isMutating` at *signal* time; a mutation starting inside the 2 s window still fires a refresh mid-install | `waitOutTheQuietWindow()` re-checks the gate **after** the sleep and drops the refresh — the terminal will force one anyway. The debounce `Task` is now stored in `debounceTask` and cancelled when `run()`'s group ends, which is what makes the existing `Task.isCancelled` guards reachable instead of dead code |
| b | A change signal arriving mid-acquisition joins a probe that started *before* the change, so the change is lost | `InstalledStore` gains a monotonic `invalidationCount` and `public func invalidate()`. Each `InFlightRefresh` records the mark it started at; a refresh joins only when `current.mark >= mark` **and** the request URL matches. The coordinator calls `invalidate()` on every signal and every mutation terminal |
| c | `clear(to:)` strands the in-flight slot, so `.brewAbsent` can be answered later by pre-clear data | `clear(to:)` now cancels the in-flight task and vacates the slot before bumping the ordinal. The ordinal guard still discards any late answer, so cancellation is belt-and-braces, not the load-bearing part |
| d | Kind / deprecated / disabled controls are inert under Browse's `installed` and `outdated` modes | `InstalledBrowse.rows(…)` takes `SearchFilters`. `kinds` filters on `InstalledPackage.kind` (the inventory is authoritative). `excludeDeprecated`/`excludeDisabled` are **catalog** predicates — the inventory projection carries neither — so they are applied through the `catalogLookup` decoration already passed in, with *no catalog record ⇒ not excluded*: a third-party-tap package is never hidden by a flag nothing published (the II3 principle). The picker stays enabled; no control lies |

Also cheap and taken while the file is open: `FSEventsInstalledObserver.changes()` is non-idempotent —
a second call silently leaks the first stream and its retained box. `start(yielding:)` now calls
`stop()` first (last caller wins), and `stop()` takes the `Watcher` out **under** the lock and tears it
down **outside** it before finishing the old continuation — the `SystemProcess` compute-under-lock,
act-outside precedent. Doing it the other way would re-enter the non-recursive `Mutex` through
`onTermination` and trap.

Still open, explicitly not fixed here: `skippedRecordCount` is never surfaced; runner records are never
evicted (D3).

### D9 — `CellarTestSupport` is a dependency-free target, which is what lets it exist

```swift
.target(name: "CellarTestSupport", swiftSettings: [.swiftLanguageMode(.v6)])
```

`TestClock` needs only `Synchronization` and `TestPoll` needs only the stdlib — neither imports
`Testing` or any package target — so the target declares **no dependencies**, satisfying M2-0 D5 as
written. It is a `.target`, not a product, and appears only in the three test targets' `dependencies`,
so nothing links it into the app. Members become `public`; the three copies are deleted. This is why
`FakeProcessLauncher` still cannot move there (it conforms to a `BrewProcess` protocol) — the boundary
that blocked M2-1 D2 is unchanged.

### D10 — Activity UI is an inset, not a sheet, and owns no rules

`ContentView` gains `.safeAreaInset(edge: .bottom) { ActivityBar(center: center) }`, hidden entirely
when the center is empty. The bar shows the running command, a pending count and cancel; tapping
expands the same inset into `ActivityDrawer` — an inset rather than a sheet because a mutation is
background work and a sheet would hold the app hostage. Every rule the views need (what to show, which
sentence, whether cancel is offered, whether confirmation is required) is a computed property on
`OperationCenter` / `ActivityItem` / `MutationCommand` in `BrewClient`, unit-tested without a build of
the app target.

### D11 — File layout under the 400-line limit

`BrewRunner.swift` is 372 lines today and the projection adds ~45. Rather than weaken `private var
operations` so an extension in another file could reach it, `BrewOperation` (~30 lines) and
`mapLaunchFailure` (~25) move out to `BrewOperation.swift`, leaving the runner at ~390 with the
projection inside the same file as the state it derives from.

### D12 — Everything through fakes; nothing mutates a real Homebrew

**No test spawns `brew`, and no test performs a mutation.** Every runner behaviour is exercised through
`FakeProcessLauncher`; every classification is a pure function over synthesised `[LogLine]`. The lock
and sudo surfaces are covered by the *strings* probe #7097 captured, not by re-creating the conditions.
Untested-by-design: the FSEvents adapter (unchanged rationale, M2-1 D12) and the SwiftUI views, whose
rules were moved into the package precisely so the untested part is layout only.

## File Changes

| File | Action | Description |
|---|---|---|
| `Sources/BrewProcess/BrewRunner.swift` | Modify | `command`/`ordinal` fields, derived projection, `queue` stream, five yield sites |
| `Sources/BrewProcess/BrewOperation.swift` | Create | `BrewOperation` + `mapLaunchFailure` moved out (D11) |
| `Sources/BrewProcess/OperationSnapshot.swift` | Create | `OperationSnapshot`, `Phase`, `QueueSnapshot` |
| `Sources/BrewClient/MutationCommand.swift` | Create | D1/D2 vocabulary, `FormulaID`/`CaskID`, argv, `requiresConfirmation`, `displayCommand` |
| `Sources/BrewClient/MutationOutcome.swift` | Create | Outcome enum + pure `classify` (D5) |
| `Sources/BrewClient/ActivityItem.swift` | Create | Item, bounded log ring, presentation rules |
| `Sources/BrewClient/OperationCenter.swift` | Create | D4 store, gate driving, cancel |
| `Sources/BrewClient/InstalledChangeObserving.swift` | Modify | Depth-counted gate (D7); coordinator re-check + owned debounce task (D8a) |
| `Sources/BrewClient/InstalledStore.swift` | Modify | `invalidate()` + mark-guarded join (D8b); `clear(to:)` vacates and cancels (D8c) |
| `Sources/BrewClient/InstalledFilterMode.swift` | Modify | `rows(…)` takes `SearchFilters` (D8d) |
| `Sources/BrewClient/FSEventsInstalledObserver.swift` | Modify | Idempotent `changes()`, teardown outside the lock |
| `Sources/CellarTestSupport/{TestClock,TestPoll}.swift` | Create | D9 |
| `Tests/{BrewProcess,Catalog,BrewClient}Tests/Fakes/TestClock.swift`, `…/TestPoll.swift` | Delete | Replaced by D9 |
| `Package.swift` | Modify | New target + three test dependencies |
| `Tests/BrewProcessTests/QueueProjectionTests.swift` | Create | D3 |
| `Tests/BrewClientTests/{MutationCommandTests,ClassificationTests,OperationCenterTests}.swift` | Create | D1/D2/D5/D4 |
| `Tests/BrewClientTests/{InstalledRefreshTests,InstalledStoreTests,BrowseCompositionTests}.swift` | Modify | D8a–d |
| `cellar/Activity/{ActivityBar,ActivityDrawer,ActivityLogView,MutationConfirmation}.swift` | Create | D10 |
| `cellar/{ContentView,cellarApp}.swift` | Modify | Own the center, attach the installation, bottom inset |
| `cellar/Installed/{InstalledListView,InstalledRow}.swift`, `cellar/Browse/{PackageDetailView,BrowseView,CatalogFilterBar}.swift` | Modify | Mutation affordances; filters threaded into `rows(…)` |
| `cellar.xcodeproj/project.pbxproj` | Modify | New Activity group |

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit — argv | Every case's exact vector, `--formula`/`--cask` present on every package-naming command including `pin`/`unpin`, `zap` cask-only, `upgradeAll == ["upgrade"]` with no flag and no name | Parameterised over `MutationCommand` |
| Unit — argv hardening | A name beginning with `-` or empty is refused at construction | Failable factories |
| Unit — projection | Queued mutation reads `.pending` and spawns nothing; predecessor terminal flips it to `.running`; submission order preserved; snapshot carries verbatim argv; a slow consumer sees the newest snapshot | `FakeProcessLauncher` + `queue` stream |
| Unit — classification | Probe #7097 stderr → `.busy`; a busy message naming an unrelated command still classifies busy and its command name never appears in the rendered text; sudo signature → `.needsPrivileges`; unrecognised failure → `.failed` with log intact; `.cancelled` and `.abandoned` never misread as failure | Pure function, synthesised `[LogLine]` |
| Unit — center | Gate `begin()` once for a batch, `end()`/terminal per item; a selection of N packages fans out into exactly N operations in selection order, each carrying its own kind flag; one failing mid-batch item attributes to that package and does not fail its siblings; cancel of a pending item produces the generic sentence and spawns nothing; log ring truncates at 2,000 with a marker; submission with no runner is a terminal item | Fake launcher + `InstalledMutationGate` |
| Unit — D8a | A mutation starting inside the quiet window suppresses the debounced refresh; cancelling the debounce task prevents it | `TestClock` |
| Unit — D8b | A signal during an in-flight acquisition starts a **new** acquisition instead of joining the stale one | Counting fake source + `invalidate()` |
| Unit — D8c | Brew going absent mid-acquisition leaves `.brewAbsent` resident and the slot empty; a later refresh is adopted normally | Scripted source |
| Unit — D8d | Kind, deprecated and disabled all change the row set under `installed`/`outdated`; a row with no catalog record is never hidden by a catalog flag | `InstalledBrowse` with injected lookup |
| Unit — observer | Two `changes()` calls leave exactly one live stream; teardown does not re-enter the mutex | Construction-level |
| Regression | Full suite green, zero concurrency warnings, three `TestClock` copies gone | `swift test --package-path Packages/CellarCore` |
| Integration (app) | Builds and links; activity bar hidden with nothing running | `xcodebuild` only — no live-brew mutation test exists anywhere |

Every component is RED-first: the failing test precedes its production change.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A — nothing is classified or executed by path | — | — |
| Git repository selection / commit / push / PR commands | N/A — no VCS or PR automation | — | — |
| **Subprocess argument composition** | **Applicable** — seven new `brew` verbs, all state-changing | argv only, element-by-element through the process seam; no shell, no string joining, no interpolation. Kind flag always explicit. Names are brew-derived and additionally rejected at construction when empty or `-`-prefixed (D2). `displayCommand` is one-way: nothing parses it back | Exact `ProcessSpec.arguments` per command; `kind == .mutate`; option-looking name refused; a display string is never a source of argv |
| **Untrusted subprocess payload as classification input** | **Applicable** — stderr decides which sentence the user sees | Matching is confined to the last 20 `.stderr` lines and can change **only** the message — never a retry, an escalation or an argv. Unmatched output degrades to `.failed` with the full log visible. brew's guessed command name is never parsed (probe #7097) | Adversarial stderr containing `Password:` inside package output; busy text naming another command; multi-megabyte log |
| **Privilege boundary** | **Applicable** — casks that invoke `sudo` | `standardInput = /dev/null` is unchanged, so brew can never block on a prompt Cellar cannot answer. No askpass, no helper, no escalation: the operation fails and the user is directed to Terminal (product Q1) | A sudo-signature run terminates rather than hangs, and offers no in-app credential path |
| **Irreversible mutation scope** | **Applicable** — `uninstall` and `zap` destroy user data | Confirmation required for exactly those two, showing the exact command; no bulk destructive path exists (`upgradeAll` is the only bulk command and is non-destructive); FIFO serialization means no destructive command runs concurrently with anything | `requiresConfirmation` is true for `.uninstall`/`.zap` and false for all others; `zap` is unrepresentable for a formula |

No new file location, no network call, no persisted format.

## Migration / Rollout

No migration. Nothing persisted changes; the inventory and the activity list are in-memory derived data.
Rollback is a revert of the feature branch: the runner changes are additive, and
`InstalledMutationGate` returns to its unused-but-tested M2-1 state.

## Review Budget Forecast

**~3,600–4,400 authored lines** (production ~1,200, tests ~1,500, app UI ~650, package/project ~60),
against the accepted `size:exception` for one PR (product Q4). If the exception is withdrawn at the
tasks forecast, the clean cut is **D8 + D9 alone as PR #1** (the four absorbed defects plus the test-
support extraction, ≈900 lines, independently shippable and independently valuable), leaving
D1–D7 + D10–D12 as PR #2.

## Open Questions

- [ ] **Sudo signature text is unprobed.** Unlike the lock surface, no live sudo-requiring cask was
      exercised. Mitigated by design — a miss degrades to `.failed` with the log visible — but the exact
      strings should be confirmed opportunistically and the set widened without a design change.
- [ ] **Runner record eviction.** `operations` still grows for the process lifetime (D3). Small per
      record once logs drain, but it should get a bounded retention policy when M2-3 adds history.
