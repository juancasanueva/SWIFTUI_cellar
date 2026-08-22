```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:1108b4e3ba897179c34e9aec9984fd3982ae211e9b876e039f1a25712de31ea7
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 9/9
scenarios: 40/40
test_command: "xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests"
test_exit_code: 0
test_output_hash: sha256:c1bb6951b9699754a08c1a6309fc6be447f6ef0b8ad5a4bba05b8512c277df9b
build_command: "swift test --package-path Packages/CellarCore"
build_exit_code: 0
build_output_hash: sha256:5a54b4c1640f10d83ace89052b5e6051ca1ac25623bcecec1f3679ee1faceb26
```

# Verification Report — `m6-tip-jar`

> **Envelope reflects ROUND 2** (remediation `20a4576`). Round 1 below is preserved verbatim as
> the historical record; its FAIL verdict was superseded on evidence, not overwritten. Round 2
> begins at "Round 2 — re-verification of the remediated findings".

**Mode**: Strict TDD (both runners present) · **Store**: hybrid · **Branch**: `feature/m6-tip-jar` @ `d56fb61`
**Verdict**: **FAIL** — 1 CRITICAL, 9 WARNING, 4 SUGGESTION.

The implementation is functionally sound and every owned test passes. The single blocker is a
**coverage** gap, not a defect: the spec's headline claim in requirement 3 — that an *unverified*
transaction is finished — has no runtime evidence anywhere, in either half of the suite.

## Completeness

| Dimension | Result |
|---|---|
| Tasks checked | 29/29, all `[x]` |
| Tasks matching code state | 29/29 verified against the tree (see deviations) |
| Not-touched bindings | 4 of 5 held at 0 lines; `project.pbxproj` +7 (maintainer-approved) |
| Artifacts read | proposal, specs (rev 2), design (rev 2), tasks, apply-progress |

`AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift` and every `.xcscheme`
measured at exactly **0 lines** changed against the merge base `506e08f`.

## Test evidence — counted from per-test result lines, never from exit codes or `TEST SUCCEEDED`

| Suite | Command | Executed | Passed | Failed |
|---|---|---|---|---|
| `CellarCore` | `swift test --package-path Packages/CellarCore` | **1769** in 208 suites | 1769 | 0 |
| — `TipJarTests` (new) | `… --filter TipJarTests` | **37** in 4 suites | 37 | 0 |
| `cellarTests` | full verify command, `Test case '…' passed` lines | **206** | 206 | 0 |
| — `TipCompositionTests` (new) | | 25 | 25 | 0 |
| — `TipThankYouPreferenceTests` (new) | | 6 | 6 | 0 |
| — `StoreKitTipSourceTests` (new) | | 4 | 4 | 0 |
| `cellarUITests` | `-only-testing:cellarUITests` | 35 | 3 | 32 — **not attributable**, see W2 |

Reconciliation against `apply-progress`: **exact match** on every figure (1769, 37, 206, 25/6/4).
Baseline 171 + 25 + 6 + 4 = 206. The 206 result lines contain 18 legitimate duplicates, all
parameterized cases (`theScannerDetectsAPlantedStoreKitEscape` ×6 and four others); 188 distinct
identifiers. Zero `failed` result lines in either owned suite. CellarCore's single known issue is
`OperationCenterCancelTests` — pre-existing and unrelated.

The declared full verify command exits **65** solely because of `cellarUITests`; both owned halves
are green.

## Spec compliance — 9 requirements / 40 scenarios

Legend: ✅ passing runtime test · 🟡 partial (substance proven, named clause proven only by
inspection) · ❌ no runtime evidence.

### Req 1 — The tip catalog has three states, and empty is one of them
| # | Scenario | Evidence | |
|---|---|---|---|
| 1.1 | A catalog with one product loads | `TipAvailabilityTests.aCatalogCarryingOneProductResolvesToThatProduct` (+ `…ADifferentProduct`, `…LongerList`) | ✅ |
| 1.2 | Empty list is a settled state, not a spinner | `anEmptyProductListSettlesAsUnavailable` — asserts `isSettled`, `!= .loading`, `!= .unknown`, `product == nil` | ✅ |
| 1.3 | Loading is observable while in progress | `loadingIsPublishedWhileTheSeamHoldsItsAnswer…` (gated fake, sequence log) + `anEmptyCatalogAlsoPublishesLoading…` | ✅ |
| 1.4 | A failure is not an empty catalog | `aFailedLoadIsUnavailableForATypedReason…` + `emptyAndFailedAreDistinguishable…` | ✅ |
| 1.5 | The product id has one home | `theProductIDIsASingleDeclaredConstant` asserts the constant's **value**, not literal uniqueness | 🟡 W5 |

### Req 2 — Six outcomes, and each one claims exactly what happened
| # | Scenario | Evidence | |
|---|---|---|---|
| 2.1 | Verified purchase completes and thanks | `aCompletedPurchaseIsTheOnlyOutcome…` + `aCompletedTipRecordsTheThankYouExactlyOnce` | ✅ |
| 2.2 | Cancelling says nothing | `cancellingIsSilent…` — outcome, `isSilent`, no reason, seam still reached | ✅ |
| 2.3 | Ask to Buy is honest | `aDeferredApprovalSaysTheTipIsNotComplete` — `claimsTipComplete == false` | ✅ |
| 2.4 | Unverified finished but never thanked (outcome half) | `anUnverifiedTransactionIsNeitherThankedNorCalledAFailure` | ✅ |
| 2.5 | A thrown purchase is a typed failure | `aThrownPurchase…` + `aDifferentFailureReasonIsCarriedThroughUnchanged` | ✅ |
| 2.6 | Purchasing without a product attempts nothing | `aPurchaseWithAnEmptyCatalogReachesTheSeamNotAtAll` — recorder empty | ✅ |

`@unknown default → failed` is covered by `anUnrecognizedStoreAnswerBecomesATypedFailureNotSilence`
and mapped in the conformer.

### Req 3 — Every transaction is finished, including the unverified one
| # | Scenario | Evidence | |
|---|---|---|---|
| 3.1 | Completed purchase finishes its transaction | `StoreKitTipSourceTests.buyingTheTipCompletesAndLeavesNothingUnfinishedBehindIt` — **real store**, `Transaction.unfinished` empty after a purchase the test made | ✅ |
| 3.2 | **An unverified transaction is still finished** | **none** — see C1 | ❌ |
| 3.3 | Unfinished queue drained at launch | `twoDrainedTransactionsAreBothConsumed…` (fake) + `drainingFinishesALeftoverThisTestSeededItself` (real store, seeded leftover) | ✅ |
| 3.4 | Later Ask-to-Buy approval caught after quit | `anApprovalArrivingOnTheStreamRecordsTheThankYou` | ✅ |
| 3.5 | A second window joins the one observation | `startingTwiceYieldsOneObservationAndTheFirstIsNeverRestarted` — also proves the first was not cancelled | ✅ |

### Req 4 — A tip may be given again, and nothing is entitled by it
| # | Scenario | Evidence | |
|---|---|---|---|
| 4.1 | Tipping twice works | `aRecordedThankYouNeitherHidesTheSurfaceNorRefusesASecondTip` + `theConsumableCanBeBoughtTwiceAndBothAreFinished` (real store) | ✅ |
| 4.2 | The thank-you does not remove the surface | same test — `showsTipSurface` true, price still from product | ✅ |
| 4.3 | Nothing is entitled or restorable | `nothingIsEntitledRestorableOrDecidedAtCompileTime` scans `currentEntitlements`, `AppStore.sync`, `canMakePayments`, `restorePurchases`; the flag's only readers are `TipJarCard` copy | ✅ |

### Req 5 — The tip surface exists only when the build can transact
| # | Scenario | Evidence | |
|---|---|---|---|
| 5.1 | Empty catalog renders no tip surface | `theSurfaceShowsOnlyForAnAvailableCatalog`; `TipJarCard.body` returns nothing without a product — absent, not disabled | ✅ |
| 5.2 | Loaded catalog makes the surface available | same test + sentinel-price assertions | ✅ |
| 5.3 | Availability ignores the payments-capability flag | `canMakePayments` swept app-wide; `#if`/`#available` scanned in the conformer (S3) | ✅ |
| 5.4 | A failed load is also no surface | `aFailedLoadIsUnavailableForATypedReason…` asserts `product == nil`, which is exactly what `showsTipSurface` derives from | ✅ |

### Req 6 — The thank-you is one local boolean
| # | Scenario | Evidence | |
|---|---|---|---|
| 6.1 | The thank-you survives a relaunch | `aRecordedTipIsReadBackByAFreshInstance` (fresh instance off a real `UserDefaults` suite) + `recordingWritesExactlyOneNamespacedKeyAndItIsABoolean` | ✅ |
| 6.2 | Nothing else is remembered | `noDateCountIdentifierPriceOrStorefrontIsStored` — domain read back key by key, `CFBooleanGetTypeID`, `intValue == 1` after **two** recordings; `appAccountToken` swept; no iCloud API anywhere | ✅ |
| 6.3 | No egress and no brew process | Substance proven by the **zero-dependency manifest assertion**; the named test's recorder is inert — see W1 | 🟡 W1 |
| 6.4 | A non-completing outcome writes nothing | `everyOutcomeOtherThanCompletedLeavesTheRecordUntouched` (4 parameterized) + `anUnavailableCatalogWritesNothingAndAttemptsNothing` = all five | ✅ |

### Req 7 — The copy is gratitude, never a nag, and the price is never a string
| # | Scenario | Evidence | |
|---|---|---|---|
| 7.1 | No price literal exists anywhere | `noSwiftSourceInTheAppOrItsTestsCarriesAPriceLiteral` + bidirectional scanner control (3 violations caught, 5 ordinary lines spared incl. `$0` shorthand). Sweep scope excludes `Packages/` — W6 | ✅ |
| 7.2 | Nothing is shown at launch | **no test** — verified by inspection only | ❌ W3 |
| 7.3 | A dismissed tip is never re-asked | value-level `isSilent` + `outcomeNote == nil` for `.cancelled`; the relaunch clause untested | 🟡 W3 |
| 7.4 | No external payment link ships | `noExternalPaymentOrDonationDestinationAppearsInAnySource` over 9 destinations + planted-link control | ✅ |

### Req 8 — One purchase call site, and no new section
| # | Scenario | Evidence | |
|---|---|---|---|
| 8.1 | Exactly one purchase call site | `exactlyOneFileInvokesThePurchasingSeam` (== `["TipJarCard.swift"]`) + `theAboutSurfaceNeverPurchasesAndNeverSelectsASection` | ✅ |
| 8.2 | About row is a signpost, only when there is something to point at | `theAboutSignpostCarriesNoActionOfAnyKind` proves the no-action half over the extracted row; the availability gating is inspection-only | 🟡 W4 |
| 8.3 | The section enumeration is untouched | `AppSectionPlacementTests` 7/7 passed unchanged + 0-line diffs on all three files | ✅ |
| 8.4 | The existing free-app card is unchanged | `theFreeAppCardsCopyIsUnchangedAndTheTipCardSitsAboveIt` (both strings + ordering); `SettingsView` diff is +4, of which 3 are comments | ✅ |

### Req 9 — StoreKit lives behind exactly one seam
| # | Scenario | Evidence | |
|---|---|---|---|
| 9.1 | The tip target depends on nothing | `theTipJarTargetDeclaresAnEmptyDependencyListAndImportsNoStoreKit` + `Persistence` negative control + ≥4 sources read | ✅ |
| 9.2 | StoreKit is imported exactly once | `exactlyOneFileUnderTheAppTargetImportsStoreKit` (== conformer) + `noFileButTheConformerNames…` with positive anchor | ✅ |
| 9.3 | The conformer is proven against a real local store | `StoreKitTipSourceTests` 4/4 against `SKTestSession`; 0-line `.xcscheme` diff | ✅ |
| 9.4 | The test store configuration never ships | `tipStoreKitLivesWithTheTestsAndNowhereElse` + `theBuiltAppBundleCarriesNoStoreKitConfiguration` reading the real host `Bundle.main` | ✅ |
| 9.5 | UI tests stay at zero egress and zero StoreKit | structural wiring assertion only; **no UI test executed successfully this session** | ❌ W2 |

**Fully covered: 34/40 scenarios; 4/9 requirements have every scenario runtime-proven.** The five
🟡 partials all have their substance proven and only a named clause resting on inspection.

## Issues

### CRITICAL

**C1 — Req 3 / "An unverified transaction is still finished" has no runtime evidence.**
The spec devotes an entire requirement to this and states the reason plainly: *"skipping it on the
unverified path MUST NOT be treated as a safety measure, because an unfinished consumable replays
forever."* Nothing proves it at runtime.

- Core layer cannot: `RecordingTipPurchases` has `Event = {purchased, drained, observed}` and **no
  `finished` event**. The fake *is* the conformer there, so there is no transaction to finish. The
  spec's own scenario text ("the recorder shows that transaction finished") describes a recorder
  that was never built.
- Real-store layer does not: `StoreKitTipSourceTests` covers load, purchase→completed, buy-twice and
  drain. It has **no unverified case**, so only the `.verified` branch of
  `StoreKitTipSource.finish(_:)` is ever executed.
- Evidence today is source inspection alone: `StoreKitTipSource.swift:104–115` calls
  `await transaction.finish()` on **both** branches, and reads correct.

Note for whoever resolves it: `SKTestSession` has no straightforward way to produce an unverified
transaction, so this may be a **spec/design decision** (amend the scenario to accept the documented
structural proof, or make `finish(_:)` reachable from a test) rather than ordinary apply work. It is
recorded as a blocker rather than absorbed, because the change's own spec makes it the headline
claim.

### WARNING

**W1 — `ForbiddenSideEffectRecorder` asserts something its own test cannot observe.**
`TipGratitudeTests.aWholeTipCycleIssuesNoRequestAndSpawnsNoProcess` creates the recorder, hands it to
nothing (`TipFakes.swift:215–230` says so outright), then asserts both counters are zero. Those two
assertions cannot fail regardless of what the tip path does. The trailing live-counter control proves
the counter increments, not that it could ever have observed a request. The requirement itself *is*
proven — by the zero-dependency manifest assertion, which makes egress unreachable at the build-graph
level — so this is a misleading test name, not an unproven requirement.

**W2 — `cellarUITests` produced no usable signal; the failures are not attributable to this change.**
Measured rather than assumed, and an initial regression call was retracted on evidence:

| Run | Tree | Result |
|---|---|---|
| 1 | branch, shared DerivedData | runner failed to initialize (`Timed out while enabling automation mode`), 0 executed |
| 2 | branch working tree | 35 executed, 32 failed |
| 3 | **baseline `506e08f` worktree** | **35 executed, 0 failed** |
| 4 | branch, isolated DerivedData | 32 failed |
| 5 | branch tip `d56fb61`, clean worktree | 32 failed |
| 6 | **baseline `506e08f`, re-run after the above** | **29 failed** |

Run 6 is decisive: unmodified `main` fails 29/35 with the *identical* signature (`Home is no longer
in the sidebar`, app menu bar present but no Window in the accessibility tree). Four narrowing probes
on the branch (launch loop disabled, view surfaces reverted, environment injection removed, all app
wiring reverted to baseline) all still failed, and `otool -L` shows the baseline and branch binaries
link an identical framework list. The UI-automation environment on this machine degraded during the
session. `cellarUITests` has a 0-line diff on this branch. Conclusion: **no regression evidence, and
no clearing evidence either** — 9.5 must be re-run on a healthy machine before archive.

**W3 — Req 7's launch-quiet claims have no automated proof.** "Nothing is shown at launch" (7.2) has
no test at all, and 7.3's relaunch clause is untested. Verified by inspection: `cellarApp` only
injects the environment and starts the loop, no tip file contains `.sheet`/`.alert`/`.popover`/
`.confirmationDialog`/badge/toast, and `outcomeNote` returns `nil` for `.cancelled`. Cheap to close
with a `TipCompositionTests` scan.

**W4 — The About row's availability gating is inspection-only.** The row's *no-action* half is well
tested over the extracted source; the "present in the first case and absent in the second" half is
not. Verified by inspection: `AboutView.swift:93` gates on `tips.showsTipSurface`.

**W5 — Req 1.5 is asserted as a value, not as a structure.** The scenario says "inspected
structurally… no second literal of that id exists in shipped source"; the covering test compares the
constant to its own literal. Verified at verify time: exactly one occurrence in shipped source
(`TipProduct.swift:13`); other occurrences are the test's pin, two deliberately *different* ids, and
the `Tip.storekit` fixture.

**W6 — The price-literal sweep does not cover `Packages/CellarCore/`.** `swiftSources()` walks
`cellar/` and `cellarTests/` only, but requirement 7 says "the change's shipped sources and its
tests", which includes `Sources/TipJar/` and `Tests/TipJarTests/`. Verified clean at verify time.

**W7 — Design deviation: `TipCatalogLoader` and `TipPurchaseRunner` are types `design.md` does not
name.** Justified in `apply-progress` (an in-progress state and an absence are otherwise
unassertable) and every signature `design.md` fixes is unchanged. Does not break a spec.

**W8 — `project.pbxproj` gained 7 lines, breaking a not-touched binding.** Additive product linkage
only; the design's no-pbxproj claim covered file membership, not linkage, and a zero-dependency
target has no dependent to inherit linkage from. Reported rather than absorbed, per the design's own
rollout note, and **approved by the maintainer (2026-08-22)**. The other four bindings held at 0.

**W9 — The declared full verify command exits 65.** Attributable entirely to W2; both owned halves
exit 0 / are fully green.

### SUGGESTION

**S1 — The `failed` note does not surface the typed reason the spec's outcome table promises.**
Requirement 2's table says a `failed` outcome tells the user "a typed reason"; `TipJarCard` renders
"That did not go through. Nothing was charged." The outcome *carries* the reason
(`String(describing: error)`), which is not user-facing prose, so rendering it verbatim would likely
be worse. Worth an explicit decision during the copy pass.

**S2 — `TipProduct.description` is carried and asserted but never rendered** (apply finding 4).
Not a spec violation; the spec requires the value to carry it.

**S3 — The `#if` / `#available` scan is scoped to the conformer.** Verified at verify time that
**zero** `#if` or `#available` occurrences exist anywhere under `cellar/`, so 5.3 holds app-wide.

**S4 — Indentation drift in `StoreKitTipSourceTests`** — the `guard … else` bodies inside
`withLock` closures are under-indented (lines 132–151, 163–181, 193–206, 220–240). Cosmetic.

## Copy compliance (placeholder wording, per apply finding 3)

| Rule | Result |
|---|---|
| Gratitude, not begging | ✅ "Say thanks"; "It is a thank-you, nothing more." |
| No nag, no countdown, no escalation | ✅ copy is identical before and after a tip except the acknowledgement |
| No claim the app is at risk / feature depends on tipping | ✅ "every feature stays free whether you do this or not" |
| No launch prompt, modal, sheet, banner, toast, badge | ✅ none present (W3: unasserted) |
| Price by `displayPrice` interpolation only | ✅ `Text("\(buttonVerb) \(product.displayPrice)")`, the only price render |
| No literal currency anywhere | ✅ swept across `cellar/`, `cellarTests/` **and** `Packages/` at verify time — none |
| `cancelled` says nothing | ✅ `outcomeNote` returns `nil` |
| `pending` does not claim success | ✅ "Waiting for approval. Nothing has been paid yet." |
| `unverified` is not an accusation | ✅ "could not be verified, so it has not been recorded" |
| No external payment language | ✅ tested + verified |

## PRD amendments — read in context at lines 9, 10, 186, 234

| Line | Reads correctly |
|---|---|
| 9 | Distribution — names the MAS channel the consumable needs and states it **unproven** (U22), with the empty-product-list fallback | ✅ |
| 10 | Monetization — "in-app tip jar (StoreKit 2 consumable)", records that *external* was superseded and why (3.1.1 exclusivity) | ✅ |
| 186 | §6 bullet — full supersession with the original text quoted, corrects the "StoreKit is unavailable" premise, states the unproven ship path, restates "no new sidebar section" against the PRD's own "single subtle" instruction | ✅ |
| 234 | Open question 2 struck through and closed, replaced by U22 | ✅ |

All four are in-place rewrites that carry their own reason; none silently overwrite history.

## TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD evidence reported | ✅ | Full cycle table in `apply-progress` |
| All tasks have tests | ✅ | 29/29; 1.2 / 4.3 / 7.x are structural or fixtures |
| RED confirmed (test files exist) | ✅ | 9/9 new test files present |
| GREEN confirmed (tests pass now) | ✅ | 1769 + 206, re-executed this session |
| Triangulation adequate | ✅ | Every new suite carries deliberate second-value cases and negative controls |
| Safety net for modified files | ✅ | Counts recorded per phase (22, 31, 171, 181, 195) |
| Declared-inadmissible REDs | ✅ | Notes A/B/C are honest: planted-mutation proof for 3.3, design-declared inadmissibility for 4.4, planted-violation controls for 5.1/5.2 |

## Test layer distribution

| Layer | Tests | Files |
|---|---|---|
| Unit (`swift test`, fakes only) | 37 | 5 |
| Structural (file-text / manifest / bundle) | 25 | 1 |
| Integration (real `UserDefaults` domain) | 6 | 1 |
| Behavioral (real local StoreKit store) | 4 | 1 |
| E2E | 0 | — (none added, by design) |

## Assertion quality

| File | Location | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TipGratitudeTests.swift` | 252–253 | `recorder.requestCount == 0` / `processCount == 0` | Recorder is wired to nothing; cannot fail | WARNING (W1) |

Everything else verifies real behaviour. No tautologies, no ghost loops, no smoke-only tests, no
mock-heavy suites. Notable strengths: the price scanner asserts **both** directions; every structural
absence is paired with a planted violation or a positive anchor; `theBuiltAppBundleCarriesNoStoreKit
Configuration` reads the real host bundle; the corrected `NSNumber`/`CFBoolean` assertion now
separates a flag from a counter by recording **twice**.

## Design coherence

| Decision | Held | Note |
|---|---|---|
| D-A zero-dependency `TipJar` | ✅ | Asserted in the manifest with a negative control |
| D-B availability from product-list emptiness | ✅ | `canMakePayments` swept out |
| D-C thank-you = one `UserDefaults` boolean | ✅ | `isTipRecorded` naming deviation only |
| D-D `.environment(tips)`, no `ContentView` diff | ✅ | 0-line diff held |
| D-E static About row | ✅ | No action of any kind |
| D-F one `"tips"` loop slot | ✅ | Asserted structurally + `hasStarted` guard tested |
| D-G re-resolve `Product` per purchase | ✅ | |
| D-H filter streams by `TipProductIDs.all` | ✅ | |
| File list | 🟡 | +2 core types (W7), +1 test file, +7 pbxproj lines (W8) |

## Coverage and quality metrics

Coverage analysis skipped — no coverage tool configured for this project. Linter/type-checker: no
standalone tool detected; the Swift 6 language-mode build is the type gate and it is clean.

## Verdict

**FAIL** — 1 CRITICAL, 9 WARNING, 4 SUGGESTION.

No functional defect was found and both owned suites are fully green at 1769/1769 and 206/206, with
counts reconciled exactly against `apply-progress`. The blocker is C1: the requirement the spec
argues hardest for is the one thing the suite never executes. W2 additionally means requirement 9's
last scenario cannot be cleared on this machine today.

---

# Round 2 — re-verification of the remediated findings

**Remediation**: `20a4576` (662 changed lines, within the 700 budget) · **Scope**: only the findings
round 1 raised. The 34 scenarios already marked runtime-proven were not re-mapped.
**Round-2 verdict**: **PASS WITH WARNINGS** — 0 CRITICAL, 0 blockers.

## Counts — 194 distinct, and the third false-green vector

| Suite | Command | Executed | Passed | Failed |
|---|---|---|---|---|
| `CellarCore` | `swift test --package-path Packages/CellarCore` | **1772** in 208 suites | 1772 | 0 |
| — `TipJarTests` | `… --filter TipJarTests` | **40** in 4 suites (39 + 1 parameterized ×4) | 40 | 0 |
| `cellarTests` | `xcodebuild … -only-testing:cellarTests` | **194 distinct** over 212 result lines | 194 | 0 |
| — `TipCompositionTests` | | **23 distinct** | 23 | 0 |

Reconciliation is exact: 1769 + 3 = **1772**; 188 round-1 distinct + 6 new = **194**; 17 + 6 = **23**
`TipCompositionTests`. Both suites exit 0.

**A third false-green vector, caught by counting distinct ids against the roster.** A naive
`Test case '` anchor returned **193** distinct — one short. The absentee was
`BrewfileCompositionTests/confirmingSubmitsAllThreeTapFirst()`, a pre-existing test in a file this
branch does not touch. It did **not** silently skip: log line 366 reads
`est case 'BrewfileCompositionTests/confirmingSubmitsAllThreeTapFirst()' passed` — interleaved
parallel-worker output ate the leading `T`. Re-counted with a truncation-tolerant anchor
(`case '[^']+' (passed|failed)`) the roster is exactly **194 / 0 failed**.

This is distinct from the two vectors already recorded: it is neither a missing `-only-testing` `()`
nor the StoreKit-agent worker race. A mangled result line makes strict counting **under**-count,
which fails safe — but only if the count is reconciled against an expected roster rather than
eyeballed. `** TEST SUCCEEDED **` and exit 0 were printed throughout and remain worthless as
evidence.

## Per-finding rulings

### C1 — Req 3 scenario 3.2 · **CLOSED** (was the sole blocker)

Three independent layers now carry the claim, and I verified the planted-violation behaviour by
reading the assertions rather than re-planting:

| Layer | Evidence | Executed |
|---|---|---|
| Rule | `TipTransactionDisposition.forTransaction(isVerified:)` with a **stored** `mustFinish` | 3 tests, both inputs: `anUnverifiedTransactionMustStillBeFinished…`, `aVerifiedTransactionIsFinishedToo…`, `finishingIsUnconditional…` |
| Structural | `TipCompositionTests.neitherVerificationBranchCanLeaveTheConformerWithoutFinishing` over the extracted `finish(_:)` | ✅ + scanner control `theFinishShapeScannerRejectsABranchThatReturnsBeforeFinishing` |
| Behavioural | `StoreKitTipSourceTests.buyingTheTipCompletesAndLeavesNothingUnfinishedBehindIt` — real store | ✅ pre-existing |

**Does it satisfy 3.2's intent?** Yes. The intent is that the unverified path is not exempted from
finishing. The conformer's `switch` now only *classifies* (extracts the transaction and an
`isVerified` flag); the decision is a value, and the finishing call is **one line reached from both
branches**. Critically, that same single call site is runtime-proven to finish a real transaction on
the verified path, so the only branch-dependent input to the gate is `isVerified` — whose mapping to
`mustFinish == true` is executed for both values. The residual is not a Cellar rule at all but
StoreKit's own behaviour when handed an unverified transaction value, and `SKTestSession` cannot mint
one.

**Is the evidence honest?** Yes — no unfailable assertion. Verified by reading the guard against the
old shape (`d56fb61`): two `return`s and two `finish()` calls would break
`components(separatedBy: "return").count == 2`, `…"await transaction.finish()").count == 2`,
`contains("return") == contains("return disposition.outcome")`, and both exact-line assertions —
**5 failing assertions**, matching the commit message's claim. At the rule layer, changing
`mustFinish: true` to `mustFinish: isVerified` fails 3 assertions. The guard's bite is independently
evidenced: its first run surfaced the latent `??` extractor bug rather than passing over it.

**Disclosed residual (SUGGESTION, not blocking)**: `mustFinish` is a stored constant `true`, so
`if disposition.mustFinish` is always taken and the gate is representational rather than behavioural.
The doc comment says so outright ("**Always true.**"), and representing a rule so it can be asserted
is the right trade here.

### W1 — inert side-effect recorder · **CLOSED**

`ForbiddenSideEffectRecorder` is deleted outright (confirmed absent from the whole tree). The
replacement, `aWholeTipCycleTouchesTheThreeDeclaredSeamsExactlyThisManyTimes`, asserts an exhaustive
ordered ledger: `catalog.callCount == 1`, `purchases.events == [.drained, .observed, .purchased(product)]`,
`gratitude.readCount == 1`, `writeCount == 1`.

- **Failable?** Yes, every assertion. A second catalog fetch, a fourth seam interaction, a re-read
  outside hydration, or a reordering all break it. The ordered array equality is the strongest form
  available here.
- **Does it prove what the deleted recorder pretended to?** Not by itself, and the apply report says
  so plainly rather than papering over it: the no-egress / no-brew-process claim rests on the
  zero-dependency manifest assertion, which is where it actually holds — `TipJar` cannot reference a
  network or process type at build-graph level. The ledger proves the complementary half ("the tip
  path does only these three things"). The test name now matches what it measures instead of
  overclaiming, which was the substance of W1.

**Follow-up (documentation, not code)**: spec scenario 6.3's literal GIVEN — "a recording network
seam and a recording process seam" — is unimplementable by design, since D-A gives `TipJar` no such
seams. The scenario wording, not the implementation, is what is out of step. Same class as 3.2.

### W3–W6 and the shared extractor · **ALL CLOSED, none vacuous**

| # | Addition | Anti-vacuity anchor | Ruling |
|---|---|---|---|
| W3 | `noTipSurfacePresentsAnythingAtLaunchOrAfterAnyOutcome` — 6 tip-path files × 9 presentation modifiers; plus no `tips.tip()` in the composition root | each file `#require`d into scope, so a rename fails instead of silently passing | ✅ sound |
| W3 | `aCancelledOutcomeRendersNoNoteAndNoOutcome…` — the `.completed, .cancelled` arm returns `nil` | two positive controls (`return "Waiting for approval.`, `case .pending:`) prove the note still distinguishes outcomes | ✅ sound |
| W4 | `theAboutSignpostIsGatedOnTheSameAvailabilityValueSettingsReads` — gate exists, precedes the row, within 120 chars, reads the injected store, About queries no storefront | ordering + proximity, not mere co-occurrence | ✅ sound (proximity threshold is mildly brittle) |
| W5 | `theProductIDLiteralAppearsExactlyOnceInShippedSource` | **exhaustive dictionary equality** `== ["TipJar/TipProduct.swift": 1]`, stronger than a "no more than one" bound | ✅ strong |
| W6 | price sweep extended to `Sources/TipJar` and `Tests/TipJarTests` | per-area `Issue.record` if a path is missing, **plus** two named per-area anchors — precisely the "an area that read nothing" hole | ✅ strong |
| — | `member(named:in:)` | `.min()` over all boundary markers replaces `range(of: a) ?? range(of: b)`, which took the first non-nil marker rather than the nearest and ran two members past the end; now shared by both extractors | ✅ correct fix |

The extractor bug is worth recording on its own: it was latent in round 1's About-row test, where it
happened to be harmless, and it only became visible because the new C1 guard swept up a `return`
belonging to another member. A guard that finds a bug in its own scaffolding on first run is a guard
that bites.

## Updated scenario coverage — 40/40, and exactly what tier each rests on

**40/40 scenarios covered; 9/9 requirements complete** (round 1: 34/40, 4/9). Closed this round by
new passing tests: 1.5, 3.2, 7.2, 7.3, 8.2.

**Scenario 9.5 is counted as covered on STRUCTURAL evidence, and the basis is stated rather than
assumed.** Both of its THEN clauses have passing covering tests:

- *"the seams in use are fakes"* — `theCompositionRootWiresTheTipStoreIntoBothScenesAndOneLoopSlot`
  asserts the composition root constructs `AppTestTipSource(` on the UI-test branch.
- *"no StoreKit request and no network request was issued"* — `AppTestFixtures.swift` lives under
  `cellar/`, so it is inside `AppSecuritySources.load()` and therefore inside both the
  importers-must-equal-`[conformer]` assertion and the every-other-file token exclusion. Verified
  directly this round: all six `AppTestTipSource` seam bodies are pure values (`.loaded([…])`,
  `.cancelled`, `{}`, a never-yielding stream, `false`, `{}`) with no StoreKit type, no `URLSession`
  and no process.

This is the same evidence tier requirement 9 uses for its own other scenarios ("WHEN they are
inspected structurally"). What remains outstanding is the strictly *stronger* end-to-end
confirmation — an actual UI-test launch — which this machine cannot supply. That is carried as open
follow-up 1 below with its re-run condition, and it is a deferred confirmation, not an unmet
requirement.

## Open follow-ups (none blocking)

1. **Req 9.5 — end-to-end UI confirmation: OPEN, not failed.** The scenario is counted covered on
   structural evidence (above); what is deferred is the stronger runtime confirmation. Out of scope
   this round. The
   machine's UI-automation environment is invalidated (round 1 proved it: unmodified `main` failed
   29/35 with the same signature after passing 35/35 earlier). **Re-run condition**: execute
   `xcodebuild test … -only-testing:cellarUITests` on a healthy machine *together with a same-session
   baseline control on the merge base*, and require both a green branch run and a green baseline run
   before treating the result as evidence in either direction. A lone green or red run on this
   machine remains worthless.
2. **Spec wording** — scenarios 3.2 and 6.3 are written against mechanisms the design deliberately
   makes unreachable (an unverified transaction from `SKTestSession`; network/process seams inside a
   zero-dependency target). Worth amending the scenario text to name the evidence mode actually
   available, so a future verify does not re-raise a closed finding.
3. **W7 / W8** — accepted deviations (`TipCatalogLoader`/`TipPurchaseRunner`; pbxproj +7,
   maintainer-approved). Unchanged.
4. **S1–S3** — copy and scoping decisions awaiting the maintainer. Unchanged.
5. **`mustFinish` is a constant** — disclosed; revisit only if the finishing rule ever gains a real
   condition.

## Bindings and hygiene

Re-checked at `20a4576`: `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`
and every `.xcscheme` still at **0 lines**; `project.pbxproj` still the approved **+7**. The
remediation touched only test files plus two small source additions
(`TipPurchaseOutcome.swift` +34 for the disposition, `StoreKitTipSource.swift` +29 −12 for the
extract-then-decide split); no view, wiring, or copy changed.

## Round-2 verdict

**PASS WITH WARNINGS.** The round-1 blocker is closed on evidence rather than on assertion, every
in-scope warning is closed with a failable, anchored test, and both suites are green at 1772/1772 and
194/194 distinct with the roster reconciled exactly. Not a clean `pass` because three things are
deferred rather than settled: requirement 9.5's end-to-end confirmation needs a healthy UI-automation
machine, scenarios 3.2 and 6.3 are worded against mechanisms the design makes unreachable and should
be amended, and the S1–S3 copy decisions are still the maintainer's to make.
