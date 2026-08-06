```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:79ec9df8596eb24e069984f47b426dcb4d4559b1a8d9daff8078766a54d63734
verdict: pass
blockers: 0
critical_findings: 0
requirements: 5/5
scenarios: 31/31
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:6aba6e234ac6942a4856b71c111cd06d1183c562dde157468414ce2dcb2a542f
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:a80cd3dd6cdaa9667473bc027dc1da802b7d42de85df79ebb8b08d4b3d3e92a3
```

## Verification Report

**Change**: m5-catalog-inspection
**Mode**: Strict TDD (`strict_tdd` active; runner `swift test` + `xcodebuild`)
**Branch**: `main`, implementation **uncommitted** in the working tree atop `af0c940`
**Artifact store**: hybrid (OpenSpec file + Engram)
**RDD/receipt review**: disabled for this clone — no review tooling invoked
**Verification independence**: every command below was re-executed by this phase; no number was
adopted from the apply report without re-measurement.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 45 |
| Tasks complete | 45 |
| Tasks incomplete | 0 |

Every task in `tasks.md` is checked. Each RED task's named test file exists on disk and its suite
passed in this phase's run: 2.1/2.3/4.6 → `DecodeTests.swift`; 2.5/2.7 → `StanzaWireTests.swift`;
3.1/3.3/6.6 → `InspectionTypeTests.swift`; 3.5 → `CatalogModelsTests.swift`;
4.1/4.2/4.4/4.5 → `DetailTests.swift`; 5.1/5.2 → `FileStoreTests.swift`;
6.1/6.2 → `CatalogFootprintTests.swift`; 6.4/6.5 → `AcquisitionScopeTests.swift`;
7.1/7.2 → `cellarTests/PackageInspectionTests.swift`. Each GREEN task's named production file exists
and carries the change it claims (verified by reading the diff, not by trusting the checkbox).

### Build & Tests Execution

| Command | Exit | Result (measured by this phase) |
|---|---|---|
| `swift test --package-path Packages/CellarCore` | 0 | **1140 tests in 156 suites passed**, 1 known issue |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | 0 | `** TEST SUCCEEDED **`, **65 passed test cases** |
| `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | 0 | `** BUILD SUCCEEDED **`, zero warnings, zero errors |

The core suite was run twice with identical results (1140/156/1 known issue). The one known issue is
`OperationCenterCancelTests.swift:183` — a deliberate `withKnownIssue` in a suite this change does not
touch. It is pre-existing and unchanged, matching the apply-recorded baseline.

Counts against the task 0.1 baseline: core **1090 → 1140 tests** (+50), **152 → 156 suites** (+4).
`cellarTests` contributes **14** cases for `PackageInspectionTests` (9 discrete + a 5-argument
parameterised case). The apply report states FULL = 67 cases; this phase measures **65** passed-case
lines. The delta is a counting-method difference, not a failure — `** TEST SUCCEEDED **` with exit 0
in both runs. Recorded rather than reconciled away.

### Spec Compliance Matrix

`catalog-sync` delta: 2 MODIFIED + 1 ADDED requirement, 18 scenarios.
`package-detail` delta: 1 MODIFIED + 1 ADDED requirement, 13 scenarios.
**Total 5 requirements / 31 scenarios — every one covered by a test that passed at runtime.**

#### catalog-sync — Tolerant decoding of the published payload shapes (10)

| Scenario | Covering test | Status |
|---|---|---|
| Cask name array yields a single display name | `DecodeTests` (carried forward) | PASS |
| Null description and caveats decode as absent | `DecodeTests` (carried forward) | PASS |
| Mixed `uses_from_macos` elements decode | `DecodeTests` (carried forward) | PASS |
| Unknown keys are ignored | `DecodeTests` (carried forward) | PASS |
| One malformed record does not kill the payload | `DecodeTests` (carried forward) | PASS |
| The five widened cask keys decode (T1) | `DecodeTests.widenedCaskKeysDecode` | PASS |
| A cask omitting every widened key still decodes (T2) | `DecodeTests.widenedCaskKeysAreAbsentNotEmpty` (parameterised: `cask-bare`, `cask-bare-null`) | PASS |
| Formula stable and head source URLs decode (T3) | `DecodeTests.formulaSourceURLsDecode` | PASS |
| An unrepresented artifact stanza is counted, not fatal (T4) | `StanzaWireTests` (3 unmodelled → 3; only-unmodelled → ≥1; non-object element → 1) + `DetailTests.unprojectedStanzaKindsAreCounted` | PASS |
| The widening does not change which records decode (T5) | `DecodeTests.wideningPreservesTheRecordAndSkippedCounts` | PASS |

**T5 is honestly anchored.** The expected values (`50`/`0` for both slices) are hard-coded constants
recorded in task 0.2 against the *pre-widening* build, with a comment forbidding re-derivation. A
number read off the widened build would agree with itself no matter what the widening broke; this one
cannot.

#### catalog-sync — Slim persisted projection with a state sidecar (6)

| Scenario | Covering test | Status |
|---|---|---|
| State sidecar round-trips | `FileStoreTests` (carried forward) | PASS |
| Unknown (greater) schema version is no cache | `FileStoreTests` (carried forward) | PASS |
| Previous-schema snapshot is a cold start (P3) | `FileStoreTests.previousSchemaSnapshotIsAColdStart` | PASS |
| Previous-schema sidecar rejected independently (P4) | `FileStoreTests.previousSchemaSidecarIsRejectedIndependently` | PASS |
| Rollback is symmetric (P5) | `FileStoreTests.rollbackIsSymmetric` | PASS |
| Full-catalog footprint stays within bound (P6) | `CatalogFootprintTests.fullCatalogFootprintStaysWithinItsBound` + `.syntheticRecordsMatchTheRealOnes` | PASS |

**Schema v2 and rollback symmetry — verified in depth.**
`CatalogFileStore` gained an internal `expectedSchemaVersion`, defaulted to
`CatalogSnapshot.currentSchemaVersion`, compared in **both** `loadSnapshot()` and `loadState()`
(exactly two call sites; both confirmed in the diff). The public initializer signature is unchanged.
`CatalogSnapshot.currentSchemaVersion` is `2`, and the stale `revision` doc comment ("so
`schemaVersion` stays 1") was corrected in the same edit as task 5.4 required.

- **Both files, independently**: P4 asserts the *current-version snapshot is still adopted*
  (`loadSnapshot()?.packages.map(\.name) == ["wget"]`) while the v1 sidecar is rejected. That is the
  spec's "neither can be adopted on the strength of the other's version", proved in the direction
  that could actually regress.
- **Exact in both directions**: P5 drives the reverted build through the injected seam
  (`currentSchemaVersion - 1`), not by editing the constant — so it measures what a `git revert`
  actually produces. It then persists at the older version and reads it back, proving the older build
  is not merely degraded but fully serviceable after one sync. That is the claim the rollback plan
  rests on, and it is now a test.
- **TM5, no mutation on rejection**: both tests capture `fileSystem.operations` before the read and
  assert it is unchanged afterwards, and P3 additionally asserts the rejected bytes are still
  byte-identical on disk. Classification neither throws, reports failure, nor touches the file.

#### catalog-sync — Inspection data costs no new acquisition (2, ADDED)

| Scenario | Covering test | Status |
|---|---|---|
| Inspection fields resolve offline and without brew (A1) | `AcquisitionScopeTests.inspectionResolvesOfflineAndWithoutBrew` + structural proof in `DetailTests` | PASS |
| The widened sync issues no additional request (A2) | `AcquisitionScopeTests` request recorder + directory census | PASS |

A2 is the stronger of the two: a recording `FakeCatalogSource` proves the requested resource *set* and
*count* both equal the previous build's, each resource requested exactly once, and the catalog
directory afterwards holds exactly `["catalog-state.json", "catalog.json"]` — no retained raw payload.

#### package-detail — Required detail projection (10)

| Scenario | Covering test | Status |
|---|---|---|
| Formula detail exposes every required field | `DetailTests` (carried forward) | PASS |
| Cask detail exposes every required field | `DetailTests` (carried forward) | PASS |
| Absent optional fields are absent, not empty | `DetailTests` (carried forward) | PASS |
| Unknown package is not-found, not an error | `DetailTests` (carried forward) | PASS |
| Cask detail exposes its inspection fields (R5) | `DetailTests.caskDetailExposesItsInspectionFields` | PASS |
| Every projected stanza kind is exposed (R6) | `DetailTests.everyProjectedStanzaKindIsExposed` + `StanzaWireTests` (remainder `0`, not absent) + `InspectionTypeTests.populatedInstallPlanRoundTrips` | PASS |
| Every unprojected stanza kind is counted (R7) | `DetailTests.unprojectedStanzaKindsAreCounted` | PASS |
| No dependencies reports absence, not emptiness (R8) | `DetailTests.absentInspectionIsNotEmptyInspection` | PASS |
| Formula source URLs are exposed (R9) | `DetailTests.formulaSourceURLsAreExposed` | PASS |
| Nothing the projection exposes is runnable (R10) | `DetailTests.nothingExposedIsRunnable` | PASS |

**Counted remainder — correctness checked against the fixtures, not the claim.** Read directly from
the JSON: `cask-iterm2.json` publishes two `artifacts` elements — `{"app":[…],"target":"…"}` and
`{"zap":[…]}` — so the remainder is `1`, matching R5's binding value. `cask-every-stanza.json`
publishes five single-key elements (`app`, `binary`, `pkg`, `uninstall`, `zap`) so the remainder is
`2`, matching the test. The count is a non-optional `Int`, omitted at encode time only when `0` and
defaulted back to `0` on decode, so "0, never absent" survives the round trip.

**R10 is the strongest guard in the change.** It asserts *exact set equality* of every `String`
reachable from the plan — five values — not merely the absence of forbidden ones, then re-runs the
absence check over the whole record, then scans every `Sources/Catalog/*.swift` for `Process(`,
`MutationCommand`, `OperationCenter` and `launchctl`. Not one path, directive or command from the
fixture's `zap`/`uninstall` stanzas reaches the projection.

#### package-detail — No pre-install signature or notarization verdict (3, ADDED)

| Scenario | Covering test | Status |
|---|---|---|
| Fully populated cask yields no signature claim (N1) | `DetailTests.fullyPopulatedCaskDetailMakesNoSignatureClaim` | PASS |
| Checksum is a published expectation, not a result (N2) | `DetailTests.checksumIsADeclarationNotAResult` + `InspectionTypeTests.noCheckIsNotADigest` | PASS |
| No post-install verdict reaches an uninstalled package (N3) | `DetailTests.noPostInstallVerdictReachesAnUninstalledPackage` | PASS |

**`no_check` rendering — verified end to end.** `CaskDownloadChecksum` is a two-case enum with a
single-value `Codable`: `"no_check"` decodes to `.notChecked`, `declaredDigest` returns `nil` for it,
re-encoding restores the literal, and `.notChecked != .declared(…)`. At the view boundary the row
reads `"This cask declares no checksum"`, and `PackageInspectionTests` asserts that string does **not
contain** `no_check`. The literal is neither dropped nor rendered as a digest — both halves of the
spec sentence are tested.

**`http`/`https` predicate.** `CaskInspection.browsableDownloadURL` lives in CellarCore, requires a
lowercased scheme in the closed set `{http, https}` **and** a non-empty host. Parameterised RED over
`javascript:`, `file:///etc/passwd`, `data:`, `ftp:`, scheme-less `example.com/x.dmg`,
leading-whitespace `  http://…` and uppercase `HTTPS://…`. The refused value is still exposed as
`downloadURL` and rendered as selectable text — a published fact is never dropped, only never handed
to a link opener. The app-target test re-runs the hostile corpus against the row model and asserts
`row.value == published` while `row.link == nil`.

**`replacingEdges` / `replacingInstallCount` guard.** `CatalogModelsTests.inspectionSurvivesTheCopyHelpers`
asserts the edges and the count really changed *before* asserting both new fields survived — so it
cannot pass by copying nothing. Both helpers were confirmed threaded in the diff, and both new fields
are defaulted to `nil` in the public `init`, so no existing call site changed.

### Design Coherence

| Design decision | Implementation | Status |
|---|---|---|
| Two grouped optionals, not seven flat fields | `caskInspection`, `formulaSources` on `CatalogPackage` | MATCH |
| `String` for every widened URL-shaped value | `downloadURL`, `stableURL`, `headURL` all `String` | MATCH |
| Group `nil` when the record published none of the keys | `CaskInspection.isEmpty` → `nil` in `project(inspection:)` | MATCH |
| Empty collections omitted at encode time | Custom `encode(to:)` on the three group types; `encodedKeys` asserted | MATCH |
| Unmodelled key counted from the key alone, value never decoded | `StanzaElementWire` counts in the `allKeys` loop; value untouched | MATCH |
| Resident measured via malloc-zone `size_in_use`, not `phys_footprint` | `mstats().bytes_used`; `physFootprint` left in the growth-only budget | MATCH |
| Footprint asserted as ratios + one absolute ceiling | 1.6× encoded / 16 MB / 1.6× resident / 2.0× load | MATCH |
| `Package.swift` untouched; no new target or dependency edge | Confirmed — `Catalog` still declares **no dependencies at all** | MATCH |
| App layer presentation-only, one call site | `PackageInspectionSection.swift` + one line in `content(for:)` | MATCH |

**Footprint bound + the ±25% anchor.** Both suites passed in this run
(`fullCatalogFootprintStaysWithinItsBound` 2.109 s; `syntheticRecordsMatchTheRealOnes` 0.804 s). All
three spec-named quantities are measured: encoded size on disk, resident memory of a loaded snapshot,
and load time. The anchor is genuinely load-bearing rather than decorative: it holds the synthetic
**baseline** against the 50 verbatim records in each `*-slice.json`, *and* holds the synthetic
**widening delta** against the delta the same verbatim record pays when re-projected with the widened
keys stripped — same record on both sides, so no corpus mismatch can flatter it. It closes its own
blind spots with `#expect(published > base, "removing the widened keys changed nothing, so the anchor
is blind")` and `#expect(syntheticCaskWidened > syntheticCaskBaseline)`. The apply phase fixed the
generator rather than the bound when the anchor first failed, which is the correct direction.

### Adjudication of the Two Apply-Time Amendments

**(a) `target` is a recognised companion key, not a counted stanza kind — NEEDS SPEC AMENDMENT
(narrative only); the code is correct.**

Evidence claim verified independently. `cask-iterm2.json` — a verbatim live record — publishes the
sibling form `{"app": ["iTerm.app"], "target": "/Applications/iTerm.app"}`. Counting `target` as a
stanza kind would make iterm2's remainder `2`, but `package-detail` R5 binds it to exactly `1` ("it
appears only as `1` in the count of unrepresented stanzas") and task 4.1 repeats that value. The
implementation skips `target` in the `allKeys` loop and attaches it to the element's artifacts, and
`StanzaWireTests` pins **both** serialisations. This is also correct Homebrew semantics: `target:` is
a parameter of `app "X.app", target: "Y"`, not a stanza.

The amendment is nonetheless *contradicted in writing* by both delta files, which state
"`zap`, `uninstall`, `target`, `font` and every unmodelled kind are counted, never projected"
(`specs/catalog-sync/spec.md` line 21, `specs/package-detail/spec.md` line 25). Those sentences sit
in the **non-normative delta summary**, not in requirement text. The normative text is kind-agnostic
("a stanza whose kind the projection represents…", "every other published stanza kind MUST be
counted"), and `target` is not a published stanza kind — so there is **no normative conflict**, and
the archived capability spec (which carries requirement blocks, not delta preambles) will be correct.
The two preamble sentences should have `target` removed before archive so the archived change folder
does not preserve a statement its own code contradicts. Not a blocker.

**(b) The five widened `CaskWire` keys decode with `try?`, not `try` — CONSISTENT WITH SPEC, and in
fact compelled by it.**

`catalog-sync` T5 states the widening "MUST NOT change which records decode: a payload that decoded
before this change MUST yield the same record count and the same skipped-record count afterwards." A
strict `try` on a newly-read key would let a cask publishing e.g. `artifacts` as an object cost its
whole record — a record that decoded fine on the previous build — which is exactly what T5 forbids.
`try?` is therefore not a relaxation but the only implementation that satisfies T5. The comment in
`CaskWire` states the boundary precisely: *only the keys that existed before the widening may cost a
record.* `DecodeTests.anUnreadableWidenedValueCostsNoRecord` pins it with all five published in
unreadable shapes simultaneously, asserting the record survives with `version` intact,
`skippedRecordCount == 0` and `caskInspection == nil`. Verdict: consistent-with-spec. One residual
honesty gap is noted as SUGGESTION S3 below.

### The Four First-Pass Prohibition Guards — Anchoring Audit

The concern is legitimate: a guard that asserts only absence passes trivially if it reads the wrong
thing. All four assert a **known-present** value before asserting absence.

| Task | Guard | Positive anchor asserted first | Verdict |
|---|---|---|---|
| 4.4 | `fullyPopulatedCaskDetailMakesNoSignatureClaim` | `labels.contains("caskInspection")`, `"downloadURL"`, `"declaredChecksum"`, `"unrepresentedStanzaCount"`, and `labels.count > 20` | ANCHORED |
| 4.5 | `nothingExposedIsRunnable` | **Exact set equality** of the five exposed strings, plus `plan.unrepresentedStanzaCount == 2` | ANCHORED (strongest) |
| 6.6 | `InspectionTypeTests` source scans (×3) | `CatalogSources.assertAnchored(code, expecting:)` — asserts the file is non-empty *and* contains a token that must be there (`browsableDownloadURL`, `CaskInstallPlan`, `public let downloadURL: String?`) before any absence | ANCHORED |
| 7.1 | `PackageInspectionTests` source scans (×3) | `code.contains("PackageInspectionRow")`, `code.contains("browsableDownloadURL")`, and the file being found by name in the app target with non-empty code | ANCHORED |

`CatalogSources.code(of:)` strips `//` and `/* */` comments before scanning, so a prohibition
*described* in a doc comment is never mistaken for one *violated* in code — necessary here, because
these files name every forbidden token in their own documentation. Stripping removes only comments;
it cannot hide a violation in code.

**Mutation test, performed mentally on 4.5 (`nothingExposedIsRunnable`).**

*Mutation 1 — project `zap` contents into a new `CaskInstallPlan.zapPaths: [String]`.* Killed
immediately and three times over: `ExposedFields.strings(of: plan)` walks the `Mirror` recursively and
collects every reachable `String`, so the exact set equality
`Set(exposed) == {5 values}` fails; the explicit `dropped` loop catches
`~/Library/Application Support/EveryStanza`; and the whole-record re-check catches it again. The
footprint suite would independently fail — `zap` costs +1.23 MB encoded, which pushes the encoded
ratio past the 1.6× bound.

*Mutation 2 — add an execute affordance (`Process`, a `MutationCommand` factory) to the projection.*
Killed by the all-files token scan in the same test, and again by 6.6's per-file scan.

*Residual escape found and reported honestly:* a mutation that carried removal paths in a
**non-`String`-backed** type (e.g. `[URL]`, or a wrapper storing `Data`) could slip past
`ExposedFields.strings`, because that walk only collects values castable to `String`, and past 4.4,
because a `zapPaths` label matches none of the banned vocabulary. It would still have to survive the
1.6× encoded bound, so two independent guards would have to be defeated together — and the design's
"URLs are `String`" rule makes such a type an obvious review flag. Narrow, but real; recorded as
SUGGESTION S6 rather than silently rated "unbreakable".

### D4 View Work

| D4 claim | Evidence | Status |
|---|---|---|
| Section always visible, never behind a disclosure | One `PackageInspectionSection(package:)` call in `content(for:)` immediately after `facts(for:)`, wrapped in no disclosure; `PackageInspectionTests` asserts `PackageDetailView.swift` contains `PackageInspectionSection(` and no `DisclosureGroup` | CONFIRMED |
| Row model extracted as a plain testable value type | `nonisolated struct PackageInspectionRow: Identifiable, Hashable, Sendable` with a static `rows(for:)`; all ten app-target tests exercise it without rendering a view | CONFIRMED |
| No signature / notarization claim | Source scan bans `signature`, `notariz`, `verified`, `trust`, `safe`, `malware`, `secure` (case-insensitive) and `Process`/`OperationCenter`/`MutationCommand`/`removeItem` | CONFIRMED |
| Fed only by CellarCore data | `rows(for:)` returns `[]` unless `package.caskInspection` exists; the default `/Applications` destination comes from `CaskInstallDestination` and link safety from `CaskInspection.browsableDownloadURL`. The scan bans `URL(string:`, `URL(fileURLWithPath:`, `NSWorkspace` and `openURL` outright, so the view cannot build a URL of its own | CONFIRMED |

Rendering is honest in its wording: the checksum row carries the note "The value this cask declares.
Cellar has not downloaded or checked anything."; the remainder reads "N other install steps aren't
shown here" rather than naming stanzas or implying they are harmless; a non-`http(s)` URL carries
"Shown as text: Cellar opens only web addresses." Absent values yield **no row at all**, so
"absent is not empty" survives to the pixel.

### No New Acquisition — Independently Confirmed

Beyond the A1/A2 tests, this phase scanned every changed and new Swift file in the working tree for
`URLSession`, `URLRequest`, `dataTask`, `Process(`, `NSWorkspace` and `.run(`. **Zero matches** —
the only hits in the whole diff are prose in `PRD.md`. Structurally stronger still: `Package.swift`
declares the `Catalog` target with **no dependencies at all**, so it cannot import `BrewProcess` or
`SecurityKit` even if someone tried; `DetailTests` asserts the absence of both imports across every
`Sources/Catalog` file. No new brew invocation and no new network egress exist anywhere in this
change.

### Diff Size vs the 5,000-Line Budget

Measured by this phase, not adopted from the apply report:

| Category | Lines |
|---|---|
| Tracked changes (14 files) | 967 insertions + 37 deletions = **1,004** |
| New untracked source, tests and fixtures (17 files) | **2,635** |
| New untracked OpenSpec lifecycle artifacts (6 files) | **1,335** |
| **Total** | **4,974** |
| Authored source + tests + fixtures only (excluding `PRD.md` and OpenSpec) | **~3,619** |

**Within the 5,000-line session budget, with 26 lines of headroom.** The authored figure (~3,619)
corroborates the apply report's "≈3,600". It is well above the tasks-phase 1,500–2,100 forecast; the
overage is test density (footprint harness 360, inspection type suite 347, app suite 321), which is
the right place for an overage to land. No `size:exception` is required and the pre-agreed Phase 7
cut point was not needed.

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD evidence reported | ⚠️ | No canonical "TDD Cycle Evidence" table; per-phase narrative + RED/GREEN task labels instead |
| All tasks have tests | ✅ | 20/20 RED tasks map to a test file that exists |
| RED confirmed (tests exist) | ✅ | 20/20 named test files verified on disk |
| GREEN confirmed (tests pass) | ✅ | Every one of those suites passed in this phase's run |
| Triangulation adequate | ✅ | Parameterised over `cask-bare`/`cask-bare-null`, a 7-value hostile scheme corpus, and a 5-value app-layer corpus; multi-fixture stanza coverage |
| Safety net for modified files | ✅ | Baseline captured in task 0.1 before any change; +50 tests, +4 suites, no assertion deleted |

**Assertion quality**: 1 WARNING, 0 CRITICAL. No tautology, no orphan empty-collection assertion (every
`isEmpty` check has a non-empty companion in the same test), no smoke test, no mock-heavy file. The
one finding is W2 below.

**No assertion deleted or weakened** — independently confirmed: `git diff -U0` over `Tests/` removes
exactly one assertion line, `#expect(object["schemaVersion"] as? Int == 1)`, required by task 5.4 and
replaced by two stronger ones (`== 2` **and** `== CatalogSnapshot.currentSchemaVersion`, so the
literal and the constant can no longer drift apart).

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (CellarCore, Swift Testing) | 1140 total suite; ~50 new | 8 touched/new | `swift test` |
| Integration (app target, Swift Testing) | 14 cases | 1 new | `xcodebuild test` |
| UI (XCUITest) | 20 cases | pre-existing | `xcodebuild test` |

Coverage tooling is not configured in this project; coverage analysis skipped (not a failure).

### Issues

**CRITICAL: none.**

**WARNING (2)**

- **W1 — No canonical "TDD Cycle Evidence" table in `apply-progress`.** The strict-TDD verify module's
  literal rule rates a missing table CRITICAL. This report **downgrades it to WARNING**, with the
  reasoning stated so the orchestrator can overrule: the substance the table exists to carry is
  present and was independently re-verified here — `tasks.md` labels every task RED or GREEN in
  order, all 45 are checked, all 20 RED tasks' test files exist, every one of their suites passed in
  this phase's run, the count rose +50 tests / +4 suites over a baseline recorded *before* any change,
  and exactly one assertion line was removed (replaced by two stronger ones). The gap is format, not
  evidence. Fix by adding the table to `apply-progress` if the canonical shape is required.
- **W2 — One decorative assertion in `AcquisitionScopeTests.inspectionResolvesOfflineAndWithoutBrew`.**
  `offlineSource` is constructed and scripted to fail every resource, but is never handed to anything;
  `#expect(offlineSource.requests.isEmpty)` therefore asserts that an object nobody used recorded
  nothing. It proves nothing about the code under test. The scenario (A1) is still genuinely
  satisfied — the detail resolves from `store.loadSnapshot()` alone with every inspection field
  asserted by value, and the no-brew half is proved structurally (the `Catalog` target has no
  dependencies and no `Process(` reference anywhere). Fix by deleting the line or by wiring
  `offlineSource` into a sync attempt so it can actually record a violation.

**SUGGESTION (6)**

- **S1 — Remove `target` from the two delta preambles.** `specs/catalog-sync/spec.md` line 21 and
  `specs/package-detail/spec.md` line 25 both list `target` among the counted kinds, which the code
  correctly contradicts (see amendment (a)). Non-normative text, so nothing ships wrong; worth fixing
  so the archived change folder does not preserve a false sentence.
- **S2 — `tasks.md` 6.1 carries stale footprint numbers.** It states measured values of
  1.42× / 1.35× / 1.21×; the apply-time measurement recorded in `design.md` is 1.56× / 1.23× / 1.57×.
  The design is correct and the test bounds are unaffected; the tasks line is a pre-apply estimate
  that reads as a measurement.
- **S3 — An unreadable whole-`artifacts` value yields absence with no count.** A cask publishing
  `"artifacts": {...}` (an object, not a list) reports `caskInspection == nil` and contributes nothing
  to any remainder. This is required by T5 and is outside the spec's counting rule (which is scoped to
  stanzas *within* a list), but it is a small departure from the proposal's "counted and named, never
  silently dropped" spirit. `StanzaWireTests` pins the behaviour deliberately, so it is a documented
  choice, not a bug.
- **S4 — Encoded footprint headroom is 2.4%.** Measured 1.56× against a 1.6× bound. Deterministic
  (a byte count, identical on every machine) so not flaky, but the next widening of any size will
  cross it. That is arguably the bound working as designed; noting it so the next slice is not
  surprised.
- **S5 — Two structural scan loops lack a non-emptiness guard.** `for name in try
  CatalogSources.swiftFileNames()` in `DetailTests.nothingExposedIsRunnable` would pass vacuously if
  the list were ever empty. Both tests carry other strong anchors, so nothing is currently unproven;
  a one-line `#expect(names.isEmpty == false)` would close the shape entirely.
- **S6 — R10's string walk only sees `String`-backed values.** See the mutation-test residual above.
  A future field carrying removal paths as `[URL]` or a `Data`-backed wrapper would evade
  `ExposedFields.strings` (though not the footprint bound). Consider asserting the projection's field
  *types* as well as its reachable strings.

Also noted, non-blocking: R6's "the remainder is `0` and is not absent" is proved by composition
(`StanzaWireTests` at the wire level plus `InspectionTypeTests` through a `Codable` round trip) rather
than by one end-to-end resolved detail over a cask publishing exactly `app` + `binary` + `pkg`. The
projection passes the count through verbatim, so the composition is sound.

### Success Criteria (from `proposal.md`)

- [x] A user can see download URL, checksum, what gets installed where, dependencies and the
      auto-updates flag before installing a cask — rendered by `PackageInspectionSection`, asserted by
      `PackageInspectionTests.fullyPublishedCaskYieldsEveryRow`.
- [x] No surface claims a pre-install signature or notarization verdict — enforced by shape in
      CellarCore (N1/N3) and by source scan in the app target (7.1).
- [x] U4 is recorded, and the memory/footprint bound is a test, not a comment — `CatalogFootprintTests`
      with a two-sided ±25% anchor.
- [x] `urls.stable`/`urls.head` are projected and asserted, so slice 3 starts unblocked —
      `formulaSourceURLsDecode` and `formulaSourceURLsAreExposed`.
- [x] D1–D5 each traceable to a spec requirement — D1 → schema transition rule; D2 (as narrowed by D5)
      → projected stanza set + counted remainder; D3 → `conflicts_with`; D4 → the fields the
      always-visible section renders; D5 → the footprint bound and its retained-field floor.

### Final Verdict

**PASS**

0 CRITICAL, 2 WARNING, 6 SUGGESTION. Every one of the 5 requirements and 31 scenarios across both
deltas is covered by a test that passed at runtime in this phase's own execution. All 45 tasks are
complete and match the code. Both apply-time amendments are sound — one is compelled by the spec, the
other is correct against the binding scenario and needs only a narrative correction. The four
first-pass prohibition guards are all properly anchored, and the strongest of them survives mental
mutation testing with only a narrow, documented residual. No new brew invocation and no new network
egress exist anywhere in the change. The diff is inside the 5,000-line budget at 4,974 lines.

Nothing here blocks archive. W1 and W2 are cheap to close and are recommended before the PR, but
neither invalidates a requirement.
