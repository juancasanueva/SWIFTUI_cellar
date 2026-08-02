```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:77c8ef000e05242b9626a579d02f88b3afee614270ce60c0cbefb29242b2a57f
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 15/15
scenarios: 60/60
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:927122de8a15d273cff1848cb36a0f8651962fe3b4b1949b147dd0ae7b95592c
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
build_exit_code: 0
build_output_hash: sha256:3be7b5333ecccb4a527b111630f310016fad50f849b534dbd7e18a4eccc80120
```

## Verification Report

**Change**: m2-mutations-activity
**Version**: branch `feature/m2-mutations-activity` @ `4064465` (9 apply commits `c801daa..474fdb9` + evidence commit)
**Mode**: Strict TDD

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 73 |
| Tasks complete | 73 |
| Tasks incomplete | 0 |

Task 9.1 was executed post-apply by the orchestrator and is now checked with its evidence
table in place. No task remains unchecked, so full verification was in scope.

### Build & Tests Execution

**Build**: PASSED

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
** TEST SUCCEEDED **   exit 0
```

**Tests**: 432 passed / 0 failed in 56 suites (authoritative run)

```text
swift test --package-path Packages/CellarCore
Test run with 432 tests in 56 suites passed after 5.258 seconds.   exit 0
```

**Full disclosure — the gate is intermittently red.** The declared test command was executed
five times end to end. Run 1 exited **1**; runs 2-5 exited **0**.

| Run | Exit | Result |
|---|---|---|
| 1 | 1 | 432 tests, 1 issue — `Catalog store` > "A sync that lands while the store is running replaces the results" (`CatalogStoreTests.swift:122`), output hash `sha256:316a2b96a5146a8692dab34d7ca73c6d4784aaa1877fd405da216017b8f0053f` |
| 2 | 0 | 432 tests passed (envelope's authoritative run) |
| 3 | 0 | 432 tests passed |
| 4 | 0 | 432 tests passed |
| 5 | 0 | 432 tests passed |

Isolated re-runs of the suite (`--filter CatalogStoreTests`) passed **6/6**. See WARNING-1 for
the ruling: the flake is pre-existing, is not a defect of this change, and covers none of this
change's 60 scenarios. The envelope records the reproducible steady state (exit 0); run 1's
non-zero exit and its hash are recorded here so nothing is hidden.

**Coverage**: not available — no coverage tool is configured for this package. Not a failure.

### Spec Compliance Matrix

15 requirements / 60 scenarios, counted from the four retrieved delta files
(package-mutation 7/25, operation-activity 5/15, brew-execution 1/6, installed-inventory 2/14).

#### package-mutation — 7 requirements / 25 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| PM1 typed command, explicit kind flag | Installing a formula names it as a formula | `MutationCommandTests > Every command lowers to exactly its documented vector` | COMPLIANT |
| PM1 | Installing a cask names it as a cask | same, `install --cask iterm2` case | COMPLIANT |
| PM1 | Uninstalling a cask names it as a cask | same, `uninstall --cask iterm2` case | COMPLIANT |
| PM1 | Reinstall, pin and unpin carry the kind flag too | same, `reinstall/pin/unpin --formula git` cases | COMPLIANT |
| PM1 | A token in both namespaces is never ambiguous | `MutationCommandTests > A token in both namespaces is disambiguated by the flag, never by brew`; `> The argv that reaches the process seam is the argv that was inspected` | COMPLIANT |
| PM2 three upgrade scopes | A single upgrade names one package | `MutationCommandTests > Every command lowers to exactly its documented vector` (`upgrade --formula wget`) | COMPLIANT |
| PM2 | A selected upgrade expands to one invocation per package | `OperationCenterTests > A selection fans out into exactly one operation per package, in order` | COMPLIANT |
| PM2 | Upgrade all is a bare brew upgrade | `MutationCommandTests > Upgrade all is a bare brew upgrade with nothing added` | COMPLIANT |
| PM2 | A pinned package is never force-upgraded | `OperationCenterTests > A pinned formula is never named and never unpinned to upgrade it` | COMPLIANT |
| PM3 confirmation gate | Uninstall asks first and shows the exact command | `OperationCenterProjectionTests > Declining a confirmation submits nothing and spawns nothing`; `> Confirming submits exactly the command that was shown` | COMPLIANT |
| PM3 | Declining spawns nothing | `OperationCenterProjectionTests > Declining a confirmation submits nothing and spawns nothing` | COMPLIANT |
| PM3 | Zap is confirmed separately and shows its own command | `MutationCommandTests > Exactly uninstall and zap require confirmation`; `> The display command is stable and pasteable for the destructive cases` | COMPLIANT |
| PM3 | Non-destructive mutations run without confirmation | `MutationCommandTests > Install, reinstall, upgrade, upgrade-all, pin and unpin never confirm`; `OperationCenterProjectionTests > A non-destructive command needs no confirmation and submits directly` | COMPLIANT |
| PM4 sudo is a typed failure | A cask that asks for a password fails with Terminal guidance | `ClassificationTests > Every sudo signature with a non-zero exit is the typed privilege failure`; `> The privilege guidance echoes the exact command and names the package` | COMPLIANT |
| PM4 | Standard input is never interactive | `ClassificationTests > The outcome offers no credential surface, no retry and no escalation` (2nd clause only) | PARTIAL |
| PM4 | An unrecognised failure keeps the raw log | `ClassificationTests > An unrecognised failure degrades to the plain failure, keeping its status`; `> A non-zero exit without either lock phrase is a plain failure` | PARTIAL |
| PM5 external lock is typed busy | A lock conflict is reported as busy, not generic | `ClassificationTests > The probed lock output classifies as busy`; `> The busy message tells the user Homebrew is busy in another terminal` | COMPLIANT |
| PM5 | The lock holder is never named from brew's message | `ClassificationTests > A busy message naming an unrelated command still classifies busy, silently`; `> The outcome offers no credential surface...` (structural no-parse) | COMPLIANT |
| PM5 | A non-zero exit without the signature is not busy | `ClassificationTests > A non-zero exit without either lock phrase is a plain failure` | COMPLIANT |
| PM6 one re-snapshot per terminal | A successful mutation refreshes exactly once | `OperationCenterProjectionTests > Success, failure, busy, needs-privileges and cancellation each force exactly one` (status 0) | COMPLIANT |
| PM6 | A failed mutation still refreshes | same, statuses 1 and 2 | COMPLIANT |
| PM6 | A cancelled mutation refreshes and admits partial state | `OperationCenterProjectionTests > A cancelled item forces its re-snapshot too`; `> Cancelling a pending item spawns nothing and shows the generic sentence`; `ClassificationTests > The cancelled message is one generic sentence for every command` | COMPLIANT |
| PM7 no mutation when brew absent | Absent brew spawns nothing | `OperationCenterProjectionTests > With no runner a submission becomes a terminal item reporting unavailable` | COMPLIANT |
| PM7 | An invalid configured path is guidance, not failure | `OperationCenterProjectionTests > The rejection reason is available as read-only guidance` | COMPLIANT |
| PM7 | Mutations become available when brew appears | `OperationCenterProjectionTests > Mutations become available when brew appears, with no restart` | COMPLIANT |

#### operation-activity — 5 requirements / 15 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| OA1 queue enumerable, ordered, argv | Pending operations visible before they run, in run order | `QueueProjectionTests > Queued mutations are enumerable before they run, in FIFO order, with their argv` | COMPLIANT |
| OA1 | An operation's identity is stable across its states | `QueueProjectionTests > The same command submitted twice yields two different, stable identities`; `OperationCenterTests > A submission produces one item whose identity and copy text never change` | COMPLIANT |
| OA1 | Each enumerated operation carries the exact argv | `OperationCenterTests > The item carries the exact argv in every state` | COMPLIANT |
| OA1 | Terminal operations remain enumerable for the session | `QueueProjectionTests > A terminal operation stays enumerable with its outcome and restarts nothing` | COMPLIANT |
| OA2 copy command | The copied text matches the argv | `OperationCenterTests > A submission produces one item whose identity and copy text never change`; `MutationCommandTests > The display command matches the argv character for character` | COMPLIANT |
| OA2 | Copying a pending operation matches copying it later | `OperationCenterTests > A submission produces one item whose identity and copy text never change` | COMPLIANT |
| OA3 live verbatim logs | Lines appear while the operation is still running | `QueueProjectionTests > Lines are readable while the operation is still running, tagged and in order`; `OperationCenterTests > The log drains verbatim, tagged, in emission order` | COMPLIANT |
| OA3 | Order and stream tagging survive the projection | same two tests | COMPLIANT |
| OA3 | A terminal operation's log stays readable | `OperationCenterTests > The log drains verbatim, tagged, in emission order`; bound proven by `> The 2,001st line evicts the oldest and raises the truncation marker` | PARTIAL |
| OA4 cancel is the only queue control | Cancelling a pending operation spawns nothing | `QueueProjectionTests > Cancelling a pending operation spawns nothing and resolves it cancelled`; `OperationCenterProjectionTests > Cancelling a pending item spawns nothing and shows the generic sentence` | COMPLIANT |
| OA4 | Cancelling the running operation lets the queue proceed | `QueueProjectionTests > Cancelling the running operation reports cancelled and lets the next start` | COMPLIANT |
| OA4 | No reorder or remove affordance exists | `OperationCenterProjectionTests > The controls offered for a pending item are cancel and nothing else` | COMPLIANT |
| OA5 one source of truth | The summary reports the running operation and the pending count | `OperationCenterProjectionTests > The summary reports the running operation and the pending count` | COMPLIANT |
| OA5 | An empty queue reports idle | `OperationCenterProjectionTests > An empty centre and an all-terminal centre both report idle` | COMPLIANT |
| OA5 | Summary and detail never disagree | `OperationCenterProjectionTests > Summary and detail never disagree across a whole sequence` | COMPLIANT |

#### brew-execution — 1 MODIFIED requirement / 6 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| BE1 serialized mutations, concurrent reads | Two mutations never overlap | `SerializationTests > Three mutations run one at a time, in submission order` | COMPLIANT |
| BE1 | Reads proceed during a mutation | `SerializationTests > A read starts and completes while a mutation is still running`; `QueueProjectionTests > A read-only query is running immediately and never pending` | COMPLIANT |
| BE1 | Cancelling a queued mutation spawns nothing | `SerializationTests > Cancelling a queued mutation spawns nothing and reports cancelled`; `QueueProjectionTests > Cancelling a pending operation spawns nothing and resolves it cancelled` | COMPLIANT |
| BE1 | Queued mutations are enumerable before they run | `QueueProjectionTests > Queued mutations are enumerable before they run, in FIFO order, with their argv` | COMPLIANT |
| BE1 | Identity is stable and distinguishes identical submissions | `QueueProjectionTests > The same command submitted twice yields two different, stable identities` | COMPLIANT |
| BE1 | Enumerating does not perturb scheduling | `QueueProjectionTests > Enumerating repeatedly while one runs spawns nothing and does not reorder` | COMPLIANT |

#### installed-inventory — 2 MODIFIED requirements / 14 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| II-A filters composed, never in the index | The installed filter narrows browse results | `InstalledFilterTests > The installed filter narrows browse results` | COMPLIANT |
| II-A | The not-installed filter is the complement | `InstalledFilterTests > The not-installed filter is the complement` | COMPLIANT |
| II-A | The outdated filter excludes self-updating casks | `InstalledFilterTests > The outdated filter excludes self-updating casks` | COMPLIANT |
| II-A | With no inventory the filters are disabled and results unchanged | `InstalledFilterTests > With no inventory the mode is forced to all and the picker is disabled` | COMPLIANT |
| II-A | The catalog filter set still declares no installed predicate | `FilterTests > No declared filter refers to installed, not-installed or outdated state` | COMPLIANT |
| II-A | No catalog filter control is enabled but inert under the installed mode | `InstalledFilterCompositionTests > The kind control narrows the installed mode, and the picker stays enabled`; `> Deprecated and disabled both narrow the installed mode`; `> A row with no catalog record is never hidden by a catalog-only flag` | COMPLIANT |
| II-A | The outdated mode obeys the same rule | `InstalledFilterCompositionTests > The kind control applied to casks leaves only the cask under outdated` | COMPLIANT |
| II-B invalidation, debounced and coalesced | An external install is reflected without user action | `InstalledRefreshTests > An external install is reflected after the quiet window, with no user action` | COMPLIANT |
| II-B | A burst of signals causes exactly one re-snapshot | `InstalledRefreshTests > Twenty signals inside the quiet window cost exactly one re-snapshot` | COMPLIANT |
| II-B | Signals during a mutation are suppressed and settled once | `InstalledRefreshTests > Signals during a Cellar mutation are suppressed and settled exactly once`; `> A directly reported change during a mutation is suppressed too` | COMPLIANT |
| II-B | A refresh requested after the one in flight settles is fresh | `InstalledStoreTests > A refresh requested after the previous settled takes a fresh snapshot` | COMPLIANT |
| II-B | A window opened before a mutation began does not fire during it | `InstalledRefreshTests > A window opened before a mutation began does not fire during it` | COMPLIANT |
| II-B | A signal during an acquisition is not answered by that acquisition | `InstalledRefreshDefectTests > A signal during an acquisition is not answered by that acquisition`; `InstalledStoreFreshnessTests > A refresh requested after an invalidation does not join the stale acquisition` | COMPLIANT |
| II-B | Resetting during an acquisition does not strand the inventory | `InstalledStoreFreshnessTests > Resetting during an acquisition does not strand the inventory`; `> A pre-clear acquisition never lands on top of the cleared state` | COMPLIANT |

**Compliance summary**: 60/60 scenarios have a named covering test that passed at runtime.
57 COMPLIANT, 3 PARTIAL (PM4-sc2, PM4-sc3, OA3-sc3 — see WARNING-2 and WARNING-3).
0 UNTESTED, 0 FAILING.

### Correctness (Static Evidence)

| Requirement area | Status | Notes |
|---|---|---|
| Typed mutation vocabulary | Implemented | `MutationCommand.swift` — six verbs plus `zap` and `upgradeAll`; `target(_:)` is the single place a package becomes two argv elements, so the kind flag cannot be skipped per verb. `FormulaID`/`CaskID` make "pin a cask" and "zap a formula" unrepresentable. |
| Argv hardening | Implemented | `MutationName.isSafe` rejects empty, `-`-prefixed and whitespace-bearing names at construction. `displayCommand` is one-way; no public API parses a string into argv (asserted structurally). |
| Per-package fan-out (user ruling #7101) | Implemented | No `upgradeSelected` case exists. `OperationCenter.submitUpgrades(for:)` maps each `PackageID` to its own `.upgrade` submission, so each gets its own item, log, copy text, cancel and terminal outcome. |
| Outcome classification | Implemented | `MutationOutcome.classify` is pure and ordered: fault, cancellation and exit-0 are decided before any subprocess byte is read; only the last 20 stderr lines are scanned; nothing is captured out of the payload. |
| Terminal re-snapshot | Implemented | `forcesReSnapshot` is unconditionally `true`; `OperationCenter.finish` is idempotent (`guard item.outcome == nil`) so one operation pays the gate exactly once. |
| Mutation gate depth | Implemented | See the D7 ruling below. |
| Four absorbed M2-1 fixes | Implemented | See the coherence table. |
| Brew-absent guidance | Implemented | `OperationCenter.isAvailable`/`unavailableGuidance`; `MutationMenu.swift:37` and `InstalledListView.swift:94` disable the affordances and surface the guidance as help text rather than failing at spawn time. |
| Projection stores command + ordinal only | Confirmed | `OperationRecord` stores `id`, `command`, `ordinal` and lifecycle state; `projection` **derives** `Phase` from `resolvedExit` and `process`. No phase field exists anywhere — `rg` finds no stored phase in `BrewProcess`. |
| `package-search` untouched | Confirmed | `openspec/specs/package-search/spec.md` is byte-identical to `main`: both hash `sha256:9d83a389cec94640c91d1ea3bec38780c656763b56feb0258e20725f49a09c21`, and `git diff main` on the path is empty. |

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| D1 `MutationCommand` in `BrewClient`; fan-out at the call site | Yes | `Sources/BrewClient/MutationCommand.swift`; fan-out in `OperationCenter.submitUpgrades`. |
| D2 names argv-hardened at construction | Yes | `MutationName.isSafe`, failable `init?`. |
| D3 queue observability is a derived projection | Yes | `OperationRecord.projection` derives phase; `queue` is a `nonisolated let AsyncStream<QueueSnapshot>` with `.bufferingNewest(1)` built in `init`, one stored continuation, published at the five phase-change sites. |
| D4 `OperationCenter` as one `@MainActor @Observable` store | Yes | Mirrors `InstalledStore`'s shape. |
| D5 classification is a pure function over untrusted output | Yes | `static func classify` is pure and total. |
| D6 confirmation, copy, cancel | Yes | `ConfirmationRequest` carries the **typed** command, so confirming submits exactly what was shown. |
| D7 depth-counted gate; every terminal forces a re-snapshot | Yes | **See the ruling below.** Implementation matches D7 verbatim. |
| D8a post-sleep gate re-check + owned debounce task | Yes | `InstalledChangeObserving.swift:198` stores `debounceTask`; `waitOutTheQuietWindow` re-checks `mutations?.isMutating != true` after the sleep (line 219) and `run()` cancels the task at line 163, which makes the `Task.isCancelled` guards at lines 207 and 211 reachable rather than dead. |
| D8b invalidation-after-start mark | Yes | `InstalledStore.invalidationCount` + `InFlightRefresh.mark`; joining requires `current.request == request && current.mark >= invalidationCount` (lines 147-149). `changeSignalled()` and `mutationSettled()` both call `store.invalidate()` unconditionally. |
| D8c `clear(to:)` cancels and vacates | Yes | `InstalledStore.clear(to:)` lines 223-225 cancel the task and nil the slot **before** bumping the ordinal. |
| D8d `SearchFilters` threaded into installed/outdated modes | Yes | `InstalledBrowse.rows(mode:query:filters:catalogResults:catalogLookup:)` takes `filters` as a **required** parameter (apply deviation 3 — a strengthening), and `BrowseView.swift:85` passes `catalog.filters`. Kind is answered from the inventory; deprecated/disabled from the catalog decoration with "no record ⇒ not excluded". No control is enabled-but-inert. |
| D9 `CellarTestSupport` dependency-free | Yes | Declared with no dependencies; one `TestClock` in the repo. |
| D10 activity UI is an inset owning no rules | Yes | `cellar/Activity/*` renders `item.message`, `item.statusLabel`, `item.copyText`; every rule is a computed property on `ActivityItem`. |
| D11 file layout under the limit | Yes | Largest changed production file is `BrewRunner.swift` at **332** lines; `OperationCenter.swift` **313**; largest changed test file `ClassificationTests.swift` **352**. All under the 400-line `file_length` limit, and every type body is under SwiftLint's 350-line `type_body_length` error threshold. |
| D12 everything through fakes; nothing mutates real Homebrew | Yes | No test spawns `brew`; the argv-through-the-seam test uses `RecordingProcessLauncher`. |

### Rulings Requested by the Orchestrator

**RULING 1 — apply deviation 2, mutation-gate depth semantics. The implementation is correct;
task 7.10's wording is the defect.**

Task 7.10 said the gate `begin()`s once per batch. Design D7, as twice amended, says the
opposite in as many words: "`begin()` increments, `end()` decrements with a floor of zero and
**always** yields one terminal. So `isMutating` covers the whole batch ... while N terminals
still produce N re-snapshots." The apply phase implemented per-submission depth counting, which
is D7 exactly, and task 7.10 is the stale text.

Checked against the installed-inventory MODIFIED delta rather than against either artifact: the
requirement says "While a Cellar-initiated mutation is in flight, signals MUST be suppressed,
and exactly one re-snapshot MUST be taken at that mutation's terminal outcome." Both properties
hold under depth counting and only one holds under one-begin-per-batch:

- *Suppression across the batch.* `isMutating = depth > 0`, so with three fanned-out upgrades
  the depth is 3 and suppression covers the whole batch. Under one-begin-per-batch the first
  `end()` would drop the depth to 0 and reopen suppression mid-batch, re-snapshotting while brew
  was still writing — a direct violation of "while a mutation is in flight".
- *One re-snapshot per terminal.* `end()` yields unconditionally, so N terminals produce N
  re-snapshots. The requirement is written per-mutation ("that mutation's terminal outcome"),
  and each of the three fanned-out upgrades is its own mutation with its own queue item and
  terminal outcome, so three is the correct count, not one.

Both are asserted at runtime by `OperationCenterProjectionTests > N terminals produce exactly N
re-snapshots and the gate covers the batch`, which checks `isMutating` is still true after the
first of three terminals and false only after the last, and that the terminal stream yielded
exactly 3. Balance is safe: `begin()` is called once per submission only when a runner exists,
and `finish()` — the only caller of `end()` — is guarded by `guard item.outcome == nil`, so no
submission can pay the gate twice. The runner-less path settles the item directly without
calling `end()`, so it cannot underflow either. **No spec violation. Deviation accepted.**

**RULING 2 — the extra inventory refresh ~3 s after a mutation's terminal outcome is
CONFORMING, not a violation.**

The live observation in task 9.1 leg (a): one re-snapshot at the terminal outcome (21:43:54),
then a second ~3 s later (21:43:57) caused by the mutation's own Cellar write signalling
FSEvents after `end()` had already run.

Read against the requirement as written, this violates nothing:

- The suppression clause is scoped to "**While** a Cellar-initiated mutation is in flight". The
  signal arrived after `end()`, so the mutation was not in flight and the clause does not reach it.
- The scenario is likewise bounded: "WHEN change signals are emitted **continuously until that
  mutation reaches a terminal outcome** THEN no re-snapshot runs while the mutation is in flight
  AND exactly one re-snapshot runs at the terminal outcome." Both clauses held — nothing ran
  during the mutation, and exactly one ran at the terminal. A signal after that point is outside
  the scenario's window.
- Once outside that window the signal is governed by the ordinary external-change clauses, which
  it satisfies: it was treated purely as an invalidation trigger, its contents were not parsed,
  and it was debounced into **exactly one** re-snapshot after the quiet window.

So: conforming-but-suboptimal. It costs one redundant `brew info --installed` per mutation,
absorbed harmlessly by the single-flight slot and the ordinal guard. Recorded as SUGGESTION-1,
not as a defect, and it does not block archive.

**RULING 3 — duplicate same-install submissions are permitted. No requirement forbids them.**

Nothing in the 15 requirements forbids submitting the same command twice. The opposite is true:
brew-execution BE1 requires that an operation's identity "MUST distinguish two otherwise
identical submissions of the same command", which presupposes duplicates are representable and
reachable, and `QueueProjectionTests > The same command submitted twice yields two different,
stable identities` pins that behaviour deliberately. The observed duplicate ran to a benign
"already installed" outcome. Recorded as SUGGESTION-2 (a dedup affordance is a product nicety
for a later milestone), not as a finding.

**RULING 4 — the task 9.1 manual disposition is ACCEPTABLE. The residual gap does not block
archive.**

Legs (a) and (d) passed live. Legs (b, partial) and (c, not run) were deferred to named tests
because every consented small-formula mutation completed in ~1-2 s on this machine, making the
cancel-before-spawn window sub-second and unwinnable by scripted UI automation. I verified that
the named tests exist and assert what the evidence table claims, rather than taking the claim
on trust:

- Leg (b), cancel-before-spawn. `QueueProjectionTests > Cancelling a pending operation spawns
  nothing and resolves it cancelled` asserts `launchCount == 1` after a pending operation is
  cancelled behind a running one — real spawn evidence from the launcher, not a state flag — and
  then asserts the entry's phase `isTerminal` with `exit?.isCancelled == true`.
  `OperationCenterProjectionTests > Cancelling a pending item spawns nothing and shows the
  generic sentence` asserts the same at the centre layer plus `pending.outcome == .cancelled`.
  `SerializationTests > Cancelling a queued mutation spawns nothing and reports cancelled` covers
  it a third time at the runner. The claim is accurate. The half of leg (b) that *was* proven
  live — pending visibility and FIFO serialization — is the half automation could reach.
- Leg (c), cancel a running mutation. `QueueProjectionTests > Cancelling the running operation
  reports cancelled and lets the next start` asserts `exit.isCancelled` (explicitly "not a plain
  failure") and `launchCount == 2`, proving the successor started.
  `OperationCenterProjectionTests > A cancelled item forces its re-snapshot too` counts the gate's
  terminal stream and asserts exactly one re-snapshot for the cancelled item and two after the
  running one settles. `ClassificationTests > The cancelled message is one generic sentence for
  every command` pins the message. SIGINT→SIGTERM escalation is M1's `CancellationTests`, retained
  and green.
- The one thing no unit test can prove is that the SwiftUI view *displays* that sentence. I closed
  it by inspection instead: `ActivityDrawer.swift:78` renders `Text(item.message)`, and
  `item.message` is exactly the string `OperationCenterProjectionTests` asserts
  (`pending.message == MutationOutcome.cancelled.message(for:)`). Under D10 the views own no
  rules, so this is layout only — the category task 9.1 exists to cover, and the residual is
  now a single rendered `Text`.

The residual manual gap is therefore **acceptable**, not blocking.

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD evidence reported | PASS | `tasks.md` carries explicit RED/GREEN pairs throughout phases 2-8 (e.g. 3.7 RED / 3.8 GREEN, 7.3 RED / 7.4 GREEN); apply-progress #7103 records the phase-by-phase cycle. |
| All tasks have tests | PASS | 73/73 tasks complete; every behavioural task names its suite. |
| RED confirmed (test files exist) | PASS | Every named test file exists on disk and was read: `MutationCommandTests`, `ClassificationTests`, `QueueProjectionTests`, `OperationCenterTests`, `OperationCenterProjectionTests`, `InstalledFilterCompositionTests`, `InstalledStoreFreshnessTests`, `InstalledRefreshDefectTests`, `InstalledObserverTests`. |
| GREEN confirmed (tests pass) | PASS | All 432 tests executed and passed in the authoritative run; +87 tests and +9 suites over the Phase 0 baseline of 345/47, with none deleted. |
| Triangulation adequate | PASS | Heavily parameterized: `argvCases` is an 11-case table driving 6 separate property tests; sudo signatures are a 3-case table; terminal statuses a 3-case table. Both branch directions are asserted (busy *and* not-busy; formula *and* cask; enabled *and* unavailable). |
| Safety net for modified files | PASS | Phase 0 baseline run recorded on `main` (345/47) before modification; the Phase 9 splits were pure moves with 432 tests either side. |

**TDD compliance**: 6/6 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (package, fakes only) | 432 | 56 suites | Swift Testing |
| Integration (app target) | via `xcodebuild test` | `cellarTests` | XCTest + Swift Testing |
| E2E / UI | 0 executed | `cellarUITests` | XCUITest — deliberately skipped via `-skip-testing` |
| **Total** | **432 + app-target suite** | | |

Classification note: the CellarCore suite is unit-level throughout — every test drives fakes
(`FakeProcessLauncher`, `RecordingProcessLauncher`, `FakeInstalledPayloadSource`, `TestClock`)
and no test spawns `brew` or mutates a real Homebrew, which is D12 holding. The behaviours that
genuinely need a real process are the ones task 9.1 covers manually.

### Changed File Coverage

Coverage analysis skipped — no coverage tool is configured for this package. Not a failure.

### Assertion Quality

Audited every test file created or modified by this change. No tautologies, no assertions that
never call production code, no ghost loops, no smoke-only tests, no mock-heavy files.

Positive observations worth recording:

- Spawn claims are proven by `launcher.launchCount`, which is real evidence that no process was
  created, rather than by a boolean the code under test sets itself.
- `MutationCommandTests` asserts **whole argv vectors** (`==`) rather than `contains`, which is
  the only form that catches a spurious extra argument — the failure mode that actually matters
  for a destructive command.
- Empty/absence assertions always have a companion positive: `noInvocationCarriesBothKindFlags`
  sits beside `everyCommandLowersToItsVector`; `cask.arguments.contains("--formula") == false`
  sits beside `cask.arguments == ["install", "--cask", "docker"]`.
- Two deliberately **structural** tests read source text rather than behaviour
  (`noCredentialSurfaceExists`, `No public API turns a command string back into argv`). Normally
  a smell, but both are justified in-file: the safest implementation of "there is no privilege
  path" is the *absence* of a member, which no behavioural test can observe. Their forbidden-token
  lists (`askpass`, `SUDO_ASKPASS`, `AuthorizationRef`, `SMJobBless`, `Keychain`, `func retry`,
  `func escalate`) match the threat matrix as specified.

**Assertion quality**: all assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

### Quality Metrics

**Linter**: 33 authored SwiftLint findings, byte-for-byte the Phase 0 count. **Zero new.**
A bare `swiftlint` run reports 60 findings; 25 of those are inside
`Packages/CellarCore/.build/**` generated code, leaving 33 in authored source. Five findings sit
in files this branch touched, and all five pre-exist on `main`:
`InstalledDeriveTests.swift:88,222` (`optional_data_string_conversion`),
`CancellationTests.swift:14` (`large_tuple`), `cellarApp.swift:15` (`type_name`), and
`FSEventsInstalledObserver.swift:185` (`function_parameter_count`) — the last being the FFI
signature of `installedChangeCallback`, which is present on `main` and cannot be narrowed because
FSEvents dictates its arity. **No new finding lands in any file this change created.**

**Type checker / build**: no errors. `xcodebuild test` succeeded; the package builds under Swift 6
strict concurrency with no data-race diagnostics.

### Threat-Matrix RED Tests

Confirmed present and asserting as specified:

| Threat | Test | Confirmed |
|---|---|---|
| Subprocess argument composition — argv exact per command | `MutationCommandTests > Every command lowers to exactly its documented vector` over an 11-case table covering install/uninstall/reinstall/upgrade for both kinds, zap, upgradeAll, **and `pin --formula git` / `unpin --formula git`** | Yes — pin/unpin kind flags are in the table |
| Both kind flags never co-occur | `> No invocation ever carries both kind flags` (all 11 cases) | Yes |
| Exactly one kind flag per package-naming command | `> Every package-naming command carries exactly one kind flag` — a property over the whole vocabulary, so a seventh verb cannot silently skip it | Yes |
| Inspected argv == spawned argv | `> The argv that reaches the process seam is the argv that was inspected` via `RecordingProcessLauncher.specs` | Yes |
| Option injection | `> A name that is empty or option-looking is refused at construction` over `["", "-rf", "--prefix", "-", " ", "\t", "wget curl", "wget\nrm"]` | Yes |
| Display string is never a source of argv | `> No public API turns a command string back into argv`; `> Argv is only ever produced from typed cases` | Yes |
| Untrusted stderr — sudo signature | `ClassificationTests > Every sudo signature with a non-zero exit is the typed privilege failure` over the three probed signatures | Yes |
| Untrusted stderr — lock-busy signature per probe #7097 | `> The probed lock output classifies as busy` using the live-probed brew 6.0.14 strings; both phrases match independently | Yes |
| No holder-name parsing from brew's message | `> A busy message naming an unrelated command still classifies busy, silently`; message built only from Cellar's typed command | Yes |
| Adversarial payload | `> A successful run whose output contains a prompt signature is not a failure`; `> A signature appearing only on stdout does not classify`; `> Only the stderr tail is scanned, so a huge log classifies in bounded time` | Yes |

### Issues Found

**CRITICAL**: None.

**WARNING**:

- **WARNING-1 — the `swift test` gate is intermittently red because of a pre-existing flaky test
  that this change did not touch.** `CatalogStoreTests.swift:122`, "A sync that lands while the
  store is running replaces the results", failed once in five full-suite runs and passed 6/6 in
  isolation. Cause: line 120 does `await store.refreshNow()` and line 122 reads `store.results`
  **without polling**, while a sibling test in the same file documents at lines 81-84 that
  "the engine yields `.snapshot` before `.succeeded`, and adoption is now an `await` ... so
  results land one or more turns ahead of the status". Line 116 in the same test correctly uses
  `await poll { store.results.count == 2 }`; line 122 does not. Under full-suite parallel load
  the adoption turn has not run when the assertion fires. Evidence it is not this change's
  defect: `git log 2fe1c0d..4064465 -- .../CatalogStoreTests.swift` is **empty**, and no
  `Sources/Catalog` file appears in this branch's diff. This change did, however, raise suite
  parallelism (345 → 432 tests), which is plausibly what made a latent race start surfacing.
  Recommended fix (out of scope here, one line): replace the bare `#expect` at line 122 with
  `await poll { store.results.count == 3 }` followed by the same assertion. Does not block
  archive; should be raised as a follow-up before the flake erodes trust in the gate.

- **WARNING-2 — PM4 scenario "Standard input is never interactive" is only half testable at the
  seam the spec names.** The scenario reads "GIVEN a recording process spawner ... THEN the
  recorded standard input for the process is `/dev/null`". `ProcessSpec` carries
  `executableURL`, `arguments` and `environment` only — it has **no** stdin field — so a
  recording launcher structurally cannot observe stdin and no test asserts it at any layer. The
  behaviour is genuinely implemented, at `SystemProcess.swift:50`
  (`process.standardInput = FileHandle.nullDevice`), in untouched M1 code below the seam. The
  scenario's second clause ("no password input surface was offered") *is* covered, by
  `ClassificationTests > The outcome offers no credential surface, no retry and no escalation`.
  Classified PARTIAL rather than UNTESTED because half the scenario passes at runtime and the
  other half is verified by inspection of a one-line, unchanged assignment. To make the scenario
  testable as written, `ProcessSpec` would need a `standardInput` field carried through to
  `SystemProcess` — a small, low-risk change worth a follow-up.

- **WARNING-3 — two scenarios say "untruncated" while the design caps the log at 2,000 lines.**
  PM4 sc3 ("its full output remains readable, verbatim and untruncated") and OA3 sc3 ("every
  emitted line is still present, verbatim and untruncated") are literally true only for logs of
  ≤ 2,000 lines. `ActivityItem.logCapacity` is 2,000 and `append` evicts the oldest line past
  that. This is **design-sanctioned, not an apply deviation**: design D4 specifies a "2,000-line
  ring with a truncation marker", `design.md:251` and the test plan at `design.md:276` both name
  it, and tasks 7.3/7.4 implement it under RED/GREEN. The intent behind both scenarios — no
  per-line mutilation (no trimming, re-encoding, reordering, deduplication, prefixing or
  annotation) — is fully met, and the loss is never silent: `isLogTruncated` surfaces it, pinned
  by `OperationCenterTests > The 2,001st line evicts the oldest and raises the truncation
  marker`. A `brew upgrade` over a large machine can exceed 2,000 lines, so this is reachable in
  practice. Recommend the archive step amend both scenarios to state the bound explicitly (e.g.
  "verbatim, and untruncated up to the ring capacity, with truncation surfaced") so the promoted
  spec matches shipped behaviour rather than overstating it.

**SUGGESTION**:

- **SUGGESTION-1** — suppress the mutation's own post-terminal FSEvents echo. Extending gate
  suppression by a short grace window past `end()`, or having the coordinator ignore signals
  whose timestamp precedes the terminal re-snapshot, would remove one redundant
  `brew info --installed` per mutation. Conforming today (see RULING 2); purely an efficiency
  nicety.
- **SUGGESTION-2** — consider a duplicate-submission guard. Permitted today and arguably correct
  (see RULING 3), but collapsing an identical in-flight submission would spare the user a queue
  item that can only end in "already installed".
- **SUGGESTION-3** — `skippedRecordCount` is still never surfaced and runner records are never
  evicted. Both are explicitly listed as "still open, not fixed here" at `design.md:201-202`, so
  they are carried forward knowingly; worth entering in the follow-up register rather than
  losing at archive.
- **SUGGESTION-4** — the sudo signature set remains unprobed against a live sudo-requiring cask
  (`design.md:316-318`). A miss degrades safely to `.failed` with the log visible, so this is
  low risk, but the strings should be confirmed opportunistically and widened when they are.

### Verdict

**PASS WITH WARNINGS**

All 15 requirements and all 60 scenarios are implemented and covered by named tests that passed
at runtime; 73/73 tasks are complete; the build and both declared gates succeed; SwiftLint adds
zero new findings; `package-search` is byte-identical to `main`; and every apply deviation was
checked and found real, benign and spec-consistent. Nothing blocks archive. The three warnings
are one pre-existing flaky test this change did not touch, and two places where the spec's
literal wording is narrower than what the design deliberately shipped — both of which the
archive step should reconcile in the promoted spec text rather than in code.
