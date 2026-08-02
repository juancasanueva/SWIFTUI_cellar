# Tasks: M2-2 — Mutations & Activity

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 4,000–5,000 authored (phase sums ≈ 4,300; design forecast 3,600–4,400) |
| Default review budget | 400 lines |
| Repo `review_budget_lines` (`openspec/config.yaml`) | 800 lines |
| Session `review_budget_lines` | 1,500 lines |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR under the accepted `size:exception`; **Phases 1 + 2** (D9 + D8, ≈ 1,040 lines) are the pre-agreed cut point |
| Delivery strategy | single-pr with an accepted `size:exception` (effective `exception-ok`) |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

**Honest reading, for the orchestrator.** ≈ 2.9× the 1,500-line session budget, ≈ 5.4× the repo's
own `review_budget_lines: 800`, ≈ 11× the default 400. The `size:exception` is already accepted
(product Q4, Engram #7094), so apply is **not** blocked and no decision is owed — but this is the
largest single change in the project's history and the number is stated plainly rather than
absorbed.

Calibration, and where M2-1 went wrong. M2-1 forecast 2,400–2,800 and landed 4,918 (1.8×). The
error was almost entirely the test ratio: its design assumed tests ≈ 0.58× production, actuals came
in at **1.19×**, because strict TDD demands a RED per scenario and both threat rows earned their own
suites. This forecast applies **1.2× production** to a ~1,330-line non-UI production estimate
(≈ 1,600 test lines) instead of copying M2-1's optimism. Residual risk that remains unpriced:
M2-1's *production* also overran its design by ~38% (`Sources/BrewClient/` 1,451 against ~1,050), and
Phase 7 (`OperationCenter`) is the same kind of surface. Treat 5,000 as likely, not as the tail.

Line counts below exclude `openspec/` artifacts. Generated goldens: none in this change.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | `CellarTestSupport` extraction, three `TestClock` copies deleted (Phase 1) | PR 1 | `FAST` | N/A — test-only target, never linked into the app; no runtime surface exists | Revert the `Package.swift` hunk and restore the three `Fakes/TestClock.swift` copies; no `Sources/` file moves |
| 2 | The four absorbed M2-1 defects + FSEvents idempotency (Phase 2) | PR 1 (**or PR 2 if cut**) | `FAST --filter "InstalledRefresh\|InstalledStore\|InstalledFilter"` | With the app running: `brew install <small formula>` in Terminal → exactly one refresh after the quiet window; toggle Kind/deprecated/disabled under Browse's Installed mode → the row set changes | Revert the `InstalledChangeObserving`/`InstalledStore`/`InstalledFilterMode`/`FSEventsInstalledObserver` hunks; all four are additive to shipped behaviour |
| 3 | Mutation vocabulary + outcome classification (Phases 3–4) | PR 1 | `FAST --filter "MutationCommand\|Classification"` | N/A — pure functions with no process and no I/O; the runtime boundary appears only at Unit 5 | Delete `Sources/BrewClient/{MutationCommand,MutationOutcome}.swift` and their two suites; nothing else references them yet |
| 4 | `BrewRunner` pure-move split + queue projection (Phases 5–6) | PR 1 | `FAST --filter "QueueProjection\|Serialization\|Cancellation"` | Not user-visible until Unit 6; proven by the existing `BrewIntegrationTests` staying green against real `brew` | Revert `BrewOperation.swift`/`OperationSnapshot.swift` creation and the `BrewRunner` hunk; the FIFO gate and cancellation policy are untouched, so revert restores M1 behaviour exactly |
| 5 | `OperationCenter`, `ActivityItem`, depth-counted gate (Phase 7) | PR 1 | `FAST --filter "OperationCenter\|ActivityItem"` | `brew install hello` **from Cellar**: one queue item, live log, exactly one re-snapshot at the terminal outcome | Delete `Sources/BrewClient/{ActivityItem,OperationCenter}.swift` and revert the gate depth hunk; `InstalledMutationGate` returns to its unused-but-tested M2-1 state |
| 6 | Activity UI and mutation affordances (Phase 8) | PR 1 | `FULL` | Launch with nothing queued → the bar is absent; submit an install → the bar appears, expands, streams, cancels | Revert `cellar/Activity/**`, the `ContentView`/`cellarApp`/`Installed`/`Browse` hunks and the `project.pbxproj` group |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Requirement tags: `PM1..PM7` (package-mutation ADDED, delta order), `OA1..OA5` (operation-activity
  ADDED, delta order), `BE1` (brew-execution MODIFIED — "Serialized mutations with concurrent reads"),
  `II8` / `II10` (installed-inventory MODIFIED — filter composition, external-change invalidation).
- Design decisions are `D1..D12`; M1/M2-1 decisions are cited as `M1 D4`, `M2-1 D6`.
- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `openspec/` or `cellar.xcodeproj/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests`.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No
  production line without a red test. Phase 8 (app-target SwiftUI) is xcodebuild-only and sits
  outside the `FAST` inner loop — which is exactly why every rule it needs is a computed property in
  `BrewClient` (D10).
- SwiftLint `file_length` warns at 400. `BrewRunner.swift` is 372 today; Phase 5 is the pure-move
  that buys the room Phase 6 spends.
- Design names the D8d test file `BrowseCompositionTests.swift`; the shipped file is
  `Tests/BrewClientTests/InstalledFilterTests.swift` and that is what Phase 2 extends.
- `TestPoll` exists in **one** copy (`Tests/BrewClientTests/Fakes/`), not three; only `TestClock` is
  triplicated. Design's delete row over-counts by two files.
- **No test spawns `brew` and no test performs a mutation** (D12). Every runner behaviour goes
  through `FakeProcessLauncher`; every classification is a pure function over synthesised `[LogLine]`.
- **Sequencing.** Phases run in order; tasks inside a phase are sequential (RED strictly before its
  GREEN). Two independent tracks exist once Phase 1 lands and **may** be worked in parallel by a
  single writer if useful, since they share no file: **track A** = Phase 2 (`BrewClient` inventory
  fixes), **track B** = Phases 3–4 (`BrewClient` mutation vocabulary) and Phases 5–6 (`BrewProcess`).
  Phase 7 joins both tracks and cannot start before either completes. Phase 8 needs Phase 7. Phase 9
  needs everything. Do **not** run parallel writers in separate worktrees — the tracks reconverge on
  `InstalledChangeObserving.swift` at 7.11.

---

## Phase 0: Baseline (blocking, no production change)

- [x] 0.1 Record the green baseline on `main` @ `2fe1c0d`: `FAST`, `FULL`, `swiftlint`. Capture the
  `@Test` / suite counts so Phase 9 can prove nothing was deleted, and the `swiftlint` finding count
  so new findings are separable from the 11 pre-existing ones.

## Phase 1: `CellarTestSupport` (D9 — M2-0 D5) — ≈ 390 lines — **cut point with Phase 2**

Scheduled first so no new suite in Phases 2–7 mints a fourth `TestClock`.

- [x] 1.1 `Package.swift`: add `.target(name: "CellarTestSupport", swiftSettings: [.swiftLanguageMode(.v6)])`
  with **no dependencies** (that is what satisfies M2-0 D5), and add it to the `dependencies` of
  `BrewProcessTests`, `CatalogTests` and `BrewClientTests`. It is a `.target`, not a `.library`
  product, so nothing links it into the app.
- [x] 1.2 Create `Sources/CellarTestSupport/TestClock.swift` and `Sources/CellarTestSupport/TestPoll.swift`
  by moving the `Tests/BrewClientTests/Fakes/` copies verbatim and raising members to `public`.
  `TestClock` imports only `Synchronization`; `TestPoll` imports only the stdlib. Neither imports
  `Testing` or any package target.
- [x] 1.3 Delete `Tests/{BrewProcess,Catalog,BrewClient}Tests/Fakes/TestClock.swift` and
  `Tests/BrewClientTests/Fakes/TestPoll.swift`; add `import CellarTestSupport` at every use site.
  Verify: `FAST` green with the Phase 0 test count intact, and
  `rg -c 'struct TestClock' Packages/CellarCore` returns exactly one file.
- [x] 1.4 `FakeProcessLauncher` **stays** in `Tests/BrewProcessTests/Fakes/` — it conforms to a
  `BrewProcess` protocol, so moving it would give `CellarTestSupport` a dependency. Record this as a
  deliberate non-move, not an oversight (D9).

## Phase 2: The four absorbed M2-1 defects + FSEvents idempotency (D8 — II10, II8) — ≈ 650 lines — **cut point with Phase 1**

Independent of the mutation command layer; reviewable standalone.

- [x] 2.1 RED `Tests/BrewClientTests/InstalledRefreshTests.swift` (D8a — II10 sc5): a change signal
  opens the quiet window; a mutation begins **before** the window elapses; the window then elapses
  while the mutation is in flight → **no** re-snapshot runs, and exactly one runs at the mutation's
  terminal outcome. Second case: cancelling the debounce task prevents the pending refresh entirely.
- [x] 2.2 GREEN `Sources/BrewClient/InstalledChangeObserving.swift`: `waitOutTheQuietWindow()`
  re-checks the gate **after** the sleep and drops the refresh (the terminal owes one anyway). Store
  the debounce `Task` in `debounceTask` and cancel it when `run()`'s group ends — that is what makes
  the existing `Task.isCancelled` guards reachable instead of dead code.
- [x] 2.3 RED `Tests/BrewClientTests/InstalledStoreTests.swift` (D8b — II10 sc6): with a counting
  scripted source, an acquisition is in flight against payload `P1`; a signal arrives **after** it
  started and the payload is now `P2` → a further invocation is performed after the quiet window and
  the inventory reflects `P2`, not `P1`. A signal that arrived *before* the acquisition still joins it.
- [x] 2.4 GREEN `Sources/BrewClient/InstalledStore.swift`: a monotonic `invalidationCount` and
  `public func invalidate()`. Each `InFlightRefresh` records the mark it started at; a later caller
  joins only when `current.mark >= mark` **and** the request URL matches (M2-1 D6's key is kept, not
  replaced). `InstalledRefreshCoordinator` calls `invalidate()` on every signal and every mutation
  terminal.
- [x] 2.5 RED `InstalledStoreTests` (D8c — II10 sc7): an acquisition is in flight and has not
  settled; `clear(to:)` resets the store to `.brewAbsent`; a later valid refresh performs an
  invocation and publishes its snapshot → the inventory does not stay empty, and `.brewAbsent` is
  never answered by pre-clear data.
- [x] 2.6 GREEN `InstalledStore.clear(to:)`: cancel the in-flight task and vacate the slot **before**
  bumping the ordinal. The ordinal guard still discards any late answer, so the cancellation is
  belt-and-braces rather than load-bearing.
- [x] 2.7 RED `Tests/BrewClientTests/InstalledFilterTests.swift` (D8d — II8 sc6–7): under
  `installed` mode over an inventory of one formula and one cask, one deprecated — kind, deprecated
  and disabled each change the visible rows (or report themselves unavailable for the mode); under
  `outdated` mode the kind control applied to casks leaves only the cask. Plus the II3 principle: a
  row whose package has **no catalog record** is never hidden by a catalog-only flag.
- [x] 2.8 GREEN `Sources/BrewClient/InstalledFilterMode.swift`: `InstalledBrowse.rows(…)` takes
  `SearchFilters`. `kinds` filters on `InstalledPackage.kind` (the inventory is authoritative).
  `excludeDeprecated` / `excludeDisabled` are **catalog** predicates and are applied through the
  `catalogLookup` decoration already passed in, with *no catalog record ⇒ not excluded*. The picker
  stays enabled; no control lies.
- [x] 2.9 RED `Tests/BrewClientTests/InstalledObserverTests.swift` (new, construction-level): two
  `changes()` calls on one `FSEventsInstalledObserver` leave exactly **one** live stream — the first
  is finished, not leaked — and teardown completes without trapping.
- [x] 2.10 GREEN `Sources/BrewClient/FSEventsInstalledObserver.swift`: `start(yielding:)` calls
  `stop()` first (last caller wins). `stop()` takes the `Watcher` out **under** the lock and tears it
  down **outside** it, then finishes the old continuation — the `SystemProcess` compute-under-lock,
  act-outside precedent. **Trap to avoid:** finishing the continuation inside the lock re-enters the
  non-recursive `Mutex` through `onTermination` and traps.
  Verify: `FAST --filter "InstalledRefresh\|InstalledStore\|InstalledFilter\|InstalledObserver"`.

## Phase 3: Mutation vocabulary and argv (D1, D2 — PM1, PM2, PM3, PM7) — ≈ 500 lines

- [x] 3.1 RED `Tests/BrewClientTests/MutationCommandTests.swift`, parameterised over every case —
  **threat: subprocess argument composition**. Assert the exact recorded `ProcessSpec.arguments`:
  `install --formula wget` (PM1 sc1), `install --cask iterm2` (sc2), `uninstall --cask iterm2`
  (sc3), `reinstall/pin/unpin --formula git` (sc4), `upgrade --formula wget` (PM2 sc1),
  `uninstall --cask --zap iterm2`, and `upgrade` alone for `upgradeAll` — **no name, no kind flag,
  no `--greedy` variant, no `--force`** (PM2 sc3). Also: `kind == .mutate` on every one of them; no
  invocation carries both kind flags; the `docker` collision resolves by flag, never by brew's token
  disambiguation (PM1 sc5).
- [x] 3.2 GREEN `Sources/BrewClient/MutationCommand.swift`: the `MutationCommand` enum (D1),
  `FormulaID` / `CaskID` with failable `init?(_ id: PackageID)`, and `var arguments: [String]`
  lowering to `BrewCommand.mutate([…])`. The kind flag is explicit on all six package-naming verbs —
  **including `pin`/`unpin`**, confirmed by live `brew pin --help` / `brew unpin --help` on 6.0.14.
  There is no per-verb exception.
- [x] 3.3 RED `MutationCommandTests` — **threat: subprocess argument composition (option injection)**:
  a name that is empty or begins with `-` is **refused at construction**, so no argv is ever built
  from it. Separately: `zap` is **unrepresentable** for a formula and `pin` for a cask — the failable
  wrapper is the proof, not a runtime `guard` (threat: irreversible mutation scope).
- [x] 3.4 GREEN the failable factories on `MutationCommand` (D2). This is the one place option
  injection could enter, so it is a rejection at the type boundary, not a validation deeper in.
- [x] 3.5 RED `MutationCommandTests` — **threat: irreversible mutation scope**: `requiresConfirmation`
  is `true` for exactly `.uninstall` and `.zap` and `false` for install, reinstall, upgrade,
  `upgradeAll`, pin and unpin (PM3 sc4). `displayCommand` renders
  `"brew " + arguments.joined(separator: " ")` and matches the argv character for character
  (PM3 sc1, sc3; OA2 sc1).
- [x] 3.6 GREEN `requiresConfirmation` and `displayCommand` on `MutationCommand` (D6).
- [x] 3.7 RED `MutationCommandTests` — **threat: display string is never a source of argv**: assert
  no public API accepts a command *string* and produces argv; the only argv producer is
  `MutationCommand.arguments` over the typed cases. A structural/grep-style assertion is acceptable
  here; the point is that `displayCommand` is one-way.
- [x] 3.8 GREEN: no production change expected. A failure here means a string→argv path leaked in.
  Verify: `FAST --filter MutationCommand`.

## Phase 4: Outcome classification (D5 — PM4, PM5, PM6) — ≈ 400 lines

- [x] 4.1 RED `Tests/BrewClientTests/ClassificationTests.swift` (PM5 sc1) — the live-probed surface
  (#7097): stderr carrying ``Error: A `brew uninstall hello` process has already locked
  /opt/homebrew/Cellar/hello.`` followed by `Please wait for it to finish or terminate it to
  continue.` with exit 1 → `.busy`, and the message tells the user Homebrew is busy in another
  terminal.
- [x] 4.2 RED `ClassificationTests` (PM5 sc2) — **threat: untrusted subprocess payload**: the same
  busy text naming an **unrelated** command still classifies busy, **and that command name never
  appears in the rendered text**. Per probe #7097 brew names its own invocation, not the real holder,
  so parsing a holder out of it would print a lie.
- [x] 4.3 RED `ClassificationTests` (PM5 sc3): exit 1 with output containing neither lock phrase is
  `.failed`, never `.busy`.
- [x] 4.4 GREEN `Sources/BrewClient/MutationOutcome.swift`: the `MutationOutcome` enum and the pure
  `static func classify(exit:fault:stderrTail:) -> MutationOutcome`. Order: `fault` →
  `.launchFailed` / `.abandoned(after:)`; `exit.isCancelled` → `.cancelled`; `exit.isSuccess` →
  `.succeeded`; then signature matching on the **last 20 `.stderr` lines only**.
- [x] 4.5 RED `ClassificationTests` (PM4 sc1) — **threat: privilege boundary**: output carrying
  `sudo: no tty present`, `sudo: a password is required` or `Password:` with a non-zero exit →
  `.needsPrivileges`, whose guidance echoes the exact command to run in Terminal and names the
  package. Assert there is **no** in-app credential surface, no retry, and no escalation path
  anywhere in the outcome's API.
- [x] 4.6 RED `ClassificationTests` (PM4 sc3) — **threat: untrusted payload, adversarial**: a
  *successful* run whose stdout happens to contain `Password:` inside package output is **not**
  `.needsPrivileges`; an unrecognised non-zero failure degrades to `.failed(status:)` with the full
  log preserved verbatim and untruncated; a multi-megabyte log classifies in bounded time because
  only the 20-line tail is scanned.
- [x] 4.7 GREEN the sudo and fallback branches. Record in the file header the two safety properties
  that make the heuristic acceptable: classification changes **only the sentence shown** — never a
  retry, an escalation or an argv — so a false positive is a wrong message and a false negative
  degrades to `.failed` with the log on screen.
- [x] 4.8 RED `ClassificationTests` (PM6): `.cancelled` and `.abandoned` are never misread as
  failure; the cancelled message is **one generic sentence for every command**, does not claim the
  change was undone, and admits possible partial state (PM6 sc3). `.abandoned` — mapped from the
  existing `.cancelledUnresponsive` fault — gets its own distinct sentence.
- [x] 4.9 GREEN the cancel/abandon messaging on `MutationOutcome` (D6).
  Verify: `FAST --filter Classification`.

## Phase 5: `BrewRunner` pure-move split (D11) — ≈ 120 lines — **no behaviour change**

Must land before Phase 6: `BrewRunner.swift` is 372 lines and the projection adds ~45, which would
breach SwiftLint's 400-line `file_length`.

- [x] 5.1 Create `Sources/BrewProcess/BrewOperation.swift` and move `BrewOperation` (~30 lines) and
  `mapLaunchFailure` (~25 lines) into it **verbatim** — no rename, no signature change, no
  visibility change. `private var operations` is deliberately **not** weakened: the projection stays
  in the same file as the state it derives from.
- [x] 5.2 Verify the move is behaviour-free: `FAST` green with the Phase 0 test count unchanged, and
  `git diff --stat` shows only the two moved symbol bodies. No RED precedes this task because no
  behaviour changes — record that explicitly rather than faking a red test.

## Phase 6: Queue projection (D3 — BE1, OA1, OA3, OA4) — ≈ 390 lines

- [x] 6.1 RED `Tests/BrewProcessTests/QueueProjectionTests.swift` (BE1 sc4, sc6; OA1 sc1) with
  `FakeProcessLauncher`: mutation A in flight, B then C submitted → enumeration reports A running and
  B, C pending **in submission order**, each entry carrying the argv its operation was submitted
  with. Enumerating repeatedly while A runs spawns nothing extra and does not change the post-A start
  order (BE1 sc6 — enumeration is read-only and never blocks on the in-flight operation).
- [x] 6.2 GREEN `Sources/BrewProcess/OperationSnapshot.swift`: `OperationSnapshot` (`id`, `command`,
  `Phase`), `Phase { pending, running, terminal(BrewExit, fault:) }`, and `QueueSnapshot`. Phase is
  **derived** — `resolvedExit != nil ? .terminal : process != nil ? .running : .pending` — and never
  stored, so it cannot drift from `process`/`resolvedExit`.
- [x] 6.3 GREEN `Sources/BrewProcess/BrewRunner.swift`: `OperationRecord` gains exactly two stored
  fields, `let command: BrewCommand` and `let ordinal: Int`, plus a `snapshot()` projection ordered
  by ordinal. The FIFO gate (I2), the SIGINT→SIGTERM policy and the SIGKILL ban (M1 D4) are untouched.
- [x] 6.4 RED `QueueProjectionTests` (BE1 sc5; OA1 sc2, sc4): the same command submitted twice yields
  two **different** identities, each stable across pending → running → terminal; a terminal operation
  stays enumerable afterwards with its outcome, and enumerating it restarts nothing.
- [x] 6.5 GREEN: identity is the existing per-operation `UUID`, asserted stable — expected to be a
  no-op on the runner. A failure here means identity is being minted per enumeration.
- [x] 6.6 RED `QueueProjectionTests` (OA1 sc3; OA3 sc1–2): the snapshot carries verbatim argv while
  pending **and** once terminal; a running operation's lines are readable before it exits, tagged
  stdout/stderr, in emission order, with no trimming, reordering, deduplication or prefixing.
- [x] 6.7 RED `QueueProjectionTests`: a **slow consumer** of the `queue` stream sees the newest
  snapshot rather than a backlog, and the actor is never back-pressured by it.
- [x] 6.8 GREEN the `queue: AsyncStream<QueueSnapshot>` made in `init` with `.bufferingNewest(1)`,
  one stored continuation, yielded at the five sites where phase already changes: enqueue, install,
  spawn, terminal, cancel. `queue` is a `nonisolated let` of `Sendable` elements, so reading it
  crosses no isolation. Dropping an intermediate state snapshot is lossless by construction.
- [x] 6.9 RED `QueueProjectionTests` (BE1 sc3; OA4 sc1–2): cancelling a **pending** operation spawns
  no process and resolves it cancelled; cancelling the **running** one reports cancelled rather than
  failed and the next pending operation then starts.
- [x] 6.10 GREEN: expected to be a no-op on the runner — M1 already guarantees both. A failure here
  means the projection perturbed scheduling.
  Verify: `FAST --filter "QueueProjection\|Serialization\|Cancellation"`.

## Phase 7: `OperationCenter`, `ActivityItem`, depth-counted gate (D4, D6, D7 — OA2, OA5, PM2, PM3, PM6, PM7) — ≈ 980 lines

Touches `InstalledChangeObserving.swift` a second time (Phase 2 owns D8a, this phase owns D7); keep
the two hunks in separate commits so each reviews on its own terms.

- [ ] 7.1 RED `Tests/BrewClientTests/OperationCenterTests.swift` (`@MainActor`, fake launcher):
  submitting one command produces one `ActivityItem` whose id, `displayCommand` and copy text are
  stable from pending through terminal, and whose copy text is **identical** at both points
  (OA2 sc1–2).
- [ ] 7.2 GREEN `Sources/BrewClient/ActivityItem.swift`: id, command, display string, derived phase,
  bounded log, outcome — plus the presentation rules the views will read (which sentence, whether
  cancel is offered, whether confirmation is required). Every rule is a computed property here, not
  in the app target (D10), so it is `FAST`-testable.
- [ ] 7.3 RED `OperationCenterTests`: the log drains into a **2,000-line ring**; the 2,001st line
  evicts the oldest and a truncation marker becomes visible; lines stay verbatim and stream-tagged
  (OA3 sc3).
- [ ] 7.4 GREEN the ring buffer and marker on `ActivityItem`.
- [ ] 7.5 RED `OperationCenterTests` (**D1 fan-out — the settled per-package shape**): a selection of
  `[formula wget, formula git, cask iterm2]` in that order fans out into **exactly three**
  operations with argvs `upgrade --formula wget`, `upgrade --formula git`, `upgrade --cask iterm2`,
  in selection order, each its own queue item — and **no argv names more than one package**
  (PM2 sc2). There is no `upgradeSelected` case anywhere in the API.
- [ ] 7.6 RED `OperationCenterTests` (**per-item attribution obligation**): with the same three-item
  fan-out where the middle operation fails, the failure attributes to `git` **only** — `wget` and
  `iterm2` reach their own terminal outcomes independently and are not marked failed.
- [ ] 7.7 GREEN `Sources/BrewClient/OperationCenter.swift`: `@MainActor @Observable`, built on the
  `InstalledStore` exemplar. `submit(_:)` per command; a selection is expanded by the caller-facing
  helper into N `.upgrade(id)` submissions. Per submission: one drain task over `operation.lines`,
  `await operation.exit()`, `classify`, settle the gate.
- [ ] 7.8 RED `OperationCenterTests` (PM2 sc4): a pinned formula is named in neither the `upgradeAll`
  argv nor the selected-upgrade expansion over the outdated set, and **no unpin is submitted on its
  behalf**.
- [ ] 7.9 GREEN the outdated-set source for selected upgrade, taking `InstalledInventory.outdatedIDs`
  (which already excludes self-updating casks, M2-1 II4/II5) so the exclusion agrees with the
  inventory's own derivation.
- [ ] 7.10 RED `OperationCenterTests` (PM6 sc1–2; II10 sc3): the gate `begin()`s once for a batch and
  `end()`s per item; **N terminals produce exactly N re-snapshots**, never N−1 and never 2N; a quiet
  window between two queued mutations wastes no refresh; success, `.failed`, `.busy`,
  `.needsPrivileges` and `.cancelled` each force exactly one.
- [ ] 7.11 GREEN `Sources/BrewClient/InstalledChangeObserving.swift` (D7): `InstalledMutationGate`
  keeps its API and gains a depth — `begin()` increments, `end()` decrements with a floor of zero and
  **always** yields one terminal. `isMutating` therefore covers the whole batch. Overlapping
  refreshes are absorbed by `InstalledStore`'s single-flight slot and ordinal guard (M2-1 D6).
- [ ] 7.12 RED `OperationCenterTests` (OA4 sc1, sc3; PM3 sc2): cancelling a **pending** item spawns
  nothing and renders the one generic partial-state sentence; the controls the center exposes for a
  pending item contain cancel and **no reorder, move or remove**; declining a confirmation submits
  nothing and spawns nothing.
- [ ] 7.13 GREEN cancel and the confirmation gate on `OperationCenter` (D6). Queue control is
  cancel-only; I2 stays immutable.
- [ ] 7.14 RED `OperationCenterTests` (OA5 sc1–3): the summary projection reports in-flight, names
  the running operation and the pending count; an empty center and an all-terminal center both
  report **idle** with a pending count of 0; across any sequence of submissions, cancellations and
  terminals the summary's running operation and pending count **always agree** with the detail
  listing, because both derive from the one `QueueSnapshot`.
- [ ] 7.15 GREEN the summary and detail projections on `OperationCenter`.
- [ ] 7.16 RED `OperationCenterTests` (PM7 sc1–3): with no runner attached, a submission becomes a
  **terminal item reporting unavailable** — not a silent no-op, nothing thrown, nothing spawned; the
  rejection reason is available as read-only guidance; after `attach(installation:)` a later
  submission runs normally **without an app restart**.
- [ ] 7.17 GREEN `attach(installation:)`: builds the runner on arrival, and repointing `brew` builds
  a new one while in-flight items keep the old runner alive until they settle.
  Verify: `FAST --filter "OperationCenter\|ActivityItem"`.

## Phase 8: Activity UI and mutation affordances (D10 — xcodebuild only, outside the `FAST` loop) — ≈ 690 lines

Views own **no rules**: everything they read is a computed property proven in Phases 3–7.

- [ ] 8.1 `cellar.xcodeproj/project.pbxproj`: add the `Activity` group and its four files to the
  `cellar` target. Verify: `xcodebuild build`.
- [ ] 8.2 Create `cellar/Activity/ActivityBar.swift`: running command, pending count, cancel. Hidden
  **entirely** when the center is empty.
- [ ] 8.3 Create `cellar/Activity/ActivityDrawer.swift` and `cellar/Activity/ActivityLogView.swift`:
  the expanded list with per-item state, argv, copy-command and streamed log.
- [ ] 8.4 Create `cellar/Activity/MutationConfirmation.swift`: the uninstall/zap sheet, rendering
  `displayCommand` verbatim. Zap is a **separate** choice, never implied by an ordinary uninstall.
- [ ] 8.5 `cellar/cellarApp.swift` + `cellar/ContentView.swift`: own the `OperationCenter`, call
  `attach(installation:)` from the detection wiring, and add
  `.safeAreaInset(edge: .bottom) { ActivityBar(center: center) }`. An inset rather than a sheet —
  a mutation is background work and a sheet would hold the app hostage.
- [ ] 8.6 `cellar/Installed/{InstalledListView,InstalledRow}.swift` and
  `cellar/Browse/{PackageDetailView,BrowseView}.swift`: install / uninstall / zap / reinstall /
  upgrade / pin / unpin affordances, upgrade-selected and upgrade-all entry points, and
  copy-command everywhere. Affordances are **unavailable** (not failing) when the center reports no
  runner.
- [ ] 8.7 `cellar/Browse/CatalogFilterBar.swift` + `BrowseView.swift`: thread `SearchFilters` into
  `InstalledBrowse.rows(…)` so the kind / deprecated / disabled controls are honoured under the
  `installed` and `outdated` modes (Phase 2's D8d rule, view side only).
- [ ] 8.8 Integration checks via `FULL`: builds and links; the activity bar is absent with nothing
  running. Build-level only — **no new live-brew test**.

## Phase 9: Manual verification and gate

- [ ] 9.1 **Manual verification (D12, for the surfaces that are untested by design).** Left
  unchecked for the orchestrator. With the app running and brew present:
  (a) install a small formula **from Cellar** → one queue item, live streamed log, exactly one
  re-snapshot at the terminal outcome, the exact command visible and copyable;
  (b) submit two mutations → the second is visible as pending and cancellable **before** it spawns,
  and cancelling it spawns no process;
  (c) cancel a running mutation → the generic partial-state sentence appears and the inventory
  re-snapshots once;
  (d) `brew install <small formula>` in an external Terminal → exactly one refresh after the quiet
  window (re-confirms the FSEvents adapter after the Phase 2 idempotency change).
  Record each observation verbatim in the apply report. Do **not** exercise sudo-requiring casks or
  a real lock conflict: both are covered by probe #7097's captured strings, and neither is inside
  the consented mutation scope.
- [ ] 9.2 Full gate: `FAST` green with the Phase 0 `@Test` count intact plus the new suites (none
  deleted), `FULL` green, `swiftlint` on changed files with new findings separated from the 11
  pre-existing ones. Every changed file **under 400 lines** — check `BrewRunner.swift` and
  `OperationCenter.swift` explicitly. Record every command and its exact result.
- [ ] 9.3 Scope guard: `git diff --stat main` touches only the files in design "File Changes" (plus
  `InstalledObserverTests.swift`, which task 2.9 mandates); `Catalog` still declares no `BrewProcess`
  dependency (`PackageGraphTests` green); `CellarTestSupport` declares **no** dependencies and is
  linked by no app target; exactly one `TestClock` exists in the repo; no `@unchecked Sendable` in
  `Sources/BrewClient/` or `Sources/CellarTestSupport/`; nothing from M2-3 (favorites, notes, history,
  persistence) present.
- [ ] 9.4 Record the actual authored line count against the 4,000–5,000 forecast and the accepted
  `size:exception`. If it overruns materially, the pre-agreed cut is **Phases 1 + 2** (D9 + D8) as
  PR 1 — a clean prefix, unlike M2-1's mid-stack cut — leaving Phases 3–8 as PR 2 on a
  feature-branch-chain with base = PR 1 branch.
