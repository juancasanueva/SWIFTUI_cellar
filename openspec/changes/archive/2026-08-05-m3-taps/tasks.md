# Tasks: M3-2 Tap Management

## Review Workload Forecast

| Burden | Lines |
|---|---:|
| Core production | 900–1,250 |
| App/UI | 350–500 |
| Tests | 1,750–2,450 |
| Existing planning/docs; separate docs PR | 1,700–2,500 |
| Verification/archive | 700–1,200 |
| Lifecycle total vs 1,200 | 5,400–7,900 (4.5–6.6×) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: not applicable (`size:exception`)
400-line budget risk: High

`size:exception` is approved (Engram #7218). Implementation ships as one PR; chain strategy is not applicable. Planning Markdown remains a separate docs PR later.

`C[S]`=`swift test --package-path Packages/CellarCore --filter S`; `APP[X]`=`xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' X`; `BUILD` substitutes `build`. `S`/`T`=`Packages/CellarCore/Sources`/`Packages/CellarCore/Tests`. RED ordinals ledger all 57 spec scenarios exactly once.

### Suggested Work Units

Each plans one code+tests+docs commit.

| Unit | Evidence | Test | Runtime | Rollback |
|---|---|---|---|---|
| D | exit-0 | `git diff --check -- openspec` | N/A—docs | Markdown;config-lines |
| 1 | exit-0 | `C['MutationAuthorizationTests|OperationCenterAuthorizationTests']` | N/A—whole-change | `S/BrewProcess/*`;`S/BrewClient/{OperationCenter,ActivityItem,MutationOutcome}.swift` |
| 2 | exit-0 | `C['ConfirmationBacklogTests|ForceDenialRecoveryTests']` | N/A—whole-change | `S/BrewClient/{MutationRefreshReceipts,ForceDenialRecoveryCoordinator,OperationCenterBulk}.swift` |
| 3 | exit-0 | `C['Tap|History']` | N/A—whole-change | `S/BrewClient/Tap*`;history-fields |
| 4 | exit-0 | `APP`;`BUILD` | whole-change-`m3-taps` | `.taps`;`cellar/Taps`;app-wiring |

## Phase 1: Authorization

- [x] 1.1 **RED:** Create `T/BrewProcessTests/MutationAuthorizationTests.swift`,`T/BrewClientTests/OperationCenterAuthorizationTests.swift`; read-impossibility/default-compatibility/queue-front/no-fake-exit/snapshot-query/cancellation/reentrancy/exactly-once-spawn-finish-terminal-history; fails:contract/order. `C['MutationAuthorizationTests|OperationCenterAuthorizationTests']`.
- [x] 1.2 **GREEN:** Update `S/BrewProcess/{MutationLaunchAuthorization,BrewRunner,BrewOperation,OperationSnapshot}.swift`,`S/BrewClient/{OperationCenter,ActivityItem,MutationOutcome}.swift`,`S/Persistence/SwiftDataHistoryRecorder.swift`; pass-1.1-only; rerun.

## Phase 2: Receipts and Recovery

- [x] 2.1 **RED:** Create `T/BrewClientTests/MutationRefreshReceiptTests.swift`; keyed-success/failure/brew-absence/installation-change/cancel/no-consumer/duplicate/stream-app-teardown; fails:leak/misrouting. `C[MutationRefreshReceiptTests]`.
- [x] 2.2 **GREEN:** Add/update `S/BrewClient/{MutationRefreshReceipts,BrewMutating,InstalledStore,InstalledChangeObserving,ServicesRefreshCoordinator}.swift`; settle-once; rerun.
- [x] 2.3 **RED:** Create `T/BrewClientTests/{ConfirmationBacklog,ForceDenialRecovery}Tests.swift`; occupied/vacant/latest-wins/ineligible/deleted/absent/teardown/cancellation; terminal-history-gates→two-receipts→evidence→one-promotion; fails:overwrite/premature/stuck/duplicate. `C['ConfirmationBacklogTests|ForceDenialRecoveryTests']`.
- [x] 2.4 **GREEN:** Update `S/BrewClient/OperationCenterBulk.swift`; add `S/BrewClient/ForceDenialRecoveryCoordinator.swift` and keyed-gates; rerun both suites.

## Phase 3: Tap Core

- [x] 3.1 **RED [TM1.1–2,TM2.1–4,TM3.1–3]:** Create `T/BrewClientTests/{TapPayload,TapDecode,TapStore}Tests.swift`; fails:acquisition/tolerance/redaction/freshness. `C[Tap]`.
- [x] 3.2 **GREEN:** Add `S/BrewClient/{TapPayloadSource,TapWire,TapStore}.swift`: one-probe/tolerant/non-persistent/current-only; rerun.
- [x] 3.3 **RED [TM4.1–2,TM5.1–5,TM10.1–3]:** Create `T/BrewClientTests/TapProjectionTests.swift`; fails:official/action/filter/handoff/state. `C[TapProjectionTests]`.
- [x] 3.4 **GREEN:** Add `S/BrewClient/TapProjection.swift`: kind/exact-tap/lazy-filter/last-good/error/absence; rerun 3.3.
- [x] 3.5 **RED [TM6.1–4,TM7.1–3,TM8.1–4,PM3.7–9]:** Create `T/BrewClientTests/TapCommandTests.swift`; fails:validation/typed-argv/plain-force/disclosure/staleness. `C[TapCommandTests]`.
- [x] 3.6 **GREEN:** Add `S/BrewClient/TapCommand.swift`,typed-authorizer/disclosure; prohibit prose→argv; rerun.
- [x] 3.7 **RED [PM3.1–6]:** Extend `T/BrewClientTests/{ConfirmationBox,OperationCenter}Tests.swift`; fails:uninstall/zap/bulk-compatibility. `C['ConfirmationBoxTests|OperationCenterTests']`.
- [x] 3.8 **GREEN:** Preserve package behavior and add tap presentation; rerun 3.7.

## Phase 4: Integration and History

- [x] 4.1 **RED [TM9.1–2,TM11.1]:** Create `T/BrewClientTests/TapIntegrationTests.swift`: FIFO/activity/exactly-once-domain-refresh-replacement; PD6/dependency/no-catalog-invalidation/no-payload-persistence/no-prose→argv/no-RDD; fails:containment. `C[TapIntegrationTests]`.
- [x] 4.2 **GREEN:** Wire `.taps`/coordinators/force-ordering while preserving PD6 and `BrewClient→BrewProcess`; rerun 4.1.
- [x] 4.3 **RED [IH1.1–9,IH5.1–6]:** Extend `T/BrewClientTests/OperationCenterHistoryTests.swift`,`T/PersistenceTests/{HistoryRecorder,HistoryStore,HistorySubject}Tests.swift`; fails:exactly-once/null-identity/argv/outcome/compatibility/order/search. `C[History]`.
- [x] 4.4 **GREEN:** Update `S/Persistence/SwiftDataHistoryRecorder.swift`,`S/BrewClient/ActivityItem.swift`,`cellar/History/HistoryRow.swift`; no schema change; rerun 4.3.

## Phase 5: App and Verification

- [x] 5.1 **RED automated:** Extend `cellarUITests/cellarUITests.swift`: navigation/add-plain-force/full-confirmations/Installed-handoff/official-empty-error-absent/large-filter/accessibility-identifiers/keyboard; fails:missing-surfaces. `APP[-only-testing:cellarUITests]`.
- [x] 5.2 **GREEN:** Add `cellar/Taps/*`; update `cellar/{AppSection,ContentView,cellarApp}.swift`,`cellar/Activity/MutationConfirmation.swift`; keep-app-thin; rerun.
- [x] 5.3 **Manual:** verified navigation, confirmation, thousands-row laziness/filtering, VoiceOver, Full Keyboard Access, distinct states, and Installed handoff on 2026-08-04; authoritative observations are recorded in `apply-progress.md`.
- [x] 5.4 Progress focused suites; run authoritative `swift test --package-path Packages/CellarCore`, configured app test/build. The `cellar` scheme excludes package suites.
- [x] 5.5 Read back 4.1 guards; never call `gentle-ai review` or create review receipts.
- [x] 5.6 Before runtime-bearing apply/verify, acquire then settle one native whole-`m3-taps` `sdd-attempt`, using distinct request IDs and SHA-256 evidence revision; invent no counters/batch attempts.
