# Apply Progress: M3 Cleanup Operations

## Batch

- Change: `m3-cleanup`
- Completed work units: `U0-runtime-gate`, `U1-typed-process-boundary`, `U2-preview-evidence`, `U3-shared-mutation-spine`, `U4-persistence-presentation`, `U5-app-composition`, `U6-verify-freeze-preparation`
- Current work unit: `U6-unmanaged-delivery-closure` (complete)
- Mode: Strict TDD
- Artifact store: hybrid
- Delivery: single PR with maintainer-approved `size:exception`
- RDD: disabled by explicit maintainer decision at `clone_local`; ordinary-policy delivery applies
- Delivery authority: unmanaged by candidate choice, not approved; `reviewGate`, receipt, reviewer, lineage, and approval are absent
- Native attempt token: `sha256:8aaefb0ba15d7fd5ae70d183c7acb2e4ca5267e4813e3722368f8b48a831dfbf`
- Native attempts used: 1 of 2
- U1 native attempt token: `sha256:e4ed2e8fd6174839a1ac06624ac997a06bf2ab9befd03e9fbd4d81a9ca982e1f`
- U1 settlement: owned by the orchestrator; no settle/reset/finish action was called
- U2 native attempt token: `sha256:18ef08b71476484e6604a15494c0522be316b3de51db36c17bf9d2a000290c9a`
- U2 settlement: owned by the orchestrator; no settle/reset/finish action was called
- U3 native attempt token: `sha256:9c11fff29def987b767356f88d35e5d6d7802d5a6788e349fc7f67fdb49a8fd5`
- U3 native attempts allowed: 2; settlement remains orchestrator-owned and no settle/reset/finish action was called
- U4 native attempt token: `sha256:525b0ca6f7c0486c95e9106fea7660c4424a9b1006e02aad4afce8065e69c658`
- U4 native attempts allowed: 2; settlement remains orchestrator-owned and no settle/reset/finish action was called
- U5 native attempt token: `sha256:e2f7d71baec1ab6442ce7d2aea1809a8e4d479433ca3e9cb82cc0e12ec8edd2d`
- U5 native attempts allowed: 2; settlement remains orchestrator-owned and no settle/reset/finish action was called
- U6 native attempt token: `sha256:52acd6d856fa8afc6f28d99f6b160e5b969892926c54788c72ca6aa5c0ebe5c5`
- U6 UI attempts used: 2 of 2; both were blocked by the macOS test host reporting the app as `Running Background`
- U6 settlement remains orchestrator-owned; no settle/reset/finish, review, freeze, validation, or receipt action was called
- U6 activation-retry token: `sha256:fea234ff951b7c92a759fdeea48b905c53a5794e6d9fcae372854d577e0f484c`
- U6 activation retry: focused UI 18/18 passed; exact primary passed 2 app tests plus 18/18 UI/launch tests
- U6 retry settlement remains orchestrator-owned; no settle/reset/finish, review, freeze, validation, lineage, or receipt action was called
- U6 unmanaged-closure token: `sha256:009d88dfd8b337f3e0a4095d6f2a240187ffaf787cce5fba5dbe8692b365055a`
- U6 closure settlement remains orchestrator-owned; no settle/reset/finish or review operation was called

## Completed Tasks

- [x] 0.1 RED list Homebrew assertions; prove `/opt/homebrew` and `/usr/local` destructive probes are denied.
- [x] 0.2 GREEN probe only a sentinel temporary prefix; capture argv/environment/output/contention.
- [x] 0.3 REFACTOR store byte-exact fixtures at `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Cleanup/`.
- [x] 1.1 RED add cleanup environment/command tests for CO1, CO5, and hostile targets.
- [x] 1.2 GREEN add typed command-local overrides and cleanup scope/command models.
- [x] 1.3 REFACTOR prove exact argv, local overrides, guidance, no shell, and zero hostile-target spawn.
- [x] 2.1 RED add parser/store tests for CO2/CO3 provenance, overflow, supersession, and cancellation.
- [x] 2.2 GREEN add tolerant parser, raw preview source, generation store, and canonical SHA-256 fingerprints.
- [x] 2.3 REFACTOR prove typed authorization equality and complete same-root currently-on-disk allocation.
- [x] 3.1 RED add cleanup authorization/operation tests for CO4, CO6, and every modeled terminal.
- [x] 3.2 GREEN add typed cleanup disclosure, queue-front authorization, shared FIFO execution, history, and scoped invalidation.
- [x] 3.3 REFACTOR prove launch plus declared-domain exactly-once/zero invariants.
- [x] 4.1 RED add cleanup history presentation tests for IH1/IH2 verbs, subjects, labels, search, and fallback.
- [x] 4.2 GREEN add cleanup action labels, operation-scope subjects, and label-aware persistence search without changing Schema V1 or replayability.
- [x] 4.3 REFACTOR centralize cleanup presentation vocabulary and prove temporary-store round-trip and rollback readability.
- [x] 5.1 RED add six CO7 XCUITests for preview-first scopes, all preview states, typed confirmations, denial refresh, and terminal refresh.
- [x] 5.2 GREEN compose the app-owned cleanup store/source, deterministic fixtures, exact disclosure, and stable identifiers.
- [x] 5.3 REFACTOR preserve direct package disclosure rows, thin dependency injection, and copyable command/provenance evidence.

All 21 tasks are complete. Task 6.3 closed under the explicit maintainer-selected
clone-local RDD-disabled ordinary policy without review, receipt, approval,
lineage, or candidate freeze. Independent `sdd-verify` remains required.

## Safety Boundary

The bounded harness canonicalized the candidate prefix before every Homebrew
invocation. It denied exact canonical roots `/opt/homebrew` and `/usr/local`,
required `.cellar-m3-cleanup-sentinel`, and required the copied `brew --prefix`
to equal the disposable prefix. The developer Homebrew executable and source
were read/copied only; no cleanup, autoremove, repository, installation, or
package-state mutation targeted either developer prefix.

Disposable prefix:

```text
/var/folders/v7/6grrq9ws0r373mpmxjjfx9fh0000gn/T/opencode/m3-cleanup-u0-probe/cellar-m3-cleanup-sentinel-prefix
```

## TDD Cycle Evidence

| Task | Test File / Harness | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 0.1 | Bounded zsh guard | Runtime integration | `swift test --package-path Packages/CellarCore`: 775 tests / 113 suites passed; 1 known issue | Assertions ran first; forbidden roots were denied and the missing sentinel captures produced expected exit 1 | 2/2 forbidden roots denied; spawn count 0 | `/opt/homebrew` and `/usr/local` both exercised | One canonical guard reused for every safe invocation |
| 0.2 | Sentinel-prefix Homebrew harness | Runtime integration | Same baseline | Shared RED ended with `RED sentinel-prefix captures are absent` | Harness exit 0; four scope probes plus two contention controls passed | Empty global/autoremove, non-empty Full preview/mutation, held/released lock paths | Environment and argv split into a byte-exact manifest |
| 0.3 | `cmp` fixture integrity harness | Fixture integration | N/A — new fixture files | Shared RED established that captures/fixtures were absent before the runtime probe | 14 captures existed after the safe probe | 5 non-empty and 9 intentional zero-byte files compared | `cmp`: 14/14 source and stored fixtures byte-identical; BrewClient tests remained green |
| 1.1 | `CleanupEnvironmentTests.swift`, `CleanupCommandTests.swift` | Unit + process seam | 530 tests / 78 suites passed; 1 known issue | Focused build failed on missing `commandOverrides`, `CommandOverride`, and `CleanupScope` APIs | 9 tests / 2 suites passed | 5 scope cases, 4 hostile names, override-present/absent, direct/authorized paths | Focused rerun stayed 9/2 green |
| 1.2 | Same two files | Unit + process seam | Same baseline | Task 1.1 RED established the missing production contract first | 9 tests / 2 suites passed after preserving original overload symbols | Formula/cask identity plus global/full/autoremove and authorized FIFO | Added a tested authorized-runner overload while retaining the original symbol |
| 1.3 | Same two files plus impacted BrewProcess/BrewClient suites | Unit + process seam | Same baseline | First GREEN link exposed replacement-signature incompatibility; triangulation RED rejected missing authorized overrides | Additive overloads restored both paths; focused 9/2 passed | Existing structural command-family and FIFO/read tests joined the new matrix | 539 tests / 80 suites passed; 1 pre-existing known issue |
| 2.1 | `CleanupParserTests.swift`, `CleanupStoreTests.swift` | Unit + raw process seam | `Cleanup` baseline: 9 tests / 2 suites passed | Focused compile exited 1 on missing request/result/evidence/parser/source/store APIs | 13 tests / 2 suites passed after the minimum implementation | 14 byte-exact fixtures; content/empty/partial/error/cancelled/stale; late/current generations | Final focused parser/store rerun: 14 tests / 2 suites passed |
| 2.2 | Same files | Unit + raw process seam | Same baseline | Task 2.1 established the missing contract before production files existed | Raw source, tolerant parser, typed store, and v1 SHA-256 fingerprints passed | Footer/no-footer, malformed/overflow, exact/mismatched orphans, absent/invalid brew, source cancellation | Byte parser and canonical encoder were kept pure; source/store stay isolated |
| 2.3 | Same files | Unit + integration join | Same baseline | Equality/allocation assertions existed in the original RED | Complete same-root formula allocation = 30 bytes; incomplete/wrong-root = unknown | Equality ignores request identity but includes typed facts/unknown bytes; fingerprint changes diagnostically | Full `Cleanup` result: 23 tests / 4 suites passed; impacted regression 553/82 |
| 3.1 | `CleanupAuthorizationTests.swift`, `CleanupOperationTests.swift` | Unit + process/gate integration seams | 18 tests / 5 affected suites passed | Focused compile exited 1 on missing `CleanupAuthorizationUpdate`, `requestCleanup`, `confirmCleanup`, and cleanup disclosure APIs | 7 tests / 2 suites passed after minimum spine implementation | Full/Autoremove disclosure; unchanged FIFO; changed/empty/failed/cancelled/unavailable denials; five scopes and ten modeled terminals | Final focused rerun: 7 tests / 2 suites passed |
| 3.2 | Same files plus `OperationCenterCleanup.swift` | FIFO/process/history/gate integration | Same baseline | Task 3.1 established the missing production contract before any U3 production edit | Exact typed request/evidence equality, one authorized spawn, typed denial updates, local environment, history, and scoped receipts passed | Formula/cask/global/Full/autoremove, exact request replay, five denial modes, null/package subjects, all outcome cases | Shared `OperationCenter.finish` remained the only terminal/history/invalidation funnel |
| 3.3 | Same files plus impacted BrewProcess/BrewClient suites | Characterization + integration | Same baseline | Existing finish-funnel safety net and RED terminal matrix preceded edits | Every modeled outcome paid one history and installed/disk refresh; services/taps remained zero | 10 outcomes, five scope area sets, unchanged/changed/unavailable queue-front cases | Cleanup 30/6 and impacted 560/84 passed with 1 pre-existing known issue |
| 4.1 | `CleanupHistoryPresentationTests.swift` | Persistence unit + SwiftData integration | 23 tests / 2 affected suites passed in isolated safety-net runs | Authoritative compile exited 1 on missing `HistoryRecord.actionLabel` and `Subject.operationScope` | 3 tests / 1 suite passed after minimum presentation/search implementation | Four cleanup scopes, eight search queries, and null/package fallback rows | Final focused rerun stayed 3/1 green |
| 4.2 | Same file plus `HistoryPresentation.swift` and `HistoryStore.swift` | Presentation + SwiftData query integration | Same baseline | Task 4.1 established labels/scope subjects before production edits | Exact labels, semantic null subjects, package identity, and label-aware predicates passed | Label, verb, cleanup/full/autoremove, package-name, and argv searches | Cleanup vocabulary centralized in one internal enum |
| 4.3 | Same file with temporary on-disk Schema V1 store | Persistence round-trip + rollback characterization | Same baseline | Original RED included round-trip/fallback assertions | Six rows survived close/reopen; unknown null/package verbs stayed readable and copy-only | Added named-package fallback beside null fallback after GREEN | 3/1 focused and 26/3 impacted suites passed after refactor |
| 5.1 | `cellarUITests/cellarUITests.swift` | macOS XCUITest | Existing UI baseline passed before U5 production edits | Six selected CO7 tests exited 65 with 6 expected failures in 43.655s because cleanup identifiers and flows were absent | Same six tests passed after minimum app composition | Global/package/Full/autoremove, content/empty/unknown/partial/error/cancelled/unavailable/stale, exact confirmation, denial refresh, terminal refresh | Final selected rerun: 6 tests / 0 failures in 70.559s |
| 5.2 | Same file plus cleanup app composition files | SwiftUI + app integration | Same baseline | Task 5.1 established all missing UI behavior first | App-owned store/source, preview-first actions, typed disclosure, fixtures, and identifiers passed | Process-free fixture matrix plus queue-front publish/adoption and post-terminal disk invalidation | Exact primary `xcodebuild test` passed 2 app unit tests and 18 UI/launch tests |
| 5.3 | Same files plus existing package-row characterization | UI regression + accessibility | Same baseline | Exact primary first exposed the nested package `DisclosureGroup` regression: 1 failure in 18 UI tests | Direct package rows restored the accessible disclosure triangle; focused characterization passed 1/1 in 4.607s | Six CO7 tests, package expansion, app units, complete UI suite, and launch appearances | Final primary test exited 0; 18 UI/launch tests in 160.261s and 2 app unit tests passed |
| 6.1 | Complete package/app verification commands | Regression + runtime | `CORE`: 808 tests / 120 suites passed in 15.596s with 1 known issue | U0–U5 RED evidence remains cumulative; U6 adds no production behavior | Initial focused UI attempts were infrastructure-blocked; authorized retry focused UI passed 18/18 and exact primary passed 2 app + 18/18 UI/launch tests | Focused Cleanup 33/7, focused UI 18/18, exact primary 2+18, app build, fixtures, and safe U0 probes all pass | No source refactor occurred; final identity and `git diff --check` passed |
| 6.2 | Normalization, inventory, scope, budget, and rollback checks | Candidate hygiene | No source formatter or mutating normalizer is configured | N/A — verification-only task with no source edits | Source/test candidate remained byte-identical before and after both U6 attempts | 42 source/test paths, all mode `0644`; exclusions, exception, work-unit rollback boundaries, and single-PR rollback inspected | Complete; inventory is ready for parent-owned freeze, but no freeze/review/receipt was performed |
| 6.3 | Clone-local RDD-disabled delivery closure | Structural artifact evidence | Candidate identity and completed U6 verification were already green | N/A — policy closure only; no production behavior | No review was run and no receipt/approval was created | `reviewGate`, receipt, reviewer, lineage, and approval recorded absent; delivery recorded unmanaged, not approved | All tasks checked; independent `sdd-verify` remains required |

### Test Summary

- U0 new Swift tests: 0; U0 is runtime-only by the tasks forecast.
- Baseline: 775 tests in 113 suites passed after 15.547 seconds with 1 known issue.
- Focused rerun: 411 tests in 59 suites passed after 15.043 seconds with 1 known issue.
- Runtime assertions: 2 forbidden-prefix cases, 4 scope probes, 2 contention controls.
- Pure functions created: 0.
- U0 approval tests: None — no production refactor occurred in U0.
- U1 new tests: 9 tests in 2 suites, including 5 parameterized scope cases and 4 hostile-target cases.
- U1 focused result: 9 tests / 2 suites passed after 0.001 seconds.
- U1 impacted regression: 539 tests / 80 suites passed after 15.047 seconds with the same 1 known issue.
- U1 pure value types created: `CleanupScope`, `CleanupTargetRejection`, and `CleanupCommand`.
- U2 new Swift tests: 14 tests in 2 suites, including 14 parameterized U0 fixture cases.
- U2 focused result: 23 tests in 4 Cleanup suites passed after 0.006 seconds.
- U2 impacted regression: 553 tests in 82 suites passed after 15.053 seconds with the same 1 known issue.
- U2 pure functions/value seams: tolerant byte parser, canonical encoder, typed equality, and same-root allocation join.
- U3 new Swift tests: 7 test declarations in 2 suites, including five denial cases, five cleanup scopes, and all ten modeled terminal outcomes.
- U3 focused result: 7 tests / 2 suites passed after 0.007 seconds.
- U3 Cleanup result: 30 tests / 6 suites passed after 0.010 seconds.
- U3 impacted regression: 560 tests / 84 suites passed after 15.044 seconds with the same 1 known issue.
- U3 approval/characterization coverage: one all-terminal finish-funnel test plus the 18-test affected safety net.
- U3 pure/value seams: typed `CleanupEffect`, immutable `CleanupConfirmationDisclosure`, and `CleanupAuthorizationUpdate`; no second mutable center or queue.
- U4 new Swift tests: 3 declarations in 1 suite, covering four cleanup scopes, eight search queries, and null/package fallback paths.
- U4 focused result: 3 tests / 1 suite passed after 0.039 seconds.
- U4 impacted result: 26 tests / 3 suites passed after 0.198 seconds.
- U4 temporary runtime: six Schema V1 rows survived an on-disk close/reopen with exact empty-absence fields, package identity, argv, and copy-only controls.
- U4 pure/value seams: centralized cleanup action vocabulary and immutable label-match flags; no schema, migration, command reconstruction, or replay API.
- U5 new XCUITests: 6 declarations covering all CO7 states and flows.
- U5 focused result: 6 tests / 0 failures in 70.559 seconds after final refactor.
- U5 package-row regression: 1 test / 0 failures in 4.607 seconds after restoring direct disclosure rows.
- U5 exact primary result: 2 app unit tests and 18 UI/launch tests passed; UI/launch duration 160.261 seconds.
- U5 process/runtime boundary: deterministic in-app fixture source only; no Homebrew process or developer prefix was invoked.
- U6 package result: 808 tests / 120 suites passed in 15.596 seconds with the same 1 known issue.
- U6 focused Cleanup result: 33 tests / 7 suites passed in 0.040 seconds.
- U6 focused UI attempt 1: exit 65 after 1,123 seconds; 18 tests / 18 activation failures.
- U6 focused UI attempt 2: exit 65 after 1,123 seconds; 18 tests / 18 activation failures after explicitly terminating `cellar` first.
- U6 app build: exit 0 in 2 seconds; `** BUILD SUCCEEDED **`.
- U6 exact primary app test was not run because it would be a third UI attempt after the two-attempt ceiling was exhausted.
- U6 check-only SwiftLint: exit 2 in under 1 second. The repository has no SwiftLint configuration or baseline; output included generated `.build` files, existing violations, and candidate violations, so it is recorded as non-authoritative failed hygiene evidence rather than normalized.
- U6 fresh destructive safe probe was not run after the UI attempt ceiling blocked completion. Fixture integrity passed for 15 files, 12 streams, 5 pinned non-empty hashes, and 9 intentional empty streams; cumulative U0 sentinel-prefix runtime evidence remains unchanged.
- U6 authorized activation retry: bounded stale-process termination passed; the built app was opened and activated with `open` and AppleScript; System Events confirmed `cellar` was frontmost.
- U6 retry focused UI: exit 0; 18 tests / 0 failures in 162.107s test time and 171s wall time.
- U6 retry exact primary: exit 0; 2 app unit tests plus 18 UI/launch tests / 0 failures; UI test time 162.920s and 173s wall time.
- U6 post-test environment cleanup passed; final source/test identity and `git diff --check` remained unchanged/passing.

## Exact RED Command and Result

The RED harness defined the assertions before creating any disposable prefix or
capture. Its exact guard logic and invocation matrix were:

```zsh
STAGE="/var/folders/v7/6grrq9ws0r373mpmxjjfx9fh0000gn/T/opencode/m3-cleanup-u0-probe"
rm -rf "$STAGE"
integer spawn_count=0
guarded_probe() {
  local prefix="$1"; shift
  case "$prefix" in
    /opt/homebrew|/usr/local)
      print -r -- "DENIED destructive probe prefix=$prefix argv=$* reason=forbidden-developer-prefix"
      return 77 ;;
  esac
  [[ -f "$prefix/.cellar-m3-cleanup-sentinel" ]] || return 78
  (( spawn_count += 1 ))
}
for prefix in /opt/homebrew /usr/local; do
  guarded_probe "$prefix" cleanup --prune=all
  rc=$?
  [[ $rc -eq 77 ]] || exit 90
done
[[ $spawn_count -eq 0 ]] || exit 91
[[ -d "$STAGE/captures" ]] || exit 1
```

Exact outcome: exit 1 at the intended missing-captures RED gate after both
forbidden roots returned 77; output reported `PASS forbidden-prefix denial:
2/2 denied, spawned=0` and `RED sentinel-prefix captures are absent`.

## Exact GREEN Runtime Commands and Result

The copied Homebrew launcher reported the disposable prefix before every child
command. The harness then invoked these exact child commands (variables expand
to the disposable paths recorded in `probe-manifest.txt`):

```zsh
env -i HOME="$STAGE/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
  HOMEBREW_CACHE="$PREFIX/cache" HOMEBREW_LOGS="$PREFIX/logs" HOMEBREW_TEMP="$PREFIX/tmp" \
  HOMEBREW_NO_AUTOREMOVE=1 "$PREFIX/bin/brew" cleanup --dry-run
env -i HOME="$STAGE/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
  HOMEBREW_CACHE="$PREFIX/cache" HOMEBREW_LOGS="$PREFIX/logs" HOMEBREW_TEMP="$PREFIX/tmp" \
  HOMEBREW_NO_AUTOREMOVE=1 "$PREFIX/bin/brew" cleanup --dry-run --prune=all
env -i HOME="$STAGE/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
  HOMEBREW_CACHE="$PREFIX/cache" HOMEBREW_LOGS="$PREFIX/logs" HOMEBREW_TEMP="$PREFIX/tmp" \
  "$PREFIX/bin/brew" autoremove --dry-run
env -i HOME="$STAGE/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
  HOMEBREW_CACHE="$PREFIX/cache" HOMEBREW_LOGS="$PREFIX/logs" HOMEBREW_TEMP="$PREFIX/tmp" \
  HOMEBREW_NO_AUTOREMOVE=1 "$PREFIX/bin/brew" cleanup --prune=all
```

All four exited 0. Full preview reported two disposable cache rows and 22B;
Full mutation removed those same two files and reported 22B. Autoremove was
byte-empty. Global dry-run was byte-empty on stdout and emitted Homebrew API
acquisition diagnostics on stderr.

Contention used the exact lock holder below, followed by the same cleanup
mutation once while held and once after release:

```zsh
ruby -e 'file = File.open(ARGV[0], File::RDWR); file.flock(File::LOCK_EX); File.write(ARGV[1], "ready"); File.read(ARGV[2])' "$LOCK" "$READY" "$RELEASE"
```

Both cleanup controls exited 0. The held lock remained present; after release,
the next cleanup removed it. The harness final result was exit 0 with
`forbidden-targets-touched=0`, cleanup no-autoremove `1`, autoremove
no-autoremove absent, and both contention assertions true.

## U1 Exact RED Command and Result

Tests were added before any U1 production edit, then executed with:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Environment|Command)Tests'
```

The command exited 1 at compile time for the intended missing behavior. Exact
diagnostics included `extra argument 'commandOverrides' in call`, `reference to
member 'noAutoremove' cannot be resolved`, `CommandOverride is not a member type
of BrewEnvironment`, and `cannot find type 'CleanupScope' in scope`.

The first implementation run also exposed an incremental-link compatibility
failure: cached callers still referenced `BrewCommand.mutate([String])`. The
implementation was corrected, not the tests, by retaining the original overload
and adding a separate environment-aware overload.

Triangulation then added the authorized FIFO path first. Its RED command,
`swift test --package-path Packages/CellarCore --filter CleanupEnvironmentTests`,
exited 1 with `extra argument 'environmentOverrides' in call`; the production
overload was added only after that failure.

## U1 Exact GREEN and REFACTOR Results

The same focused command exited 0 after GREEN and again after REFACTOR:

```text
Test run with 9 tests in 2 suites passed after 0.001 seconds.
```

It proved five exact scope rows (global, formula package, cask package, Full,
autoremove), command-local override present/absent behavior, inherited
`PATH`/`HOME`, pinned normalization, four hostile-name rejections with typed
guidance, two exact Full `ProcessSpec` records plus one authorized FIFO spec,
direct brew execution with no shell/`-c`, and zero process records for rejected targets.

The impacted regression command was:

```text
swift test --package-path Packages/CellarCore --filter 'Brew(Process|Client)Tests'
```

It exited 0 with 539 tests in 80 suites passed after 15.047 seconds and one
pre-existing known issue. This retained existing FIFO, concurrent-read,
authorization-denial, cancellation, argument-composition, and structural
command-family coverage.

## U2 Exact RED Command and Result

After both U2 test files existed and before any U2 production file existed:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Parser|Store)Tests'
```

The command exited 1 at compile time for the intended missing behavior. Exact
diagnostics included `cannot find type 'CleanupPreviewResult' in scope`, `cannot
find type 'CleanupPreviewError' in scope`, `cannot find type
'CleanupPreviewSourcing' in scope`, `cannot find 'CleanupPreviewRequest' in
scope`, `cannot find 'CleanupParser' in scope`, and `cannot find 'CleanupStore'
in scope`. The tests were corrected once before this authoritative RED to remove
an unrelated private nested-type visibility diagnostic; no production code
existed during either run.

## U2 Exact GREEN, TRIANGULATE, and REFACTOR Results

The first complete GREEN for the two new suites was:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Parser|Store)Tests'
Test run with 13 tests in 2 suites passed after 0.004 seconds.
```

Triangulation added the store-level per-scope empty/partial distinction while
retaining the initial RED matrix for all 14 U0 fixtures, footer/no-footer,
overflow/malformed/unknown lines, exact/mismatched autoremove counts,
authorization equality, fingerprints, source cancellation, supersession, and
stale retention. After refactoring to the 900-line native limit:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Parser|Store)Tests'
Test run with 14 tests in 2 suites passed after 0.005 seconds.

swift test --package-path Packages/CellarCore --filter Cleanup
Test run with 23 tests in 4 suites passed after 0.006 seconds.

swift test --package-path Packages/CellarCore --filter 'Brew(Process|Client)Tests'
Test run with 553 tests in 82 suites passed after 15.053 seconds with 1 known issue.
```

The raw runtime seam recorded `cleanup --dry-run --prune=all` as a `.read`
specification, preserved stdout/stderr bytes, applied
`HOMEBREW_NO_AUTOREMOVE=1`, used the detected executable directly with no
shell, returned typed absence/invalid-path guidance with zero spawns, and sent
one cooperative interrupt on cancellation. Controlled source runs proved a
late generation cannot adopt over the current result.

## U3 Exact RED Command and Result

Both U3 test files were added before any U3 production edit. After correcting
test-only actor isolation and helper visibility while production remained
untouched, the authoritative RED was:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Authorization|Operation)Tests'
```

It exited 1 at compile time for the intended missing behavior. Exact diagnostics
included `cannot find type 'CleanupAuthorizationUpdate' in scope`, `value of
type 'OperationCenter' has no member 'requestCleanup'`, `value of type
'OperationCenter' has no member 'confirmCleanup'`, and `cannot find
'CleanupConfirmationDisclosure' in scope`. No U3 production code existed for
that run.

## U3 Exact GREEN, TRIANGULATE, and REFACTOR Results

The first complete GREEN was:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Authorization|Operation)Tests'
Test run with 7 tests in 2 suites passed after 0.006 seconds.
```

Triangulation added Autoremove orphan names/count/effects beside the Full warning
and total provenance assertions. The final focused and impacted results were:

```text
swift test --package-path Packages/CellarCore --filter 'Cleanup(Authorization|Operation)Tests'
Test run with 7 tests in 2 suites passed after 0.007 seconds.

swift test --package-path Packages/CellarCore --filter Cleanup
Test run with 30 tests in 6 suites passed after 0.010 seconds.

swift test --package-path Packages/CellarCore --filter 'Brew(Process|Client)Tests'
Test run with 560 tests in 84 suites passed after 15.044 seconds with 1 known issue.
```

The process/runtime seams proved authorization waited at the shared FIFO front,
replayed the identical `CleanupPreviewRequest`, allowed one equal-evidence
spawn, retained `HOMEBREW_NO_AUTOREMOVE=1`, and launched zero processes for
changed, empty-after-nonempty, failed, cancelled, or unavailable evidence.
Typed updates carried the refreshed result or the exact reviewed result marked
stale. Five scopes produced exact history subjects and disk-area receipts. Ten
modeled outcomes each paid one history entry plus one installed and one disk
terminal; services and taps remained zero, and catalog has no mutation domain.

## U4 Exact RED Command and Result

After `CleanupHistoryPresentationTests.swift` existed and before any U4
production edit, the authoritative RED was:

```text
swift test --package-path Packages/CellarCore --filter CleanupHistoryPresentationTests
```

It exited 1 at compile time with the intended diagnostics `value of type
'HistoryRecord' has no member 'actionLabel'` and `type 'HistoryRecord.Subject'
has no member 'operationScope'`. One test-only dynamic-comment type error was
removed before this authoritative RED; production remained untouched.

## U4 Exact GREEN, TRIANGULATE, and REFACTOR Results

```text
swift test --package-path Packages/CellarCore --filter CleanupHistoryPresentationTests
GREEN: Test run with 3 tests in 1 suite passed after 0.048 seconds.
TRIANGULATE: Test run with 3 tests in 1 suite passed after 0.039 seconds.
REFACTOR: Test run with 3 tests in 1 suite passed after 0.043 seconds.

swift test --package-path Packages/CellarCore --filter '(CleanupHistoryPresentation|HistorySubject|HistoryStore)Tests'
Test run with 26 tests in 3 suites passed after 0.198 seconds.
```

The focused runtime created a temporary on-disk Schema V1 store, recorded four
cleanup rows plus unknown null/package fallback rows, closed it, reopened it,
and read all six. Exact empty-string absence encoding, formula identity, verbs,
argv, labels, scope subjects, raw fallback, and copy-only controls survived.
No stored row became executable.

## U5 Exact RED Command and Result

After the six CO7 XCUITests existed and before any U5 production edit, the
authoritative RED command selected them individually:

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7PreviewFirstScopesAndStorageRows \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7StateMatrixIsDeterministicAndHonest \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7FullConfirmationDisclosesCommandProvenanceAndWarning \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7AutoremoveDisclosesExactOrphans \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7DenialRefreshRequiresReconfirmation \
  -only-testing:cellarUITests/cellarUITests/testCleanupCO7TerminalOutcomeRefreshesStorage
```

It exited 65 with 6 tests failed in 43.655 seconds. The failures were the
intended missing-behavior failures: cleanup preview/action/state/confirmation,
provenance, orphan, cancellation, denial-refresh, and terminal-refresh
identifiers and flows did not yet exist.

## U5 Exact GREEN, TRIANGULATE, and REFACTOR Results

The same six-selector command exited 0 after GREEN and remained green through
the first refactor. After the exact primary run exposed a package disclosure-row
regression, the existing characterization was run as a focused RED safety net:

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' \
  -only-testing:cellarUITests/cellarUITests/testCleanupRouteShowsStablePackageFirstOnDiskRows
Test Suite 'Selected tests' passed: 1 test / 0 failures in 4.607 seconds.
```

The final six-test REFACTOR rerun was:

```text
Test Suite 'Selected tests' passed: 6 tests / 0 failures in 70.559 seconds.
```

The exact primary app command then passed:

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
cellarTests: 2 tests passed.
cellarUITests.xctest: 18 tests / 0 failures in 160.261 seconds.
** TEST SUCCEEDED **
```

Earlier final app-unit, full-UI, and build commands also exited 0. All cleanup
fixture paths were in-process and deterministic; no Homebrew executable, shell,
developer prefix, or filesystem cleanup mutation was invoked.

## U0 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter BrewClientTests` → exit 0; 411 tests / 59 suites passed in 15.043s with 1 existing known issue. |
| Runtime harness command/scenario and exact result | Exact commands above → exit 0; forbidden targets touched 0; four scope probes exited 0; held/released contention checks true. |
| Fixture integrity | Explicit `cmp -s` loop over `captures/*` and stored `Cleanup/*` → exit 0; 14/14 files byte-identical. |
| Changed-line count | 233 authored additions+deletions: 70 fixture lines, 157 apply-progress lines, and 3 checkbox additions + 3 deletions. Generated fixture bytes remain included in the snapshot even though goldens are excluded from review-risk accounting. |
| Rollback boundary | Remove `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Cleanup/`, remove this file, and restore only task checkboxes 0.1–0.3 plus their Engram mirrors. No production behavior is involved. |

## U1 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter 'Cleanup(Environment\|Command)Tests'` → exit 0; 9 tests / 2 suites passed in 0.001s. |
| Runtime harness command/scenario and exact result | Same command, `ProcessSpec` seam scenario → exit 0; Full preview/mutation recorded exactly 2 specs and authorized FIFO recorded 1 spec with exact argv, brew executable, no shell/`-c`, and `HOMEBREW_NO_AUTOREMOVE=1`; hostile-target scenario recorded 0 specs/spawns. |
| Impacted regression | `swift test --package-path Packages/CellarCore --filter 'Brew(Process\|Client)Tests'` → exit 0; 539 tests / 80 suites passed in 15.047s with 1 pre-existing known issue. |
| Changed-line count | 464 authored implementation additions+deletions: 111 in tracked BrewProcess edits and 353 lines across four new BrewClient/test files. This is below U1's 600-line native-attempt limit. |
| Rollback boundary | Revert only `BrewCommand.swift`, `BrewEnvironment.swift`, and `BrewRunner.swift`; remove `CleanupModels.swift`, `CleanupCommand.swift`, `CleanupEnvironmentTests.swift`, and `CleanupCommandTests.swift`; restore only task checkboxes 1.1–1.3 and the U1 sections of both progress mirrors. U0 fixtures/evidence and all U2+ work remain intact. |

## U2 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter Cleanup` → exit 0; 23 tests / 4 suites passed in 0.006s. |
| Runtime harness command/scenario and exact result | Same command over recording/controllable `ProcessLaunching` seams → exit 0; exact `.read` argv/environment and raw bytes passed; absent/invalid brew recorded 0 spawns; cancellation delivered one interrupt; late generation was rejected. |
| Allocation/equality join | Parser/store suites → complete same-root formula allocation summed 12+18 = 30 currently-on-disk bytes; incomplete/wrong-root remained unknown; typed authorization equality and v1 SHA-256 diagnostics passed. |
| Impacted regression | `swift test --package-path Packages/CellarCore --filter 'Brew(Process\|Client)Tests'` → exit 0; 553 tests / 82 suites passed in 15.053s with 1 pre-existing known issue. |
| Changed-line count | Exactly 900 authored source/test lines across five new U2 files, equal to the native-attempt limit and below the maintainer-approved 2,000-line single-PR review budget. |
| Rollback boundary | Remove only `CleanupParser.swift`, `CleanupPreviewSource.swift`, `CleanupStore.swift`, `CleanupParserTests.swift`, and `CleanupStoreTests.swift`; restore only task checkboxes 2.1–2.3 and U2 sections of both progress mirrors. Preserve all U0/U1 work and every U3+ file. |

## U3 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter 'Cleanup(Authorization\|Operation)Tests'` → exit 0; 7 tests / 2 suites passed in 0.007s. |
| Runtime harness command/scenario and exact result | Same command over scripted preview, controllable process, FIFO, history, and gate seams → exit 0; exact request replay; unchanged evidence launched once; five denial modes launched 0; exact command-local environment survived; every modeled terminal settled. |
| History and refresh receipts | Five scopes recorded exact namespaced verbs/argv; only package cleanup retained identity. Ten modeled outcomes recorded once and emitted installed+disk once; exact disk areas matched scope; services/taps/catalog were zero. |
| Impacted regression | `swift test --package-path Packages/CellarCore --filter 'Brew(Process\|Client)Tests'` → exit 0; 560 tests / 84 suites passed in 15.044s with 1 pre-existing known issue. |
| Changed-line count | 603 authored source/test additions+deletions across six U3 files and three minimal existing-file edits, below the U3 900-line native-attempt limit and the maintainer-approved 2,000-line single-PR review budget. |
| Rollback boundary | Remove `OperationCenterCleanup.swift`, `CleanupAuthorizationTests.swift`, and `CleanupOperationTests.swift`; revert only U3 edits in `BrewMutating.swift`, `OperationCenter.swift`, and `OperationCenterBulk.swift`; restore task checkboxes 3.1–3.3 and U3 progress sections. Preserve all U0–U2 files/evidence and every U4+ file. |

## U4 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | `swift test --package-path Packages/CellarCore --filter CleanupHistoryPresentationTests` → exit 0; 3 tests / 1 suite passed in 0.039s after triangulation. |
| Runtime harness command/scenario and exact result | Same command, temporary on-disk `PersistenceContainer` scenario → exit 0; six Schema V1 rows survived close/reopen with exact null/package subjects, empty version fields, labels, argv, and copy-only controls. |
| Fallback/search proof | Eight case-insensitive label/verb/scope/package/argv queries passed; unknown null identity degraded to stored verb + no-package subject + raw argv, while unknown package identity retained its package subject. |
| Impacted regression | `swift test --package-path Packages/CellarCore --filter '(CleanupHistoryPresentation\|HistorySubject\|HistoryStore)Tests'` → exit 0; 26 tests / 3 suites passed in 0.198s. |
| Changed-line count | 238 authored source/test additions+deletions: 46 in `HistoryPresentation.swift`, 9 in `HistoryStore.swift`, and 183 in the new test file; below U4's 400-line native-attempt limit. |
| Rollback boundary | Remove `CleanupHistoryPresentationTests.swift`; revert only U4 edits in `HistoryPresentation.swift` and `HistoryStore.swift`; restore task checkboxes 4.1–4.3 and U4 sections of both progress mirrors. Preserve U0–U3 implementation/evidence and all U5+ work. |

## U5 Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | Six-selector CO7 `xcodebuild test` command above → exit 0; 6 tests / 0 failures in 70.559s after final refactor. |
| Runtime harness command/scenario and exact result | Same command over deterministic in-process app fixtures → exit 0; preview-first global/package/Full/autoremove, all modeled states, exact command/provenance/Full warning, orphan disclosure, cancellation, denial refresh, and post-terminal storage refresh passed. No external runtime boundary was crossed. |
| Regression and app proof | Package disclosure characterization → 1/1 passed in 4.607s. Exact primary `xcodebuild test` → exit 0; 2 app unit tests plus 18 UI/launch tests passed, with UI/launch duration 160.261s. Earlier `-only-testing:cellarTests`, `-only-testing:cellarUITests`, and `xcodebuild build` commands also exited 0. |
| Changed-line count | 673 authored implementation/test additions+deletions: 655 across six tracked app/UI-test files plus 18 lines for the narrow public `CleanupStore.adopt(_:)` integration. This stays inside the U5 native attempt and the maintainer-approved single-PR `size:exception`. |
| Rollback boundary | Revert only U5 edits in `MutationConfirmation.swift`, `AppTestFixtures.swift`, `CleanupView.swift`, `ContentView.swift`, `cellarApp.swift`, and `cellarUITests.swift`; remove only the public authorization-update `adopt(_:)` block from `CleanupStore.swift`; restore task checkboxes 5.1–5.3 and U5 sections of both progress mirrors. Preserve all U0–U4 implementation/evidence and every U6 artifact. |

## U6 Freeze-Preparation Evidence (Blocked)

### Normalization ordering and candidate identity

No source formatter is configured, `swift-format` is unavailable, no
`.swiftlint.yml` or mutating hook exists, and SwiftLint is installed only as an
unconfigured linter. No `swiftlint --fix`, synthetic formatting edit, or other
source-mutating normalizer was run. The source/test candidate was snapshotted
before functional verification and re-snapshotted after the final build:

```text
source/test paths: 42
path modes: 42 × 0644
source/test candidate SHA-256: 9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4
before checks: 9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4
after checks:  9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4
```

The identity covers every changed source, test, and cleanup fixture path while
excluding mutable SDD evidence artifacts. No source byte, path, or mode changed
after verification began. This is an inventory identity only, not an RDD freeze,
lineage, receipt, or review candidate.

### Commands and exact results

| Command | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | Exit 0; 808 tests / 120 suites passed in 15.596s with 1 known issue. |
| `swift test --package-path Packages/CellarCore --filter 'Cleanup'` | Exit 0; 33 tests / 7 suites passed in 0.040s. |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarUITests` | Attempt 1 exit 65 after 1,123s; 18/18 failed before behavior because app activation reported `Running Background`. |
| Same focused UI command after `pkill -x cellar` and confirmed no remaining process | Attempt 2 exit 65 after 1,123s; same 18/18 infrastructure activation failures. |
| Exact primary `xcodebuild test ...` | Not run: it would cross the two-attempt UI ceiling after the focused retries exhausted it. |
| `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | Exit 0 in 2s; build succeeded. |
| `git diff --check` | Exit 0. |
| Cleanup fixture SHA-256/integrity harness | Pass: 15 files, 12 streams, 5 pinned non-empty hashes, 9 intentional empty streams. |
| `swiftlint lint --strict --quiet` | Exit 2 in under 1s; non-authoritative because no repo config/baseline exists and generated `.build` plus pre-existing files were included. |

### Acceptance matrix

| ID | Evidence | U6 result |
|---|---|---|
| CO1 | Exact scope/argv/environment tests in focused Cleanup and full CORE | Pass |
| CO2 | Parser, raw-byte, provenance, uncertainty, and fixture tests | Pass |
| CO3 | State, supersession, cancellation, and stale-retention tests | Pass |
| CO4 | Queue-front equality/reconfirmation authorization tests | Pass |
| CO5 | Hostile target and unavailable-brew zero-spawn tests | Pass |
| CO6 | Shared FIFO, history, terminal, and scoped refresh tests | Pass |
| CO7 | Authorized retry focused UI and exact primary XCUITest commands | Pass: focused 18/18; exact primary 18/18 plus 2 app tests |
| IH1 | Exact verbs, subjects, argv, outcomes, and Schema V1 round trip | Pass |
| IH2 | Labels, search, fallback readability, and non-replayability | Pass |

### Scope, budget, and rollback

- Direct filesystem deletion scan: zero candidate matches. Mutations remain typed
  Homebrew commands.
- Queue/target: no new runner or queue type was added; the only candidate runner
  declaration is the existing `BrewRunner`. No `Package.swift` or
  `project.pbxproj` changed, so no second target was added.
- Persistence: no schema or migration file changed and candidate source contains
  no `VersionedSchema`, `SchemaMigrationPlan`, or `MigrationStage` addition.
- Localization/accessibility: no localization file/API change exists; accessibility
  edits are bounded to cleanup controls and confirmation identifiers/labels.
- Candidate source/test lines: 2,882 additions + 66 deletions = 2,948 changed.
  Cleanup fixture goldens account for 70 additions, leaving 2,878 authored
  source/test changes. The approved single-PR `size:exception` covers the 2,000
  line review budget overage; chain strategy remains not applicable.
- `git log --oneline -10` and the working tree show no U0–U6 work-unit commits;
  all M3 cleanup source/test changes remain uncommitted. The U0–U6 rollback
  boundaries are documented, but this U6 scope explicitly forbids creating
  commits, so commit-level boundary proof remains unavailable.
- SDD artifacts before this blocked-attempt update contained 946 additions.
  A pre-existing unrelated untracked `openspec/changes/m3-4/exploration.md`
  contains 215 additions and is explicitly outside the source/test candidate.
- U6 made no source/test edits. Its rollback is only this U6 progress section.
  The single-PR product rollback remains the whole M3 cleanup source/test
  candidate while preserving `disk-usage` and Schema V1.
- Tasks 6.1–6.3 are complete. Task 6.3 uses ordinary-policy unmanaged delivery
  because the maintainer explicitly disabled RDD for this clone; it does not
  claim review, receipt, approval, lineage, or a review gate.

### Explicitly authorized U6 activation-only retry

The retry began by confirming the same 42-path, all-`0644` source/test candidate
identity. It made no source, test, project, permission, security-policy, or
Homebrew-prefix change.

Activation recovery actions were bounded to the macOS process environment:

1. Enumerated stale `cellar`, test-runner, `xctest`, and `xcodebuild` processes.
2. Terminated stale `cellar` and `cellarUITests-Runner` processes; none remained.
3. Launched the existing DerivedData `cellar.app` with `open -n -a`.
4. Activated bundle `com.juancasanueva.cellar` with AppleScript and reopened it
   through Launch Services.
5. System Events returned `cellar` as the frontmost application.
6. Re-activated and reconfirmed `cellar` frontmost before exact-primary testing.
7. Terminated the app/test runner after testing; no matching process remained.

| Retry command/action | Exact result |
|---|---|
| Candidate identity before activation | 42 paths, 42 × `0644`, SHA-256 `9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4` |
| Stale-process termination | Exit 0; no matching app/test-runner remained |
| `open -n -a <DerivedData>/cellar.app` | Exit 0; `cellar` process started immediately |
| AppleScript activate + Launch Services reopen | Both exit 0; frontmost query exit 0 returned `cellar` |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarUITests` | Exit 0; 18 tests / 0 failures in 162.107s (162.119s suite), 171s wall; `** TEST SUCCEEDED **` |
| Pre-primary activation check | Frontmost query exit 0 returned `cellar` |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | Exit 0; 2 app tests plus 18 UI/launch tests / 0 failures; UI 162.920s (162.934s suite), 173s wall; `** TEST SUCCEEDED **` |
| Post-test environment cleanup | Exit 0; no matching app/test-runner remained |
| Candidate identity after exact primary | Same 42 paths, 42 × `0644`, same SHA-256 |
| Final `git diff --check` | Exit 0 |

The recurring `DebuggerVersionStore` “no debugger version” diagnostic remained
non-fatal in both passing retry commands. Prior unchanged-candidate CORE,
focused Cleanup, build, fixture-integrity, safe disposable-prefix, scope,
exception, and rollback evidence remains valid.

### U6 unmanaged delivery closure

- Policy decision: explicit maintainer selection to disable RDD for this clone.
- Mode source: `clone_local`; reported review mode: off.
- Candidate identity: `9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4`.
- Candidate inventory: 42 source/test paths, all mode `0644`.
- `reviewGate`: absent.
- Review lineage: absent.
- Reviewer: absent.
- Receipt: absent.
- Approval: absent.
- Delivery classification: unmanaged by candidate choice, not approved.
- Review/freeze operation executed: no.
- Long tests rerun for closure: no; completed unchanged-candidate U6 evidence was preserved.
- Required next step: independent `sdd-verify` under ordinary policy.
- Closure rollback: restore task 6.3 to unchecked and remove only this closure
  evidence; source/test bytes and prior verification remain untouched.

## U1 Files Changed

| File | Action | What changed |
|---|---|---|
| `Packages/CellarCore/Sources/BrewProcess/BrewCommand.swift` | Modified | Stores typed command-local environment overrides while retaining original overload symbols. |
| `Packages/CellarCore/Sources/BrewProcess/BrewEnvironment.swift` | Modified | Composes allow-listed overrides after inherited and pinned values. |
| `Packages/CellarCore/Sources/BrewProcess/BrewRunner.swift` | Modified | Applies overrides to direct commands and authorized FIFO mutation `ProcessSpec`s. |
| `Packages/CellarCore/Sources/BrewClient/CleanupModels.swift` | Added | Adds typed cleanup scopes and rejected-target guidance. |
| `Packages/CellarCore/Sources/BrewClient/CleanupCommand.swift` | Added | Adds exact preview/mutation argv, verbs, identities, overrides, and declared invalidation scopes. |
| `Packages/CellarCore/Tests/BrewProcessTests/CleanupEnvironmentTests.swift` | Added | Proves environment composition and runner plumbing. |
| `Packages/CellarCore/Tests/BrewClientTests/CleanupCommandTests.swift` | Added | Proves scope matrix, identity, guidance, shell-free specs, and zero hostile-target spawn. |

## U2 Files Changed

| File | Action | What changed |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/CleanupParser.swift` | Added | Adds immutable evidence/provenance values, tolerant byte parsing, typed equality, canonical v1 SHA-256, and honest disk allocation joining. |
| `Packages/CellarCore/Sources/BrewClient/CleanupPreviewSource.swift` | Added | Adds raw stdout/stderr acquisition, exact `.read` command/environment use, typed unavailable/failure/cancelled diagnostics, and cooperative cancellation. |
| `Packages/CellarCore/Sources/BrewClient/CleanupStore.swift` | Added | Adds `@MainActor @Observable` per-scope states, owned tasks, generation rejection, cancellation, and last-good stale retention. |
| `Packages/CellarCore/Tests/BrewClientTests/CleanupParserTests.swift` | Added | Covers all 14 U0 files plus synthetic uncertainty, equality, fingerprint, and allocation cases. |
| `Packages/CellarCore/Tests/BrewClientTests/CleanupStoreTests.swift` | Added | Covers raw process specs, zero-spawn guidance, source cancellation, supersession, scoped states, and stale retention. |

## U3 Files Changed

| File | Action | What changed |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/OperationCenterCleanup.swift` | Added | Adds typed disclosure/effects, queue-front preview authorization, refreshed/stale updates, and cleanup request/confirm entry points on the existing center. |
| `Packages/CellarCore/Sources/BrewClient/BrewMutating.swift` | Modified | Preserves typed command-local environment policy through erasure and the shared mutation abstraction. |
| `Packages/CellarCore/Sources/BrewClient/OperationCenter.swift` | Modified | Passes each command's typed environment overrides to the existing authorized BrewRunner FIFO path. |
| `Packages/CellarCore/Sources/BrewClient/OperationCenterBulk.swift` | Modified | Carries optional cleanup disclosure without widening the existing presentation enum or breaking non-cleanup confirmations. |
| `Packages/CellarCore/Tests/BrewClientTests/CleanupAuthorizationTests.swift` | Added | Covers disclosure, stale preconditions, FIFO-front equality, exact request replay, one spawn, and five fail-closed denial/update paths. |
| `Packages/CellarCore/Tests/BrewClientTests/CleanupOperationTests.swift` | Added | Covers all scopes, history subjects, exact disk areas, environment, and every modeled terminal's exactly-once/zero receipts. |

## U4 Files Changed

| File | Action | What changed |
|---|---|---|
| `Packages/CellarCore/Tests/PersistenceTests/CleanupHistoryPresentationTests.swift` | Added | Covers exact stored verbs/identity, labels, scope subjects, searches, temporary Schema V1 round-trip, unknown fallback, and copy-only non-replayability. |
| `Packages/CellarCore/Sources/Persistence/HistoryPresentation.swift` | Modified | Adds centralized cleanup labels, operation-scope subjects for null identities, and cleanup label matching with stored-verb fallback. |
| `Packages/CellarCore/Sources/Persistence/HistoryStore.swift` | Modified | Extends the existing SwiftData predicate with four presentation-label aliases while retaining name/verb/argv search. |

## U5 Files Changed

| File | Action | What changed |
|---|---|---|
| `cellarUITests/cellarUITests.swift` | Modified | Adds six RED-first CO7 XCUITests and deterministic cleanup launch helpers. |
| `cellar/Cleanup/CleanupView.swift` | Modified | Adds preview-first scope controls, truthful state/evidence rendering, stable identifiers, package controls, and preserved direct disclosure rows. |
| `cellar/Activity/MutationConfirmation.swift` | Modified | Renders exact cleanup command, provenance, effects, Full warning, orphan facts, copyable text, and cleanup-specific identifiers/actions. |
| `cellar/ContentView.swift` | Modified | Injects cleanup dependencies, routes cleanup confirmation, and adopts queue-front authorization updates. |
| `cellar/cellarApp.swift` | Modified | Owns one shared cleanup source and one app-wide cleanup store and injects both. |
| `cellar/AppTestFixtures.swift` | Modified | Adds deterministic process-free cleanup result modes and post-terminal disk refresh behavior. |
| `Packages/CellarCore/Sources/BrewClient/CleanupStore.swift` | Modified | Adds narrow public authorization-update adoption that invalidates execution and requires a fresh preview/reconfirmation. |

## Deviations from Design

None. The work stayed inside the U0 runtime/fixture boundary. Homebrew alone
performed cleanup in the sentinel prefix; the harness directly created only
disposable setup files and the advisory-lock control.

U1 also matches the design. It did not add preview parsing/store,
OperationCenter authorization, persistence, app composition, or UI work.

U2 intentionally collects raw `OutputChunk` bytes directly through the shared
`ProcessLaunching` seam instead of routing the preview through `BrewRunner`'s
line projection. `LineSplitter` removes terminators, so that design sketch could
not satisfy the stronger byte-exact stdout/stderr requirement. U2 still derives
the exact `.read` argv and command-local environment from the U1 typed command.
No queue, authorization, mutation, persistence, or UI policy was added.

U3 matches the behavioral design and reuses the existing confirmation box,
OperationCenter, BrewRunner FIFO, ActivityItem, history recorder, mutation gates,
typed denials, and terminal finish funnel. `ConfirmationRequest` carries an
optional typed cleanup disclosure rather than adding a new exhaustive case to
`ConfirmationDisclosure`; this keeps U3 autonomous and leaves SwiftUI-specific
rendering/switch updates to U5. One additional minimal edit to
`OperationCenter.swift` was necessary because its authorized runner call rebuilt
argv but dropped U1's command-local environment policy; without that edit Full,
global, and package cleanup could implicitly autoremove on the shared path.

U4 matches the presentation and compatibility design. A minimal
`HistoryStore.swift` edit was additionally required because the existing
name/verb/argv predicate cannot match multiword labels such as `Full cleanup` or
`Package cleanup`; the RED proved that persistence-search contract. Schema V1,
the migration plan, recorder, controls, and app/SwiftUI files remain unchanged.

U5 matches the app-composition design and keeps one app-owned store/source with
thin injection. A narrow public `CleanupStore.adopt(_:)` integration was added
outside the design's enumerated U5 app files because queue-front denial evidence
must visibly replace or stale the reviewed state without becoming executable;
the app cannot safely mutate `CleanupStore.states` directly. Package cleanup
controls render in a separate section so existing `CleanupRow` disclosure groups
remain direct macOS list rows and keep their accessible version expansion.

## Issues and Risks

- Homebrew `cleanup --dry-run` fetched current API package metadata even with
  auto-update and analytics disabled; its two stderr lines are preserved rather
  than reclassified or discarded.
- The fixtures intentionally preserve Homebrew version-specific prose and the
  disposable absolute prefix. Later tolerant parser tests must not assume prose
  stability or turn fixture paths into execution input.
- The focused suite's one known issue was already present in the baseline and
  remained a known issue after U0.
- Replacing an existing Swift method with a defaulted-parameter signature does
  not preserve its old linker symbol. U1 therefore uses additive overloads for
  command-local environment support; the impacted regression is green.
- U1 declares cleanup invalidation metadata on the command but does not connect
  it to OperationCenter. That wiring remains U3 by design.
- `DiskUsageSnapshot.isComplete` does not itself prove all three root-state keys
  exist; U2 requires exact Cellar/Caskroom/cache key coverage before allocation.
- U2 is exactly 900 source/test lines, leaving no margin under its native-attempt
  limit; later work must not expand the U2 rollback boundary silently.
- Before U3, `OperationCenter.run` forwarded authorized argv but not command-local
  environment overrides. U3 now preserves the typed policy for every conformer;
  existing commands use the empty default and remain behaviorally unchanged.
- Cleanup denial publishes a typed refreshed/stale update and records the typed
  denial through the existing finish funnel. U5 must adopt that update into the
  app-owned `CleanupStore` before presenting a new confirmation; U3 intentionally
  adds no SwiftUI composition.
- Schema V1 encodes absent history identity/version strings as empty values and
  projects them as nullable `packageID`/`versions`; U4 preserved those exact
  shipped bytes and added no schema version or migration.
- An exploratory combined recorder safety-net run exited with signal 10 in the
  pre-existing async execution-record retirement test after its other nine tests
  passed. U4 does not modify that recorder/BrewRunner path; the 23 tests covering
  the modified presentation/store files and the final 26-test impacted set pass.
- U5's first exact primary run exposed one regression: nesting `CleanupRow` and
  its package preview control in a `VStack` removed the macOS disclosure triangle
  from the accessibility hierarchy. The package preview controls were separated
  into their own section; the focused characterization and final 18-test UI run
  now pass.
- U6 activation failures were environment-state dependent: explicitly launching
  and bringing the built app frontmost restored XCUITest activation without any
  source, permission, or policy change. Both bounded retry commands passed.

## Remaining Tasks

All 21 tasks are complete. RDD is clone-locally disabled, delivery is unmanaged
and not approved, and no review gate or receipt exists. Ready for independent
`sdd-verify`.

## Verification Remediation: Cancellation Coverage Race

- Work unit: `verify-remediation-cancellation-coverage`
- Native attempt token: `sha256:205597a1dcd4a71fc92bb4af898176783d3a09a9471bee24dba29604a0e06074`
- Attempt budget: 1 attempt, 200 changed lines; this remediation used 88 changed lines (25 source/test + 63 OpenSpec evidence).
- Remediated verification report revision: `sha256:d3162fc2f4062f22a928635c71f75833840ee596a5c3c878cbb6eefb537a2c8d`
- Failed source/test evidence identity: `sha256:9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4`
- RDD remains disabled; delivery remains unmanaged and not approved. No review, receipt, lineage, settlement, commit, push, PR, archive, or independent verification was started.

### Root Cause and Minimal Correction

`BrewRunner.start(.mutate)` intentionally returns a queued operation before its
gate task necessarily launches a process. `CancellationTests` called cancel or
advanced the cancellation clock immediately after `start`, so coverage
instrumentation could schedule cancellation first. That correctly exercised the
queued-cancellation branch, which launches nothing and therefore sends no
signal, while the assertion claimed an already-active process. Production
cancellation behavior was not defective.

The test seam now returns its existing `FakeProcessLauncher` and each active- or
finished-process scenario awaits `waitForLaunches(atLeast: 1)` before cancelling,
advancing the clock, emitting output, or terminating. No assertion was weakened;
no sleep, retry, timing allowance, production edit, or known-issue suppression
was added. The cooperative scenario still proves exactly one `.interrupt` is
observable before cancellation settles.

### TDD Cycle Evidence

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| Coverage-only cancellation remediation | `Packages/CellarCore/Tests/BrewProcessTests/CancellationTests.swift` | Process seam + Swift concurrency | Persisted full coverage run failed 1/808 at line 36; focused reproduction failed 1/1 with `[]` vs `[.interrupt]` | `swift test --package-path Packages/CellarCore --enable-code-coverage --filter cooperativeProcessStopsAtInterrupt` exited 1; SHA-256 `520de03fde8825775161d80dc0b54b0e3d3303f8b53a21dd7c94cf797687422b` | Focused ordinary 1/1 passed, SHA-256 `d6d3194b5ed44b0bdc728c4bb6d95ddc2a2195f5e42c257a2045cb11e5c4a798`; focused coverage 1/1 passed, SHA-256 `09514293d607b8eec6a3de1fb0c3ee1b84d8412f72f27793ccbe80f49ba67f24` | Whole coverage suite exposed the same setup race in another active-process scenario; launch synchronization was applied to all seven scenarios | Final ordinary and coverage cancellation suites each passed 7/7; SHA-256 `e558b6dd39c6d0426a11334bfd05b6f7903b7317465422114835a3dd9dd6b233` and `5fc7ef70247fa4f085c3a4621f92eb6c48aa1de1ad206ddaeb753a8d1de1b959` |

### Exact Remediation Evidence

| Command | Exit and exact result | Output SHA-256 |
|---|---|---|
| `swift test --package-path Packages/CellarCore --filter CancellationTests` | 0; 7 tests / 1 suite passed in 0.001s | `e558b6dd39c6d0426a11334bfd05b6f7903b7317465422114835a3dd9dd6b233` |
| `swift test --package-path Packages/CellarCore --enable-code-coverage --filter CancellationTests` | 0; 7 tests / 1 suite passed in 0.001s | `5fc7ef70247fa4f085c3a4621f92eb6c48aa1de1ad206ddaeb753a8d1de1b959` |
| `swift test --package-path Packages/CellarCore --filter 'Brew(Process\|Client)Tests'` | 0; 560 tests / 84 suites passed in 15.052s with 1 existing known issue | `9f1ca00fb89e69a0fc59f01b1bb81bc91113243987d5e0c3ef155e8dcc3ebaee` |
| `swift test --package-path Packages/CellarCore --filter Cleanup` | 0; 33 tests / 7 suites passed in 0.054s | `53d65746bf088de88a41333d9b388419e7043b012e0fc91f19dd2fcf5be612cf` |
| `swift test --package-path Packages/CellarCore` | 0; 808 tests / 120 suites passed in 15.645s with 1 existing known issue | `27bd875bf65b0478df165692f9df7a7eaf86b1555bc2e9f9fcf8841f97ffe248` |
| `swift test --package-path Packages/CellarCore --enable-code-coverage` | 0; 808 tests / 120 suites passed in 15.613s with 1 existing known issue | `269783677523bd1441715545204be4c6cd046290553dd19ba8e91d356a4f1399` |
| `git diff --check` | 0; no output | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

### Work Unit Evidence

| Evidence | Required value |
|---|---|
| Focused test command and exact result | Ordinary and coverage `CancellationTests` commands above both exited 0 with 7/7 tests passing. |
| Runtime harness command/scenario and exact result | The coverage-instrumented `CancellationTests` process seam is the runtime boundary: a launched `FakeProcess` receives exactly `.interrupt`, terminal cancellation settles, escalation order remains intact, and queued cancellation remains covered separately; 7/7 passed. |
| Changed-line count | `CancellationTests.swift`: 16 additions + 9 deletions = 25 source/test lines. This appended evidence adds 63 OpenSpec lines, for 88 remediation lines total, below the 200-line ceiling. File SHA-256: `d5dea5265490d2a3e2617afeaf9f262410864c35b1a1c29ffc0f033a7aaf00bb`; remediation patch SHA-256: `275cdf146e7f98318787947034c9e3681328088da72dcf0ebd8b7ff788cdc87f`. |
| Rollback boundary | Revert only `Packages/CellarCore/Tests/BrewProcessTests/CancellationTests.swift` to remove launch synchronization, then remove this remediation section from both progress mirrors. No production behavior or U0–U6 evidence is part of the rollback. |

```json
{"schema":"gentle-ai.remediation-result/v1","status":"passed","change":"m3-cleanup","work_unit":"verify-remediation-cancellation-coverage","attempt_token":"sha256:205597a1dcd4a71fc92bb4af898176783d3a09a9471bee24dba29604a0e06074","rdd_mode":"disabled","delivery_classification":"unmanaged","approved":false,"lineage_id":"","generation":0,"fix_batch":0,"remediates_verification_report_revision":"sha256:d3162fc2f4062f22a928635c71f75833840ee596a5c3c878cbb6eefb537a2c8d","failed_evidence_revision":"sha256:9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4","changed_lines":{"source_test_additions":16,"source_test_deletions":9,"evidence_artifact_additions":63,"total":88},"candidate_patch_sha256":"sha256:275cdf146e7f98318787947034c9e3681328088da72dcf0ebd8b7ff788cdc87f","settlement":"orchestrator-owned"}
```
```json
{"schema":"gentle-ai.remediation-evidence/v1","change":"m3-cleanup","work_unit":"verify-remediation-cancellation-coverage","lineage_id":"","generation":0,"fix_batch":0,"remediates_verification_report_revision":"sha256:d3162fc2f4062f22a928635c71f75833840ee596a5c3c878cbb6eefb537a2c8d","failed_evidence_revision":"sha256:9fed897a6e2c9a47bf6ac845dedb4fd776c05029c53984f95fa403ab2d8e9dc4","focused_test":{"command":"swift test --package-path Packages/CellarCore --enable-code-coverage --filter CancellationTests","exit_code":0,"tests":"7/7","output_sha256":"sha256:5fc7ef70247fa4f085c3a4621f92eb6c48aa1de1ad206ddaeb753a8d1de1b959"},"runtime_harness":{"scenario":"launched process observes exactly one interrupt before terminal cancellation settles; escalation and finished-operation controls remain deterministic","command":"swift test --package-path Packages/CellarCore --filter CancellationTests","exit_code":0,"tests":"7/7","output_sha256":"sha256:e558b6dd39c6d0426a11334bfd05b6f7903b7317465422114835a3dd9dd6b233"},"full_ordinary":{"command":"swift test --package-path Packages/CellarCore","exit_code":0,"tests":"808/808","suites":"120/120","known_issues":1,"output_sha256":"sha256:27bd875bf65b0478df165692f9df7a7eaf86b1555bc2e9f9fcf8841f97ffe248"},"full_coverage":{"command":"swift test --package-path Packages/CellarCore --enable-code-coverage","exit_code":0,"tests":"808/808","suites":"120/120","known_issues":1,"output_sha256":"sha256:269783677523bd1441715545204be4c6cd046290553dd19ba8e91d356a4f1399"},"rollback":"Revert only Packages/CellarCore/Tests/BrewProcessTests/CancellationTests.swift and remove this remediation evidence from both progress mirrors.","review_authority":"absent"}
```

Remediation implementation and evidence are complete. The orchestrator still
owns native attempt settlement and any fresh independent verification.
