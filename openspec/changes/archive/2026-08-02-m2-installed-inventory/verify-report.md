```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:7b64b398fca0f2232b73983afdb40d23f5a9c9319dcbaeff1daf3db54a52ff91
verdict: pass
blockers: 0
critical_findings: 0
requirements: 15/15
scenarios: 50/50
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:4acd7ccc91988639a3a176fde6d36cf6be41f60de2b9cd568e74a15b29be4b90
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
build_exit_code: 0
build_output_hash: sha256:effb98d361e95eb614226370f48d419a1e0f26a14a48a6abb685f70d34b39d6a
```

## Verification Report

**Change**: m2-installed-inventory
**Version**: `installed-inventory` ADDED (11 req / 34 sc) + `brew-detection` MODIFIED (4 req / 16 sc)
**Mode**: Strict TDD
**Branch / head**: `feature/m2-installed-inventory` @ `2a10c64`
**Verified**: 2026-08-02

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 60 |
| Tasks complete | 60 |
| Tasks incomplete | 0 |

Task 10.1 (manual live-brew FSEvents verification) is complete: executed by the orchestrator after
apply, with its evidence table recorded in `tasks.md` and Engram #7088. The apply-progress snapshot
(#7086) predates it and its `59/60` claim is stale.

Spec counts re-derived from the retrieved delta files, not taken from the artifacts:
`rg -c '^### Requirement:'` / `rg -c '^#### Scenario:'` returns 11/34 for `installed-inventory` and
4/16 for `brew-detection`. Base `openspec/specs/brew-detection/spec.md` is 5 req / 15 sc; the one
untouched requirement ("Absent brew is a soft signal") holds 1 scenario, so the 4 MODIFIED
requirements go 14 → 16 scenarios, i.e. exactly the two new coalescing scenarios. The delta's own
arithmetic is honest.

### Build & Tests Execution

**Tests**: ✅ 345 passed / 0 failed / 0 skipped — re-run by this phase, not quoted from apply.

```text
$ swift test --package-path Packages/CellarCore
Test run with 345 tests in 47 suites passed after 1.351 seconds.
exit 0
```

Baseline on `main` @ `ebac63d` was 243 tests / 36 suites. +102 tests, +11 suites, none deleted.

**Build**: ✅ Passed

```text
$ xcodebuild test -project cellar.xcodeproj -scheme cellar \
    -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
** TEST SUCCEEDED **
exit 0
```

**Coverage**: ➖ Not available — no coverage tool configured for this package.

### Spec Compliance Matrix

#### `installed-inventory` (ADDED — 11 requirements / 34 scenarios)

| Requirement | Scenario | Test | Result |
|-------------|----------|------|--------|
| II1 One probe, decoded off-main | One invocation per refresh | `InstalledStoreTests > One completed refresh records exactly one brew invocation` | ✅ COMPLIANT |
| II1 | Derived facts require no extra invocation | `InstalledStoreTests > Outdated, pinned and dependency-only state all come from that one invocation` | ✅ COMPLIANT |
| II1 | Main actor stays responsive during decode | `InstalledDecodeTests > The main actor stays responsive while a realistic payload is decoded` | ✅ COMPLIANT |
| II2 Asymmetric shapes decode | A single-keg formula decodes | `InstalledDecodeTests > A single-keg formula decodes with its version and install time` | ✅ COMPLIANT |
| II2 | A multi-keg formula keeps every keg | `InstalledDecodeTests > A multi-keg formula appears once and keeps every keg` | ✅ COMPLIANT |
| II2 | A cask's string installed version decodes | `InstalledDecodeTests > A cask's string installed version decodes` | ✅ COMPLIANT |
| II2 | Undeclared vs declared auto-update flag | `InstalledDecodeTests > An undeclared auto-update flag is distinguishable from a declared one` | ✅ COMPLIANT |
| II3 On-request derived, default view | Default view hides dependency-only formulae | `InstalledDeriveTests > The default view hides dependency-only formulae` | ✅ COMPLIANT |
| II3 | Toggle reveals dependency-only formulae | `InstalledDeriveTests > The dependency toggle reveals them, and each says which it was` | ✅ COMPLIANT |
| II3 | No on-request signal reads as on-request | `InstalledDeriveTests > A cask, whose records carry no on-request marker, is listed by default` | ✅ COMPLIANT |
| II4 Auto-updating casks never outdated | Outdated formula reported and counted | `InstalledDeriveTests > An outdated formula is in the outdated set and counted` | ✅ COMPLIANT |
| II4 | Self-updating cask behind published version | `InstalledDeriveTests > A self-updating cask behind its published version is never outdated` | ✅ COMPLIANT |
| II4 | Cask without auto-updates is outdated normally | `InstalledDeriveTests > A cask that does not declare auto-updates is outdated on the same terms` | ✅ COMPLIANT |
| II5 Newer version from same probe | Signal derived without a second invocation | `InstalledDeriveTests > The newer-version signal comes from the same single invocation` | ✅ COMPLIANT |
| II5 | Matching versions produce no signal | `InstalledDeriveTests > Matching versions produce no signal, and still no outdated membership` | ✅ COMPLIANT |
| II6 Pin state and install date | Pin state for both kinds, no extra invocation | `InstalledDeriveTests > Pin state is exposed for both kinds, with the recorded pinned version` + `> Pin state and install dates cost no extra invocation` | ✅ COMPLIANT |
| II6 | Install dates from recorded timestamps | `InstalledDeriveTests > Install dates are the recorded timestamps read as epoch seconds` | ✅ COMPLIANT |
| II7 Join above both packages | Matched package carries catalog metadata | `InstalledFilterTests > A matched installed package carries its version and the catalog description` | ✅ COMPLIANT |
| II7 | Unmatched installed package still listed | `InstalledFilterTests > An unmatched installed package is still listed, with its snapshot data` | ✅ COMPLIANT |
| II7 | Catalog target does not depend on brew-process | `PackageGraphTests > The catalog target declares no dependency on the brew-process target` + `> No path through the manifest reaches brew-process from the catalog` | ✅ COMPLIANT |
| II8 Filters composed, not indexed | Installed filter narrows browse results | `InstalledFilterTests > The installed filter narrows browse results` | ✅ COMPLIANT |
| II8 | Not-installed filter is the complement | `InstalledFilterTests > The not-installed filter is the complement` | ✅ COMPLIANT |
| II8 | Outdated filter excludes self-updating casks | `InstalledFilterTests > The outdated filter excludes self-updating casks` | ✅ COMPLIANT |
| II8 | No inventory → filters disabled, results unchanged | `InstalledFilterTests > With no inventory the mode is forced to all and the picker is disabled` | ✅ COMPLIANT (rule level; see WARNING 2) |
| II8 | Catalog filter set declares no installed predicate | `CatalogTests/FilterTests > noFilterReferencesInstalledState` | ✅ COMPLIANT |
| II9 Brew absent yields empty inventory | Absent brew → empty inventory with guidance | `InstalledStoreTests > No installation clears to an empty inventory, throws nothing, spawns nothing` | ✅ COMPLIANT |
| II9 | Invalid configured path is guidance | `InstalledStoreTests > An invalid configured path is guidance carrying the rejection reason` + `> A configured path that vanished is distinct from no brew at all` | ✅ COMPLIANT |
| II9 | Inventory populates when brew appears | `InstalledStoreTests > The inventory populates when brew appears, with no restart` | ✅ COMPLIANT |
| II10 External changes, debounced | External install reflected without user action | `InstalledRefreshTests > An external install is reflected after the quiet window, with no user action` | ✅ COMPLIANT |
| II10 | Burst causes exactly one re-snapshot | `InstalledRefreshTests > Twenty signals inside the quiet window cost exactly one re-snapshot` + `> A signal arriving inside the window pushes the refresh back` | ✅ COMPLIANT |
| II10 | Signals during a mutation suppressed, settled once | `InstalledRefreshTests > Signals during a Cellar mutation are suppressed and settled exactly once` + `> A mutation with no signals at all still settles with one re-snapshot` | ✅ COMPLIANT |
| II10 | Refresh after the in-flight one settles is fresh | `InstalledStoreTests > A refresh requested after the previous settled takes a fresh snapshot` + `> Two overlapping refreshes perform one acquisition and see the same inventory` | ✅ COMPLIANT |
| II11 Loops owned for app lifetime | Closing the starting window does not stop loops | `LoopOwnerTests > Closing the scene that started a loop does not cancel it` + `> A refresh after the starting window closed still updates the inventory` | ✅ COMPLIANT |
| II11 | A second window does not start a second loop | `LoopOwnerTests > Reopening a window after all were closed does not start another loop` + `> Starting the same id twice runs exactly one loop` | ✅ COMPLIANT |

#### `brew-detection` (MODIFIED — 4 requirements / 16 scenarios)

| Requirement | Scenario | Test | Result |
|-------------|----------|------|--------|
| BD1 Prefix classification | Apple Silicon prefix preferred when both exist | `DetectionTests > The native prefix wins when both prefixes exist` (asserts `.appleSilicon`) | ✅ COMPLIANT |
| BD1 | Only the Intel carry-over prefix exists | `DetectionTests > Only the Intel prefix present resolves as a carry-over installation` (asserts `.intelCarryOver`) | ✅ COMPLIANT |
| BD2 Rosetta advisory only | Advisory flag does not restrict capability | `DetectionTests > A carry-over installation is advisory only, never degraded` | ✅ COMPLIANT |
| BD3 Strict custom path validation | Path is not executable | `DetectionTests > A configured path that is not executable is invalid, not absent` | ✅ COMPLIANT |
| BD3 | Executable but not Homebrew | `DetectionTests > An executable that is not Homebrew is invalid with its output` | ✅ COMPLIANT |
| BD3 | Homebrew below the 4.x floor | `DetectionTests > Homebrew below the 4.0.0 floor is invalid with both versions` | ✅ COMPLIANT |
| BD3 | Valid custom path wins over auto-discovery | `DetectionTests > A valid configured path wins over an existing native prefix` | ✅ COMPLIANT |
| BD3 | Invalid custom path does not fall back | `DetectionTests > An invalid configured path never falls back to a working prefix` | ✅ COMPLIANT |
| BD4 Observable, re-evaluated state | Evaluated at launch | `BrewDetectionStoreTests > The launch evaluation publishes exactly one state` | ✅ COMPLIANT |
| BD4 | Focus re-evaluation observes a newly installed brew | `BrewDetectionStoreTests > Brew appearing after an absent result publishes the transition` | ✅ COMPLIANT |
| BD4 | Disappearing configured path transitions away | `BrewDetectionStoreTests > A configured path that vanishes transitions off detected` (+ `DetectionTests > A configured path that no longer exists reports the missing path` for the `invalid` vs `configuredPathMissing` half) | ✅ COMPLIANT |
| BD4 | A settled evaluation does not answer a later one | `BrewDetectionStoreTests > A settled evaluation does not answer a later re-evaluation` | ✅ COMPLIANT |
| BD4 | An abandoned caller does not poison later ones | `BrewDetectionStoreTests > An abandoned caller does not poison later re-evaluations` | ✅ COMPLIANT |
| BD4 | Concurrent re-evaluations coalesce onto one probe | `BrewDetectionStoreTests > Concurrent refreshes collapse into a single evaluation` | ✅ COMPLIANT |
| BD4 | Configured path changed mid-evaluation | `BrewDetectionStoreTests > A configured path changed mid-evaluation is not answered by the previous path` | ✅ COMPLIANT |
| BD4 | Identical concurrent requests still coalesce | `BrewDetectionStoreTests > Two callers asking about the same path still coalesce onto one probe` | ✅ COMPLIANT |

**Compliance summary**: 50/50 scenarios compliant. No `UNTESTED`, no `FAILING`.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| II1 | ✅ Implemented | `BrewInfoPayloadSource.command = BrewCommand.read(["info", "--installed", "--json=v2"])` is a compile-time constant vector; `InstalledDecoder.decode` is `@concurrent` with the attribute before the modifier. |
| II2 | ✅ Implemented | `FormulaInstalledWire.installed: [KegWire]?` vs `CaskInstalledWire.installed: String?`; `autoUpdates: Bool?` preserved to the projection as `declaresAutoUpdates`. |
| II3 | ✅ Implemented | `InstalledPackage.isOnRequest = kegs.contains(where: \.installedOnRequest)`; formula keg defaults `installedOnRequest ?? true`, cask keg synthesised with `true`. The "no signal reads as on-request" rule is in the decoder, where it belongs. |
| II4 | ✅ Implemented | `isOutdated` = flag verbatim for formulae, `snapshotOutdated && !isSelfUpdating` for casks; `outdatedCount = outdatedIDs.count`, and `outdatedIDs` is built from `isOutdated`, so badge and set cannot diverge. |
| II5 | ✅ Implemented | `hasNewerVersion = isSelfUpdating && installedVersion != catalogVersion`; not referenced by `outdatedIDs` or `outdatedCount`. |
| II6 | ✅ Implemented | `isPinned`/`pinnedVersion` read from both wire namespaces; `installedAt` from `primaryKeg.installedAt` via `Date(timeIntervalSince1970:)`. No `brew list --pinned` anywhere. |
| II7 | ✅ Implemented | Join on the existing `PackageID(kind:name:)`; `Package.swift` declares `Catalog` with no dependencies at all, and `BrewClient` depends on both one-directionally. |
| II8 | ✅ Implemented | `InstalledBrowse.rows(mode:query:catalogResults:catalogLookup:)`; `SearchFilters` still exposes exactly `["kinds", "excludeDeprecated", "excludeDisabled"]`. |
| II9 | ✅ Implemented | `refresh(for: BrewDetectionState)` maps all four detection states; `clear(to:)` spawns nothing and sets `.brewAbsent(InstalledAbsence)`. |
| II10 | ✅ Implemented | `InstalledRefreshCoordinator` — `isMutating` suppression, extending quiet window via `repeat { windowExtended = false; sleep } while windowExtended`, and store-level request-keyed single flight. |
| II11 | ✅ Implemented | `LoopOwner.start(_:_:)` guards on `loops[id] == nil` and holds unstructured `Task`s; `cellarApp` holds it as `@State`. |
| BD1–BD3 | ✅ Implemented (no-op) | `BrewPrefix` already declared `case appleSilicon` / `case intelCarryOver` on `main`. The S1 nit was spec-side only; the delta realigns the spec text. Verified by reading `Sources/BrewProcess/BrewLocation.swift`. |
| BD4 | ✅ Implemented | `BrewDetectionStore.InFlightEvaluation` carries `request: URL?`; the join is gated on `current.request == path`; publication is gated on `token > publishedToken`. |

#### Concurrency invariants — read, not trusted

All four were confirmed by reading the source, and each is load-bearing (the apply phase's mutation
runs are consistent with what the code shows):

| Invariant | Location | Evidence |
|---|---|---|
| Detection request key | `BrewDetectionStore.swift:73` | `if let current = inFlight, current.request == path` — a differing `configuredPath` cannot join. |
| Detection publication ordinal | `BrewDetectionStore.swift:93–94` | `guard token > publishedToken` — this is what makes the spec's "the published state MUST correspond to the request most recently asked for" true. `changedPathIsNotAnsweredByTheEvaluationInFlight` releases `A` **last** on purpose, so the guard is the only thing keeping `A`'s answer out. |
| Store request key | `InstalledStore.swift:126` | `if let current = inFlight, current.request == request` where `request = installation.executableURL`. |
| Store ordinal guard | `InstalledStore.swift:171–172` | `guard token > installedSequence` before the single main-actor assignment. |
| Coordinator mutation suppression | `InstalledChangeObserving.swift:153` | `if mutations?.isMutating == true { return }`. |
| Coordinator extending window | `InstalledChangeObserving.swift:157–160, 169–172` | `windowExtended = true` on a signal inside the window; `repeat { windowExtended = false; sleep } while windowExtended` — extension, not throttling. `aSignalInsideTheWindowExtendsIt` proves the difference by asserting **no** refresh after the first window closes. |
| `defer { vacate(token) }` inside the task body | both stores | Confirmed in both — the slot is empty before any joiner resumes. |

#### Scope guards re-checked independently

| Guard | Result |
|---|---|
| `git diff --exit-code main -- openspec/specs/package-search/spec.md` | ✅ exit 0 — byte-identical |
| `Catalog` target dependencies in `Package.swift` | ✅ none declared; `BrewProcess` unreachable |
| `CatalogSnapshot.currentSchemaVersion` | ✅ still `1` |
| `@unchecked Sendable` in `Sources/BrewClient/` | ✅ zero — the three `@unchecked` tokens are comments asserting its absence |
| Diff composition (apply claim: production ~2,120 / tests ~2,531 / fixtures 265) | ✅ recomputed from `git diff --stat main`: BrewClient 1,451 + BrewProcess 43 + Package.swift 16 + app UI 569 + pbxproj 43 = **2,122**; tests **2,531**; fixtures **265**; total **4,918**. The claim is honest. |

### Coherence (Design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| D1 One `BrewClient` target, one-directional edge | ✅ Yes | Asserted by `PackageGraphTests`, including a negative control proving the walk finds real edges. |
| D2 Thin adapter over a pure `payload(from:exit:)` | ✅ Yes | `BrewInfoPayloadSource.payload` is ~18 lines of glue; all semantics in `InstalledPayload`. |
| D3 Slim projection, asymmetric decode, kegs as list | ⚠️ Refined | Two wire types instead of two `init(from:)` (deviation 4). Same asymmetry, expressed in the type system. |
| D4 Every badge derived from one payload | ✅ Yes | Cask `isOnRequest` is derived through a synthesised keg rather than a literal `true`, which is the same value and keeps one derivation path. |
| D5 Inventory is authority, catalog decorates | ✅ Yes | `entry(installed:catalogLookup:)` is O(1) per rendered row; `anEmptyCatalogCostsDecorationNotRows` proves a missing catalog costs metadata, never a row. |
| D6 Request-keyed single flight, ordinal adoption | ✅ Yes | Both stores. The detection scope delta landed as designed. |
| D7 Browse composition above the index | ⚠️ Refined | The **rule** moved down into `BrewClient` (`InstalledBrowse`) so it is covered by `swift test`; only the picker stays in the app target. Recorded in the tasks legend. Strictly better for testability. |
| D8 FSEvents confinement invariant | ✅ Yes | Header comment carries the five-point invariant; `SignalBox` is `final class Sendable` with one `let continuation`; callback is file-scope and one statement. |
| D9 Coordinator owns cadence | ✅ Yes | 2 s quiet window, injected `any Clock<Duration>`, suppression, always-on baseline. |
| D10 Idempotent `LoopOwner` | ✅ Yes | Per-id guard; unstructured tasks; `@State` in `cellarApp`. |
| D11 `BrewPrefix` rename | ⚠️ No-op | D11's arrow (`appleSilicon → native`) is written backwards. The code already used the target vocabulary; the nit was spec-side. Verified, not assumed. |
| D12 Everything through fakes; one adapter untested | ✅ Yes | See the FSEvents section below. |

#### FSEvents adapter — untested by design, compensating controls verified

| Control | Status |
|---|---|
| (i) Thin adapter, no branch beyond "yield" | ✅ `installedChangeCallback` is a file-scope `@convention(c)` function with one guard and one `yield()`; it reads no paths, flags or ids. |
| (ii) Confinement-invariant header comment | ✅ Present, five numbered points, matching the code (retain before `Start`, `Stop → Invalidate → Release` under `Mutex`, private dispatch queue, deferred creation flags, zero `@unchecked Sendable`). |
| (iii) Coordinator baseline is always on | ✅ `refresh(using:)` / `refresh(for:)` are driven from launch and `didBecomeActiveNotification`; `baselineWorksWithoutAnyObserver` proves correctness with **no observer at all**. |
| (iv) Manual 10.1 evidence | ✅ Recorded in `tasks.md` and Engram #7088: exactly one debounced refresh per external mutation on both the install and uninstall legs, plus the launch baseline, plus a UI screenshot. |
| (v) Cadence fully faked | ✅ `FakeInstalledChangeObserver` + `TestClock` cover debounce, extension, suppression, terminal settle, and the no-brew path. |

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | Full "TDD Cycle Evidence" table in apply-progress #7086 |
| All tasks have tests | ✅ | Every GREEN task maps to a test file that exists; the three NO-OP/approval rows are justified in writing and independently re-verified here |
| RED confirmed (test files exist) | ✅ | 11 new suites + 2 modified suites, all present on disk |
| GREEN confirmed (tests pass) | ✅ | 345/345 pass on re-run by this phase |
| Triangulation adequate | ✅ | Every multi-scenario requirement has ≥2 distinct cases with **different** expected values; `PackageGraphTests` even carries a negative control |
| Safety Net for modified files | ✅ | `BrewDetectionStoreTests` 9/9 before the Phase 2 change, `CatalogTests/FilterTests` and `DetectionTests` unchanged and green |

**TDD Compliance**: 6/6 checks passed.

Mutation verification (apply phase, four invariants flipped and restored) is consistent with the
source read here: each guard is the only thing standing between the suite and a failure, and the
corresponding tests are written so the guard is exercised (notably `A` released last in the
detection test, and "no refresh after the first window" in the extension test).

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit | 345 | 47 suites | Swift Testing |
| Integration (app build/test) | 1 | `cellarTests` | xcodebuild |
| E2E | 0 | — | not installed (UI tests skipped by contract) |
| **Total** | **346** | | |

App-target SwiftUI (Phase 9) is build-verified only, per the design's explicit strategy.

### Changed File Coverage

Coverage analysis skipped — no coverage tool configured for `Packages/CellarCore`.

### Assertion Quality

Every new and modified test file was scanned. No tautologies, no assertion that fails to call
production code, no smoke-test-only case, no mock-heavy file (there are no mocking frameworks at all
— only hand-written fakes with counters).

| File | Line | Assertion | Issue | Severity |
|------|------|-----------|-------|----------|
| `InstalledRefreshTests.swift` | 254 | `installations.allSatisfy { … }` | No companion count assertion pinning the collection non-empty. It *is* non-empty here (the preceding `refresh` is awaited), so this is not a ghost loop — but the test would still pass if the collection emptied. | SUGGESTION |

**Assertion quality**: 0 CRITICAL, 0 WARNING. The two bare `!= nil` checks in
`InstalledDecodeTests` (lines 93–94) sit alongside a `== nil` negative and a `count == 10` value
assertion in the same test, so they are not type-only assertions.

### Quality Metrics

**Linter**: ⚠️ `swiftlint lint` — 33 findings outside `.build/`, of which 4 errors, all four
pre-existing `type_name` violations on `cellarApp`, `cellarTests`, `cellarUITests`,
`cellarUITestsLaunchTests`. 10 findings sit in files this change created; 8 of those are of kinds
already present on `main` (`optional_data_string_conversion`, `identifier_name`). **Two are new
rule kinds** — see WARNING 1.

**Type Checker**: ✅ No errors — both `swift build` (via `swift test`) and `xcodebuild` compile
clean under Swift 6 language mode with the package's `.swiftLanguageMode(.v6)` on every target.

### Apply Deviations — validated one by one

Each of the 11 recorded deviations was checked against spec text, not absorbed.

| # | Deviation | Verdict |
|---|---|---|
| 1 | D11 rename is a no-op | ✅ Real and benign. `BrewLocation.swift` declares `case appleSilicon` / `case intelCarryOver`; no `native`/`rosettaCarryOver` case exists anywhere. The spec delta adopts the code's names, so BD1–BD3 are documentation-only exactly as the delta header claims. No observable behaviour change. |
| 2 | `refresh(for: BrewDetectionState)` overload added | ✅ Required by spec, not beyond it. II9 sc2 demands the rejection reason be available as read-only guidance; `refresh(using: BrewInstallation?)` cannot carry it. `InstalledAbsence` names exactly the three absent states detection can report. Additive. |
| 3 | `changeDetected()` made public | ✅ Benign. It calls the same private `changeSignalled()` as the observed path, so quiet window and suppression are identical by construction, and two dedicated tests prove it rather than assert it. Necessary because the watcher cannot exist before detection resolves a prefix. |
| 4 | Two wire types, not two `init(from:)` | ✅ Benign. II2 requires the asymmetry to decode; the type system now enforces it. Less code, more compiler help. |
| 5 | Ordering + membership sets moved into `InstalledInventory.init` | ✅ Improvement. Makes sort order and `installedIDs`/`outdatedIDs` invariants of the value rather than of one producer; a hand-built inventory now orders like a decoded one (proved by `A decoded inventory carries the same ordering guarantee`). |
| 6 | `InstalledPresentation.swift` added outside design "File Changes" | ✅ Benign, and recorded in task 10.3. Wording only, moved down so `FAST` covers it; matches the existing `CatalogPresentation` convention. |
| 7 | `PackageRow` takes a `PackageEntry` | ✅ Required by II7 sc2 — an installed package with no catalog record must render, not vanish. |
| 8 | `LossyArray` duplicated into `BrewClient` | ✅ Benign trade. `Catalog`'s copy is internal by design; the alternative widens a public API for ~30 lines. Both copies have identical semantics. |
| 9 | Out-of-order adoption tested across two installations | ✅ Correct and structurally necessary. With request-keyed single flight, two same-request refreshes coalesce by construction, so simultaneous in-flight work can only exist across differing requests. Documented in the test itself. |
| 10 | `TestPoll.until` takes a `@Sendable` autoclosure | ✅ Test-only, required by `@MainActor` suites in this target. |
| 11 | FSEvents pointers stored as `UInt` bit patterns | ✅ Benign, with a note. It keeps "zero `@unchecked Sendable`" literally true and the pointers are non-owning handles reconstructed in exactly one place (`stop()`), inside the `Mutex` critical section, with `Unmanaged` retain/release explicitly paired. This does launder a non-`Sendable` pointer through a `Sendable` struct, but the confinement invariant in the header covers it and the reconstruction is three lines from its use. |

**None of the 11 changes observable behaviour beyond the spec.** Two (2 and 7) exist *because* the
spec demands behaviour the design under-specified; two (5 and 7-adjacent D7 refinement) strengthen
testability; the rest are implementation-shape choices.

### Issues Found

**CRITICAL**: None.

**WARNING**:

1. **The swiftlint claim in task 10.2 / apply-progress is inaccurate.** Both artifacts state
   "No new rule tripped" and characterise the findings as "10 `trailing_comma`/`large_tuple`/
   `identifier_name` warnings and the one baseline `type_name` error". Re-running `swiftlint lint`
   shows two rule kinds that fire **nowhere else in the repository**, both in new `BrewClient`
   production files:
   - `Sources/BrewClient/InstalledWire.swift:43` — `nesting` (`KegWire` nested inside
     `FormulaInstalledWire`);
   - `Sources/BrewClient/FSEventsInstalledObserver.swift:159` — `function_parameter_count`
     (6 parameters; the signature is fixed by the FSEvents C API and cannot be reduced).
   Neither is a defect and neither blocks. The finding is that the gate record misdescribes them.
   Fix the record (or silence the two rules deliberately) before archive so the archived evidence
   is true.

2. **The UI half of II8 sc4 and II11 is build-verified, not test-verified.** `InstalledBrowse
   .isFilterEnabled` and `LoopOwner` are unit-tested, but the bindings that consume them —
   `CatalogFilterBar`'s `.disabled(!isInstalledFilterEnabled)` and `cellarApp`'s
   `loops.start("catalog"|"installed"|"installed-watcher")` — are proven only by `** TEST
   SUCCEEDED **` plus the manual 10.1 screenshot. This is the design's declared Phase 9 strategy
   and is acceptable, but it is a real coverage boundary: a future edit could unbind the picker or
   drop a `loops.start` call and every automated gate would stay green.

3. **The `brew upgrade` leg of task 10.1 was deliberately not run** (consent scope — upgrading 12
   formulae including `node@22`). Coalescing of a multi-write mutation into one refresh is
   evidenced by the install leg (12 files written over ~1 s → exactly one refresh) and fully
   covered automatically by `aSignalInsideTheWindowExtendsIt` and
   `aBurstCostsOneReSnapshot`. Residual risk is narrow: no live evidence that a *multi-minute*
   write stream coalesces through the real FSEvents path. Documented, consented, non-blocking.

**SUGGESTION**:

1. Two `DetectionTests` display names still use the retired spec vocabulary — "The **native**
   prefix wins when both prefixes exist" and "Only the **Intel** prefix present…" — while the spec
   now standardises on `appleSilicon` / `intelCarryOver`. The assertions are already correct; only
   the prose lags. Since BD1–BD3 were precisely a vocabulary-alignment fold-in, closing this makes
   the alignment complete.
2. `InstalledRefreshTests > baselineRecordsTheInstallation` should pin
   `harness.source.installations.count == 2` alongside its `allSatisfy`.
3. `TestClock` is now a **third** copy. M2-0 D5's `CellarTestSupport` extraction is still deferred
   and the debt grew by one copy in this change. Worth scheduling before M2-2 adds a fourth.
4. The worktree carries two untracked strays: `default.profraw` and
   `openspec/changes/m2-mutations-installed/`. Neither is in any commit; exclude both (gitignore
   for the first) before opening the PR.
5. The review-budget overrun (4,918 vs 2,800) was ruled accepted by the user and the attempt ledger
   was reset with that decision, so it is not an open blocker. The composition claim is verified
   honest: 43% production, 51% tests, 5% fixtures. Worth carrying forward as a forecasting
   correction — strict TDD with per-scenario REDs plus mutation verification cost ~2.8× the test
   estimate, not ~1×.

### Verdict

**PASS WITH WARNINGS**

Every one of the 15 requirements and all 50 scenarios has a named covering test that passed at
runtime in this phase's own re-run; both gates are green; every scope guard, the target graph, the
four concurrency invariants and all 11 apply deviations were verified by reading source rather than
by trusting the report. The three warnings are an inaccurate lint record in the gate evidence, a
declared and design-sanctioned UI coverage boundary, and one consented gap in manual evidence.
None blocks archive; warning 1 should be corrected in `tasks.md` first so the archived gate record
is true.
