```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:7852ee64aecde68d3bb6c05c219a35b66c4a4148f7aa07293a1038e8c477d68a
verdict: pass
blockers: 0
critical_findings: 0
requirements: 11/11
scenarios: 52/52
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:863d9ea43b485d4baec9cc1f90c9735215ca9c69e08f805085d938c0cfcc7495
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination platform=macOS
build_exit_code: 0
build_output_hash: sha256:aa9d95e45c4b5c52a3be1b5e197f6e58a530072af9995fcb75aa99701a58a50a
```

## Verification Report

**Change**: m5-brewfile
**Version**: spec revision 2 (Engram obs #7522, amended after design DD1)
**Mode**: Strict TDD
**Verified at**: working tree on `main`, uncommitted, base `7d48779`

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 61 |
| Tasks complete | 61 |
| Tasks incomplete | 0 |

Task 10.4 was the last open item; it is closed by explicit user acceptance of the shipped copy,
recorded both in the `tasks.md` checkbox annotation ("Presented verbatim to the user 2026-08-07 …
**accepted as-is** with no rewording (obs #7520)") and in Engram decision #7520. Verified: 61 `[x]`
checkboxes, 0 `[ ]`.

### Build & Tests Execution

**Build**: PASS — `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS'`

```text
** BUILD SUCCEEDED **   (exit 0)
```

**Tests**:

| Suite | Command | Result |
|---|---|---|
| Package (FAST) | `swift test --package-path Packages/CellarCore` | **1517 tests in 188 suites passed**, exit 0, 1 known issue |
| App unit (APP) | `xcodebuild test … -only-testing:cellarTests` | **100 test cases passed, 0 failed**, `** TEST SUCCEEDED **`, exit 0 |
| Brewfile E2E | `xcodebuild test … -only-testing:cellarUITests/BrewfileImportUITests` | **2/2 passed**, `** TEST SUCCEEDED **`, exit 0 |
| Release-notes UI (pre-existing) | `xcodebuild test … -only-testing:cellarUITests/ReleaseNotesUITests` | **4 cases failed / 7 failures**, `** TEST FAILED **` |

The single known issue is `OperationCenterCancelTests.swift:183` ("Finishing a call that never
launched fails this test instead of crashing the suite") — the pre-existing one the apply phase
declared. It is unchanged by this slice.

**FULL-suite state**: not green, and not made worse here. `ReleaseNotesUITests` fails with exactly
**4 cases / 7 failures** — the same shape apply reproduced at clean `HEAD 7d48779` in an isolated
worktree. Independently re-confirmed here: this change touches **no** release-notes file
(`git diff HEAD --name-only | rg -i release` → empty), so the failures cannot originate in it.
Claim re-confirmed, not merely repeated.

**Coverage**: not available — no coverage tool is configured for this project. Not a failure.

### Security Invariants (verified in code, not prose)

| Invariant | Verified how | Result |
|---|---|---|
| brew never reads a user-supplied file | `BundleDumpCommand.swift` is the whole set of `bundle` argv Cellar can build; `Subcommand` is a one-case `CaseIterable` (`dump`); the only initialiser is `init(fileURL: URL)` — no `String` overload. `BundleDumpSource` constructs `<tmp>/cellar-brewfile/<UUID>/Brewfile` itself. `rg '"--file"'` over all sources returns exactly one production site. | PASS |
| No Ruby evaluation anywhere | `BrewfileParser.decode` is `@concurrent`, takes `Data`, splits on the `0x0A` **byte**, decodes per line, and reaches for nothing else. `trailingConditional` **detects** `if`/`unless` to refuse the line; it never evaluates one. `isRepresentableToken` rejects `#{` outright. No interpreter, no `Process`, no environment read on the path. | PASS |
| `trusted:` parsed, surfaced, never honoured | Parsed by `BrewfileParser.trustClaim` into `BrewfileTrustClaim` and carried on `BrewfileEntry.trustedClaim` (amendment A1 moved it off `Kind.tap` so a claim on a `brew`/`cask` line is not silently dropped). `BrewfilePlan` pattern-matches `.tap(let name, _)` and never reads the claim; `rg 'trusted\|Claim'` over `BrewfilePlan.swift` and `BrewfileDiff.swift` returns **nothing**. Surfaced in `BrewfileImportSheet` attributed to the file's author. | PASS |
| Imported names pass only through typed identity gates | `BrewfileParser.entry(kind:…)` admits a name only via `TapName(_)`, `FormulaID(name:)` or `CaskID(name:)`, each behind `isRepresentableToken`; a refusal becomes `.unrepresentableName`. `BrewfilePlan.init(selecting:)` takes `[BrewfileEntry]`, which already holds constructed identities — it "cannot fail and cannot emit free text". `MutationName.isSafe` is unchanged. | PASS |
| DD1 disclosure survives erasure | `OperationCenterBulk.request(_:)` line 149 reads `disclosure: first.disclosure`. `AnyBrewMutation` carries `disclosure` as its eighth stored projection. `rg 'as\? *TapCommand'` finds **zero** executable occurrences — the four hits are three doc comments plus one structural guard that scans for the string. | PASS |
| Export subprocess never writes to the user's disk | `--file` is a fresh per-export `<tmp>/cellar-brewfile/<UUID>/Brewfile`; a single `defer { try? fileSystem.removeItem(at: directory) }` covers success, failure and cancellation. Publication is Cellar's atomic write through `CatalogFileSystem`; `BrewfilePublication` names no well-known Brewfile location anywhere. | PASS |
| No implicit mutation on import | Parse and diff spawn nothing (`BrewfileDiff` holds no launcher). Nothing is submitted without an explicit selection and the shipped `OperationCenter` confirmation. | PASS |

### Spec Compliance Matrix

#### `brewfile-management` — 9 requirements / 38 scenarios (ADDED-only)

| Req | Scenario | Covering test | Result |
|---|---|---|---|
| BF1 | An import spawns no process at all | `BrewfileArgvStructureTests > An import spawns no bundle invocation of any kind` | COMPLIANT |
| BF1 | A hostile Brewfile executes nothing | `BrewfileArgvStructureTests > The hostile fixture executes nothing and installs nothing` | COMPLIANT |
| BF1 | Only dump reaches brew, and only on a Cellar path | `BundleDumpCommandTests > Dump is the only bundle subcommand that can be constructed` / `Every other bundle subcommand is unrepresentable, not merely unused`; `BrewfileArgvStructureTests > Every --file value is a Cellar-created temporary path` | COMPLIANT |
| BF2 | A conditional line is skipped identically on any machine | `BrewfileSkipTests > A conditional line is skipped identically on any machine` | COMPLIANT |
| BF2 | Interpolation and method calls are never evaluated | `BrewfileSkipTests > Interpolation and method calls are never evaluated` | COMPLIANT |
| BF2 | Undecodable bytes are tolerated, not fatal | `BrewfileSkipTests > Undecodable bytes are tolerated at line granularity, not fatal` | COMPLIANT |
| BF2 | An empty file is an empty parse, not a failure | `BrewfileParserTests > An empty parse, an all-skipped parse and a populated parse are distinct` | COMPLIANT |
| BF3 | A trusted tap with a URL positional parses as one tap entry | `BrewfileParserTests > A tap line with a URL positional keeps both, and counts no skip` / `A trusted tap with a URL positional parses as one tap entry` | COMPLIANT |
| BF3 | A description comment above an entry is not a skip | `BrewfileParserTests > Description comments and blank lines are ignored, not counted as skips` | COMPLIANT |
| BF3 | Quoting variants parse to the same entry | `BrewfileParserTests > Quoting variants, whitespace and a trailing comma all parse to the same entry` | COMPLIANT |
| BF3 | A tap-prefixed name is an entry, not a skip | `BrewfileParserTests > A tap-prefixed package name is an ordinary entry, not a skip` / `The real dump's tap-prefixed formulae all survive` | COMPLIANT |
| BF3 | A name the typed identity refuses is a skip, never a string | `BrewfileSkipTests > A name the typed identity refuses is a skip, never a string`; `Shell metacharacters in a name yield a refusal, never a command` | COMPLIANT |
| BF4 | Unsupported kinds are counted and named, and the file still imports | `BrewfileSkipTests > Each unsupported entry kind is counted, named, and keeps its line` | COMPLIANT |
| BF4 | A clean file reports zero, not absence | `BrewfileSkipTests > A clean document reports a skip count of zero, present rather than absent` | COMPLIANT |
| BF4 | A wholly unsupported file still parses successfully | `BrewfileSkipTests > Skips never gate the diff: an all-skipped file is still a usable projection`; `BrewfileStoreTests > Skips never gate the import, even when the file is entirely skips` | COMPLIANT |
| BF4 | A skip keeps its raw line | `BrewfileSkipTests > A skip keeps its raw line, exactly as read`; `A skip carries its line number, its raw line, and a reason a consumer can switch on` | COMPLIANT |
| BF5 | A trusted tap still raises the trust disclosure | `BrewfilePlanTests > A trusted tap still raises the identical trust disclosure` | COMPLIANT |
| BF5 | `trusted:` never becomes argv | `BrewfilePlanTests > A trusted tap still raises the identical trust disclosure`; `BrewfileArgvStructureTests > No brew argv element derives from a user path or a raw file line` | COMPLIANT |
| BF5 | The claim is surfaced, attributed to the file | `BrewfileEntryTests > A trust claim is the file author's, and it grants nothing`; `cellarTests/BrewfileCompositionTests > aTrustedClaimIsSurfacedAndAttributed` | COMPLIANT |
| BF5 | `trusted:` on a brew or cask line parses and confers nothing | `BrewfileParserTests > trusted: on a brew or cask line parses and confers nothing` | COMPLIANT |
| BF6 | Diffing a file acquires nothing | `BrewfileDiffTests > The diff has no process, no refresh and no acquisition to reach for` | COMPLIANT |
| BF6 | Missing entries arrive selected and present entries do not | `BrewfileDiffTests > Missing entries arrive selected and present entries do not`; app `missingRowsArriveSelectedAndPresentRowsAreNot` | COMPLIANT |
| BF6 | A present or skipped entry cannot enter the selection | `BrewfileDiffTests > A present or skipped entry cannot enter the selection`; `BrewfileStoreTests > Selection initialises to the missing set and refuses everything else` | COMPLIANT |
| BF6 | Three empties stay distinct | `BrewfileDiffTests > A file with no entries, an all-present file and an all-skipped file are distinct`; `BrewfileStoreTests > The store distinguishes the three empties` | COMPLIANT |
| BF7 | A mixed selection fans out, taps first | `BrewfilePlanTests > A mixed selection fans out, taps first, one subject per argv`; app `confirmingSubmitsAllThreeTapFirst` | COMPLIANT |
| BF7 | Only selected entries are submitted | `BrewfilePlanTests > Only selected entries are submitted` | COMPLIANT |
| BF7 | One confirmation covers the batch, and declining submits nothing | `BrewfilePlanTests > One confirmation covers the batch, and declining submits nothing`; `A tap selected last still leads the batch, and still leads the confirmation`; app `aTapCarryingImportRaisesExactlyOneTrustConfirmation`, `decliningATapCarryingImportSpawnsNothing` | COMPLIANT |
| BF7 | An empty selection submits nothing | `BrewfilePlanTests > An empty selection produces an empty plan, and submits nothing`; app `deselectingEverythingMakesTheApplyANoOp` | COMPLIANT |
| BF7 | A mid-batch failure attributes to one entry | Inherited: `BulkFanOutTests > A mid-batch non-zero exit attributes to the second package and the third still runs`; `OperationCenterHistoryTests > A failing, a busy and a cancelled mutation each submit one draft naming its own outcome`. Brewfile batches provably enter that same spine (`BrewfilePlanTests > The capability adds no mutating command family and no invalidation domain`, `Confirming submits every command the confirmation showed`). | COMPLIANT (inherited) |
| BF8 | The dump argv is pinned | `BundleDumpCommandTests > The dump argv is pinned exactly`; `The three type filters are all present, and --global is not` | COMPLIANT |
| BF8 | A warning on stderr at exit zero is still a success | `BundleDumpSourceTests > A warning on stderr at exit zero is still a success` | COMPLIANT |
| BF8 | A non-zero exit is a typed failure that keeps both streams | `BundleDumpSourceTests > A non-zero exit is a typed failure that keeps both raw streams` | COMPLIANT |
| BF8 | The temporary file never survives the attempt | `BundleDumpSourceTests > The temporary directory is removed after a successful / failed / cancelled export` (3 cases) | COMPLIANT |
| BF8 | Export acquires nothing else and records nothing | `BundleDumpSourceTests > An export acquires nothing else and writes no history entry`; `The dump source has no mutation spine to reach for` | COMPLIANT |
| BF9 | Published bytes equal the dump's bytes | `BrewfilePublicationTests > Published bytes equal the dump's bytes, including the trailing newline`; app `publishingWritesExactlyThePreviewedBytes` | COMPLIANT |
| BF9 | A failed publication preserves the existing file | `BrewfilePublicationTests > A failed publication preserves the existing file`; `BrewfileStoreTests > A failed publication is typed, and the preview survives it` | COMPLIANT |
| BF9 | No destination is remembered between exports | `BrewfilePublicationTests > No destination is remembered between exports`; `No default or well-known Brewfile location can be written`; app `thePanelsRememberNothingAndHoldNoBookmark` | COMPLIANT |
| BF9 | Cancelling publication writes nothing | `BrewfilePublicationTests > Cancelling the destination choice writes nothing and still removes the temporary`; app `cancellingTheDestinationPublishesNothing` | COMPLIANT |

#### `package-mutation` — 2 MODIFIED requirements / 14 scenarios (5 new)

| Req | Scenario | Covering test | Result |
|---|---|---|---|
| PM1 | Installing a formula names it as a formula | `MutationCommandTests` (shipped, unchanged, passing) | COMPLIANT |
| PM1 | Installing a cask names it as a cask | `MutationCommandTests` | COMPLIANT |
| PM1 | Uninstalling a cask names it as a cask | `MutationCommandTests` | COMPLIANT |
| PM1 | Reinstall, pin and unpin carry the kind flag too | `MutationCommandTests` | COMPLIANT |
| PM1 | A token that exists in both namespaces is never ambiguous | `MutationCommandTests` | COMPLIANT |
| PM1 | Another family enters the spine without becoming a case of this type | `BrewfilePlanTests > The capability adds no mutating command family and no invalidation domain` | COMPLIANT (new) |
| PM1 | An erased mixed batch still discloses tap trust | `ConfirmationDisclosureTests > An erased mixed batch still discloses tap trust`; E2E `BrewfileImportUITests.testATapCarryingImportShowsTheTrustWarningAndNotTheRemovalOne` | COMPLIANT (new) |
| PM1 | An erased install-only batch still discloses package removal | `ConfirmationDisclosureTests > An erased install-only batch still discloses package removal`; `A command declaring no disclosure defaults through the protocol, not the caller` | COMPLIANT (new) |
| PM1 | No disclosure is recovered by a type test | `ConfirmationDisclosureTests > No disclosure is recovered by a downcast, a type test or a verb string`; `Every shipped call site keeps the disclosure it already presented` | COMPLIANT (new) |
| PM9 | An empty or whitespace name is rejected | `MutationCommandTests` (shipped) | COMPLIANT |
| PM9 | A name that looks like an option is rejected | `MutationCommandTests` (shipped) | COMPLIANT |
| PM9 | No construction path skips validation | `MutationCommandTests` structural scan, extended by A6 with the `namesNothing` exemption | COMPLIANT |
| PM9 | A file-sourced name is validated on exactly the same terms | `BrewfileSkipTests > A name the typed identity refuses is a skip, never a string`; `BrewfilePlanTests > A refused name reaches no plan, no argv and no process` | COMPLIANT (new) |
| PM9 | No path carries a raw file-sourced string into argv | `BrewfilePlanTests > The plan accepts only already-constructed identities`; `BrewfileEntryTests > No case of the entry kind takes a raw string, and no initialiser accepts one`; `BrewfileArgvStructureTests > No brew argv element derives from a user path or a raw file line` | COMPLIANT (new) |

**Compliance summary**: **52/52 scenarios compliant**, 0 UNTESTED, 0 FAILING, 0 PARTIAL. One
(BF7 mid-batch failure) is compliant by inherited spine coverage rather than a Brewfile-specific
assertion — see SUGGESTION 1.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| BF1 structural enforceability | Implemented | `Subcommand` one-case `CaseIterable`; `--file` takes `URL`, no `String` initialiser |
| BF2 parse purity | Implemented | `@concurrent static func decode(_ data: Data)`; byte-level line split; 8 MiB bound |
| BF3 grammar | Implemented | `EntryKeyword` = tap/brew/cask; quote-aware comment stripping and comma splitting |
| BF4 skip taxonomy | Implemented | 6 reasons; `Category: String, CaseIterable` (A2) + `detail: String?`; count is `Int`, never optional |
| BF5 `trusted:` | Implemented | `BrewfileTrustClaim` on `BrewfileEntry` (A1); discarded by `BrewfilePlan` |
| BF6 diff | Implemented | `isSelectable == (state == .missing)`; `selectableIDs` is the gate |
| BF7 plan | Implemented | `commands` = `taps + installs`, erased to `[AnyBrewMutation]` |
| BF8 export | Implemented | fresh temp dir per export, single `defer` cleanup |
| BF9 publication | Implemented | atomic write through `CatalogFileSystem`; no well-known path named |
| PM1 disclosure through abstraction | Implemented | `BrewMutating.disclosure` + `.packageRemoval` extension default; `AnyBrewMutation` eighth projection |
| PM9 provenance premise restated | Implemented | `MutationCommand.swift` comment block; **zero changed executable lines** in that file |

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| D1 Cellar parses the Brewfile itself (A2) | Yes | No `bundle check` path exists |
| D2 dump to temp, publish atomically (E3) | Yes | `BundleDumpSource` + `BrewfilePublication` |
| D3 UI inside the existing Taps section | Yes | Two `.toolbar` affordances; no new `AppSection`; zero pbxproj diff |
| D4 `trusted:` parsed, surfaced, never honoured | Yes | Verified in code above |
| D5 named skip reasons | Yes | 6-case taxonomy with `Category` |
| D6 conditionals/undecodable tolerated as skips | Yes | `.rubyConditional`, `.undecodableBytes` |
| DD1 promote `disclosure` to `BrewMutating` | Yes | `first.disclosure` at `OperationCenterBulk.swift:149`; downcast gone |
| A1–A12 apply-time amendments | Yes | All twelve recorded in `design.md` → *Apply-Time Amendments*; A1, A2, A3, A4, A6, A9, A10, A12 independently verified in source here |

### Structural Bindings

| Check | Expected | Observed | Result |
|---|---|---|---|
| `Packages/CellarCore/Package.swift` | zero-line diff | `git diff HEAD --stat` empty | PASS |
| `cellar.xcodeproj/project.pbxproj` | zero-line diff | `git diff HEAD --stat` empty | PASS |
| `CatalogFootprintTests.swift` | unchanged, un-rebased, passing | not in `git status`; passes inside the 1517 | PASS (S4 headroom untouched) |
| Assertion deletions across `Tests/`, `cellarTests/`, `cellarUITests/` | zero | `git diff -U0` filtered on `#expect`/`XCTAssert`/`Issue.record` deletions → none | PASS |
| `TapShippingProofTests` (A10) | extension, not weakening | +30/−2; the two deleted lines are list continuations. "Brewfile" left the excluded-capability list and was replaced by a bounded occurrence count, 9 forbidden Brewfile-logic identifiers, `.sheet` count == 2, and `navigationDestination` absent | PASS (net stronger) |
| `MutationCommandTests` (A6) | exemption paid for with a stronger claim | +49/−2; `namesNothing` exempts `BundleDumpCommand.swift` from `isSafe` and instead requires: no `isSafe` reference, no `PackageID`/`PackageTarget`/`FormulaID`/`CaskID`/`TapName`, exactly `init(fileURL: URL)`, no stored `String` | PASS (net stronger) |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | PASS | 21-row *TDD Cycle Evidence* table in `apply-progress.md` |
| All tasks have tests | PASS | Every row names a real, on-disk test file; all 21 verified present |
| RED confirmed (tests exist) | PASS | 21/21. RED reasons are the credible compile-failure kind (`cannot find 'BrewfileParser'`, `cannot find type 'BrewfileStore'`, `cannot find 'BrewfileSourcePanel' in scope` ×10), not asserted-after-the-fact prose. Task 1.4's RED was demonstrated by mutating a fixture (2 appended bytes → 3 issues) and restoring it — a genuine falsification. Task 9.6's E2E failed twice for two *different* real reasons before passing. |
| GREEN confirmed (tests pass) | PASS | 21/21 re-executed here: 1517 package + 100 app + 2 E2E, all green |
| Triangulation adequate | PASS | Every row carries multiple cases; no `➖ Single` row exists. Examples: 11 forbidden subcommands enumerated, 10 skip kinds, 4 refused names, 4 metacharacters, 6 persistence forms, 5 well-known paths, 79 dump lines accounted for individually |
| Safety Net for modified files | PASS | Every modified-file row carries a real prior count (1396, 1448, 1469, 1487, 1511, 74/74, 88/88, 96/96); `N/A (new)` rows correspond to files that are genuinely new in `git status` (`A`, not `M`) |
| Guard/characterisation before change | PASS | Task 0.1 wrote `BrewMutatingTests`' equality/hashing guard **before** the stored property, then extended it after 0.5 — the correct order for a spine change |

**TDD Compliance**: 7/7 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (package) | 121 new (1396 → 1517) | 12 new + 3 modified | Swift Testing |
| Unit (app) | 21 | 1 (`BrewfileCompositionTests.swift`) | Swift Testing |
| Integration (app) | 5 | same file — real `OperationCenter`, real filesystem | Swift Testing |
| E2E | 2 | `cellarUITests/BrewfileImportUITests.swift` | XCUITest |
| **Total new** | **149** | **16** | |

Live `brew` probe harnesses: 3 (batch 1), including U8 re-verified first-hand. Fixture-grade byte-exact
`brew bundle` captures: the repo's first, SHA-256 pinned in both directions by
`BrewfileFixtureManifestTests`.

### Changed File Coverage

Coverage analysis skipped — no coverage tool detected in this project.

### Assertion Quality

**867** `#expect`/`#require`/`XCTAssert` assertions across the 20 changed test files.

| Pattern audited | Finding |
|---|---|
| Tautologies (`#expect(true)`, `1 == 1`) | **none** |
| Ghost loops over possibly-empty collections | **none** |
| Assertions with no production call | **none** |
| Orphan empty-collection assertions | **none** — every `#expect(x.isEmpty)` sampled sits beside a companion non-empty or exact-count assertion (e.g. `BrewfileSkipTests:148-155` pairs `entries.isEmpty` with `skips.count == 2` **and** `document.isEmpty == false` **and** a genuinely-empty control) |
| Type-only assertions used alone | **none** |
| Smoke-test-only (render + exists) | **none** — both E2E cases assert specific disclosure text present *and* the wrong disclosure text absent |
| Mock-heavy (mocks > 2× assertions) | **none** |

**Assertion quality**: All assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

**Per-instance spy rule**: satisfied. `BrewfileCompositionLedger` stores a
`Mutex<[String: [[String]]]>` keyed by a per-launcher `UUID` tag; each launcher reads and writes only
its own tag, so no shared static *count* was added and parallel cases cannot cross-contaminate.
`CompositionRequestSpy`'s shared static was explicitly not reused. See SUGGESTION 2.

### Quality Metrics

**Linter (SwiftLint, 40 changed Swift files)**: 30 warnings, 3 errors.
All **3 errors are pre-existing and byte-identical at `HEAD 7d48779`** — verified by linting the same
files in an isolated worktree: `cellarApp.swift` type name `cellarApp`, `cellarApp.swift:152`
initializer body length, `AppTestFixtures.swift` 381-character JSON fixture line (it merely moved from
line 210 to 275). **This change introduces zero new lint errors.**
New warnings are the convention-size family: `BrewfileParser.swift` file length 432 / type body 252 /
cyclomatic complexity 15 in `entry(kind:arguments:lineNumber:raw:)`; `BrewfileStoreTests.swift` 443;
`BrewfileSkipTests.swift` type body 271; `BrewfileCompositionTests.swift` 808; plus several
`optional_data_string_conversion` hits in tests and `BrewfileExportSheet`.

**Type checker**: PASS — `** BUILD SUCCEEDED **` plus `swift build` implied by the green package suite.

### Review Workload

| Measure | Value |
|---|---|
| Authored total, excluding lifecycle markdown | **7,438** lines (7,427 added / 11 deleted) |
| — excluding byte-exact fixtures (372 lines) | 7,066 |
| CellarCore sources | 1,519 + / 6 − |
| CellarCore tests | 4,132 + / 4 − |
| App target (`cellar/`) | 828 + / 1 − |
| App tests (`cellarTests/`) | 808 + |
| UI tests (`cellarUITests/`) | 140 + |
| OpenSpec lifecycle markdown (excluded) | 2,229 |
| Budget | 5,000 (`review_budget_lines`) |
| Status | Over budget, under **user-accepted `size:exception`** (obs #7520) |

Measured total **7,438** vs the apply phase's reported **≈7,435** — a 3-line reporting difference, not
a discrepancy of substance. Tests and specs are **66%** of the diff (4,132 + 808 + 140 + 372 = 5,452);
shipped source is 2,347 lines.

### Issues Found

**CRITICAL**: None.

**WARNING**:

1. **The `apply-progress` artifact is stale in both backends.** `openspec/changes/m5-brewfile/apply-progress.md` and Engram obs #7525 both still read "**partial** — 60 / 61 tasks complete", and list 10.4 as `[ ]`. `tasks.md` is 61/61 and obs #7520 records the closure. The code is correct; the progress artifact was never refreshed after the user accepted the copy. Cosmetic, but it will mislead the archive phase and anyone reading the PR.
2. **`FULL` is not green on this repository.** `ReleaseNotesUITests` fails 4 cases / 7 failures. Re-confirmed here and independently attributable elsewhere (this change touches no release-notes file), so it does not block. It does mean the repository has had no green full suite since before this slice, and nobody owns it yet.
3. **The diff is ~49% over the 5,000-line budget.** Accepted as `size:exception`, and the cut line (Phase 8 → Phase 9) remains clean if the maintainer reconsiders: batch 1 is independently revertible and batch 2 touches no CellarCore *source*. Noted, not blocking.
4. **`cellarTests/BrewfileCompositionTests.swift` is 808 lines** — twice the project's 400-line convention, holding three suites. `BrewfileParser.swift` (432) and `BrewfileStoreTests.swift` (443) also cross it.
5. **`BrewfileParser.entry(kind:arguments:lineNumber:raw:)` has cyclomatic complexity 15** against a limit of 10. It is the security-critical admission function, so its branch count deserves a second reader even though every branch is tested.
6. **`TapShippingProofTests`' A10 rewrite trades one exact claim for a loose numeric bound.** Removing `"Brewfile"` from the excluded-capability list is a genuine local weakening; it is over-compensated by 9 forbidden Brewfile-logic identifiers, `.sheet` count `== 2` and `navigationDestination` absent — but the replacement `components(separatedBy: "Brewfile").count - 1 <= 12` is a magic number with ~6 occurrences of headroom, so real growth could hide under it.

**SUGGESTION**:

1. **BF7's mid-batch-failure scenario is proven at the spine, not at the Brewfile batch.** `BulkFanOutTests` asserts it for a concrete `MutationCommand` batch. Since DD1 changed how an *erased* batch is handled, a single Brewfile-level case (three entries, second exits non-zero) would close the last inherited-coverage gap for a fraction of the cost of the tests already written.
2. **`BrewfileCompositionLedger`'s backing store is process-global and never pruned.** Per-instance semantics are correct (UUID tag per launcher), but entries accumulate for the process lifetime. Harmless at this scale; a `deinit`-time removal would make it self-cleaning.
3. **`ENABLE_USER_SELECTED_FILES = readonly` is inert behind `ENABLE_APP_SANDBOX = NO`.** Recorded in `BrewfilePanels.swift` and guarded by a test that fails if the note is deleted — good. If the sandbox is ever enabled it permits the import read and blocks the export write, i.e. half a feature. Worth a tracked issue rather than only a comment.
4. **The `optional_data_string_conversion` warnings** (9 sites) are mechanical and could be cleared in a follow-up sweep.

### Verdict

**PASS WITH WARNINGS**

All 11 requirements and all 52 scenarios are compliant with runtime evidence; all 61 tasks are
complete; every binding security invariant was verified in source rather than accepted from prose;
every structural binding (`Package.swift`, `project.pbxproj`, `CatalogFootprintTests`, zero assertion
deletions) holds. The six warnings are hygiene and reporting items, none of which blocks archive —
though warning 1 (the stale `apply-progress` artifact) should be corrected first so the archived
record does not contradict itself.
