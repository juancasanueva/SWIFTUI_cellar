# Archive report: m2-mutations-activity

**Change**: `m2-mutations-activity` — M2 slice **M2-2** ("Mutations & Activity") of the four-slice
M2 plan accepted in Engram `#7065`. Cellar could read Homebrew but not change it; this change adds
the typed mutation vocabulary (install / uninstall / reinstall / upgrade / pin / unpin, plus zap and
upgrade-all), the observable operation queue, the activity bar and streamed-log drawer, and the
first real driver for the `InstalledMutationGate` that M2-1 shipped with no caller.
**Closed**: 2026-08-02 · **Artifact store**: hybrid (OpenSpec files + Engram, project
`swiftui_cellar`)
**PRD milestone**: **M2** — this change closes slice **M2-2** only. M2 itself remains open: slice
**M2-3** (favorites, notes, snooze, operation history, persistence) has not started. The M2 exit
criterion "full daily package management without Terminal" is now behaviourally met for the mutation
path.
**Status at close**: shipped and merged to `main`. SDD cycle complete — **73/73 tasks**, zero
CRITICAL findings, zero cut phases.

This report is the terminal record of the cycle. Where it disagrees with `tasks` (#7102),
`apply-progress` (#7103) or `verify-report` (#7105), those are intermediate snapshots and **this
report states the final state**.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#5** — <https://github.com/juancasanueva/SWIFTUI_cellar/pull/5> (`feature/m2-mutations-activity` → `main`), merged by the user |
| Merge commit | **`0959677`** on `main` |
| Branch head at merge | **`77a1d73`** — 12 commits: 9 apply commits `c801daa..474fdb9`, the 9.1 evidence commit `4064465`, the pre-existing-flake fix `1009605`, and the verify report `77a1d73` |
| Tasks | **73 of 73** checked in the archived `tasks.md`. **No cut phase, no stale checkbox, no reconciliation performed at archive time** |
| Task 9.1 (manual verification) | **EXECUTED** on a Debug build at `474fdb9` against live brew 6.0.14, recorded with an **honest PARTIAL disposition** — legs (a) and (d) PASS live; leg (b) partial; leg (c) deferred. **Accepted by verify ruling 4** as non-blocking after the named tests were independently checked. See "Task 9.1" below |
| Tests (package) | **432** `@Test` in **56** suites — `swift test --package-path Packages/CellarCore`, exit 0 (Phase 0 baseline on `main` @ `2fe1c0d`: 345 / 47 → **+87 tests, +9 suites, zero deletions**) |
| Tests (app scheme) | `xcodebuild test … -skip-testing:cellarUITests` → `** TEST SUCCEEDED **`, exit 0 |
| Lint | `swiftlint` **33 authored source findings — exactly the Phase 0 count, zero new.** Every changed file under the 400-line `file_length` limit and under the 350-line `type_body_length` **error** threshold (`BrewRunner.swift` 332, `OperationCenter.swift` 313) |
| Verify verdict | **PASS WITH WARNINGS** — 0 blockers, **0 CRITICAL**, 3 WARNING, 4 SUGGESTION; **15/15** requirements, **60/60** scenarios covered by a named test that passed at runtime (57 COMPLIANT, 3 PARTIAL, 0 UNTESTED, 0 FAILING) |
| Verify WARNING 1 (flaky test) | **RESOLVED on-branch** in commit **`1009605`** — see "Snapshot claims superseded" |
| Verify WARNINGs 2 and 3 (spec wording) | **RECONCILED AT ARCHIVE** in the promoted main specs, each with an explicit `(Reconciled at archive: …)` note — see "Specs merged" |
| Native review | Lineage **`review-38936542efa96fd8`** — **approved with receipt**. Reliability lens, 63 paths / 6,891 lines: **0 blockers / 3 WARNING / 2 SUGGESTION** |
| Gates | `pre-pr` validated **allow** against that receipt |
| Authored diff | **4,538** changed lines (4,180 insertions + 358 deletions), excluding `openspec/` artifacts. With artifacts: 6,031 lines across 55 files |
| Delivery strategy | `single-pr` under the user-accepted **`size:exception`** (product Q4, Engram `#7094`) |
| Attempt ledger | `apply` settled **complete within cap** — 5,063 counted against the 5,200 cap, **no maintainer reset needed** (unlike M2-1's two). The clean within-cap settle marked the objective complete, so `verify` ran read-only without acquiring |

### The forecast held — the first time in this project

Forecast 4,000–5,000 authored lines; delivered **4,538**. This is the first slice to land inside its
band, and it is the direct payoff of M2-1's archived forecasting correction (budget tests at **~1.2×
production**, not ~0.85×). The pre-agreed Phases 1+2 cut was therefore **not** taken.

The estimate held at the total but **not per phase**, which is the calibration worth carrying:
Phase 6's production ran ~2× its ~45-line estimate and pushed `BrewRunner.swift` to 412 lines,
forcing `OperationRecord` out into `BrewOperation.swift` on top of the planned D11 move. Test files
overran hardest — `OperationCenterTests` reached 567 lines and tripped `type_body_length` at **error**
severity. Five files were split as pure moves in Phase 9, with the test count unchanged at 432 either
side. **Budget for lint-mandated file splits as a real line cost in any phase that adds a suite.**

## Native review receipt gate

| Lineage | Candidate | Outcome |
|---|---|---|
| **`review-38936542efa96fd8`** | The branch diff vs `origin/main` — 63 paths / 6,891 lines, reliability lens | **Approved with receipt.** 0 blockers, **3 WARNING / 2 SUGGESTION**, all five app-composition or test-harness gaps outside the package-tested layer. Registered as follow-ups 1–5 below |

`reviewGate.result: allow`; the `pre-pr` gate validated allow against that same receipt, and PR #5
merged at `0959677`. **The archive gate is satisfied — nothing was overridden and no reviewer was
relaunched at archive time.**

No `sdd/m2-mutations-activity/review/{transaction,ledger,receipt,gate-context}` Engram topics exist.
Review authority was read from the repository CAS receipt for lineage `review-38936542efa96fd8` as
recorded in delivery observation `#7107`, following the M2-1 precedent.

**Process lesson recorded** (from the capture-result step of this lineage): admission scans
**evidence strings** for path tokens as well as the manifest, so every filename cited in evidence
must be a full manifest path. Bare basenames, and files outside the candidate (`LineSplitter.swift`),
are rejected as `out_of_scope`.

## Task 9.1 — the manual verification, stated honestly

9.1 is checked, and it is checked over a **PARTIAL** result rather than a clean pass. That is the
disposition apply recorded, verify examined, and this report preserves. Nothing here was upgraded to
"passed" at archive time.

| Leg | Disposition at close | Basis |
|---|---|---|
| (a) install from Cellar | **PASS, live** | Copy-command put `brew install --formula hello` on the clipboard verbatim; the UI-submitted mutation spawned that argv character-for-character; the drawer showed the record, its log and a per-row copy control; **exactly one** re-snapshot at the terminal outcome |
| (b) pending visibility + cancel-before-spawn | **PARTIAL** | Pending visibility and FIFO serialization **PROVEN live** — a second submission rendered as "1 queued" with a Cancel control, and the process monitor showed the queued argv spawning only after its predecessor exited. **Cancel-before-spawn was not completed manually**: every consented small-formula mutation finished in ~1–2 s and three scripted attempts lost the race (SwiftUI exposes the buttons with no AX titles). Deferred to the named unit tests |
| (c) cancel a running mutation | **NOT RUN manually; deferred to named tests** | Same sub-second window. The rendered sentence itself was never observed live |
| (d) external Terminal change | **PASS, live** | Three external uninstalls each produced **exactly one** debounced refresh (snapshot count 13→14→15→16), re-confirming the FSEvents adapter after the Phase 2 idempotency change |

**Verify ruling 4 accepted this disposition after checking the substitute evidence rather than
trusting it.** For leg (b), `QueueProjectionTests > Cancelling a pending operation spawns nothing`
asserts `launchCount == 1` — real spawn evidence, not a mock assertion — mirrored at the centre and
runner layers. For leg (c), `QueueProjectionTests > Cancelling the running operation reports
cancelled and lets the next start` asserts `exit.isCancelled` plus `launchCount == 2`, `A cancelled
item forces its re-snapshot too` counts the gate stream, and `ClassificationTests > The cancelled
message is one generic sentence for every command` pins the text. The one residual — that the view
actually renders it — was closed by inspection at `ActivityDrawer.swift:78` (`Text(item.message)`).

**Residual risk stated plainly**: no human has watched a running mutation be cancelled in the real
UI. The behaviour is proven at every layer beneath the pixel. If M2-3 adds an artificially slow
mutation seam for manual testing, this is the leg to re-run.

## Snapshot claims explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "72 of 73 tasks complete; only 9.1 is deliberately left unchecked for the orchestrator" | `apply-progress` #7103, `tasks` #7102 | **73/73.** 9.1 was executed by the orchestrator on a Debug build at `474fdb9` against live brew 6.0.14; its verbatim evidence table is in the archived `tasks.md` and in Engram `#7104`. Recorded PARTIAL, accepted by verify ruling 4 |
| "Branch … 9 commits off `main` @ `2fe1c0d`. **NOT pushed, no PR opened**" | `apply-progress` #7103 | Pushed and merged as PR **#5** at `0959677`. Final head `77a1d73` — 12 commits, the three extra being 9.1's evidence (`4064465`), the flake fix (`1009605`), and the verify report (`77a1d73`) |
| "Pre-existing flaky test reddens the gate intermittently — `CatalogStoreTests.swift:122` failed 1 of 5 full-suite runs. **NOT this change's defect**" — WARNING 1 | `verify-report` #7105 | **FIXED on-branch in commit `1009605`**, as a **user-approved scope addition**. The assertion at line 122 read `store.results` immediately after `refreshNow()` without polling, while the same file documents at :81-84 that adoption lands asynchronously. Replaced with a polled assertion; **3× green** afterwards. The verify report's attribution was correct and is preserved: the race is pre-existing (`git log 2fe1c0d..4064465 -- CatalogStoreTests.swift` was empty), and this change's parallelism rise from 345 to 432 tests merely surfaced it |
| "Two scenarios say 'untruncated' but the design caps logs at 2,000 lines. **Recommend ARCHIVE amend both scenarios before promoting the spec**" — WARNING 3 | `verify-report` #7105 | **DONE at archive.** Both scenarios reworded in the promoted main specs with `(Reconciled at archive: …)` notes. See "Specs merged" |
| "PM4 sc2 'Standard input is never interactive' is PARTIAL — `ProcessSpec` has no stdin field" — WARNING 2 | `verify-report` #7105 | **RECONCILED at archive.** The scenario now asserts the observable behaviour without naming a seam field that does not exist. The behaviour ships correctly and always did, at `SystemProcess.swift:50` (`standardInput = FileHandle.nullDevice`, untouched M1 code). The optional `ProcessSpec` carry-through that would make the original wording testable is follow-up 8 |
| "Branch head `4064465`" | `verify-report` #7105 | Verified head only. Two commits followed: `1009605` (flake fix) and `77a1d73` (verify report). Neither changed production behaviour |
| "PR #5 **open**" | `delivery` #7107 | **Merged** at `0959677` |
| Design/tasks: "`BrewRunner.swift` lands ~390 lines (< 400 SwiftLint)" — D11 | `design` #7099, `tasks` #7102 | Phase 6's production ran ~2× estimate and pushed the file to **412**. `OperationRecord` was moved out to `BrewOperation.swift` on top of the planned D11 move; final `BrewRunner.swift` is **332**. `private var operations` was **not** weakened — the projection still lives beside the state it derives from |
| Tasks 7.10: "the gate `begin()`s once for a batch and `end()`s per item" | `tasks` #7102 | **The task text is the stale artefact, not the implementation.** Gate depth is **per-submission**. Verify ruling 1 adjudicated this explicitly: design D7 (twice-amended) already specifies depth counting verbatim, and one-begin-per-batch would drop the depth to 0 after the first terminal and reopen suppression mid-batch — a real violation of `installed-inventory`'s suppression clause. The archived `tasks.md` retains the original wording as the audit trail; **this report is where the correction lives** |

### One contradiction recorded rather than resolved

The launch prompt states **"4 recorded deviations, all validated benign; deviation 2 resolved in
implementation's favor"**, and the verify report likewise adjudicates "apply deviation 2 (gate
depth)". `apply-progress` #7103 separately enumerates **14** deliberate deviations from design and
tasks, in which the gate-depth deviation is **item 8**, not item 2.

Both statements are recorded here as written. The most likely reading is that the two lists have
different scopes — four deviations were consequential enough to be escalated for adjudication, and
verify numbered those four independently of apply-progress's fuller list of fourteen — but nothing in
a higher-ranked source confirms that mapping, so it is **not asserted**. A future reader comparing
the two documents should expect the numbering to differ and should match deviations **by subject**,
never by ordinal. What is not in doubt: the gate-depth deviation was resolved in the
implementation's favour, and every deviation in both lists was validated as non-spec-breaking.

## Specs merged (source of truth updated)

| Domain | Action | Details |
|---|---|---|
| `package-mutation` | **Created** `openspec/specs/package-mutation/spec.md` | **7 ADDED** requirements / **25 scenarios** promoted from the ADDED-only delta. New capability; nothing modified, removed or renamed. **Two scenarios reworded at archive** (see below) |
| `operation-activity` | **Created** `openspec/specs/operation-activity/spec.md` | **5 ADDED** requirements / **15 scenarios** promoted from the ADDED-only delta. New capability; nothing modified, removed or renamed. **One scenario reworded at archive** (see below) |
| `brew-execution` | **Amended** `openspec/specs/brew-execution/spec.md` | **1 MODIFIED** requirement replaced as a whole block — "Serialized mutations with concurrent reads", +3 scenarios. 6 / 12 → **6 requirements / 15 scenarios**. The other five requirements untouched |
| `installed-inventory` | **Amended** `openspec/specs/installed-inventory/spec.md` | **2 MODIFIED** requirements replaced as whole blocks, +5 scenarios. 11 / 34 → **11 requirements / 39 scenarios**. The other nine requirements untouched |
| `package-search` | **Untouched, deliberately** | PS4 "Filters answerable from the catalog alone" stays byte-identical; the installed-mode filter fix is a composition and control-state rule **above** the index. Verified byte-identical to `main` at verification time (`sha256:9d83a389…`), and **the file was not opened for writing at archive time** |

Merge method, following the M1, M2-0 and M2-1 precedent: requirement and scenario text copied
**verbatim** from the delta files; the delta-only `(Previously: …)` annotations were dropped from the
requirement bodies and their substance recorded in `## Provenance`; every requirement not named in a
delta was left untouched. Counts live in the provenance bullets, since the main specs carry no count
header.

**No destructive delta was merged** (the repo's `rules.archive` requires a warning before one). All
four deltas are additive: 12 ADDED requirements and 3 MODIFIED whole-block replacements, zero
REMOVED, zero RENAMED. Every MODIFIED replacement is a strict superset of the text it replaced —
each keeps its original body paragraphs and all its original scenarios verbatim, and appends.

### The three archive reconciliations, and why the promoted specs diverge from the deltas

These are the only places where a promoted main spec is **not** byte-identical to its delta. Each is
marked in the spec itself with an inline `(Reconciled at archive: …)` note and explained again in
that spec's `## Provenance`, so the divergence can never be mistaken for a transcription error.

1. **`package-mutation` → "Standard input is never interactive"** (verify WARNING 2). The delta wrote
   *"GIVEN a recording process spawner … THEN the recorded standard input for the process is
   `/dev/null`"*. The `ProcessSpec` seam carries no standard-input field, so a recording launcher
   **structurally cannot** observe one — the scenario was untestable exactly as written, at any layer,
   and verify correctly marked it PARTIAL. The behaviour itself is not in doubt: it is set at the
   composition root, `SystemProcess.swift:50`, in untouched M1 code. The scenario now asserts the
   observable behaviour — the spawned process's standard input is the null device — without naming a
   seam field that does not exist. **The requirement text is unchanged** and still says "Mutations
   MUST run with standard input connected to `/dev/null`".
2. **`package-mutation` → "An unrecognised failure keeps the raw log"** (verify WARNING 3).
3. **`operation-activity` → "A terminal operation's log stays readable"** (verify WARNING 3). Both
   delta scenarios promised the log stays "untruncated" while design **D4** deliberately bounds each
   operation's visible log to a **2,000-line ring** whose 2,001st line evicts the oldest and raises a
   truncation marker. "Untruncated" was an unbounded promise the implementation never made and a large
   `brew upgrade` would reach in practice. Both now read "complete up to the documented 2,000-line
   visible ring, truncation always marked". **Per-line fidelity is unchanged and still absolute** —
   the `MUST NOT trim, re-encode, reorder, deduplicate, prefix or annotate` clause governs the
   contents of each line and is untouched; the bound is on how many lines stay visible, and it is
   never silent (`isLogTruncated`, pinned by the named test "The 2,001st line evicts the oldest and
   raises the truncation marker").

The two log reconciliations were applied to **both** specs in the same wording, and each provenance
section names the other, so the two capabilities cannot drift apart on the same log.

### Two verify rulings recorded into the specs rather than left in the report

Verify rulings 1 and 2 both concern `installed-inventory` and were written into its provenance as
verification notes, because in both cases the requirement text is already correct and only its
reading was in question:

- **Ruling 1 (gate depth)** — "exactly one re-snapshot at that mutation's terminal outcome" is
  satisfied by a depth-counted gate. A selected upgrade fans out into N independent operations, so N
  terminals owe N re-snapshots while `isMutating` must still cover the whole batch.
- **Ruling 2 (post-terminal refresh)** — a signal produced by a mutation's own writes but arriving
  **after** its terminal outcome falls outside the suppression clause, which is scoped to "while a
  mutation is in flight", and is then correctly governed by the ordinary external-change clauses.
  **Conforming, not a violation.**

**Ruling 3 (duplicate submissions are PERMITTED)** was recorded into both `brew-execution` and
`operation-activity` provenance: no requirement forbids them, and BE1 positively *requires* identity
to distinguish two otherwise identical submissions.

## What shipped

- **`MutationCommand`** — the typed vocabulary, in `BrewClient` because it is the only target that
  sees both `PackageID` and `BrewCommand` (D1). `FormulaID` / `CaskID` wrappers with failable inits
  make "zap a formula" and "pin a cask" **unrepresentable**, not merely rejected. The kind flag is
  explicit on all six package-naming verbs with **no exception** — a live `brew pin --help` /
  `brew unpin --help` probe on 6.0.14 retired the design's assumed exception. `upgradeAll` carries no
  flag only because it names no package. Empty names and `-`-prefixed names are refused **at
  construction**, so option injection cannot enter, and `displayCommand` is strictly one-way: no
  public API turns a command *string* back into argv.
- **Selected upgrade fans out per package** (the settled user ruling, `#7101`). There is no
  `upgradeSelected` case; a selection of three packages becomes exactly three ordinary `.upgrade(id)`
  submissions in selection order, so queue, log, copy-command and cancel need no special path and a
  mid-batch failure attributes to exactly one package. Upgrade-all stays the deliberate grouped
  exception.
- **`MutationOutcome.classify`** — a pure function over `(exit, fault, stderrTail)`. Order: fault →
  cancelled → success → signature match on the **last 20 stderr lines only**, so a multi-megabyte log
  classifies in bounded time. `.busy` uses the two live-probed phrases (`#7097`) and **never parses a
  holder command out of brew's message**, because the probe proved brew names the *current*
  invocation there — the naive parse would confidently name the wrong process. `.needsPrivileges` is
  an admittedly unprobed heuristic, made safe by construction: classification changes **only the
  sentence shown**, never a retry, an escalation or an argv, so a false negative degrades to
  `.failed` with the full log on screen. That property is pinned by a structural test grepping
  `MutationOutcome.swift` for `askpass`, `retry`, `Keychain`, `AuthorizationRef`, `SMJobBless`.
- **Queue projection over the existing runner** (D3) — two new stored fields only, `command` and
  `ordinal`. **Phase is derived** from `process` / `resolvedExit` and never stored, so it cannot
  drift. Delivery is one `AsyncStream<QueueSnapshot>` created in `init` with `.bufferingNewest(1)`,
  yielded at the five sites where phase already changes; dropping an intermediate state snapshot is
  lossless by construction and the actor is never back-pressured by a slow consumer. **The FIFO gate,
  the SIGINT→SIGTERM escalation and the M1 SIGKILL ban are untouched.**
- **`OperationCenter`** — `@MainActor @Observable`, on the `InstalledStore` exemplar, finally driving
  `InstalledMutationGate.begin()` / `end()`. Per submission: one drain task over the operation's
  lines into a 2,000-line ring, `await exit()`, classify, settle the gate. `submit` with no runner
  attached produces a **terminal item reporting unavailable**, not a silent no-op.
- **Depth-counted gate** (D7) — `begin()` increments, `end()` decrements with a floor of zero and
  **always** yields one terminal, so N terminals produce exactly N re-snapshots while `isMutating`
  covers the whole batch. Balance is safe by construction: `begin()` once per submission only when a
  runner exists, `finish()` as the sole `end()` caller guarded by `guard item.outcome == nil`, and the
  runner-less path settling without calling `end()` at all.
- **The four absorbed M2-1 defects** (D8a–d), all confirmed by verify reading the code: the debounce
  task is stored and cancelled so its `Task.isCancelled` guards stop being dead code and the gate is
  re-checked after the sleep; `invalidationCount` + a per-acquisition mark kill the
  signal-during-inflight stale join; `clear(to:)` cancels and vacates before bumping the ordinal;
  `InstalledBrowse.rows(filters:)` is **required, not defaulted**, so no call site can silently drop
  the controls. Plus FSEvents idempotency, where the named trap held — `stop()` empties the slot
  **under** the lock and finishes the continuation **outside** it, because finishing inside re-enters
  the non-recursive `Mutex` through `onTermination` and traps.
- **`CellarTestSupport`** (D9) — a dependency-free `.target`, not a product, so nothing links it into
  the app. Three `TestClock` copies deleted; M2-0 D5 and M2-1 follow-up 10 are **closed**, and the
  fourth copy M2-1 warned about was never minted. `FakeProcessLauncher` deliberately did **not** move:
  it conforms to a `BrewProcess` protocol, which would have given the support target a dependency.
- **Activity UI** (D10) — `.safeAreaInset(edge: .bottom)` bar expanding into a drawer, an inset rather
  than a sheet because a mutation is background work and a sheet would hold the app hostage. **The
  views own no rules**: every presentation decision is a computed property in `BrewClient`, which is
  why an app-target-only surface still has fast-loop coverage.

Task **8.1 needed no `project.pbxproj` edit** at all: the project is objectVersion 77 with
`PBXFileSystemSynchronizedRootGroup`, so `cellar/Activity/` is picked up automatically. Verified in
the clean-build log rather than by editing — which also means the change's rollback story never
touches the project file.

## Follow-up register (13 open, none blocking)

Items 1–5 come from branch review `review-38936542efa96fd8`, 6–7 from task 9.1's live observations,
8–10 from verify WARNING 2 and SUGGESTIONs, 11–13 are inherited and still open.

| # | Follow-up | Source | Routed to |
|---|---|---|---|
| 1 | **Bulk-upgrade label and submission set disagree** — `InstalledListView.swift:83`'s label counts the *dependency-filtered* entries while `submitUpgradesForOutdated` filters the **whole inventory**, so the button can promise fewer upgrades than it submits | review WARNING | **M2-3** |
| 2 | **Cancel after runner detach settles cancelled without signalling the process, and pays the gate `end()` early** (`OperationCenter.swift:239`). `cellarApp` re-attaches on activation, so a transient detection absence can detach mid-operation — after which the item becomes **uncancellable** while its process keeps running | review WARNING | **M2-3** |
| 3 | **Two call sites bypass `naming(_:_:)`** — `MutationMenu.swift:27` and `PackageDetailView.swift:69` build commands from a raw, unvalidated `PackageID`. `MutationCommand.swift:20`'s by-construction validation claim is **untrue for those two sites**; the type-boundary rejection is intact everywhere else | review WARNING | **M2-3** |
| 4 | **`queuePhase` is written without an equality guard**, producing observable churn on every yield; and **runner records are never evicted** (`exit(of:)` must stay answerable). M2-3 needs a bounded retention policy for operation history anyway — do both together | review SUGGESTION + design D3 | **M2-3** |
| 5 | **`OperationCenterHarness.swift:53` indexes `launchedProcesses` after a silent poll timeout** — a trap instead of a failed expectation, so a timing regression would crash the suite rather than report | review SUGGESTION | test hygiene, unassigned |
| 6 | **A mutation's own post-terminal FSEvents echo costs one redundant `brew info --installed`** (~3 s after the terminal outcome). **Conforming, not a defect** — verify ruling 2. A short post-terminal grace window past `end()` would absorb it | 9.1 leg (a) + verify SUGGESTION 1 | **M2-3** |
| 7 | **Duplicate submission of the same install is accepted** and runs to a benign "already installed" outcome. **Permitted by design** — verify ruling 3. An optional dedup guard is a nicety, not a correctness fix | 9.1 + verify SUGGESTION 2 | unassigned |
| 8 | **Carry `standardInput` through `ProcessSpec`** so `package-mutation`'s "Standard input is never interactive" becomes testable at the recording seam as originally written. The behaviour is correct today at the composition root; only its observability is missing | verify WARNING 2 | unassigned |
| 9 | **The sudo signature set is still unprobed** against a live sudo-requiring cask (unlike the lock surface, which was probed). Safe by construction — a miss degrades to `.failed` with the log visible — so widening the strings needs no design change | verify SUGGESTION 4 | unassigned |
| 10 | **`skippedRecordCount` is never surfaced** — decode tolerance remains silent to the user | verify SUGGESTION 3, carried from M2-1 #7 | unassigned |
| 11 | **`openspec/changes/m2-mutations-installed/explore.md` doc corrections** — the six items from M2-1's docs review (over-generalised `installed_as_dependency` claim, unmarked pin read path, Defer/Prelude verdict conflict, stale `project.pbxproj` line numbers, present-tense superseded facts with no as-of anchor, six-slice arithmetic slip) | M2-1 register 11–16 | owed to `explore.md` |
| 12 | **M2-0 #1 — `CatalogStore` adoption ordinal stamps on call arrival.** Still open. M2-1 copied the *recipe* into `InstalledStore`, and this change fixed the *test* that the race made flaky (`1009605`), but **neither touched `Sources/Catalog/` production code** — the catalog-side one-line guard is still owed | M2-0 register | unassigned |
| 13 | **M2-0 #4–#7, M1 #4/#5** — unbounded watcher loop with no `.timeLimit`; poisoned-snapshot recovery gated on staleness; undelivered engine-side zero-package guard; latency test built via the synchronous initialiser; payload size cap and unwired `payloadByteLimit` | inherited | still deferred |

### Inherited register — status at this close

| Item | Status |
|---|---|
| M2-1 #1 — catalog filter controls inert under installed / outdated Browse modes | **CLOSED** by D8d (`InstalledBrowse.rows(filters:)`, required parameter) and specified in `installed-inventory` |
| M2-1 #2 — a signal during an in-flight acquisition joins the pre-change probe | **CLOSED** by D8b (`invalidationCount` + per-acquisition mark) |
| M2-1 #3 — mutation gate not re-checked after an already-open quiet window elapses | **CLOSED** by D8a (post-sleep gate re-check, stored cancellable debounce task) |
| M2-1 #4 — `clear(to:)` while a refresh is in flight strands the acquisition | **CLOSED** by D8c (cancel + vacate before bumping the ordinal) |
| M2-1 #5 — unreachable `Task.isCancelled` guards in the debounce path | **CLOSED** — storing and cancelling the debounce task made them reachable |
| M2-1 #6 — `FSEventsInstalledObserver.changes()` not idempotent | **CLOSED** — `start(yielding:)` calls `stop()` first, last caller wins |
| M2-1 #10 / M2-0 #3 — `CellarTestSupport` extraction, third `TestClock` copy | **CLOSED** by D9. Exactly one `TestClock` exists in the repo |
| M2-1 #8 / #9 — `DetectionTests` display-name prose, `InstalledRefreshTests` count assertion | **Still open, unassigned** — untouched by this change |
| M2-1 #7 — `skippedRecordCount` unsurfaced | **Still open**, now item 10 above |
| M2-0 #1 — `CatalogStore` adoption ordinal | **Still open**, now item 12 above |

**Six of M2-1's follow-ups closed here.** That is the point of routing a review WARNING to the slice
that makes it reachable rather than fixing it speculatively: all four latent defects (#1–#4) became
live the moment a real mutation drove `isMutating`, and each was closed with a RED test that
reproduced it first.

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| M2 slicing decision | `#7065` | (Engram only) |
| product decisions Q1–Q4 settled | `#7094` | (Engram only) |
| proposal | `#7095` `sdd/m2-mutations-activity/proposal` | `proposal.md` |
| product decisions extended Q5–Q7 settled | `#7096` | (Engram only) |
| brew lock-conflict live probe (design gate, RESOLVED) | `#7097` | (Engram only) |
| spec (4 deltas) | `#7098` `sdd/m2-mutations-activity/spec` | `specs/{package-mutation,operation-activity,brew-execution,installed-inventory}/spec.md` |
| design | `#7099` `sdd/m2-mutations-activity/design` | `design.md` |
| spec↔design reconciliation (pin/unpin kind-flag probe) | `#7100` | (Engram only) |
| upgrade-selected user ruling (one invocation per package) | `#7101` | (Engram only) |
| tasks | `#7102` `sdd/m2-mutations-activity/tasks` — **7.10's "begin() once for a batch" superseded by this report** | `tasks.md` (authoritative checklist, 73/73) |
| apply-progress | `#7103` `sdd/m2-mutations-activity/apply-progress` — **"72 of 73" and "not pushed" superseded** | (Engram only) |
| task 9.1 manual verification (PARTIAL disposition) | `#7104` | evidence table inside `tasks.md` |
| verify-report | `#7105` `sdd/m2-mutations-activity/verify-report` — **WARNING 1 fixed on-branch after it was written; WARNINGs 2 and 3 reconciled at archive** | `verify-report.md` |
| verify outcome | `#7106` | (Engram only) |
| delivery (review lineage, gates, capture-result lesson) | `#7107` `sdd/m2-mutations-activity/delivery` — **"PR #5 open" superseded by the merge at `0959677`** | (Engram only) |
| archive-report | `sdd/m2-mutations-activity/archive-report` | this file |

No `sdd/m2-mutations-activity/review/{transaction,ledger,receipt,gate-context}` Engram topics exist;
review authority was read from the repository CAS receipt for lineage `review-38936542efa96fd8` as
recorded in `#7107`.

Verification evidence:
`evidence_revision sha256:77c8ef000e05242b9626a579d02f88b3afee614270ce60c0cbefb29242b2a57f`;
`test_output_hash sha256:927122de8a15d273cff1848cb36a0f8651962fe3b4b1949b147dd0ae7b95592c`;
`build_output_hash sha256:3be7b5333ecccb4a527b111630f310016fad50f849b534dbd7e18a4eccc80120`;
`verify-report.md sha256:97ad90e0aa6d2b9a380b9a70c22b6051019e10945fe7e51291fd6eb7441cb002`, admitted
by `gentle-ai sdd-verify-validate --requirements 15 --scenarios 60` (`valid: true`) before any write.

**The `verify-report.md` digest is part of the audit trail.** It is preserved because the change
folder was moved into this archive with a byte-preserving `git mv` in the same commit that adds this
report — no artifact was re-transcribed.

## Archive integrity

- **`tasks.md` is fully checked (73/73).** No checkbox was altered at archive time and no
  stale-checkbox reconciliation was performed or needed. **Archive classification: clean** — zero
  CRITICAL findings, zero blockers, no gate overridden, no partial archive.
- **Three scenarios diverge from their deltas by design**, each carrying an inline
  `(Reconciled at archive: …)` note and a provenance entry. They are the only non-verbatim promotions
  and they exist because verify asked for exactly this before promotion. No requirement text was
  changed.
- **`openspec/specs/package-search/spec.md` was never opened for writing.** It stays byte-identical.
- **`openspec/changes/m2-mutations-installed/explore.md` is NOT part of this archive.** It is the
  still-open M2 umbrella exploration, tracked since M2-1 at `86e2216`, and follow-up 11 is owed to it.
- **The archive move is part of this commit, not pending.** The change folder
  `openspec/changes/m2-mutations-activity/` was relocated here via a byte-preserving `git mv` in the
  same archive commit that adds this report and the four merged main specs. This report was written
  directly at its archive path.

## Next

**M2-3** — favorites, notes, snooze, operation history and persistence, the last slice of M2. It
inherits follow-ups 1–4 and 6 above, all of which are app-composition or retention gaps in exactly
the surfaces M2-3 extends: item 4's runner-record retention policy is a prerequisite for operation
history, and items 1–3 are affordance-layer corrections in the views M2-3 will touch anyway. Item 12
(the M2-0 catalog adoption ordinal) is now the oldest open defect in the project and should be closed
on its own, not carried into a fourth slice.
