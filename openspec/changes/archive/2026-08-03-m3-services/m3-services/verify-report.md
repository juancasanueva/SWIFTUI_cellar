```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:bad0d5228618f92a4963ecd3ae14189043d7a7ecb337eb8cd763e6ff961e6e68
verdict: fail
blockers: 2
critical_findings: 0
requirements: 22/22
scenarios: 90/93
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:8cda0aed7ec423169b799573fa1944e96ecedb6a2eb009b9af016b07c0be3a92
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:b3af7f2bd1f13b7e3de77dd119d2bcec2790a44ad6de30991be773e9956d9a5b
```

## Verification Report — PASS 2 (post-remediation)

**Change**: m3-services (M3-1 — Service Management)
**Branch**: `feature/m3-services` @ `4b8f0d3`, base `main` @ `3f2c166`
**Mode**: Strict TDD
**Artifact store**: hybrid
**Receipt-driven development**: disabled/unmanaged (kill switch off; no `gentle-ai review *` lifecycle command was run, and none is claimed)
**Pass 1**: preserved byte-identically at `openspec/changes/m3-services/verify-report-pass1.md`
(sha256:8271fc5f700b99662ab79b0440f08610a154b2f196eeee053ac9ee3e440ba49b) — the same bytes Engram
obs 7191 recorded. Nothing from the first pass was discarded or rewritten.

**Verdict in one line**: every code and spec defect the first pass found is either fixed and proven at
runtime or correctly registered as open — **0 CRITICAL, 0 HIGH remain** — but the slice is **not
archive-ready**, because MV-7 and MV-1, the only end-to-end evidence for the two fixes, have still
never been run by a human, in the one target with zero automated coverage.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 94 (Phase 18 added 10 during remediation) |
| Tasks complete | 93 |
| Tasks incomplete | 1 — **16.1**, correctly unchecked, reserved for the user |

Task 16.1 is not a bookkeeping omission. It is the compensating control the VS3 ruling accepted in
place of a UI harness, and it is the gate this report holds open. See *Archive gate* below.

### Build & Tests Execution

**Tests**: ✅ `Test run with 693 tests in 96 suites passed after 15.524 seconds with 1 known issue`
— exit 0. The one known issue is pre-existing (`OperationCenterCancelTests.swift:183`, a deliberate
`withKnownIssue` guard), not a failure.

**Build**: ✅ `** BUILD SUCCEEDED **` — exit 0, zero warnings.

**Lint**: `swiftlint --quiet` = **60**, identical to the 0.1 baseline. Zero new.

**Coverage**: ➖ no coverage tool configured for this package. Not a failure; recorded as unavailable.

### Coverage reality — carried into every judgement below

`xcodebuild test -scheme cellar` runs `cellarTests` (one `example()` placeholder) and `cellarUITests`
(four template tests). The repository's only shared scheme is `CellarCore.xcscheme`. A
`** TEST SUCCEEDED **` from the app scheme is **not** corroboration of the 693 and is not used as
such anywhere in this report. **The app target has no automated coverage**, and that is precisely
where both top findings of pass 1 lived. Every app-target claim in this pass is therefore weighted as
source inspection only, never as runtime evidence.

### Independent re-verification of the orchestrator's spot-checks

| Claim | Result |
|---|---|
| `swift test` → 693 tests / 96 suites, 0 failures, 1 known issue | ✅ reproduced, exit 0 |
| `git diff main...HEAD --shortstat` = 67 files, +8,278/−206 | ✅ reproduced exactly |
| `cellar/History/HistoryRow.swift` title is `record.subject.label` | ✅ confirmed at `:69-71` |
| Working tree clean at `4b8f0d3` | ✅ `git status --porcelain` empty |

---

## Adjudication of the five remediation claims

### CLAIM 1 — CRITICAL 1 fixed. **UPHELD.**

`Packages/CellarCore/Sources/Persistence/HistoryPresentation.swift:46-49`:

```swift
public var subject: Subject {
    guard name.isEmpty else { return .package(name) }
    return verb == MutationCommand.upgradeAll.verb ? .everyPackage : .noPackage
}
```

Identity first, verb second, exactly as claimed. `cellar/History/HistoryRow.swift:69-71` reads
`record.subject.label` and owns no rule. `rg '"All packages"'` over non-markdown sources returns the
projection itself, its doc comments, its tests, and one unrelated `InstalledListView` section header
(`includeDependencies ? "All packages" : "Installed on request"`) — **no surviving sentinel logic**.
`rg 'record\.name|\.name\.isEmpty'` over `cellar/` and `Sources/` returns exactly one hit,
`ServiceCommand.swift:49`, which constructs a `ServiceTarget` and renders nothing.

**The degradation path was checked specifically, as instructed.** It is the strongest part of the
fix. `HistorySubjectTests > anUnknownNullIdentityVerbDegradesToNoPackage` drives five hostile verbs
— `""`, `"somethingNew"`, `"upgradeall"`, `"UpgradeAll"`, `"upgrade"` — and asserts `.noPackage` for
every one. Two of those five are near-misses of the grouped spelling and one is the bare package
verb: the comparison is exact and case-sensitive, so a null-identity verb this build does not
recognise **cannot** reach `.everyPackage`. The grouped label really is opt-in. `theGroupedVerbsDurableSpellingIsPinned`
additionally pins `MutationCommand.upgradeAll.verb == "upgradeAll"`, so a rename without a migration
fails loudly instead of silently reclassifying every stored grouped upgrade as "no package".

RED was claimed by ordering (`no member 'subject'`, 3 sites). That is inherently unreproducible after
the fact and is accepted on the apply phase's record rather than re-proven — the test file cannot
compile against a `main` that lacks the member, which is itself the ordering claim. Weight: adequate,
and the substantive proof is the eight passing tests plus the source scan above, not the RED claim.

**Residual, stated plainly**: `HistorySubjectTests` proves the *projection*. Nothing automated proves
that `HistoryRow` *renders* it — that link is one line, and I have read it, but reading is exactly
the evidence class that let CRITICAL 1 ship. This is what makes MV-7 blocking.

### CLAIM 2 — HIGH 1 fixed. **UPHELD.**

`ServicesLoadState.emptyState` (`ServicesPresentation.swift:93-100`) switches all five cases with no
`default`, so a sixth state could not be absorbed into "no services". `ServicesListView`'s private
`ServicesEmptyStateView` switches the four `ServicesEmptyState` cases and renders `state.title` /
`state.message`; the view owns symbols and layout only.

`ServicesEmptyStateTests` (six tests) proves it at runtime: `anUnansweredLoadDoesNotClaimThereAreNoServices`
asserts `.idle`/`.loading` never contain "not managing"; `aFailedProbeReportsTheFailure` drives all
four `ServicesError` cases and asserts the message *equals* the failure reason and is never empty;
`onlyAnAnsweredEmptyListClaimsThereAreNone` filters all eight states and asserts **exactly one**
claims absence. That last assertion is the right shape — it is a property over the whole state set,
not a spot check, so a future state that quietly maps to `.nothingManaged` fails it.

RED by ordering, same weighting as CLAIM 1. Same residual: the view's rendering of the projection is
proven by inspection only. That is what makes MV-1 blocking.

### CLAIM 3 — HIGH 2 fixed at the real seam, NOT deferred. **UPHELD, and re-proven by me.**

`ProcessSpec` was not widened. `git diff main...HEAD -- Packages/CellarCore/Sources/BrewProcess/`
returns **only** `BrewEnvironment.swift` (+15/−3): **`SystemProcess.swift` is byte-unchanged against
`main`**, as claimed.

I re-ran the named mutation myself. Commenting out `SystemProcess.swift:50`
(`process.standardInput = FileHandle.nullDevice`) and running `--filter SystemProcessTests`:

```
Test "A spawned mutation reports the same null device…" recorded an issue at SystemProcessTests.swift:141:9:
  Expectation failed: (reported.text → ["3905500540 Fifo File"]) == (["\(null) Character Device"] → ["336 Character Device"])
Test "A spawned read reports its own standard input as the null device" recorded an issue at SystemProcessTests.swift:126:9:
  Expectation failed: (reported.text → ["3905500540 Fifo File"]) == (["\(null) Character Device"] → ["336 Character Device"])
Test run with 8 tests in 1 suite failed after 0.003 seconds with 2 issues
```

Both tests failed, at exactly the two lines claimed, on both the `.read` and the `.mutate` path. The
harness's own stdin is a **pipe** (`Fifo File`), so the discriminator genuinely discriminates in this
environment. File restored; `git status --porcelain` empty afterwards.

The inode discriminator is the right call and is itself defended: `theNullDeviceIdentifiedByInodeNotByBeingACharacterDevice`
asserts `/dev/null` and `/dev/zero` have different inodes, which is what stops the assertion from
being satisfiable by "some character device". A device-class-only assertion would have passed with
stdin wired to a terminal — the one thing it must catch.

This is the strongest piece of evidence added by the remediation, and it is better than either option
pass 1 offered. **SM7 sc3, PM4 sc2 and PM4 sc5 move from UNTESTED to COMPLIANT** with runtime
evidence at the production seam.

### CLAIM 4 — IH1 sc5 amended to the namespaced spellings, code untouched. **UPHELD.**

`git show 4b8f0d3 -- .../installation-history/spec.md` touches only that file's IH1 body, its delta
table row and sc5. No source file changed for this claim.

### CLAIM 5 — stale text corrected. **UPHELD.**

`tasks.md` 11.1 no longer mentions `;` or `$(…)` at all; its parameterisation is now leading-`-`,
empty, whitespace and `--all`. `design.md`'s *Subprocess argument composition* row now states
explicitly that a shell metacharacter is **not** rejected and must not be, names `MutationName.isSafe`'s
exact rule, and points at `shellMetacharactersSurviveAsOneLiteralArgument` as the real guarantee.
Both LOW 1 halves are closed.

---

## The two deviations remediation flagged

### DEVIATION A — the IH1 amendment is larger than ADJUDICATION 1 asked for. **JUSTIFIED. ACCEPTED.**

The argument is correct, and pass 1's own numbers prove it. Pass 1 reported 86 COMPLIANT / 1 PARTIAL
/ 5 UNTESTED = 92. **CRITICAL 1 appears nowhere in that matrix.** A shipped, user-visible false
statement — `brew services stop atuin` titled "All packages" — violated no scenario, because IH1
constrained storage and said nothing about presentation. A requirement set in which the worst defect
of the slice is unrepresentable is an incomplete requirement set, not a complete one that happened to
be violated. Widening it is the correct response; leaving IH1 as-is would have shipped a fix with no
requirement behind it and no scenario to regress against.

The added text is correctly written:

- It is **strictly additive**. The diff removes no MUST, weakens no clause and deletes no scenario;
  the delta remains a strict superset, so the slice's zero-destructive-delta property holds.
- The presentation clause names both failure modes the defect actually had — presented as every
  package, and presented under the service's own name — rather than only the one that shipped.
- The new scenario asserts **both** sides in one place: the grouped entry *is* presented as every
  package, and the service entry is not. A one-sided scenario would have been satisfiable by a
  projection that simply stopped saying "All packages" at all.
- It stays inside `installation-history`. Presentation of a history entry is that capability's own
  business; nothing leaks into `service-management`.

**Reconciled count: delta scenarios 92 → 93, requirements unchanged at 22.** Independently recounted
from the six delta files (`rg -c '^#### Scenario:'`), not taken from the claim — see the per-capability
table below, which sums to exactly 22 / 93.

One SUGGESTION on the writing: IH1's trailing `(Previously: …)` note still lists only the verb
vocabulary, the null-package shape and collapsing. It was not updated to say that presentation was
also previously undefined. Cosmetic, non-blocking, but it should be corrected at archive so the
promoted requirement's own history is accurate.

**On the ordering** (test → fix → spec, rather than spec → test → fix): this is a real process
deviation and I record it as such, at WARNING. It is not a Strict TDD violation — RED still preceded
GREEN, which is what the TDD gate asserts. The spec lagged because the requirement gap was only
*discovered* by the fix. Under a clean process the amendment would have been an `sdd-spec` step
before Phase 18. The mitigating fact is that the amended text describes the behaviour that was
independently proven, rather than being back-fitted to whatever the code happened to do — I checked
the scenario against the tests rather than against the implementation, and it holds either way.

### DEVIATION B — task 18.7's RED is mutation-obtained, not ordering-obtained. **HONEST. ACCEPTED.**

The production line predates the branch, so an ordering RED is *impossible* for it, and claiming one
would have been the dishonest option. The task is labelled **"RED (by mutation, named)"** in
`tasks.md:798` — the evidence class is disclosed in the artifact, not buried. The mutation is named
to the exact line, and I reproduced it myself with the identical failure signature at the identical
two assertion sites. Mutation-obtained RED is *stronger* evidence than ordering RED here, because it
demonstrates the test discriminates against the real production line rather than merely against its
absence.

This also retires pass 1's LOW finding about a false mutation claim on 13.3: that one was corrected
in place and relabelled a characterization test. 18.7 did not repeat the error.

---

## Reconciled scenario count

| Capability | Delta type | Requirements | Scenarios |
|---|---|---:|---:|
| `service-management` | ADDED | 12 | 40 |
| `package-mutation` | MODIFIED | 4 | 20 |
| `installation-history` | MODIFIED | 3 | **15** (was 14) |
| `installed-inventory` | MODIFIED | 1 | 9 |
| `operation-activity` | MODIFIED | 1 | 6 |
| `brew-execution` | MODIFIED | 1 | 3 |
| **Total** | | **22** | **93** |

### Movement since pass 1

| Scenario | Pass 1 | Pass 2 | Evidence |
|---|---|---|---|
| SM7 — spawned stdin is the null device | ❌ UNTESTED | ✅ COMPLIANT | `SystemProcessTests > aSpawnedReadReportsTheNullDeviceAsItsStandardInput`, mutation-verified |
| PM4 — standard input is never interactive | ❌ UNTESTED | ✅ COMPLIANT | same suite, `.read` path |
| PM4 — a non-package operation runs with the same non-interactive stdin | ❌ UNTESTED | ✅ COMPLIANT | `> aSpawnedMutationReportsTheSameNullDevice`, `.mutate` path |
| IH1 — a null-package entry is never displayed as a package or as every package | *(did not exist)* | ✅ COMPLIANT | `HistorySubjectTests` — 8 tests incl. the degradation path |
| SM12 — installed projection declares no service field | ❌ UNTESTED | ❌ UNTESTED | MEDIUM 1, registered |
| SM12 — catalog query declares no service predicate | ⚠️ PARTIAL | ⚠️ PARTIAL | MEDIUM 1, registered |
| SM12 — a name collision does not join the two | ❌ UNTESTED | ❌ UNTESTED | MEDIUM 1, registered |

**Compliance summary: 90 / 93 scenarios COMPLIANT, 1 PARTIAL, 2 UNTESTED.** The three residual rows
are all SM12 and all belong to MEDIUM 1, which is registered as open with its reason and its closing
condition. Requirements: **22 / 22 implemented**.

---

## TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | Phase 18 rows present in `apply-progress.md` and `tasks.md` |
| All tasks have tests | ✅ | 3 new test files for 3 fixes; 18.8/18.9 are documentation tasks by nature |
| RED confirmed | ✅ | 18.1/18.4 by ordering (accepted on record); **18.7 by mutation, re-proven by me** |
| GREEN confirmed | ✅ | 693/693 pass on my own execution at `4b8f0d3` |
| Triangulation adequate | ✅ | 18.1 → 8 tests incl. 5 hostile verbs; 18.4 → 6 tests over 8 states; 18.7 → 3 tests over 2 command kinds |
| Safety net for modified files | ✅ | `ServicesPresentation.swift` and `SystemProcessTests.swift` were modified, not new; full suite green before and after |

**TDD compliance: 6/6.**

### Assertion Quality — the three new test files

| File | Finding |
|---|---|
| `HistorySubjectTests.swift` | ✅ clean. No tautology. The verb loop is anchored by `#expect(verbs.count == 4)` before it runs, so it cannot pass vacuously. `theThreeSubjectsAreDistinct` asserts variance (`Set(...).count == 3`) rather than a single expected value. |
| `ServicesEmptyStateTests.swift` | ✅ clean. Loops iterate literal non-empty arrays; `#expect(Self.everyState.count == 8)` anchors the total mapping test. Assertions are on values and on set cardinality, not on types or on mock call counts. |
| `SystemProcessTests.swift` | ✅ clean, and the best in the slice. Asserts an exact string containing an independently-derived inode, plus an exact `BrewExit`. `theNullDeviceIsIdentifiedByInode…` exists solely to prove the discriminator discriminates. |

**Assertion quality: ✅ all assertions verify real behaviour. 0 CRITICAL, 0 WARNING.**

### Test Layer Distribution

| Layer | Tests | Note |
|-------|------:|------|
| Unit (pure value / projection) | majority of 693 | `swift-testing`, `@Suite`/`@Test`/`#expect` throughout |
| Integration (real `Foundation.Process`, real brew) | `SystemProcessTests` (8), `BrewIntegrationTests` | the three stdin tests spawn `/usr/bin/stat` through the production runner |
| E2E / UI | **0** | no XCUITest harness exists — VS3, still open |
| **Total** | **693 in 96 suites** | |

---

## Still-open items — confirmed registered, not silently dropped

All six are in `openspec/changes/m3-services/follow-ups.md` under *"Registered by batch 3, from the
verify report, and deliberately not fixed in it"*, each with why it is open and what would close it.
Confirmed present and accurate: **MEDIUM 1, MEDIUM 2, MEDIUM 3, MEDIUM 4, LOW 3, SUGGESTION**. LOW 4
(`InstalledMutationGate` naming debt) is carried in the same file's *"remaining open items"* table.

### MEDIUM 2 — reasoning independently confirmed at source

Remediation says closing MEDIUM 2 requires `ServicesStore` to retain the detail probe's failure
reason. **That reasoning holds.** `ServicesStore.select` (`ServicesStore.swift:226-251`):

```swift
} catch {
    // A detail probe that fails costs the detail pane and nothing else…
    detail = nil
}
```

The error is bound and then **discarded entirely** — the store has no property that could carry it,
so the reason does not survive the call. `ServiceDetailView` (`ServiceDetailView.swift:29-37`)
branches `if let detail = services.detail` and otherwise renders "No service selected", so a failed
probe and a genuinely unselected pane are indistinguishable *and the information needed to tell them
apart no longer exists in the store*. HIGH 1 did not need this, because `ServicesLoadState.failed`
already carried its error. So MEDIUM 2 is strictly more work than HIGH 1, exactly as claimed, and it
is a **live defect of the same shape** in `ServiceDetailView` today.

The register states this precisely: *"It needs the store to keep the failure reason, which HIGH 1 did
not require."* Correctly registered.

---

## Issues Found

### CRITICAL — **None.**

Pass 1's single CRITICAL is fixed, proven, and now has a requirement behind it.

### HIGH — **None.**

Both are fixed. HIGH 2 is fixed better than either option pass 1 offered.

### WARNING

1. **Both fixes' last mile is proven by source inspection only.** `HistoryRow.title` reading
   `record.subject.label`, and `ServicesEmptyStateView` rendering `state.title` / `state.message`,
   are in the app target, which has zero automated coverage. The remediation did the right thing by
   hoisting each *rule* into CellarCore — that is the correct architectural response and it is what
   makes the rules provable at all — but the wiring itself is exactly the evidence class that let
   CRITICAL 1 ship. This is not a criticism of the fix; it is the reason MV-7 and MV-1 are blocking.
2. **Spec amendment ordering** (DEVIATION A): test → fix → spec instead of spec → test → fix.
   Disclosed by the remediation itself, mitigated by the amendment being checked against the tests
   rather than back-fitted to the implementation.
3. **MEDIUM 2 remains a live user-visible defect** in `ServiceDetailView`, of the identical shape to
   the HIGH that was just fixed. Correctly registered and correctly out of remediation scope, but it
   is a defect on the branch being archived, not merely a nice-to-have.
4. **SM12 remains the thinnest-covered requirement** in the slice: 2 UNTESTED + 1 PARTIAL of 3
   scenarios. Registered as MEDIUM 1. The properties hold structurally, but "structurally" is not
   runtime evidence and this report does not count it as such.

### SUGGESTION

1. **NEW — a failed refresh with a resident list surfaces nothing.** `ServicesListView` renders the
   empty state only inside `.overlay { if services.services.isEmpty { … } }`. If a refresh fails
   while a previous list is still resident — which `ServicesStore` deliberately supports — the user
   sees a stale list with no indication anything failed. This is **not a regression from the fix**:
   `InstalledListView.swift:79-83` has the identical shape, so it is a pre-existing whole-app pattern
   and consistent with the precedent HIGH 1 was told to follow. Worth one decision across both
   domains in a later slice, not a change to this one.
2. **NEW — IH1's `(Previously: …)` note is now incomplete.** It does not mention that presentation
   was previously undefined, although the requirement body now constrains it. Correct at archive.
3. Carried: `ServicesListView` passes a redundant `.tag(service.id)` inside `List(_:selection:)`.

---

## Archive gate — the manual verification question, answered plainly

**No. This slice cannot be archived with MV-7 and MV-1 unrun. They are now archive-blocking.**

The reasoning, stated without hedging:

1. Both of pass 1's top findings lived in the app target. That target has **no automated coverage**,
   and `xcodebuild test -scheme cellar` cannot supply any — it runs one placeholder plus four
   template tests.
2. The remediation's automated evidence proves the **rules** (`HistoryRecord.subject`,
   `ServicesLoadState.emptyState`). It does not, and structurally cannot, prove that the **views**
   read them. That link is currently held by my reading of two source files.
3. **MV-7 predicted CRITICAL 1 verbatim** — "no package name rendered as a package identity for any
   of them" — and was never run. Archiving now would mean shipping a fix for a defect that a written,
   unrun manual check had already anticipated, while still not running it. That is a repeat of the
   exact failure mode this slice already committed once.
4. MV-1 is the corresponding end-to-end check for HIGH 1: it asserts the services surface lists real
   state with "no error state, no empty-state placeholder" — the precise sentence HIGH 1 made false.
5. Both are cheap. MV-4 followed by MV-7 is roughly five clicks and one glance at the History pane.
   The cost of running them is trivial against the cost of a second false-claim defect reaching a user.

Task **16.1 must stay unchecked** until a human runs them and records what they saw. It is currently
unchecked and correctly so.

### Final deduplicated list of manual checks a human still owes, in run order

Machine baseline: `atuin`, status `none`, no plist, no daemon. Restore it at the end.

| # | Check | Why here in the order | Precondition |
|---:|---|---|---|
| 1 | **MV-1** — services surface lists real state | HIGH 1's end-to-end check; also gates every check below it | — |
| 2 | **MV-2 (a)(b)(d)** — 5 s poll while visible; external start reflected; external stop reflected at the baseline refresh | Confirms the list is live before any judgement is made from it. (c) was already obtained | leave `atuin` stopped after (d) |
| 3 | **MV-3, GUI half only** — enumerate the row's controls: exactly five, each self-describing, no control that chooses start-vs-run for the user | Needs `atuin` **stopped**; its live plist half was already obtained | `atuin` stopped |
| 4 | **MV-4, GUI half** — Start, Start again, Stop, Stop again; record all four Activity summary labels verbatim (expect Done / **No change** / Done / **No change**) | Produces the four history entries MV-7 reads | `atuin` stopped |
| 5 | **MV-7** — **the blocking check.** Open History. Four entries, one per click, each showing its service verb and exact argv, and **none titled "All packages" or "atuin"**. Search `atuin` → only service entries. Search `stop` → only stop entries. Count matches clicks | Must run immediately after MV-4. This is the check that predicted CRITICAL 1 | MV-4 done |
| 6 | **MV-6** — double-click Stop as fast as possible: exactly one operation, never a start-then-stop pair; then Stop again enqueues normally | Needs a started service | start `atuin` |
| 7 | **MV-8** — toggle and watch Activity Monitor: `services start` + `services list --json`, and **no** `brew info --installed --json=v2` at any point | Same started-service window as MV-6 | `atuin` started |
| 8 | **MV-5, GUI half** — detail pane: status, user, plist path match `brew services info atuin --json`; log dedupe rule as written; Open in Console opens that exact file | Same window; its data half was already obtained | `atuin` started |
| 9 | **MV-11, GUI half** — open the operation log in the Activity drawer: no `[34m` garbage, no `033` byte after copy-paste | Needs an operation to have run | after any of 4–8 |
| 10 | **MV-12** — `pkill -f atuin` with Services visible: real status within ~5 s, and **no** notification, **no** permission prompt, **no** badge, **no** alert | Destroys the started state, so it goes after 6–9 | `atuin` started |
| 11 | **MV-10** — brew-absent read-only guidance, if a configured-path affordance is reachable. **If it is not, say so explicitly and record that this coverage rests on tasks 4.2 and 12.3** — do not claim manual coverage that was not obtained | Independent of service state | restore the path after |
| 12 | **MV-9** — fixture-driven, all seven statuses plus the catch-all. Temporary local patch, **must be reverted, must not be committed**; confirm `git status` clean before continuing | Last, because it is the only one requiring a source patch and rebuild | revert + rebuild |

Of these, **#5 (MV-7) and #1 (MV-1) are the two that block archive.** The other ten are owed and
should be run, but they corroborate claims that already have headless proof; #1 and #5 are the only
end-to-end evidence for the two defects this remediation fixed.

---

## Verdict

**FAIL — not archive-ready.** Not for any code or spec defect: 0 CRITICAL, 0 HIGH, 22/22 requirements
implemented, 90/93 scenarios compliant with the 3 residuals correctly registered, 693/693 tests green,
build clean, lint at baseline, and every one of the five remediation claims upheld — with the stdin
mutation and the scenario counts re-proven independently rather than accepted. It fails on the one
gate remediation could not close: **MV-7 and MV-1 have still never been run**, and in a target with
zero automated coverage they are the only end-to-end evidence that the two fixes reach the user.

Run those two checks, record what you saw, and this slice is ready to archive. Nothing else is
outstanding that a human decision cannot close.
