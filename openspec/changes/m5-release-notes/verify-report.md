```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:6bd6cf43e968c0d20098e98483ad7a88a189bf0aadcd1fd57e18be757793e560
verdict: pass
blockers: 0
critical_findings: 0
requirements: 9/9
scenarios: 39/39
test_command: "swift test --package-path Packages/CellarCore"
test_exit_code: 0
test_output_hash: sha256:bdd1534e7e680b3fd9bb0fa5ac6e565c57f532dda3ff604b48a2c9683bebddbe
build_command: "xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'"
build_exit_code: 0
build_output_hash: sha256:e7851624d777b66c49ee5717617429cfb18ecc819fe4f26c1df86f480bb3359d
```

# Verification Report: m5-release-notes (re-verify after spy-race remediation)

**Change**: `m5-release-notes` (M5 slice 3 of 5) · **Mode**: hybrid · **Strict TDD**: active
**Base**: staged working tree atop `b3bd494` · **Delivery**: single-pr with accepted `size:exception`
**Verdict**: **PASS WITH WARNINGS** — 0 CRITICAL, 2 WARNING, 4 SUGGESTION
**Supersedes**: the verify-1 FAIL verdict (`evidence_revision sha256:1547e3af…`). This report replaces it in
full; all verify-1 findings are re-stated below with their current disposition.

## Executive Summary

The CRITICAL blocker is **resolved and independently re-proven**: `swift test --package-path
Packages/CellarCore` now exits **0 on three consecutive full-parallel runs executed by this verifier**,
1396 tests / 176 suites, with only the one pre-existing known issue. The `GlobalRequestSpy` process-global
counter is deleted; all five call sites use the per-instance, tag-keyed `RecordingNetwork`, where
cross-contamination is structurally impossible in both directions. Coverage did not shrink to buy the
green: the ReleaseNotes suite is still **187 tests / 17 suites**, all 77 `@Test` declarations across the
five touched files are intact, and net assertion count is unchanged. Both documentation warnings landed.
One new warning is raised — a test *this change added* consumes the M4 `CompositionRequestSpy`, which still
carries the identical latent shape.

---

## Re-Verify Test Evidence (per run, real exit codes)

| # | Command | Exit | Result | Output hash |
|---|---|---|---|---|
| 1 | `swift test --package-path Packages/CellarCore` | **0** | **1396 tests / 176 suites PASSED**, 1 known issue | `sha256:bdd1534e…` |
| 2 | `swift test --package-path Packages/CellarCore` | **0** | **1396 / 176 PASSED**, 1 known issue | `sha256:c8b685ac…` |
| 3 | `swift test --package-path Packages/CellarCore` | **0** | **1396 / 176 PASSED**, 1 known issue | `sha256:1c179623…` |
| 4 | `swift test … --filter <ReleaseNotes suites>` (parallel) | 0 | **187 tests / 17 suites PASSED** | — |
| 5 | `xcodebuild test -only-testing:cellarTests` | **0** | **TEST SUCCEEDED — 66 unique cases, 0 failures** | `sha256:cb1a12a6…` |
| 6 | `xcodebuild build -scheme cellar` | **0** | **BUILD SUCCEEDED** | `sha256:e7851624…` |
| — | full `xcodebuild test` (incl. `cellarUITests`) | not run | environment-blocked per user decision obs 7511 | — |

The single remaining known issue is the pre-existing `OperationCenterCancelTests` one
("Finishing a call that never launched…"), unrelated to this change and present on `main`.

Verify-1 recorded 6 of 6 parallel runs failing. Verify-2 records 3 of 3 passing — plus run 4 isolated. The
failure mode was deterministic enough that three clean runs is decisive rather than lucky.

## Remediation Assessment

### The fake is gone, with no orphans

`Fakes/GlobalRequestSpy.swift` is deleted. A repository-wide scan for `GlobalRequestSpy` returns **zero**
hits. `Fakes/` now contains only `RecordingURLProtocol.swift`.

### The replacement has no shared mutable state that can cross tests

Assessed statically against `Fakes/RecordingURLProtocol.swift`:

| Property | Finding |
|---|---|
| Claim scope | `canInit` returns `true` **only** when `X-Cellar-Release-Notes-Recorder` is present, so the protocol can never claim a request from any other session |
| Ledger isolation | `static let ledgers = Mutex<[String: Ledger]>([:])` — shared registry, but **keyed by a per-instance `UUID`**; each `RecordingNetwork` reads only `$0[tag]` |
| Counter | **No shared counter exists.** Exchanges append to the owning tag's ledger only |
| Reset semantics | No `install()`/`uninstall()`; nothing is ever zeroed, so the verify-1 false-zero hazard has no analogue |
| Global registration | None. `configuration.protocolClasses = [RecordingURLProtocol.self]` is per-session and *replaces* the list |
| Concurrency primitive | Swift 6 `Synchronization.Mutex`, not `NSLock` + `nonisolated(unsafe) static var` |
| Config provenance | Built from the **shipped** `ReleaseNotesSession.configuration()`, so a regression in the real session's cache/ephemeral settings would fail these tests rather than be bypassed — a genuine strengthening over a bespoke config |

Cross-contamination is structurally impossible in both directions. I found no residual shared mutable state.

### The two strengthened triangulations assert what is claimed

**`aRevokedGrantIssuesNoRequest`** (`ReleaseNotesConsentTests.swift:111-130`) — verified. It asserts the
revoked grant throws and `network.requestCount == 0`, then its control reaches **the shipped
`GitHubReleaseNotesSource`, on the same transport, through a real `authorise()` grant**, and asserts
`requestCount == 1`. This is strictly stronger than the verify-1 version, whose control was an unrelated
`URLSession.shared` call to a dead local port: the zero is now proven against the very code path under test.

**`theWholeFlowProducesExactlyTwoKindsOfEffect`** (`ReleaseNotesEgressStructureTests.swift:311-371`) —
verified. The `spy.observedCount == 0` assertion is removed and replaced by a comment deferring to the
structural claim. That claim is real and pre-existing: `urlSessionAppearsInExactlyOneFile` asserts
`URLSession`, `URLRequest` **and** `URLSessionConfiguration` appear in exactly one file of the target, and
`theOnePermittedFileReallyContainsTheSession` triangulates the scanner so the equality cannot pass by
finding nothing anywhere. **This migration is sound and arguably an upgrade**: the deleted runtime
assertion could only ever observe `URLSession.shared`, whereas the structural guard proves exhaustively
that no second session exists in the target at all. All other assertions in the flow test — exactly one
request, host `api.github.com`, exactly one file path touched, exactly one write, nothing else left in the
directory — are unchanged and pass.

### Coverage did not shrink to buy the green

| File | `#expect`+`#require` (v1 → v2) | `@Test` (v1 → v2) |
|---|---|---|
| `GitHubRepositoryResolverTests` | 59 → 59 | 16 → 16 |
| `ReleaseNoteRenderingTests` | 53 → 53 | 18 → 18 |
| `ReleaseNotesConsentTests` | 32 → **33** | 11 → 11 |
| `ReleaseNotesEgressStructureTests` | 40 → **39** | 16 → 16 |
| `ReleaseTagMatcherTests` | 36 → 36 | 16 → 16 |
| **Net** | **220 → 220** | **77 → 77** |

The −1 is precisely the migrated `observedCount` assertion; the +1 is the strengthened control. No test was
deleted, disabled, `.serialized`-around, or weakened. Package totals are identical to verify-1 at
1396 tests / 176 suites, and the ReleaseNotes subset at 187 / 17.

### Diff since the recorded verify-1 state is confined as described

Files modified since the verify-1 evidence run: the five test files
(`GitHubRepositoryResolverTests`, `ReleaseNoteRenderingTests`, `ReleaseNotesConsentTests`,
`ReleaseNotesEgressStructureTests`, `ReleaseTagMatcherTests`), the deleted `Fakes/GlobalRequestSpy.swift`,
and the two OpenSpec docs (`design.md`, `tasks.md`) — plus this report. **No production source file was
touched.** Confirmed by mtime comparison against the verify-1 evidence log and by the staged tree.

The remediation ran 279 lines against a 200-line bound; the maintainer authorised the widening via ledger
reset. Recorded here as instructed, not treated as a defect.

## Verify-1 Findings — Current Disposition

| Verify-1 finding | Disposition |
|---|---|
| **CRITICAL-1** `GlobalRequestSpy` process-global counter, suite red, bidirectional false-zero hazard | ✅ **RESOLVED** — fake deleted, per-instance tagged recorder, 3/3 clean parallel runs |
| **WARNING-1** unrecorded `nonisolated(unsafe)` design deviation | ✅ **RESOLVED** — `design.md` Apply-Time Amendment **16** records all five declarations, names the design line it contradicts ("that is now inaccurate"), justifies each, and confirms no `@unchecked Sendable` and no `#available` ship |
| **WARNING-2** `tasks.md` 6.7 said `data(for:)` | ✅ **RESOLVED** — task 6.7 now reads `bytes(for:)` and explains why the original was wrong, citing amendment 1 |
| **WARNING-3** E2E layer unexecuted | ⚠️ **STANDS** — carried below as WARNING-A |
| **WARNING-4** two scenarios rested on the unreliable spy | ✅ **RESOLVED** — both now rest on the per-instance recorder with real triangulation |
| **SUGGESTION-1** consider `.serialized` on the egress suite | ➖ **OBSOLETE** — the per-instance design removes the need |
| **SUGGESTION-2** RN-R1 prose vs amendment 14's non-catalog homepage fallback | ⚠️ **STANDS** — carried below |
| **SUGGESTION-3** 403 fixture `content-length` invariant | ⚠️ **STANDS** — carried below |

Amendment **17** records the remediation itself, including the false-zero hazard in the terms verify-1
raised it. Old amendment 16 (XCUITest) is correctly renumbered **18**. The amendment log is honest and
specific; nothing was absorbed silently.

## Spec Compliance

All **9 requirements / 39 scenarios** now have a covering test that **passed at runtime in this
verifier's own run**. The verify-1 matrix is unchanged except for the three previously-degraded rows:

| Scenario | Verify-1 | Verify-2 |
|---|---|---|
| RN-R1 *Unresolvable is a typed answer, and costs nothing* | ⚠️ | ✅ `resolutionIssuesNoRequestAtAll` on the per-instance recorder |
| RN-R3 *A release body cannot cause a second egress* | ⚠️ | ✅ `renderingIssuesNoRequest` on the per-instance recorder |
| RN-R9 *The whole flow spawns no brew process* | ❌ | ✅ `theWholeFlowProducesExactlyTwoKindsOfEffect` + two structural guards |

**Totals: 39 ✅ / 0 ⚠️ / 0 ❌.**

Everything verify-1 confirmed remains true and was re-confirmed by the passing runs: five distinct
outcomes with `401` classified before any exhaustion check and before any decode; rate-limit refusals never
cached; two-tier TTL over an injected clock; union resolution with tie-break-only ordering and 37 reserved
first segments refused; `_1` and `,456` suffix normalisation; drafts never matching and prereleases only on
an exact tag; the page-full qualifier distinct from a bare no-releases; one-request-per-open and
zero-on-bulk; the compile-gated grant token; the Keychain `baseQuery` with its distinct service name
compared as live symbols; Markdown degradation including the `javascript:`-link strip; and zero egress
without consent.

## Confirmations (re-checked at the staged tree)

| Check | Result |
|---|---|
| `CatalogFootprintTests` zero-line diff and passing | ✅ |
| pbxproj diff is exactly the four designed objects | ✅ 7 lines, ids `…012`/`…013` |
| No CatalogPackage / snapshot change; `currentSchemaVersion` still `2` | ✅ |
| No brew invocation in new code | ✅ |
| Consent copy equality assertion | ✅ `ReleaseNotesConsentSheet.whatIsSent == ReleaseNotesConsent.disclosure` |
| `cellarTests` cases | ✅ 66, 0 failures |

## Review Workload

| Field | Value |
|---|---|
| Authored (source, tests, fixtures) | **9,736** (was 9,783; the 64-line fake is gone) |
| OpenSpec lifecycle markdown | 1,789 |
| Session review budget | 5,000 |
| Status | Over budget by 4,736 authored lines — **covered by the USER-ACCEPTED `size:exception` (obs 7509)**. Recorded, not a blocker. |

## TDD Compliance

| Check | Result |
|---|---|
| TDD Evidence reported | ✅ 21-row table, obs 7510 |
| All tasks have tests | ✅ 69/69 tasks `[x]`, every named test file present |
| RED confirmed (tests exist) | ✅ 16 files verified |
| GREEN confirmed (tests pass) | ✅ **187/187 in parallel**, 3 consecutive clean package runs |
| Triangulation adequate | ✅ **improved** — the consent control now exercises the shipped source |
| Safety Net for modified files | ✅ `CatalogFootprintTests` zero-line diff; 66 `cellarTests` cases, none removed |

**TDD Compliance**: 6/6 checks passed.

**Assertion quality**: ✅ All assertions verify real behavior. Re-scanned the five changed files: no
tautology, ghost loop, orphan empty check, smoke-only case, or mock-heavy file. The migration removed no
assertion except the one whose claim moved to a stronger, triangulated structural guard.

---

## Issues

### CRITICAL

None.

### WARNING

**WARNING-A — A test this change added consumes the M4 `CompositionRequestSpy`, which retains the identical
latent shape.**

`cellarTests/ReleaseNotesCompositionTests.swift:219-236` (`decidingWhetherToOfferTheActionIssuesNoRequest`)
uses `CompositionRequestSpy` from `cellarTests/SecurityCompositionSupport.swift:179-215`, which still holds
`private static let counter = NSLock()` + `nonisolated(unsafe) private static var count = 0`, with
`install()` resetting the shared count and `uninstall()` **unregistering the shared `SpyProtocol` class
process-wide** — so with two concurrent users the first teardown blinds the other mid-test.

The coordinator flagged `SecurityCompositionSupport.swift` as a carried follow-up and "not this change's
defect". That is right about the **file** — it is pre-existing M4 code, and `SecurityCompositionTests.swift:140`
is its original consumer. It is not right about the **call site**: `ReleaseNotesCompositionTests.swift:235`
is new in this change and inherits the hazard, so this change does carry a share of it. Recording it
accurately matters because verify-1's CRITICAL was the same shape.

Why this is a WARNING and not a blocker:
- The `cellarTests` suite passes 66/66 with zero failures across both verify runs.
- This particular call site is also **untriangulated** — there is no paired `observedCount >= 1` control —
  so its realistic failure mode is a *vacuous pass* (the guard never proving it was consulted), not a red
  suite and not a false claim about product behaviour.
- The claim it guards is independently proven: `ReleaseNotesAffordance.isOffered` is a pure function over
  `RepositoryCandidates`, and resolver purity is proven in CellarCore by
  `resolutionIssuesNoRequestAtAll` on the per-instance recorder.

Suggested disposition: fold `SecurityCompositionSupport`'s spy into the same per-instance shape in a
follow-up change covering both M4 and this call site. Do not block archive on it.

**WARNING-B — E2E layer unexecuted.** Unchanged from verify-1. The four XCUITest cases in
`cellarUITests/ReleaseNotesUITests.swift` are written and compile but were not run; the breakage is
machine-wide and proven pre-existing on clean `main`. Verified statically: all four assert behaviourally
against accessibility identifiers and assert **both** presence and absence, so they are not smoke tests.
Every rule they cover is separately proven by value and composition tests. Recorded per the user's explicit
decision (obs 7511) as environment-blocked, not as a change defect.

### SUGGESTION

**SUGGESTION-A — `RecordingURLProtocol.ledgers` grows without bound.** Each `RecordingNetwork` inserts a
UUID-keyed ledger and nothing ever removes it, so the registry accumulates one entry per recorder for the
life of the test process. Harmless at current scale (a few hundred entries holding small exchange arrays)
and it costs nothing in correctness, but a `deinit`-time or explicit-teardown removal would keep it honest
as the suite grows.

**SUGGESTION-B — Carried follow-up: `cellarTests/SecurityCompositionSupport.swift:179-215`.** The M4 spy's
global-counter shape should be migrated to a per-instance recorder in its own change, which also clears
WARNING-A. Not this change's file to fix.

**SUGGESTION-C — `InstalledRow`'s homepage fallback reads a non-catalog source.** Unchanged from verify-1.
RN-R1's prose says "four **catalog-published** values"; amendment 14 feeds the installed snapshot's
`homepage` when no catalog record exists. Behaviourally sound and app-side rather than CellarCore
behaviour, so it does not violate the requirement as written — but a one-line spec clarification would
remove the ambiguity.

**SUGGESTION-D — Record the `403` fixture's `content-length` invariant.** Unchanged from verify-1.
`error-403-ratelimit.headers.txt` declares `content-length: 305` and the body is exactly 305 bytes. Worth
stating in the README, since `receive()` refuses on `expectedContentLength` before reading and a future
body edit would silently desynchronise the guard's input.

---

## Verdict

**PASS WITH WARNINGS**

The blocker is genuinely fixed, not suppressed: the fake is deleted rather than worked around, the
replacement removes the false-zero hazard structurally rather than by serialising around it, two claims came
out stronger than they went in, and coverage is provably identical. Three consecutive full-parallel runs at
exit 0, executed by this verifier, plus a green app suite and a successful build.

Both remaining warnings are non-blocking and carried with an explicit disposition: WARNING-A is a latent
test-integrity issue whose guarded claim is independently proven, and WARNING-B is a user-accepted
environment block. Neither affects product behaviour or spec compliance.

**Recommended next phase: `sdd-archive`.**
