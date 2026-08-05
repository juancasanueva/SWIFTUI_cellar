```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:0bcc8c0b0e33b0eb4bfd47ecd1e68dfd302a4ecef9921e9affd31933b6b3ddf8
verdict: pass_with_warnings
archive_ready: true
blockers: 0
critical_findings: 0
warning_findings: 1
requirements: 10/10
scenarios: 15/15
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:50bd7e225e47f82f04d59cb7666f6c86d86cf92f725917b923c07978303939f4
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:d5afd5d86d80cd7126f6ab3f9118f6cf1e9f5dc015a967693d3be5bff0d880f3
```

## Verification Report

**Change**: `m3-disk-usage` (M3-3)  
**Version**: N/A  
**Mode**: Strict TDD  
**Artifact mode**: Hybrid (OpenSpec + Engram)  
**Candidate base**: `65eaf16313029058424576a16ba0386b31ad67c7`  
**Candidate revision**: `09e237971d07dffbc587cce4868036955165fdb3`  
**Implementation tree**: `ed07c9d1e5fbe18f391e4869bcdde099841f269d`

### Completeness

| Metric | Value |
|---|---:|
| Requirements | 10 (9 disk-usage + 1 installed-inventory delta) |
| Scenarios | 15 (DU1–DU10 + II1–II5) |
| Tasks total | 17 |
| Tasks complete | 17 |
| Tasks incomplete | 0 |
| Candidate implementation files | 38 |
| Candidate implementation changed lines | 1,758 (1,724 additions, 34 deletions) |

All tasks are complete. The implementation exceeds the session's 1,000-line review budget, but apply proceeded under the maintainer-approved `size:exception`; that decision is recorded in `tasks.md` and Engram apply-progress #7280.

### Candidate Boundary and Working Tree Safety

Verification inspected merged M3-3 commit `387696c` through merge revision `09e2379`. Unrelated working-tree state was preserved, including the M3-2 archive and promoted specs, `openspec/config.yaml`, the additional `TapShippingProofTests.swift` edit, and other OpenSpec artifacts. Verification wrote only this report and its Engram counterpart.

### Build & Tests Execution

**Core package**: ✅ Passed — exit 0; 775 tests in 113 suites; 1 known issue.

```text
swift test --package-path Packages/CellarCore
Test run with 775 tests in 113 suites passed after 15.613 seconds with 1 known issue.
```

The known issue is the pre-existing expected harness case at `OperationCenterCancelTests.swift:183`; it is unrelated to M3-3 and did not fail the suite.

**Primary Xcode runner**: ✅ Passed — exit 0; `** TEST SUCCEEDED **`; 12 UI tests and 2 app Swift Testing cases passed.

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
Executed 12 UI tests, with 0 failures; 2 cellarTests cases passed; TEST SUCCEEDED.
```

**Diff hygiene**: ✅ `git diff --check` passed.  
**Coverage**: ➖ Skipped — no cached/configured coverage capability or threshold was detected. This is informational and non-blocking.

### Spec Compliance Matrix

| ID | Requirement / Scenario | Passing runtime evidence | Result |
|---|---|---|---|
| DU1 | Validated roots remain independent | `RootsAccountingTests.rootsComeOnlyFromValidatedInstallations`; production-backed `rootStatesAreIndependent`; `EngineEventsTests.missingRootsAndProgressRemainBounded` | ✅ COMPLIANT |
| DU2 | Brew is unavailable | `cellarUITests.testCleanupAbsenceWarningsAndReadOnlyBoundary` | ✅ COMPLIANT |
| DU3 | Accounting remains safe and honest | `RootsAccountingTests.metadataTraversalIsLinkSafe`; `caskBundleDescendantsAreMeasured`; Cleanup “on disk”/read-only assertions | ✅ COMPLIANT |
| DU4 | Attribution is exact | `EngineEventsTests.engineAttributesPackagesAndVersions`; `InstalledDeriveTests.linkedKegStateIsNotInferredFromPrimaryKeg` | ✅ COMPLIANT |
| DU5 | Incremental rows remain deterministic | `StoreCacheTests.incrementalOrderingPreservesIdentity`; Cleanup disclosure XCUITest | ✅ COMPLIANT |
| DU6 | Cache adoption is complete and atomic | `StoreCacheTests.cacheAdoptionMatchesRoots`; `currentCompleteGenerationReplacesAtomically` | ✅ COMPLIANT |
| DU7 | Cancellation stays responsive | Engine bounded-progress case; `progressAndCancellationPreserveAcceptedData`; `ownedScanPublishesAndCancels` | ✅ COMPLIANT |
| DU8 | Failure and recovery are explicit | `currentCompleteGenerationReplacesAtomically`; warning-state XCUITest | ✅ COMPLIANT |
| DU9 | Invalidation stays scoped | `InstalledObserverTests.oneStreamFansOutToBothConsumers`; `diskMutationRevalidatesWithoutInstalledRefresh`; mutation gate/receipt tests | ✅ COMPLIANT |
| DU10 | Storage remains read-only | Cleanup read-only and Installed no-size-column XCUITests | ✅ COMPLIANT |
| II1 | A single-keg formula decodes | `InstalledDecodeTests.singleKegFormulaDecodes` | ✅ COMPLIANT |
| II2 | A multi-keg formula keeps every keg | `InstalledDecodeTests.multiKegFormulaKeepsEveryKeg` | ✅ COMPLIANT |
| II3 | A cask string installed version decodes | `InstalledDecodeTests.caskStringInstalledVersionDecodes` | ✅ COMPLIANT |
| II4 | Auto-update declaration remains tri-state | `InstalledDecodeTests.undeclaredAutoUpdatesIsNotAnExplicitFalse` | ✅ COMPLIANT |
| II5 | Linked-keg absence remains unlinked | `InstalledDeriveTests.linkedKegStateIsNotInferredFromPrimaryKeg` | ✅ COMPLIANT |

**Compliance summary**: 15/15 scenarios compliant; 10/10 requirements compliant.

### Re-evaluation of Previous Critical Findings

| Previous finding | Current evidence | Disposition |
|---|---|---|
| DU9 invalidation did not trigger revalidation | `DiskUsageStore.invalidate` now retains the scoped area set and restarts its stored scan configuration; FSEvents and disk-only mutation tests observe a second scanner invocation while Installed remains unchanged | Superseded — fixed and runtime-proven |
| DU3 skipped `.app` descendants | `MetadataDirectoryMeasurer` now enumerates with only `.skipsHiddenFiles`; `caskBundleDescendantsAreMeasured` asserts logical and allocated bytes from `Ghostty.app/Contents/MacOS/ghostty` | Superseded — fixed and runtime-proven |
| DU5 lacked dynamic sorting/identity proof | `incrementalOrderingPreservesIdentity` introduces tied and earlier-sorting arrivals, repeats the read, preserves package ID, and exposes both selected versions | Superseded — runtime proof added |
| `rootStatesAreIndependent` exercised no production code | The test now constructs real roots, runs `DiskUsageEngine.scan`, requires the completed snapshot, and asserts independent root states | Superseded — production-backed assertion |

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Validated independent roots | ✅ Implemented | `HomebrewRoots` centralizes standard/custom root projection; missing areas settle independently. |
| Allocated, link-safe accounting | ✅ Implemented | Metadata-only traversal includes package descendants, skips symlinks/aliases, and deduplicates `(device, inode)` identities per measurement root. |
| Exact package/version/link attribution | ✅ Implemented | Raw components and exact optional `linkedKeg` state are preserved. |
| Stable package-first presentation | ✅ Implemented | Stable `PackageID`/`DiskVersionID` identities and deterministic allocated-byte/kind/name/version ordering are used during live overlays. |
| Complete-only stale cache | ✅ Implemented | Matching complete cache is adopted stale; only current warning-free completion saves and replaces it. |
| Cancellation/current generation | ✅ Implemented | Store-owned task cancellation and generation guards reject late events. |
| Partial warning/recovery | ✅ Implemented | Last-good data remain visible with warnings until complete recovery clears them. |
| Scoped invalidation/revalidation | ✅ Implemented | Area scopes are retained, disk invalidation restarts revalidation, and the disk-only gate does not refresh Installed. |
| Read-only visibility | ✅ Implemented | No cleanup action, recommendation, reclaimable claim, or Installed size column exists. |
| Exact linked-keg delta | ✅ Implemented | Payload absence remains unlinked; the primary-keg fallback remains separate for legacy Installed presentation. |

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| One-way dependency graph | ✅ Yes | `DiskUsage -> BrewProcess, Catalog`; receipt mapping remains inward in `BrewClient`. |
| Sole root projection | ✅ Yes | Root arithmetic and root identity remain in `HomebrewRoots`. |
| Metadata-only allocated accounting | ✅ Yes | No content reads or followed links; `.app` descendants are now measured. |
| Off-main streaming and cancellation | ✅ Yes | `@concurrent` producer, unit events, cancellation checks, and MainActor store separation are present. |
| Complete-only atomic cache | ✅ Yes | Cache actor and store adoption rules follow the design. |
| Exact links and scoped invalidation | ✅ Yes | Link projection, fan-out, disk gate, restart, and no-Installed-refresh behavior are covered. |
| Package-first read-only presentation | ✅ Yes | Stable IDs, separate cache, “on disk” labels, and excluded cleanup behaviors are present. |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD evidence reported | ✅ | Engram apply-progress #7280 and `tasks.md` contain RED/GREEN work-unit evidence. |
| All executable tasks have tests | ✅ | 16/16 executable tasks map to test files/commands; 6.2 is documentation-only. |
| RED confirmed (tests exist) | ✅ | 13 test-bearing change files and 2 test helpers exist. |
| GREEN confirmed (tests pass) | ✅ | Both required full commands passed in this verification run. |
| Triangulation adequate | ✅ | All 15 scenarios have passing runtime coverage; former DU3/DU5/DU9 gaps now have variant-specific tests. |
| Safety net for modified files | ⚠️ | Full suites pass, but apply-progress groups evidence by work unit and omits the strict module's explicit TRIANGULATE and SAFETY NET columns. |

**TDD Compliance**: 5/6 checks passed without qualification.

### Test Layer Distribution

M3-focused new or changed behavioral cases:

| Layer | Tests | Files | Tools |
|---|---:|---:|---|
| Unit | 20 | 11 | Swift Testing |
| Integration | 5 | 2 | Swift Testing + temporary filesystem/coordinator seams |
| E2E | 3 | 1 | XCTest/XCUITest |
| **Total** | **28** | **13 test-bearing files** | |

### Changed File Coverage

Coverage analysis skipped — no cached/configured coverage capability or threshold was detected. This is informational and not a failure.

### Assertion Quality

**Assertion quality**: ✅ All M3-related assertions verify production behavior. No tautologies, production-free assertions, ghost loops, smoke-only tests, orphan empty checks, or mock-heavy assertion ratios were found. The former `rootStatesAreIndependent` critical finding is resolved by executing `DiskUsageEngine.scan` against a temporary root tree.

### Quality Metrics

**Linter**: ➖ Not available/detected.  
**Type checker/build**: ✅ Swift 6 package compilation and Xcode build completed without compile errors. The app target uses Swift 6 with MainActor default isolation; package concurrency boundaries compile under the current toolchain.  
**SwiftUI API review**: ✅ The Cleanup surface uses current APIs (`@Observable`, `foregroundStyle`, `ContentUnavailableView`, stable `ForEach` identity) and no deprecated API identified by the loaded SwiftUI reference.

### Issues Found

**CRITICAL**: None.  
**WARNING**:
1. Strict TDD history is behaviorally supported but not structurally complete: apply-progress lacks explicit TRIANGULATE and SAFETY NET columns and reports grouped work units rather than one row per task.

**SUGGESTION**: None.

### Verdict

**PASS WITH WARNINGS**

Both required runtime commands pass, all 17 tasks are complete, all 10 requirements and 15 scenarios have passing evidence, and the four previous critical findings are superseded by current production code plus runtime tests. There are 0 blockers and 0 critical findings. Archive is ready; only the non-blocking Strict TDD evidence-format warning remains.
