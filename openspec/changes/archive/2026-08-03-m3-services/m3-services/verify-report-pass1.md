```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:1a3aa701b75aac86cb1e86ef6f2e21b916f6faf05b2418b99e8f4e221aa8c61f
verdict: fail
blockers: 1
critical_findings: 1
requirements: 22/22
scenarios: 86/92
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:04b9132237d3e99f7bef5654aa55148fc2780cdb8446fce4312885f320bc81d8
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:90e1f5254a1240535f89c83ae9f62f061e0700372f21a5300b1982e598c9695e
```

## Verification Report

**Change**: m3-services (M3-1 — Service Management)
**Branch**: `feature/m3-services` @ `1165a1e`, base `main` @ `3f2c166`
**Mode**: Strict TDD
**Artifact store**: hybrid
**Delivery**: `exception-ok`, `size:exception` recorded at task 0.2 — size not re-litigated
**Receipt-driven development**: disabled/unmanaged (kill switch off; no review lifecycle command run)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 84 |
| Tasks complete | 83 |
| Tasks incomplete | 1 — 16.1, reserved for the user, correctly unchecked |
| Delta requirements | 22 (12 ADDED + 10 MODIFIED) |
| Delta scenarios | 92 |

Task 16.1 is the only unchecked task and it is reserved by design. Under the standard SDD gate an
unchecked task blocks full verification; here it is the user's own manual-verification task and the
orchestrator explicitly instructed that it must stay unchecked, so verification proceeded and the
owed manual work is enumerated below instead.

### Build & Tests Execution

**Build**: PASSED — `xcodebuild build … -destination 'platform=macOS,arch=arm64'` → `** BUILD SUCCEEDED **`, exit 0, **zero** `warning:` lines in the raw log.

**Package tests**: PASSED — `swift test --package-path Packages/CellarCore` → **676 tests in 94 suites passed, 1 known issue**, exit 0. Baseline was 571/77, so +105 tests. The 1 known issue is the same pre-existing one recorded at task 0.1.

**Full Xcode suite**: PASSED — `xcodebuild test … -destination 'platform=macOS,arch=arm64'` → `** TEST SUCCEEDED **`. Run alone, per batch 1's false-red lesson. **Scope note, recorded because it changes what this proves**: this scheme runs `cellarTests` (exactly **one** test, `example()`) and `cellarUITests` (4 untouched Xcode-template tests). It does **not** run the CellarCore package suites. `** TEST SUCCEEDED **` is therefore not corroboration of the 676; it is corroboration that the app target links and launches. The app target has no behavioural coverage at all — VS3, restated with a number.

**Real-brew integration**: the self-skipping ESC test really runs on this machine — `Real Homebrew integration > No escape byte survives capture from a real brew invocation` passed. BE1 sc3 has genuine runtime evidence, not a skip.

**Lint**: `swiftlint --quiet` = **60**, equal to the 0.1 baseline. Zero new.

**File length**: largest source file `OperationCenter.swift` at 391; every new and touched file under 400. Confirmed.

**Coverage**: no coverage tool configured — skipped, not a failure.

### Independent re-verification of the orchestrator's checks

| Claim | Re-checked | Result |
|---|---|---|
| 676 tests / 94 suites, 0 failures, 1 known issue | yes | confirmed |
| `InstalledChangeObserving.swift` 0 changed lines | yes | confirmed, file absent from the diff |
| No `isSettling` / `settleGrace` in sources | yes | `rg` over `Sources/` + `cellar/` = 0 |
| `BulkSelection.Action` exactly two cases | yes | confirmed, and pinned by `ServiceSubmissionTests` |
| 60 files, +6,942/−188 | yes | confirmed |
| `openspec/specs/package-mutation/spec.md` changed header prose only | yes | **confirmed** — the whole diff is 10 insertions / 3 deletions inside the capability header, lines 2–12. No requirement text, no scenario, no heading. It is the only shipped spec touched on this branch |

### Strict TDD — mutation claims re-proven, not accepted

Batch 2 named nine mutation verifications. Four tests were written **after** their production code with
RED obtained by mutation. I re-ran those mutations myself in a throw-away worktree at `1165a1e`.

| Claim | Mutation applied | Observed | Verdict |
|---|---|---|---|
| D4 containment (11.6) — moving the marker pass to the shared default fails **both** containment tests | inlined the marker pass into `BrewMutating`'s default `classify` | `packageClassificationIsByteIdentical` failed with 10 issues at `:116`; `aPayloadContainingAServiceMarkerCannotReclassifyAnInstall` failed with 4 issues at `:140/141/149/150` | **RE-PROVEN** |
| 9.3 — broadcasting instead of intersecting fails at `isMutating → true` | `MutationGates.begin/end` broadcast to every gate | `InstalledRefreshScopeTests:96` — `(harness.mutations.isMutating → true) == false` | **RE-PROVEN, on the exact assertion named** |
| 9.4 — the same mutation fails at `installed.value → 1` | same | `OperationCenterScopedHistoryTests:62` — `(installed.value → 1) == 0`, on all three recorder shapes | **RE-PROVEN, on the exact assertion named** |
| 13.1–13.2 — fabricating a `PackageID` and de-namespacing a verb each fail them by name | `packageID` returned `PackageID(.formula, target.name)`; verbs de-namespaced | fabrication failed `ServiceHistoryTests:68/72/76/97`; de-namespacing failed `:50/60/96/122/146` | **RE-PROVEN** |
| 13.3 — "same" (RED by the same two mutations) | both mutations | `HistoryStoreTests > aNullPackageServiceEntryIsFindableByVerbAndByItsArgv` **passed under both** | **NOT REPRODUCED — see WARNING 1** |

I additionally checked out `main`'s `HistoryStore.swift` under the branch's tests: 13.3 passes against
unmodified production code. It is a genuine, well-formed characterization test of an already-correct
behaviour — but it never had a RED, and the apply record says it did.

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | PASS | Two tables, batch 1 and batch 2, preserved verbatim |
| All behavioural tasks have tests | PASS | 44 RED tasks; every named test file exists |
| RED confirmed | PASS with one exception | 4 of 5 mutation-obtained REDs re-proven on the named assertion; 13.3 not reproducible |
| GREEN confirmed | PASS | every named test passes at runtime now |
| Triangulation | PASS | 55 command×payload pairs, 10 hostile names + 6 legitimate, 12 argv vectors, 8 statuses, 3 terminal kinds |
| Safety net | PASS | counts recorded per task and monotonically increasing (571→626→676) |

### Assertion Quality

Audited every new test file. **No** tautologies, **no** ghost loops, **no** assertion that never calls
production code, **no** smoke-test-only tests. Every structural scan anchors positively before
asserting an absence (the M3-0 lesson), including `nothingParsedFromBrewsOutputReachesAnArgv`
(`#expect(source.contains("func classify"))`) and `theServicesSurfaceDeclaresNoNotification`
(`sources.count >= 5` plus two positive content checks). Loop-bounded assertions carry an explicit
count guard (`compared == 55`, `commands.count == 12`).

Three `!= nil` type-only assertions exist (`ServicesStoreTests:249`, `MutationCommandTests:173-177`)
but each sits beside a value assertion in the same test. Not flagged.

**Assertion quality**: all assertions verify real behaviour.

### Test Layer Distribution

| Layer | Tests | Notes |
|-------|-------|-------|
| Unit | 104 of the 105 added | `swift test`, no process or one fake process |
| Integration | 1 | real `brew`, self-skipping, `.tags(.realBrew)` — verified to actually run here |
| UI / app-target | 0 | `cellarTests` contains one `example()` placeholder; `cellarUITests` is untouched template code |

### Spec Compliance Matrix

`service-management` (12 ADDED requirements / 40 scenarios)

| Req | Scenario | Proving test | Result |
|---|---|---|---|
| SM1 | One invocation per refresh, exact argv | `ServicesPayloadTests > One refresh records exactly one invocation with the exact argv` | COMPLIANT |
| SM1 | All seven statuses decode | `ServicesDecodeTests > All seven statuses decode to their own case` | COMPLIANT |
| SM1 | Unrecognised status never fails the payload | `ServicesDecodeTests > An unrecognised status preserves the raw string…` + `brew's own other status is not the catch-all` | COMPLIANT |
| SM1 | Null user and null exit code decode as absent | `ServicesDecodeTests > A null user and null exit code decode as absent` | COMPLIANT |
| SM2 | Detail fetched only for the selected service | `ServicesStoreTests > Detail is fetched only for the selected service, once, and never with --all`; `ServicesPayloadTests > The detail probe names exactly one service and never uses --all` | COMPLIANT |
| SM2 | A poll tick fetches no detail | `ServicesRefreshTests > A poll tick fetches no detail` | COMPLIANT |
| SM2 | Null optional keys decode as absent | `ServicesDecodeTests > Null optional info keys decode as absent` | COMPLIANT |
| SM2 | Identical log/error-log paths presented once | `ServicesDecodeTests > Identical log and error-log paths are presented once` + `A service declaring only an error log presents exactly that one` | COMPLIANT |
| SM3 | Refreshes on the poll cadence while visible | `ServicesRefreshTests > The list refreshes on the five-second cadence while visible` + `Four seconds … buys no refresh` | COMPLIANT |
| SM3 | Hiding stops polling entirely | `ServicesRefreshTests > Hiding the surface stops polling entirely` + `No process is spawned at all while the surface is hidden` + `Hiding the window stops polling even while the section is still selected` | COMPLIANT |
| SM3 | Only one poll loop per launch | `ServicesRefreshTests > Only one poll loop runs per launch` (counts clock sleepers, not probes) | COMPLIANT |
| SM3 | Polling suppressed while a mutation is in flight | `ServicesRefreshControlTests > Polling is suppressed while a service mutation is in flight` | COMPLIANT |
| SM4 | Each verb produces its exact argv | `ServiceCommandTests > Each verb produces its exact argv` | COMPLIANT |
| SM4 | No service argv contains --all | `ServiceCommandTests > No service argv ever contains --all` | COMPLIANT |
| SM4 | kill and stop --keep not offered | `ServiceCommandTests > kill and stop --keep are not offered` | COMPLIANT |
| SM4 | Several services enqueue one each, in order | `ServiceSubmissionTests > Acting on several services enqueues one operation each, in order` | COMPLIANT |
| SM4 | Installed bulk vocabulary unchanged | `ServiceSubmissionTests > The installed bulk vocabulary is unchanged` | COMPLIANT |
| SM5 | The two actions submit different commands | `ServiceCommandTests > The two actions submit different commands, neither derived from the other` | COMPLIANT |
| SM5 | Neither action is a hidden default | `ServiceCommandTests > The row control surface is exactly the five enumerated controls` | COMPLIANT |
| SM6 | A cold start is classified as started | `ServiceClassificationTests > A cold start is classified as started` | COMPLIANT |
| SM6 | Already-running start classified from the marker | `ServiceClassificationTests > A start on an already-running service is classified from the marker, not the exit code` | COMPLIANT |
| SM6 | Already-stopped stop classified from stderr | `ServiceClassificationTests > A stop on an already-stopped service is classified from its stderr warning` | COMPLIANT |
| SM6 | Unmatched outcome is never a success | `ServiceClassificationTests > An unmatched outcome is never a success it did not earn` + `The success line corroborates but never decides` | COMPLIANT |
| SM6 | Nothing parsed reaches an argv | `ServiceClassificationContainmentTests > Nothing parsed from brew's output reaches an argv` | COMPLIANT |
| SM7 | Root warning on a zero exit is still a success | `ServiceClassificationTests > A root-domain warning on a zero exit is a success, not a privilege failure` | COMPLIANT |
| SM7 | Rejected bootstrap is a generic failure, log intact | `ServiceClassificationTests > A rejected bootstrap is a generic failure with its log intact and no retry` | COMPLIANT |
| SM7 | **No password surface — spawned stdin is the null device** | **(none)** | **UNTESTED** |
| SM8 | Success refreshes services once, inventory never | `MutationGatesTests > A command that does not declare the installed set takes no inventory snapshot`; `ServicesRefreshControlTests > A successful service verb refreshes services once, with no poll running` | COMPLIANT |
| SM8 | Failed/cancelled still refreshes services once | `ServicesRefreshControlTests > A failed or cancelled service verb still forces exactly one services refresh` | COMPLIANT |
| SM9 | A dying service shows as failed at the next poll | `ServicesStoreTests > A changed status replaces the previous one rather than being retained` + `ServicesPresentationTests > A changed status replaces the previous one`, composed with the SM3 cadence tests | COMPLIANT |
| SM9 | No notification requested or delivered | `ServicesPresentationTests > The services capability declares no notification, badge or blocking alert` (positively anchored; scans CellarCore only — the four app-target views were checked by hand and are also clean) | COMPLIANT |
| SM10 | Second op for the same service refused | `ServiceSubmissionTests > A second operation for the same service is refused while one is in flight` | COMPLIANT |
| SM10 | A different service is not blocked | `ServiceSubmissionTests > A different service is not blocked` | COMPLIANT |
| SM10 | Guard released at the terminal outcome | `ServiceSubmissionTests > The guard is released at the terminal outcome` | COMPLIANT |
| SM11 | Absent brew: empty list with guidance | `ServicesStoreTests > Absent brew gives an empty list with guidance and no spawn` + `An invalid configured path is guidance carrying the rejection reason` | COMPLIANT |
| SM11 | Verb with brew absent spawns nothing | `ServiceSubmissionTests > Absent brew spawns nothing for any of the four verbs` | COMPLIANT |
| SM11 | Services populate when brew appears | `ServicesStoreTests > The list populates when brew appears, with no restart` + `ServicesRefreshTests > Polling begins when brew appears while the surface is already visible` | COMPLIANT |
| SM12 | **Installed projection declares no service field** | **(none)** — `InstalledModels.swift` is byte-unchanged vs `main`, so nothing was added, but no test enumerates its fields | **UNTESTED** |
| SM12 | Catalog query declares no service predicate | `InstalledFilterFavoritesTests > The catalog query's declared filter set contains no installed or favorite predicate` asserts the filter set **exhaustively** (`== ["excludeDeprecated","excludeDisabled","kinds"]`), so a service predicate would fail it. The second half — "no service term was added to the search index" — has no test; `Sources/Catalog/` contains zero occurrences of "service" and is byte-unchanged | PARTIAL |
| SM12 | **A name collision does not join the two** | **(none)** | **UNTESTED** |

`brew-execution` (1 MODIFIED / 3 scenarios)

| Scenario | Proving test | Result |
|---|---|---|
| Environment applied to every invocation | `EnvironmentTests > theSpawnedProcessReceivesTheSuppressionKeyAndNotTheForceKey` | COMPLIANT |
| The force-colour key is never set at any value | `EnvironmentTests > theForceColourKeyIsNeverSetAtAnyValue` | COMPLIANT |
| No ANSI escape byte survives capture | `BrewIntegrationTests > No escape byte survives capture from a real brew invocation` — **confirmed to actually execute** on this machine | COMPLIANT |

`installation-history` (3 MODIFIED / 14 scenarios)

| Req | Scenario | Proving test | Result |
|---|---|---|---|
| IH1 | sc1–sc4 (carried forward) | shipped `HistoryRecordingTests` / `HistoryStoreTests` | COMPLIANT |
| IH1 | Each service verb writes one entry with a null package identity | `ServiceHistoryTests > Each service verb writes one entry with a null package identity` | COMPLIANT **on storage**; see ADJUDICATION 1 for the verb spelling and CRITICAL 1 for the display |
| IH1 | Repeated toggling appends one entry per operation | `ServiceHistoryTests > Repeated toggling appends one entry per operation` | COMPLIANT |
| IH5 | sc1–sc4 (carried forward) | shipped `HistoryStoreTests` | COMPLIANT |
| IH5 | Null-package entry findable by verb and argv | `HistoryStoreTests > A null-package service entry is findable by verb and by its argv` | COMPLIANT (characterization — passes unchanged against `main`) |
| IH7 | sc1–sc2 (carried forward) | shipped `OperationCenterHistoryTests` | COMPLIANT |
| IH7 | A failing recorder does not affect a non-package operation | `OperationCenterScopedHistoryTests > A failing recorder changes neither the outcome nor the per-domain refresh counts` | COMPLIANT |

`installed-inventory` (1 MODIFIED / 9 scenarios)

| Scenario | Proving test | Result |
|---|---|---|
| sc1–sc7 (carried forward) | shipped `InstalledRefreshTests` / `InstalledStoreTests` | COMPLIANT |
| An operation that does not invalidate the installed set forces no re-snapshot | `MutationGatesTests > A command that does not declare the installed set takes no inventory snapshot` (asserts on the literal argv, across succeeded/failed/cancelled) | COMPLIANT |
| External signals are not suppressed by a non-invalidating operation | `InstalledRefreshScopeTests > External signals are not suppressed by a non-invalidating operation` | COMPLIANT |

`operation-activity` (1 MODIFIED / 6 scenarios)

| Scenario | Proving test | Result |
|---|---|---|
| sc1–sc5 (carried forward) | shipped `OperationCenterHistoryTests` / `UnknownOperationTests` | COMPLIANT |
| An operation with no package identity records exactly one entry | `ServiceHistoryTests > Each service verb writes one entry with a null package identity` + `A no-change outcome records one entry naming itself` + `A refused duplicate submission writes no entry of its own` | COMPLIANT |

`package-mutation` (4 MODIFIED / 20 scenarios)

| Req | Scenario | Proving test | Result |
|---|---|---|---|
| PM1 | sc1–sc5 (carried forward) | `MutationCommandTests` | COMPLIANT |
| PM1 | Another family enters the spine without becoming a case | `BrewMutatingTests > Another family enters the spine without becoming a case of the mutation command type` | COMPLIANT |
| PM4 | A cask that asks for a password fails with Terminal guidance | `ClassificationTests > Every sudo signature with a non-zero exit is the typed privilege failure` | COMPLIANT |
| PM4 | **Standard input is never interactive** (carried forward) | **(none)** — pre-existing gap, not caused by this change | **UNTESTED** |
| PM4 | An unrecognised failure keeps the raw log | `ClassificationTests` | COMPLIANT |
| PM4 | A non-fatal privilege warning on a successful run is not a sudo failure | `ServiceClassificationTests > A root-domain warning on a zero exit is a success…` + `A genuine sudo signature on a failed run still reaches the typed failure` | COMPLIANT |
| PM4 | **A non-package operation runs with the same non-interactive stdin** | **(none)** | **UNTESTED** |
| PM6 | sc1–sc3 (carried forward, re-bodied) | `MutationGatesTests > A command declaring the installed set refreshes it exactly once at every terminal` (success / non-zero / typed busy / cancelled) | COMPLIANT |
| PM6 | A command not declaring the installed set takes no inventory snapshot | `MutationGatesTests` (same-named test) | COMPLIANT |
| PM6 | Failed/cancelled non-inventory command still refreshes what it declared | `MutationGatesTests > Declaring both domains refreshes both, and declaring none still settles`; `ServicesRefreshControlTests` | COMPLIANT |
| PM7 | sc1–sc3 (carried forward) | shipped `OperationCenter` availability tests | COMPLIANT |
| PM7 | A non-package family is equally unavailable when brew is absent | `ServiceSubmissionTests > Absent brew spawns nothing for any of the four verbs` | COMPLIANT |

**Compliance summary**: 86 / 92 scenarios COMPLIANT, 1 PARTIAL, 5 UNTESTED. Of the 5 UNTESTED, 1 (PM4
sc2) is pre-existing and not caused by this change.

### Coherence (Design D1–D9)

| Decision | Followed | Notes |
|---|---|---|
| D1 `BrewMutating`, generic parameters, one erased value | Yes | Protocol is `Sendable`-only; `AnyBrewMutation` is `Sendable, Equatable, Hashable`; `MutationCommand` conforms in a 3-line extension declaring only `invalidates` |
| D2 `InvalidationScope`, `forcesReSnapshot` deleted | Yes | Confirmed: zero occurrences in `Sources/` and `cellar/`; `1<<2`/`1<<3` reserved by comment and not declared |
| D3 poll loop, not a `LoopOwner` slot | Yes | `pollTask` owned by the coordinator, cancelled **and** niled; `LoopOwner.start("services")` runs only `run()` |
| D4 marker pass, family-owned, stdout widened | Yes | Override on `ServiceCommand` only; default untouched; containment re-proven by mutation |
| D5 `HOMEBREW_NO_COLOR` | Yes | Key swapped, doc comment corrected, real-brew ESC test executes |
| D6 absorbed register items | Yes | Sticky failure reason; `pendingConfirmation` has no setter at all; `ServiceSubmissionGuard` services-scoped; VS4 not adopted, recorded |
| D7 reads, decoders, store | Yes, with one recorded deviation | Constant list argv; the one parameterised read argv puts the validated name last and separate; `@concurrent` decode satisfies "off the main actor". Deviation: `ServicesStore` opens no container — recorded, and `LocalStoresTests > oneContainerServesBothStores` still holds |
| D8 services UI | Yes structurally, **No on failure presentation** | `AppSection` 5th case, four views, `LogFileOpening` seam, four visible verbs. But "Brew-absent → read-only guidance … No new rule" was implemented as *only* a brew-absent branch, discarding `.idle`/`.loading`/`.failed` — see HIGH 1 |
| D9 four verbs, namespaced | Yes | `serviceStart/Run/Stop/Restart`; `--all` unrepresentable because no case omits a target — see ADJUDICATION 1 |

Deviations recorded in `apply-progress.md` (`ServiceTarget` moved not redeclared; concrete overloads for
leading-dot inference; `MutationConfirmation` reads the verb; `OperationCenterSummary.swift` and three
test splits; `ConfirmationBox` in `OperationCenterBulk.swift`) are all real, all benign, and all match
the shipped code.

---

## The four adjudications the apply phase deferred

### ADJUDICATION 1 — verb naming: **the spec text is wrong, not the code**

The shipped verbs are `serviceStart` / `serviceRun` / `serviceStop` / `serviceRestart`. The
`installation-history` delta's IH1 sc5 says "each carrying its own verb — `start`, `stop`, `restart`,
`run`".

**Ruling: the implementation is right and the delta text must be amended before archive.**

Reasons, in order of weight:

1. IH5's own requirement text — in the same delta — says the search must match "the operation verb —
   including the non-package service verbs `start`, `stop`, `restart` and `run`". `serviceStop`
   satisfies that by case-insensitive substring, and `HistoryStoreTests > A null-package service entry
   is findable by verb and by its argv` proves it at runtime. So the namespaced form satisfies **every
   IH5 scenario**.
2. The bare form is affirmatively unsafe for IH5. `MutationCommand` already ships a verb vocabulary of
   `install/uninstall/reinstall/upgrade/zap/upgradeAll/pin/unpin`. A bare `run` or `start` entering it
   creates a search vocabulary where a future package verb could collide with a service verb and the
   user could not tell which they matched. Design D9 states exactly this reason; the delta text states
   no reason at all — it simply inherited the four words from the product vocabulary.
3. `ServiceCommandTests > Each verb records under its own namespaced name` already asserts
   `Set(verbs).isDisjoint(with: packageVerbs)`. Reverting to bare verbs would break that assertion,
   which exists to protect IH5.

Strictly read, IH1 sc5's THEN clause is not literally satisfied by the shipped bytes. That is a spec
defect, not a code defect. **Required before archive**: edit
`openspec/changes/m3-services/specs/installation-history/spec.md` IH1 sc5 to read `serviceStart`,
`serviceStop`, `serviceRestart`, `serviceRun`, and add one sentence to IH1's requirement body stating
that a non-package family namespaces its verbs so the IH5 search vocabulary cannot collide. IH5's own
text already reads correctly as a *search input* and needs no change. This is a text-only edit with no
code consequence. Until it is made, IH1 sc5 is COMPLIANT-in-substance and non-conformant-in-letter.

### ADJUDICATION 2 — task 11.1's override was **correct**

Task 11.1 required `$(…)` and `;` to be rejected at construction. Apply refused. That refusal is right.

- `MutationName.isSafe` (`MutationCommand.swift:104-107`) is exactly `!isEmpty && !hasPrefix("-") && !contains(where: \.isWhitespace)`. Verified by reading it.
- The `package-mutation` delta says PM9 is untouched. Widening `isSafe` would change package
  construction rules the delta explicitly preserves — a real spec violation in the opposite direction.
- **No spec scenario requires the rejection.** SM4 requires exact argv; the threat matrix in
  `design.md` requires it, and the threat matrix is a design artifact, not a requirement.
- The replacement test is stronger than the one it replaced: `shellMetacharactersSurviveAsOneLiteralArgument`
  runs `$(whoami)`, `atuin;rm`, `` `id` ``, `a|b`, `a&b`, `a>b` through the **real** `BrewRunner` and
  `RecordingProcessLauncher` and asserts `spec.arguments == ["services","stop",name]` with
  `spec.arguments.last == name`. That proves the property that actually protects the user — argv is a
  vector, no shell exists — rather than a rejection that would have been theatre.
- The hostile names that *are* rejected are still covered: `""`, `-`, `-rf`, `--all`, `--json`, spaces,
  tabs, `atuin redis`, `atuin\nrm`, `a;rm -rf /`. And `legitimateServiceNamesAreAccepted` stops the
  gate from passing vacuously.

**No requirement went unimplemented.** Residual, LOW: `tasks.md` 11.1 and `design.md`'s threat-matrix
row still say `;` and `$(…)` are "rejected at construction", and 11.1 is checked `[x]`. Two planning
artifacts now describe a behaviour the code deliberately does not have. Fix the text before archive so
a future reader does not treat it as a regression.

### ADJUDICATION 3 — `forcesReSnapshot` at `MutationGatesTests.swift:255` is a **correct exception**

Confirmed at HEAD:

- `rg 'forcesReSnapshot'` over `Packages/CellarCore/Sources` and `cellar/` → **zero matches**.
- The only match in the whole repository outside markdown is
  `MutationGatesTests.swift:255`: `#expect(source.contains("forcesReSnapshot") == false, "the outcome still decides invalidation")`.

That is the guard asserting the member is gone. A guard cannot forbid a name without naming it. The
exception is correct, correctly recorded, and the guard is doing real work — it is a source scan over
`MutationOutcome.swift`, so re-adding the member fails it. **Accepted, no action.**

### ADJUDICATION 4 — D4's stdout widening: containment **re-proven independently**

I applied the mutation myself rather than trusting the record: I moved the marker pass into
`extension BrewMutating`'s default `classify` (the shared default every package command uses), rebuilt,
and ran the containment suite.

Both containment tests failed, on exactly the assertions that name the leak:

- `packageClassificationIsByteIdentical` — 10 issues at `:116`, `(command.classify(…) → .noChange) == (MutationOutcome.classify(…) → .succeeded)`
- `aPayloadContainingAServiceMarkerCannotReclassifyAnInstall` — 4 issues at `:140`, `:141`, `:149`, `:150`, `(onStdout → .noChange) == .succeeded` and the stderr twin

The design is also sound on its own terms, and I checked the code rather than the prose:

- `ServiceCommand.classify` guards `fault == nil, exit.isSuccess, Marker.isNoChange(in: log)` — a fault,
  a cancellation and a non-zero exit are all decided by the default **before** any marker is consulted,
  so a marker can never rescue a failure or mask a cancel.
- The two markers are membership tests on interior invariants; nothing is captured or extracted, and
  `nothingParsedFromBrewsOutputReachesAnArgv` proves both behaviourally (argv byte-identical after
  classifying a hostile payload; message echoes nothing) and structurally (no `range(of:`,
  `components(separatedBy:`, `split(separator:`, `firstMatch`, `replacingOccurrences` … in the file).
- The regression anchor deliberately includes the two service-marker payload rows, without which the
  55-pair comparison would still pass under the leak. That is the detail that makes the anchor bite,
  and it is why the mutation failed it.

**Accepted. The most review-sensitive decision in this slice is the best-defended one in it.**

---

## Issues Found

### CRITICAL

**CRITICAL 1 — Every service history entry renders in the History list as "All packages".**

`cellar/History/HistoryRow.swift:63-65`:

```swift
private var title: String {
    record.name.isEmpty ? "All packages" : record.name
}
```

A service entry stores a null package identity, which `SwiftDataHistoryRecorder.swift:46-47` persists as
`kindRaw: ""`, `name: ""` — the same sentinel the grouped `upgradeAll` uses. `HistoryRow` reads only
`name`, so `brew services stop atuin` is displayed to the user under the title **"All packages"**.

Why this is CRITICAL, not cosmetic:

- It is a **false statement about what happened**. Stopping one service is presented as an operation
  over every package on the machine. This is the same failure shape as M2-3's IH6 CRITICAL.
- It fires on the very first service toggle any user performs. It is not an edge case.
- It defeats the purpose of the null identity that IH1 was amended for. IH1 says a null-package entry
  "MUST NOT synthesize, borrow or infer a package identity". Storage obeys that; the presentation layer
  then invents a *worse* identity than the one IH1 forbade.
- **`tasks.md` MV-7 predicted it exactly**: "*Expect*: … **no** package name rendered as a package
  identity for any of them." MV-7 was never obtained. This is the check the manual plan existed for.

The information needed to fix it is already stored: `verb` distinguishes `upgradeAll` from
`serviceStart`/`serviceRun`/`serviceStop`/`serviceRestart`. Fix is a few lines in `HistoryRow.title`
(and it deserves a `cellarTests` or a `HistoryRecord`-level projection test, since the app target
currently has none).

**This blocks archive.**

### HIGH

**HIGH 1 — `ServicesListView` presents a failed and a loading services list as an affirmative "no services".**

`cellar/Services/ServicesListView.swift:50-69` branches on `services.absence != nil` only. But
`ServicesStore.state` is a five-case `ServicesLoadState` — `idle`, `loading`, `loaded`,
`brewAbsent(_)`, `failed(ServicesError)` — and `absence` is non-nil only for `brewAbsent`. So both of
these render the string *"No services — Homebrew is not managing any background services on this Mac."*:

- `.idle` / `.loading` — every cold entry into the Services section, for the ~0.37 s the probe takes.
  Guaranteed to be seen on every visit.
- `.failed(error)` with no last-good list — a non-zero exit, a malformed payload or a cancelled probe
  is reported to the user as a confident factual claim that is false, and the error is discarded.

This is not a delta-scenario violation — `service-management` writes no requirement about presenting a
failed list probe. It is a violation of **this project's own established precedent**:
`cellar/Installed/InstalledEmptyState.swift` switches over all five `InstalledLoadState` cases and
renders `.idle/.loading` as "Reading installed packages" and `.failed` as "Could not read installed
packages" with `error.shortDescription`. The sibling surface gets it right; the new one does not.

The fix is a `switch services.state` in place of the `if let absence`, mirroring `InstalledEmptyState`.
`ServicesError` is a closed enum, so it is exhaustive by construction. I recommend fixing this in the
same pass as CRITICAL 1.

**HIGH 2 — Two new spec scenarios about non-interactive stdin have no runtime evidence at all.**

`service-management` SM7 sc3 ("that process's standard input is the null device") and
`package-mutation` PM4 sc5 ("A non-package operation runs with the same non-interactive stdin") are
both new in this slice and neither has a covering test. `rg` over the whole test tree finds **no**
assertion mentioning `standardInput`, `nullDevice` or `/dev/null`.

The property does hold: `Sources/BrewProcess/SystemProcess.swift:50` sets
`process.standardInput = FileHandle.nullDevice` unconditionally, that file is **byte-unchanged** on
this branch, and every service command lowers to `.mutate` through the same `BrewRunner` path. So this
is a coverage gap, not a defect. It is also knowingly caused: the register keeps **M2-2 #8** ("carry
`standardInput` through `ProcessSpec`") deferred, which is precisely the seam that would make it
observable, and the register's stated reason ("stdin observability stays cosmetic") was written before
this slice added two scenarios that assert it.

The carried-forward PM4 sc2 has the same gap and is **pre-existing** — not caused by this change.

Two honest resolutions, either acceptable: implement M2-2 #8 (small — one field on `ProcessSpec` and
one recording assertion), or amend SM7 sc3 / PM4 sc5 to assert the structural guarantee the codebase
can actually observe. What is not acceptable is archiving them as proven.

### MEDIUM

**MEDIUM 1 — SM12's three scenarios are the thinnest-covered requirement in the slice.**

- sc1 ("the installed projection declares no service field") — no test. `InstalledModels.swift` is
  byte-unchanged vs `main`, so nothing was added, but nothing pins it either. An analogous exhaustive
  test already exists for the catalog filter set (`InstalledFilterFavoritesTests`), so the idiom is
  available and cheap.
- sc2 — the filter-set half is covered by an existing exhaustive equality; the search-index half is not.
- sc3 ("a name collision does not join the two") — no test. The property holds structurally
  (`ServicesStore` never reads `InstalledStore`; it borrows only `InstalledAbsence`, which is
  detection guidance, not inventory data), but the scenario is written as a behavioural claim and is
  unproven.

SM12 is the requirement whose whole job is to stop a service being modelled as a package — and
CRITICAL 1 is a service being displayed as a package. The two are related.

**MEDIUM 2 — `ServiceDetailView` reports a failed detail probe as "No service selected".**

`ServicesStore.select` swallows a failed `services info --json <name>` into `detail = nil`
(`ServicesStore.swift:245-250`), while `selected` stays set. `ServiceDetailView` branches on
`detail != nil` only, so a service whose detail probe failed shows *"No service selected — Select a
service to see where it is installed and what it logs."* while a service **is** selected. `selected`
is already `public`; the view has everything it needs to say the truth. Same shape as HIGH 1, smaller
blast radius.

**MEDIUM 3 — the services list is probed once per app launch and once per app activation even when the Services section has never been shown.**

`cellarApp.refreshEverything()` calls `servicesRefresher.refresh(for:)` unconditionally;
`ServicesRefreshCoordinator.refresh(for:)` calls `store.refresh(...)` and only then consults
`syncPolling()`, which is the visibility gate. So a user who never opens Services still pays one
`brew services list --json` (~0.37 s) per foreground activation.

Read strictly, SM3 forbids only *polling* while not visible, and it separately mandates a baseline on
becoming visible — so this is not a scenario violation, and `InstalledRefreshCoordinator` behaves the
same way for the inventory. But it contradicts the requirement's own headline ("polls only while
visible") and the design's "zero cost while hidden" framing, and it is exactly what MV-2(c) exists to
observe. Decide it deliberately: either gate the baseline on visibility too, or state in SM3 that a
launch/activation baseline is permitted regardless of visibility.

**MEDIUM 4 — closing one of two windows stops the poll while another window still shows Services.**

`setVisible` is a single shared boolean on an app-lifetime coordinator, driven by every
`ServicesListView.onDisappear`. With two windows both showing Services, closing either one reports
`setVisible(false)` and stops the poll for both. SM3 sc3 only requires that never **more than one**
loop runs, which holds, so this violates no scenario. It is a visibility-refcount gap, not a leak.

### LOW

**LOW 1 — `tasks.md` 11.1 and `design.md`'s threat-matrix row still claim `;` and `$(…)` are rejected at construction**, and 11.1 is checked `[x]`. Reconcile the text to what shipped (see ADJUDICATION 2).

**LOW 2 — apply's TDD evidence overstates task 13.3.** The row says RED was obtained "by two mutations". Neither mutation reaches that test, and it passes unchanged against `main`'s `HistoryStore`. It is a valid characterization test of pre-existing behaviour — say that, rather than claiming a RED it never had.

**LOW 3 — `ServiceControls`' Copy-command control copies `brew services start <name>` regardless of the service's current state** (`ServiceControls.swift:60`). Defensible as a default, but the label says "Copy command" without saying which one.

**LOW 4 — the `InstalledMutationGate` naming debt is now load-bearing in two domains.** Already registered in `follow-ups.md`; restated here only because the app now constructs two instances of an installed-named type, one of which is the services gate.

### SUGGESTION

- `ServicesListView` passes `.tag(service.id)` inside `List(data, selection:)`, which already derives the tag from `Identifiable`. Harmless, but redundant.
- The app target's `cellarTests` bundle contains exactly one `example()` test. Because `xcodebuild test` reports `** TEST SUCCEEDED **` on that basis, the phrase is easy to misread as corroboration of the package suite. Worth one sentence in the archive report, and worth noting that CRITICAL 1 and HIGH 1 both live in exactly the untested target.

---

## Manual verification still owed by a human

Task 16.1 is correctly unchecked. Apply obtained four half-checks live on brew 6.0.15 and claimed
nothing more. **Nothing below is treated as passed.** Build first:

`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`

Already obtained during apply, and **not** owed again: MV-3's `~/Library/LaunchAgents` discriminator
(with the finding that `start` on an *already running* service does not register it, so MV-3 must be
run from a **stopped** service or it reports a false negative); MV-4's four classification markers
byte-for-byte; MV-5's data half (`log_path == error_log_path == /opt/homebrew/var/log/atuin.log`);
MV-11's byte half on the services path (0 ESC bytes pinned, 3 under the old key).

**Still owed, in full — 8 whole checks and 4 GUI halves:**

1. **MV-1** — select Services in the sidebar; confirm `atuin` is listed with status `none`, matching `brew services list`, with no error state and no empty-state placeholder. *(Run this one first: it is the check that would expose HIGH 1's loading flash.)*
2. **MV-2 (a)** — with Services visible, watch Activity Monitor filtered to `brew`; expect a short-lived process roughly every 5 s.
3. **MV-2 (b)** — `brew services start atuin` from Terminal; expect the row to flip to `started` within ~5 s with no user action.
4. **MV-2 (d)** — `brew services stop atuin` from Terminal, then re-show Services; expect `none` at the baseline refresh.
5. **MV-3, GUI half** — enumerate the controls on the `atuin` row: expect exactly five, labelled Start at login / Run once / Stop / Restart / Copy command, with no single control that chooses between start and run.
6. **MV-4, GUI half** — click Start, Start again, Stop, Stop again; record all four Activity summary labels verbatim. Expect the two repeats to read **"No change"**, not "Done" and not a failure.
7. **MV-5, GUI half** — select the started `atuin` row; expect status, user and plist `file` matching the JSON, **exactly one** log location (the two paths are the same file on this machine), and Open in Console opening that exact file.
8. **MV-6** — with `atuin` started, double-click Stop as fast as possible; expect exactly **one** operation in the Activity list, never two and never a queued start-then-stop pair. After it settles, click Stop again and confirm it enqueues normally.
9. **MV-7** — after MV-4, open History; expect one entry per click, each showing its service verb and exact argv, and **no** package name rendered as a package identity. Search `atuin` → only the service entries; search `stop` → only the stop entries; confirm the count matches the number of clicks. **This is the check that CRITICAL 1 will fail. Re-run it after the fix.**
10. **MV-8** — with Activity Monitor showing `brew` processes, click Start on `atuin`; expect the `services start` invocation and a `services list --json` refresh, and **no** `brew info --installed --json=v2` process at any point.
11. **MV-9** (FIXTURE-DRIVEN — temporary local patch that **MUST be reverted and MUST NOT be committed**) — point `ServicesStore`'s payload source at the Phase 2 fixture, build, open Services; expect eight rows (`started`, `none`, `scheduled`, `stopped`, `error`, `unknown`, `other`, `mystery`), failure states visibly red, the unrecognised one showing its raw string. Screenshot, revert, rebuild, confirm `git status` clean.
12. **MV-10** — if a configured-brew-path affordance is reachable, point it at a nonexistent path; expect an empty list with the app's ordinary read-only guidance (not an error state), all four controls unavailable with that guidance attached, and **no** `brew` process spawned. Restore afterwards. **If no such affordance is reachable, say so explicitly** — coverage then rests on tasks 4.2 and 12.3 and must be recorded as such.
13. **MV-11, GUI half** — open a service operation's log in the Activity drawer; expect no `[34m`-style garbage; copy it out and confirm no `033` byte.
14. **MV-12** — with `atuin` started and Services visible, `pkill -f atuin`; expect the row to show brew's real status within ~5 s (record whether it is `error` or `none`), and — this is the point — **no** system notification, **no** permission prompt, **no** badge, **no** blocking alert. If launchd relaunches it too fast, record that and fall back to task 6.4.

Restore the machine afterwards: `atuin` stopped, no `~/Library/LaunchAgents/homebrew.mxcl.atuin.plist`,
no `atuin` daemon running.

### Verdict

**FAIL** — 1 CRITICAL (service history entries are displayed as "All packages"), 2 HIGH, 4 MEDIUM,
4 LOW. The engineering underneath is strong: 676/94 green, zero new lint, zero build warnings, scope
guards hold, and the slice's most review-sensitive decision (D4's stdout widening) survived an
independent mutation. Every defect found is in the app target — the one target with no automated
coverage — and the check that would have caught the CRITICAL, MV-7, was written before apply and never
run. Route back to `sdd-apply` for the view-layer fixes and the IH1 sc5 spec amendment, then re-run
MV-1 and MV-7 before archive.
