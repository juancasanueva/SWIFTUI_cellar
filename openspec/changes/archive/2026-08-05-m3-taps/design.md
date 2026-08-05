# Design: M3-2 Tap Management — Revision 3

## Technical Approach

Preserve the proposal and all 57 scenarios. Taps remain a non-persistent `BrewClient` projection; PD6/`BrewMutating` stay unchanged; dependency remains `BrewClient → BrewProcess`. RDD stays disabled: receipts are process-local and unpersisted.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| Mutation-only authorized start | Authorizer on `BrewCommand` | Reads are unrepresentable. |
| Typed no-process terminal | Fake `BrewExit` | Denial is not process execution. |
| Actor receipt registry | Unkeyed `Void` inference | Makes refresh completion operation/domain-exact. |
| One visible slot + one latest-wins recovery backlog | Overwrite or “wait/cancel” | Preserves unrelated UI and guarantees promotion. |

## A. Authorized Mutation API

`BrewProcess` owns:

```swift
public struct BrewMutation: Sendable, Equatable {
  public let arguments: [String]; public init(arguments: [String])
}
public struct MutationLaunchDenial: Error, Sendable, Equatable {
  public enum Code: Sendable { case evidenceChanged, evidenceUnavailable }
  public let code: Code
}
public enum MutationLaunchDecision: Sendable, Equatable { case allow, deny(MutationLaunchDenial) }
public protocol MutationLaunchAuthorizing: Sendable {
  func authorizeLaunch() async -> MutationLaunchDecision
}
public struct AllowMutationLaunch: MutationLaunchAuthorizing { /* returns .allow */ }
public func start(_ mutation: BrewMutation,
  authorizer: any MutationLaunchAuthorizing = AllowMutationLaunch())
  async throws(BrewProcessError) -> AuthorizedMutationOperation
```

`BrewMutation` always queues `.mutate`; no read conversion exists. Existing `start(BrewCommand)` routes mutations through `AllowMutationLaunch`; reads remain immediate. Authorization runs at FIFO front immediately before `launcher.launch`, followed by cancellation recheck. `BrewClient.ForceUntapLaunchAuthorizer` compares immutable typed target/expected `Set<PackageID>`, never prose.

## B. No-Process Terminal Model

`BrewProcess` adds `AuthorizedMutationTerminal { case process(BrewExit, fault: BrewProcessError?); case authorizationDenied(MutationLaunchDenial) }`. `AuthorizedMutationOperation.terminal()` returns it; denial finishes `lines` empty. `OperationRecord` stores one internal terminal enum. `OperationSnapshot.Phase` retains `.terminal(BrewExit,fault:)` and adds `.authorizationDenied`. Existing `BrewOperation.exit()/fault()`, exits, cancellation, and launch failures remain unchanged; only authorized starts return the new handle.

Denial sets terminal once, publishes/compacts once, and launches nothing. `OperationCenter` maps `MutationOutcome.authorizationDenied(Code)` through sole idempotent `finish`. Persistence writes one null-package/exact-argv row: `outcomeRaw` is `authorizationDeniedEvidenceChanged` or `authorizationDeniedEvidenceUnavailable`, `exitStatus=nil`; labels are “Needs fresh confirmation”/“Could not verify current packages.”

## C. Refresh Receipt Protocol

`BrewClient` owns `MutationOperationToken(UUID)`, `RefreshDomain { taps, installedInventory, services }`, `MutationTerminalEvent(token,domain,installationURL)`, `RefreshResult { refreshed, failed, brewUnavailable, installationChanged, cancelled, teardown }`, `RefreshReceipt(token,results)`, and actor `MutationRefreshRegistry`.

On confirmed force, `ForceDenialRecoveryCoordinator` creates the token, registers `{.taps,.installedInventory}`, starts its waiter, then `OperationCenter.perform(id:)` begins gates. `MutationGates.end(scope,token,installationURL)` emits one event/domain. Each app-lifetime coordinator invalidates once, refreshes once, then calls `complete`; the registry accepts the first result/domain, ignores duplicates/unknown tokens, and resumes at set completion.

Failure, absence, installation mismatch, and cancellation return their named result. Waiter cancellation removes its entry; coordinator/app teardown `shutdown()` resolves `.teardown`; stream end resolves that domain likewise. Unregistered events refresh normally then discard completion. M3-1 never waits; no UI consumer is required; one refresh or teardown bounds lifetime, with no retry/timer.

Only authorization denial plus two `.refreshed` results permit post-refresh complete evidence to build replacement; `finish` cancels every non-denial expectation. The denied operation cannot stale it.

## D. Confirmation Backlog/Vacancy

`@MainActor ConfirmationBox` adds `visible` plus one `RecoveryCandidate(request,token,supersessionKey,isEligible,onCancel)`. `enqueueRecovery` ignores duplicate tokens; unrelated visible UI remains; newest recovery cancels/replaces backlog. Confirm/decline vacancy synchronously promotes iff eligible. Newer force for the same tap supersedes visible/backlogged recovery; decline cancels, confirm consumes once. Tap deletion, ineligibility, brew absence/change, or `shutdown()` cancel matching state. Thus exactly one current candidate promotes after vacancy.

## E. End-to-End Ordering Proof

1. Complete evidence creates immutable confirmation. 2. Confirm creates/registers token, waiter and authorizer, then submits. 3. FIFO wait preserves old request. 4. Front authorization compares complete current sets: reorder allows; add/remove/kind-change denies. 5. Post-await terminal check makes cancellation win. 6. Denial finishes empty stream/no process once. 7. `finish` settles outcome, keyed gates, then one history row. 8. Both coordinators invalidate/refresh/complete once. 9. Successful receipt yields post-refresh evidence and one replacement candidate. 10. Slot presents now or auto-promotes on vacancy.

After every await, cancellation, latest-token, installation, and eligibility are rechecked; actor state commits before suspension. Idempotent terminal, `finish`, receipt, and candidate consumption absorb reentrancy.

## F. Files and Strict TDD

| Files | Change |
|---|---|
| `Sources/BrewProcess/{MutationLaunchAuthorization,BrewRunner,BrewOperation,OperationSnapshot}.swift` | Authorized API/terminal. |
| `Sources/BrewClient/{OperationCenter,OperationCenterBulk,ActivityItem,MutationOutcome,BrewMutating,InstalledStore,InstalledChangeObserving,ServicesRefreshCoordinator,MutationRefreshReceipts,ForceDenialRecoveryCoordinator}.swift` | Mapping, keyed gates/receipts/backlog/recovery. |
| `Sources/Persistence/SwiftDataHistoryRecorder.swift`, `cellar/History/HistoryRow.swift`, `cellar/cellarApp.swift` | Vocabulary and wiring. |
| `Sources/BrewClient/{TapCommand,TapPayloadSource,TapWire,TapStore,TapProjection}.swift`, `cellar/Taps/*` | Tap surfaces. |
| `Tests/BrewProcessTests/MutationAuthorizationTests.swift`, `Tests/BrewClientTests/{MutationRefreshReceipt,ConfirmationBacklog}Tests.swift`, `Tests/PersistenceTests/HistoryRecorderTests.swift` | RED contracts. |

RED→GREEN tests cover: read-impossibility and source/default compatibility; denial has no exit/process and old exit/fault/cancel behavior; queue-front races; receipt success/failure/absence/installation-change/cancel/teardown/no-consumer/duplicate; occupied-slot vacancy, latest-wins, decline, newer force, ineligible/deleted/absent/teardown; and end-to-end invalidation-before-reconfirmation. Retain all 57 scenario, hostile argv, PD6, dependency-direction, and RDD-containment tests.

## Threat Matrix

Documentation paths, Git selection, commit, push, and PR commands: N/A—absent. Subprocess: applicable; typed argv/no shell/fail-closed front authorization; RED covers hostile text, stale queue, cancellation, denial, launch failure.

## Migration / Rollout

No schema/data migration or flag. Apply remains blocked pending `size:exception`. Rollback removes additions; existing outcomes and PD6 remain intact. Open questions: none.
