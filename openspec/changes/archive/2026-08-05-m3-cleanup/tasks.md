# Tasks: M3 Cleanup Operations

## Review Workload Forecast

Planning: ~75 additions/0 deletions. Implementation: 2,050–2,900 additions+deletions, High versus 2,000. Delivery: one PR under approved `size:exception` / `exception-ok`; U0→U6 reviewable commits.

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: size-exception
400-line budget risk: High

The exception supersedes chaining. CO1–CO7/IH1–IH2 map requirements in order.

### Suggested Work Units

`CORE`=`swift test --package-path Packages/CellarCore`; `X`=`xcodebuild -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`; `UI`=`X test -only-testing:cellarUITests`.

| Unit | Goal/map | Proof | Runtime | Rollback |
|---|---|---|---|---|
| U0 | Probes; CO1–7 | N/A—runtime-only | Sentinel prefix; four probes; forbidden-prefix denial | Fixtures |
| U1 | Process; CO1,5 | `CORE --filter CleanupCommand` | `ProcessSpec`/zero-spawn | Process/command |
| U2 | Preview; CO2,3 | `CORE --filter Cleanup` | Bytes/concurrency/cancel | Preview |
| U3 | Spine; CO4,6 | `CORE --filter CleanupOperation` | Launcher/gate receipts | OperationCenter |
| U4 | History; IH1,2 | `CORE --filter CleanupHistory` | Schema-V1 round trip | Persistence |
| U5 | UI; CO7 | `UI` | Fixture flows | App |
| U6 | Regression/RDD | Full commands | Candidate receipts/validation | Whole PR |

## Completion Evidence

Require RED failure before production edits, GREEN result, REFACTOR rerun, runtime evidence/N/A, acceptance IDs, line count, and rollback files. Keep tests/docs per commit. No second queue/target, direct deletion, migration, or broader work.

## Phase 0: Runtime Gate

- [x] 0.1 RED list Homebrew assertions; prove `/opt/homebrew` and `/usr/local` destructive probes are denied.
- [x] 0.2 GREEN probe only a sentinel temporary prefix; capture argv/environment/output/contention.
- [x] 0.3 REFACTOR store byte-exact fixtures at `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Cleanup/`.

## Phase 1: Typed Process Boundary (depends U0)

- [x] 1.1 RED add `Packages/CellarCore/Tests/BrewProcessTests/CleanupEnvironmentTests.swift` and `Packages/CellarCore/Tests/BrewClientTests/CleanupCommandTests.swift` for CO1/CO5/hostile targets.
- [x] 1.2 GREEN modify `Packages/CellarCore/Sources/BrewProcess/{BrewCommand,BrewEnvironment,BrewRunner}.swift`; add `Packages/CellarCore/Sources/BrewClient/{CleanupModels,CleanupCommand}.swift`.
- [x] 1.3 REFACTOR prove argv/overrides/guidance and zero shell/spawn.

## Phase 2: Preview Evidence (depends U1)

- [x] 2.1 RED add `Packages/CellarCore/Tests/BrewClientTests/{CleanupParserTests,CleanupStoreTests}.swift` for CO2/CO3 provenance/overflow/supersession/cancellation.
- [x] 2.2 GREEN add `Packages/CellarCore/Sources/BrewClient/{CleanupParser,CleanupPreviewSource,CleanupStore}.swift`; canonicalize versioned SHA-256 fingerprints.
- [x] 2.3 REFACTOR prove equality authorization and complete same-root “currently on disk” allocation.

## Phase 3: Shared Mutation Spine (depends U2)

- [x] 3.1 RED add `Packages/CellarCore/Tests/BrewClientTests/{CleanupAuthorizationTests,CleanupOperationTests}.swift` for CO4/CO6/all terminals.
- [x] 3.2 GREEN add `Packages/CellarCore/Sources/BrewClient/OperationCenterCleanup.swift`; modify `Packages/CellarCore/Sources/BrewClient/{BrewMutating,OperationCenterBulk}.swift` for disclosure/denial/history/invalidation.
- [x] 3.3 REFACTOR prove launch and declared-domain exactly-once/zero invariants.

## Phase 4: Persistence (depends U3)

- [x] 4.1 RED add `Packages/CellarCore/Tests/PersistenceTests/CleanupHistoryPresentationTests.swift` for IH1/IH2 verbs/subjects/labels/search/fallback.
- [x] 4.2 GREEN modify `Packages/CellarCore/Sources/Persistence/HistoryPresentation.swift`; retain nullable Schema V1 and non-replayability.
- [x] 4.3 REFACTOR record round-trip/rollback readability.

## Phase 5: App Composition (depends U2–U4)

- [x] 5.1 RED extend `cellarUITests/cellarUITests.swift` for all CO7 states/flows.
- [x] 5.2 GREEN modify `cellar/Cleanup/CleanupView.swift`, `cellar/Activity/MutationConfirmation.swift`, `cellar/{ContentView,cellarApp,AppTestFixtures}.swift` with specified identifiers.
- [x] 5.3 REFACTOR prove storage rows, fixtures, identifiers, thin DI, command/provenance copy.

## Phase 6: Verify and Freeze (depends U0–U5)

- [x] 6.1 Run `CORE`, `UI`, `X test`, `X build`, and safe probes; map CO1–7/IH1–2.
- [x] 6.2 Normalize; verify exclusions, exception, work-unit commits, and single-PR rollback.
- [x] 6.3 Close delivery under the explicit maintainer-selected clone-local RDD-disabled ordinary policy: preserve candidate `9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4`; record `reviewGate`, receipt, reviewer, lineage, and approval as absent; classify delivery as unmanaged by candidate choice, not approved; require independent `sdd-verify`.
