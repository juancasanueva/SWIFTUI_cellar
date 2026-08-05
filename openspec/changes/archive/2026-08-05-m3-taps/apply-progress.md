# Apply Progress: M3-2 Tap Management

## Status

- Mode: Strict TDD
- Delivery: `size:exception` (Engram #7218)
- Completed: 24/24 tasks
- Pending: None — apply is complete
- Next: `sdd-verify` after parent settlement
- RDD: disabled; no review command or receipt was created
- Focused remediation: complete for failed evidence revision `sha256:b71e639032cc5f7fa5965d143dff81d14b42d60e222df0722797273a38eb53a4`
- Remediation evidence revision: `sha256:e9ea2844bd26a3bc81fd78c67c4e4b949fab1d4060d9b4d89a0b5c9eddb67857`
- Native attempt: parent-owned token `sha256:592610c4a7860fc7f71dfdfe97f1a4a7d049a1c7f27d327ee4e7b2f02fe9d574`; this executor did not acquire, settle, reset, begin, or finish it

## Completed Tasks

- [x] 1.1–1.2 Mutation-only queue-front authorization and typed no-process denials
- [x] 2.1–2.4 Keyed refresh receipts and latest-wins confirmation recovery
- [x] 3.1–3.8 Tap acquisition, decoding, store, projection, commands, and confirmation compatibility
- [x] 4.1–4.4 FIFO integration, scoped refresh, containment, and history
- [x] 5.1–5.2 Taps app surfaces and automated UI coverage
- [x] 5.3 Maintainer-observed manual navigation, confirmation, performance, accessibility, state, and Installed-handoff verification
- [x] 5.4 Authoritative package/app test and build verification
- [x] 5.5 Structural guard readback with RDD left disabled
- [x] 5.6 Parent-orchestrator-owned native `sdd-attempt` acquired and settled

## TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 1.1 | Authorization contract/order tests failed before the API existed. | Paired 1.2 implementation passes the focused authorization suites. | Kept one FIFO-front authorization path and one terminal funnel. |
| 1.2 | 1.1 established missing typed denial/default compatibility behavior. | `MutationAuthorizationTests|OperationCenterAuthorizationTests`: 6 tests in 2 suites passed. | Preserved legacy read and default mutation behavior. |
| 2.1 | Receipt tests exposed unkeyed completion/leak/misrouting behavior. | Paired 2.2 implementation passes receipt tests. | Centralized first-result-per-domain settlement in an actor registry. |
| 2.2 | 2.1 failed before operation/domain keys and teardown settlement existed. | Receipt suite passes, including five bounded failure-result cases. | Duplicate and unknown completions remain idempotent no-ops. |
| 2.3 | Backlog/recovery tests failed on overwrite, premature promotion, and stuck candidates. | Paired 2.4 implementation passes backlog and recovery suites. | Reduced recovery state to one visible request plus one latest-wins candidate. |
| 2.4 | 2.3 established missing vacancy and post-refresh ordering. | Receipt/backlog/recovery filter: 14 tests in 3 suites passed. | Recovery composition moved behind keyed gates and eligibility checks. |
| 3.1 | Tap payload/decode/store tests failed before tap acquisition and state existed. | Paired 3.2 implementation passes tap acquisition/decode/store suites. | Kept payload process-free at decode seams and non-persistent in the store. |
| 3.2 | 3.1 established exact invocation, tolerant decode, redaction, and freshness gaps. | Full Tap/History filter and full package suite pass. | Split acquisition, wire decode, and freshness into focused files. |
| 3.3 | Projection tests failed before official framing, filtering, handoff, and distinct states existed. | Paired 3.4 implementation passes projection tests. | Projection remains pure and UI-independent. |
| 3.4 | 3.3 established missing kind/exact-tap/lazy-filter behavior. | Tap/History filter: 88 tests in 19 suites passed. | Filtering and Installed handoff share typed `PackageID` identity. |
| 3.5 | Command tests failed before canonical targets, exact argv, plain/force rules, and staleness checks. | Paired 3.6 implementation passes command tests. | Tap names now pass the shared `MutationName.isSafe` argv gate plus canonical `user/repo` validation. |
| 3.6 | 3.5 established unsafe/unrepresentable command paths. | `MutationCommandTests`: 18 tests in 1 suite passed after the shared-gate fix. | Prose remains presentation-only and cannot be parsed into argv. |
| 3.7 | Existing package confirmation tests failed when tap disclosure was introduced. | Paired 3.8 preserves uninstall/zap/bulk behavior. | Typed disclosure extended presentation without changing package command semantics. |
| 3.8 | 3.7 established compatibility requirements before presentation changes. | Full package suite: 754 tests in 109 suites passed with one pre-existing known issue. | One custom confirmation surface renders all disclosure families. |
| 4.1 | Integration/containment tests failed before FIFO, scoped refresh, and structural guards were wired. | Paired 4.2 implementation passes `TapIntegrationTests`. | Dependency remains `BrewClient -> BrewProcess`; no catalog persistence or RDD coupling. |
| 4.2 | 4.1 established missing exact-domain refresh and recovery ordering. | Tap/History filter and full package suite pass. | Tap coordination reuses the existing mutation spine and keyed gates. |
| 4.3 | History tests failed before namespaced tap verbs/null identity/exact argv were projected. | Paired 4.4 implementation passes history suites. | No persistence schema change was needed. |
| 4.4 | 4.3 established missing history vocabulary and presentation. | Tap/History filter: 88 tests in 19 suites passed. | History presentation owns labels; app views contain no outcome rules. |
| 5.1 | XCUITests failed on absent Taps navigation/surfaces; extended state/large tests later failed on missing fixture modes. | Paired 5.2 now passes all Taps UI scenarios. | Stable accessibility identifiers replaced ambiguous global queries. |
| 5.2 | 5.1 captured missing navigation, add/plain/force, handoff, states, large filtering, and keyboard behavior. | Full `cellarUITests`: 10 tests, 0 failures. | Native `confirmationDialog` was replaced by a custom sheet because macOS accessibility truncated full command disclosures. |
| 5.2 Installed-handoff remediation | Strengthened `testPlainUntapAndInstalledHandoff` failed with `XCTAssertTrue failed - Show in Installed must select formula:widget`; the exact row existed but remained unselected. | The focused handoff XCUITest passed; `cellarTests` passed 3 tests; full `cellarUITests` passed 10 tests with 0 failures. | Extracted pure `InstalledSelection.adopting`, retained valid bulk selection, ignored nil/unavailable handoffs, and added stable row identity. |
| 5.4 | Final package run exposed `TapCommand.swift` bypassing the shared argv safety gate. | Shared-gate fix passed 18 focused tests; rerun passed 754 package tests, configured app tests, and build. | Added the common safety gate without weakening canonical tap-name validation. |
| 5.5 | 4.1's structural guards were treated as required regression evidence. | Readback confirmed PD6/dependency/no-persistence/no-prose-to-argv/no-RDD assertions; full suite passes. | No review tooling or receipt path was introduced. |

## Work Unit Evidence

| Work unit | Focused test command and exact result | Runtime harness command/scenario and exact result | Rollback boundary |
|---|---|---|---|
| 1 — Authorization | `swift test --package-path Packages/CellarCore --filter 'MutationAuthorizationTests|OperationCenterAuthorizationTests'` — exit 0; 6 tests/2 suites passed | N/A for isolated core unit; whole-change process/runtime coverage is included in the 754-test package run and app harness | Revert `Sources/BrewProcess/{MutationLaunchAuthorization,BrewRunner,BrewOperation,OperationSnapshot}.swift` and authorization changes in `Sources/BrewClient/{OperationCenter,ActivityItem,MutationOutcome}.swift` |
| 2 — Receipts/recovery | `swift test --package-path Packages/CellarCore --filter 'MutationRefreshReceiptTests|ConfirmationBacklogTests|ForceDenialRecoveryTests'` — exit 0; 14 tests/3 suites passed | N/A for isolated actor/state unit; runtime composition is exercised by the whole-change app harness | Revert `Sources/BrewClient/{MutationRefreshReceipts,ForceDenialRecoveryCoordinator,OperationCenterBulk}.swift` plus keyed-gate coordinator changes |
| 3 — Tap core/history | `swift test --package-path Packages/CellarCore --filter 'Tap|History'` — exit 0; 88 tests/19 suites passed | `swift test --package-path Packages/CellarCore` — exit 0; 754 tests/109 suites passed, one pre-existing known issue; includes real Homebrew integration | Revert `Sources/BrewClient/Tap*.swift`, tap history vocabulary, and their package tests without removing app-independent authorization work |
| 4 — App surfaces | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarUITests` — exit 0; 10 tests, 0 failures | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` — exit 0; 1 app unit + 10 UI tests passed. `xcodebuild build ...` — `BUILD SUCCEEDED` | Revert `.taps`, `cellar/Taps`, `AppTestFixtures`, app composition/confirmation/Installed identifier, and Taps XCUITests |
| 4R — Installed handoff remediation | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarUITests/cellarUITests/testPlainUntapAndInstalledHandoff` — exit 0; 1 test, 0 failures. `xcodebuild test ... -only-testing:cellarTests` — exit 0; 3 tests passed | Configured whole-app test — exit 0; 3 app tests and 10 UI tests passed. Configured app build — exit 0; `BUILD SUCCEEDED` | Revert `cellar/Installed/{InstalledListView,InstalledRow}.swift`, `cellar/Browse/PackageDetailView.swift`, and the handoff assertions/tests in `cellarUITests/cellarUITests.swift` and `cellarTests/cellarTests.swift` |
| 5 — Manual verification closeout | N/A — task 5.3 is manual-only and this continuation was explicitly prohibited from rerunning automated suites; all prior focused evidence remains preserved above | Maintainer-observed runtime verification on 2026-08-04 — PASS for all eight scenarios recorded below | Revert only the task 5.3 checkbox and this manual closeout/status evidence; production code and tests are unchanged |

## Manual Verification

Maintainer-observed results from 2026-08-04; each result is recorded as a manual PASS, not inferred from automation:

1. **PASS — Base fixture navigation:** The base fixture opened Taps; official Core/Cask and `acme/tools` navigation rendered correctly.
2. **PASS — Add Tap and cancellation focus:** Add Tap for `acme/new-tools` showed the complete exact command and third-party warning. With VoiceOver enabled, cancellation worked and focus returned to Add Tap.
3. **PASS — Force Untap disclosure:** Force Untap showed exact `brew untap --force acme/tools`, named `formula: widget` individually, and did not truncate disclosure.
4. **PASS — Installed handoff remediation:** After the strict-TDD remediation, Show in Installed highlighted `formula:widget` and showed `Package details unavailable`, never `No package selected`.
5. **PASS — Full Keyboard Access:** Tab/Shift-Tab navigation and `⌘↩` Add Tap activation worked, no modal keyboard trap occurred, and focus returned after cancellation.
6. **PASS — Large fixture:** `--ui-testing-m3-taps-large` remained responsive with 5,000 rows; filtering showed `needle-4999`, omitted `needle-0`, and caused no scrolling or focus stall.
7. **PASS — Distinct fixture states:** Empty, error, and Homebrew-absent fixtures rendered their distinct expected states; the absent state disabled Add Tap.
8. **PASS — Full VoiceOver traversal:** Sidebar, add, official, tap, filter, package, and action controls had clear labels; Formula/Cask identity and full force disclosure were announced; modal containment and focus restoration worked; no controls were unreachable and no traps occurred.

## Verification Summary

- `swift test --package-path Packages/CellarCore`: 754 tests in 109 suites passed; one existing known issue remained classified as known.
- Configured app test after Installed-handoff remediation: 3 app tests and 10 UI tests passed with zero failures.
- Configured app build: `BUILD SUCCEEDED`.
- Post-bookkeeping `git diff --check`: exit 0 on 2026-08-04.
- Installed handoff now selects the exact `formula:widget` row and removes the false `No package selected` state; a selected installed package absent from catalog data instead presents `Package details unavailable`.
- Maintainer-observed manual accessibility, keyboard, performance, fixture-state, confirmation, navigation, and Installed-handoff verification passed all eight scenarios on 2026-08-04.
- Native whole-change attempt was settled by the parent orchestrator as `interrupted` because manual task 5.3 remains outstanding. Evidence revision: `sha256:e6e9fb90c309a6ea36e27274e2b29511254401386dea56baafe7d555ace30eb3`; native state permits continuation.
- Current parent-owned native authorization is `proceed` for whole-change `m3-taps`, token `sha256:f70732f87c86ba06a37020ff48148e83730e1c2e5209bb7304f064d021b8acdd`. This executor did not acquire, settle, or reset it; the recommended parent settlement outcome is `passed`.
- Apply is complete at 24/24 tasks with no pending work. The next recommended phase is `sdd-verify` after parent settlement.

## Focused Disabled/Unmanaged Remediation — 2026-08-05

This single remediation addresses only the four CRITICAL findings in verification revision
`sha256:b71e639032cc5f7fa5965d143dff81d14b42d60e222df0722797273a38eb53a4`.
RDD is globally disabled, so there is no lineage, generation, fix batch, receipt, or review invocation.
The parent owns native-attempt settlement under token
`sha256:592610c4a7860fc7f71dfdfe97f1a4a7d049a1c7f27d327ee4e7b2f02fe9d574`.

### Remediation Outcome

- **TM10.1:** `TapShippingProofTests.unavailableDetectionBlocksEveryTapProcessPath` passed for absent, invalid, and configured-path-missing detection. Each case requested tap data, direct refresh, coordinator refresh, confirmed add, and plain untap; it proved unavailable guidance, an empty tap inventory, zero launches, and zero recorded process specifications.
- **TM10.2:** `TapShippingProofTests.absentDetectionRecoversInPlace` passed. One store, coordinator, operation center, and launcher transitioned from absent to detected, populated `acme/tools`, enabled mutations, and successfully ran refresh/add/untap without recreating the process-lifetime harness.
- **TM11.1:** `TapShippingProofTests.completeActionSurfaceIsBounded` passed. It enumerated exactly refresh, filter, Installed handoff, canonical add, plain untap, and eligible force untap; asserted exact read/mutation argv; asserted the complete static button set; rejected dynamic unenumerated buttons; and structurally rejected every named adjacent capability from the tap UI.
- **Assertion quality:** the stale `cellarTests.example()` observed at failed verification head `023a51943a575cb466bb0b813867286b51f2d092` is absent at current head. `cellarTests.swift` now exercises production `InstalledSelection.adopting` behavior with three meaningful assertions across valid, nil, and unavailable handoffs; both tests passed.
- **Production behavior changed:** No. This remediation added thirteen test assertions and evidence only.
- **Tasks:** unchanged at 24/24 complete.

### TDD Cycle Evidence

| Remediation item | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| TM10.1 unavailable no-process proof | `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift` | Runtime integration through production stores, coordinator, operation center, runner, and process-launch seam | `swift test --package-path Packages/CellarCore --filter 'TapShippingProofTests|TapIntegrationTests'` — exit 0; 7 tests in 2 suites passed before modification | The admitted verifier reported TM10.1 PARTIAL because it had no accepted all-path runtime proof. Evidence-only strict-TDD exception: the current behavior was already green, so no production change was justified. Additional assertions were written first for operation-center availability and an empty launch-spec ledger. | `swift test --package-path Packages/CellarCore --filter 'TapShippingProofTests'` — exit 0; 3 tests in 1 suite passed, with all 3 unavailable arguments passing | Absent, invalid, and configured-path-missing cases each exercised data, two refresh seams, add, and untap; both launch count and launch-spec ledger remained empty | Kept one parameterized runtime harness; no production refactor |
| TM10.2 in-lifetime restoration proof | `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift` | Runtime integration | Same 7-test safety net passed | The admitted verifier reported TM10.2 UNTESTED. Evidence-only strict-TDD exception: the current test already exercised restoration, so no production change was justified. The pre-restoration launch-spec assertion was added before rerun. | Focused command exit 0; absent state restored to loaded `acme/tools`, then add and untap succeeded with exact three-spec sequence | Absent no-launch path and detected refresh/mutation path ran on the same harness objects | No production refactor; retained one explicit transition test |
| TM11.1 exhaustive action boundary | `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift` | Runtime plus structural | Same 7-test safety net passed | The admitted verifier reported TM11.1 UNTESTED. Evidence-only strict-TDD exception: exact six-action runtime enumeration already passed, so production was left untouched. Explicit excluded-capability assertions were added before rerun. | Focused command exit 0; six allowed actions, exact argv, exact static button set, no dynamic buttons, and nine excluded adjacent capabilities all passed | Read, filter, handoff, three mutation variants, static controls, and excluded-capability terms cover distinct branches | Consolidated exclusions in one data-driven assertion loop; production unchanged |
| Assertion-free app test replacement | `cellarTests/cellarTests.swift` | App unit | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` — exit 0; 2 tests passed | Failed verification revision inspected stale head `023a519...`, where assertion-free `example()` existed. Current head already contains the test-first replacement from M3-2, so recreating a fake failure or changing production was not justified. | Same app-unit command exit 0; 2 production-behavior tests passed with three meaningful assertions | Valid handoff adds identity; nil and unavailable handoffs preserve the existing selection | No remediation edit required; existing focused production assertions were retained |

### Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter 'TapShippingProofTests'` — exit 0; 3 tests in 1 suite passed; the unavailable test passed all 3 parameterized detection cases; output SHA-256 `5481ba101e7fdbf773bbe7f09f86d87b433e307f8fdb9b5c365592fb4253445b` |
| App assertion command and exact result | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` — exit 0; 2 tests passed; output SHA-256 `b3a01768551b9d8a825697895010a33d8a5c2f59445a135947abe732de08c4dc` |
| Runtime harness command/scenario and exact result | The focused package command drove production `TapStore`, `TapRefreshCoordinator`, `OperationCenter`, `BrewRunner`, and `ProcessLaunching`; all three proof tests passed. `swift test --package-path Packages/CellarCore` also passed 775 tests in 113 suites with 1 pre-existing known issue; output SHA-256 `8243e565ee76d6b972aaad9ba8fd4dff8c354b9802fd016c9e8397526377ead8`. |
| Minimum app regression | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` — exit 0; 2 app tests and 12 UI test executions passed; output SHA-256 `7e504527ee68b6a277d3dcd03a33ea1babdf0105dec420e35c5f8f5639c4d926` |
| Rollback boundary | Revert only the thirteen added assertions in `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift` and this remediation section/status metadata in `openspec/changes/m3-taps/apply-progress.md`. No production source or prior M3-2 evidence is part of the rollback. |

### Canonical Remediation Evidence Preimage

The exact bytes inside this block, including the final newline, hash to
`sha256:e9ea2844bd26a3bc81fd78c67c4e4b949fab1d4060d9b4d89a0b5c9eddb67857`:

```text
schema=gentle-ai.remediation-evidence-preimage/v1
change=m3-taps
mode=disabled/unmanaged
parent_attempt_token=sha256:592610c4a7860fc7f71dfdfe97f1a4a7d049a1c7f27d327ee4e7b2f02fe9d574
failed_evidence_revision=sha256:b71e639032cc5f7fa5965d143dff81d14b42d60e222df0722797273a38eb53a4
git_head=09e237971d07dffbc587cce4868036955165fdb3
strict_tdd=true
rdd=disabled
tasks_complete=24
tasks_total=24
tap_shipping_proof_sha256=e8a0909c485e4fceab3e8d93f6f59341d68dfb8ecbc8520e0aa3e7576830c570
app_test_sha256=e71a10aff21c6fa9ed9aec8bfef3a313856052cd5e10853b34368ec20874ac08
focused_command=swift test --package-path Packages/CellarCore --filter TapShippingProofTests
focused_exit=0
focused_result=3 tests in 1 suite passed; unavailable scenario passed 3 arguments
focused_output_sha256=5481ba101e7fdbf773bbe7f09f86d87b433e307f8fdb9b5c365592fb4253445b
app_unit_command=xcodebuild test -project cellar.xcodeproj -scheme cellar -destination platform=macOS,arch=arm64 -only-testing:cellarTests
app_unit_exit=0
app_unit_result=2 tests passed
app_unit_output_sha256=b3a01768551b9d8a825697895010a33d8a5c2f59445a135947abe732de08c4dc
core_regression_command=swift test --package-path Packages/CellarCore
core_regression_exit=0
core_regression_result=775 tests in 113 suites passed with 1 known issue
core_regression_output_sha256=8243e565ee76d6b972aaad9ba8fd4dff8c354b9802fd016c9e8397526377ead8
app_regression_command=xcodebuild test -project cellar.xcodeproj -scheme cellar -destination platform=macOS,arch=arm64
app_regression_exit=0
app_regression_result=2 app tests and 12 UI test executions passed
app_regression_output_sha256=7e504527ee68b6a277d3dcd03a33ea1babdf0105dec420e35c5f8f5639c4d926
production_behavior_changed=false
authored_test_additions=13
git_diff_check_exit=0
status=success
next_recommended=sdd-verify
```

### Remediation Status

Focused disabled/unmanaged remediation is complete. The parent may settle its native attempt using
evidence revision `sha256:e9ea2844bd26a3bc81fd78c67c4e4b949fab1d4060d9b4d89a0b5c9eddb67857`,
then delegate fresh independent `sdd-verify`. Archive remains blocked until that verification reports
zero blockers.
