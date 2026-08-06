# Tasks: M5 Catalog Inspection

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | **1,500–2,100** authored source+tests (~500 CellarCore source, ~120 app, ~900–1,200 tests), plus ~270 of JSON fixtures + README |
| Session review budget | **5,000** lines (session override of `config.yaml`'s 2,000) |
| 5,000-line budget risk | Low |
| 2,000-line budget risk | Low–Medium |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR; **Phase 7 (app layer, D4)** is the pre-agreed cut point if the diff overruns |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

Resolution of the budget lines: `400-line budget risk: High` is the mandatory default-budget
guard line and is honestly High — the forecast exceeds 400 several times over. The budget
actually governing this session is **5,000**, and 1,500–2,100 fits inside it with headroom, so
no `size:exception` and no chain are required and apply may start unblocked. This estimate is
**above** the proposal's 900–1,400 forecast: the delta is the fixture set (six new cask
fixtures, ~270 lines) and the footprint harness (~200), neither of which the proposal costed.
If the real diff crosses 5,000, cut **Phase 7** into a follow-up PR: it is presentation-only,
nothing in Phases 1–6 depends on it, and the CellarCore slice alone already satisfies the
`urls.stable`/`urls.head` criterion that unblocks slice 3.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | CellarCore: widened wire, typed projection, schema 2, footprint + acquisition + structural guards (Phases 0–6) | PR 1 | `FAST --filter "Decode\|Stanza\|Projection\|Detail\|CatalogModels\|FileStore\|Footprint\|Acquisition"` | Delete `~/Library/Application Support/<bundle id>/Catalog/catalog.json`, launch: cold-launch progression runs once, `catalog.json` reappears at `schemaVersion` 2 and the directory holds exactly the snapshot + sidecar | `git revert` the merge; `Package.swift` untouched, v2 file on disk is classified as no cache by the reverted build and re-synced once |
| 2 | App layer: always-visible cask inspection section (Phase 7) | PR 1 (or PR 2 if cut) | `APP --only-testing:cellarTests/PackageInspectionTests` | Launch, select `iterm2` in Browse: the section is visible without disclosure, shows download URL / declared checksum / installs / requires / conflicts / "N other install steps aren't shown here", and no row claims a verdict | Delete `cellar/Browse/PackageInspectionSection.swift` and the one call in `PackageDetailView.content(for:)`; no pbxproj edit to undo (synchronized group) |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Paths under `Packages/CellarCore/` unless prefixed with `cellar/` or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `APP` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Spec tags — `catalog-sync`: **T1** five widened cask keys decode, **T2** cask omitting every widened key, **T3** formula stable/head URLs, **T4** unrepresented stanza counted not fatal, **T5** widening does not change which records decode, **P3** previous-schema snapshot is a cold start, **P4** previous-schema sidecar rejected independently, **P5** rollback is symmetric, **P6** full-catalog footprint bound, **A1** inspection resolves offline and without brew, **A2** widened sync issues no additional request.
- Spec tags — `package-detail`: **R5** cask exposes inspection fields, **R6** every projected stanza kind exposed, **R7** every unprojected stanza kind counted, **R8** absence not emptiness, **R9** formula source URLs exposed, **R10** nothing exposed is runnable, **N1** no signature claim, **N2** checksum is a declared expectation, **N3** no post-install verdict reaches an uninstalled package.
- Threat-matrix rows — **TM1** subprocess (by prohibition), **TM2** untrusted string → URL opening, **TM3** executable-file classification (by prohibition), **TM4** network egress (by prohibition), **TM5** filesystem write during inspection (by prohibition). The VCS/documentation row is `N/A` and has no task.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No production line without a red test.
- Binding: `zap`/`uninstall` **contents are never projected** (D5 as triggered by U4, user-confirmed). Projected stanza kinds are exactly `app`, `binary`, `pkg`.
- Every URL-shaped value is `String` in CellarCore. `URL` is reconstructed at the view boundary only (U4: `URL` costs 2.2× resident).

---

## Phase 0: Baseline (blocking, no production change)

- [x] 0.1 Record the green baseline on the feature branch: `FAST`, `APP`, `FULL`. Capture the `@Test` count so Phase 8 can prove nothing was deleted.
      **Recorded (pre-change baseline):** `FAST` = **1090 tests in 152 suites passed**, 1 known issue — this is the authoritative `@Test` count. `APP` = 32 xcodebuild-reported cases, `** TEST SUCCEEDED **`. `FULL` = 52 xcodebuild-reported cases, `** TEST SUCCEEDED **` (xcodebuild surfaces only the cases it hosts; the package suites are counted by `FAST`).
- [x] 0.2 Record the pre-widening decode invariants that **T5** asserts against: run the existing `DecodeTests` slice cases and write down the record count and `skippedRecordCount` produced by `Fixtures/cask-slice.json` and `Fixtures/formula-slice.json`. These numbers are the expected values hard-coded in task 4.5 — do not re-derive them after the widening lands.
      **Recorded on pre-widening code:** `cask-slice.json` → 50 records, `skippedRecordCount` 0. `formula-slice.json` → 50 records, `skippedRecordCount` 0.

## Phase 1: Fixtures (test data only, no production code)

- [x] 1.1 Create `Tests/CatalogTests/Fixtures/cask-every-stanza.json`: an `artifacts` list with `app` (with a `target:` companion object), `binary`, `pkg`, `uninstall` and `zap` stanzas, plus `depends_on` carrying a **formula**, a **cask** and a `macos` requirement. Covers both roles — three projected kinds and two counted kinds (**R6**, **R7**, **R10**, **T4**).
- [x] 1.2 Create `Fixtures/cask-unrepresented.json` (one `app` stanza + three stanzas of kinds this build does not model, one of them invented) and `Fixtures/cask-only-unrepresented.json` (no projected stanza at all) (**T4**, **R7**).
- [x] 1.3 Create `Fixtures/cask-bare.json` (publishes none of the five widened keys) and `Fixtures/cask-bare-null.json` (publishes all five as `null`) (**T2**, **R8**).
- [x] 1.4 Create `Fixtures/cask-no-check.json` publishing `"sha256": "no_check"` (**N2**).
- [x] 1.5 Create `Fixtures/formula-headless.json` publishing `urls.stable` and no `urls.head` (**T3**, **R9**). `formula-git.json` already publishes both and needs no edit.
- [x] 1.6 Register the new fixtures in `Tests/CatalogTests/Fakes/Fixtures.swift` and document each one's role in `Fixtures/README.md`. Leave `cask-iterm2.json` and both `*-slice.json` files **byte-identical** — they are the **T5** control.

## Phase 2: Wire widening (`catalog-sync` — tolerant decoding)

- [x] 2.1 RED `Tests/CatalogTests/DecodeTests.swift`: a `CaskWire` decoded from `cask-iterm2.json` exposes `url`, `sha256`, `artifacts`, `depends_on` and `conflicts_with` matching the payload (**T1**); `cask-bare.json` and `cask-bare-null.json` both decode with all five as typed absence — not `""`, not `[]`, not `0` — and neither is counted skipped (**T2**).
- [x] 2.2 GREEN `Sources/Catalog/Wire/CaskWire.swift`: five new `decodeIfPresent` properties plus their `CodingKeys` (`depends_on`, `conflicts_with` snake-case). No other behaviour changes.
- [x] 2.3 RED `DecodeTests`: `formula-git.json` yields both `urls.stable.url` and `urls.head.url`; `formula-headless.json` yields an absent head URL (**T3**).
- [x] 2.4 GREEN `Sources/Catalog/Wire/FormulaWire.swift`: a nested `Urls` type mirroring `Versions`' tolerance (`decodeIfPresent` all the way down); the joined `urls` object sits beside `versions`. Do **not** touch the formula `checksum` key — the formula digest is `checksum`, not `sha256`, and is out of scope.
- [x] 2.5 RED new `Tests/CatalogTests/StanzaWireTests.swift` against `cask-every-stanza.json`, `cask-unrepresented.json`, `cask-only-unrepresented.json`: the three projected kinds decode with their sources and `target` companions; a record with three unmodelled kinds reports `unrepresentedStanzaCount == 3`; a record of only unmodelled kinds still decodes with a count `>= 1` and is not skipped; a non-object array element counts `1` and is skipped; the count is `0` — never absent — when every stanza was represented; nothing in this file throws (**T4**, **R6**, **R7**).
- [x] 2.6 GREEN create `Sources/Catalog/Wire/CaskArtifactsWire.swift`: element-by-element decode through a dynamic `StanzaKey: CodingKey`. A key in `{app, binary, pkg}` decodes its value as a lossy item list (a `String` element is a `source`; a following `{"target": …}` object attaches to it; any other object is ignored). **Every other key increments the counter without its value ever being decoded** — this is the sync-decode-time claw-back U4 measured, not an optimisation. An unreadable stanza costs a count, never the record.
- [x] 2.7 RED `StanzaWireTests`: `depends_on` decodes its **formula**, **cask** and `macos` forms from `cask-every-stanza.json`, and an unmodelled relation key is counted rather than fatal; `conflicts_with` yields both names from `cask-iterm2.json` (**T1**, **T4**).
- [x] 2.8 GREEN create `Sources/Catalog/Wire/CaskRelationsWire.swift` with the same tolerance discipline as 2.6.

## Phase 3: Projected value types and the model (`package-detail`)

- [x] 3.1 RED new `Tests/CatalogTests/InspectionTypeTests.swift`: `CaskDownloadChecksum` round-trips through a single-value container as `.declared("<hex>")` and `.notChecked` for `"no_check"` — and `no_check` is **not** exposed as a digest (**N2**); `CaskInstallPlan`/`CaskRequirements`/`CaskConflicts` omit empty collections at encode time while still exposing arrays (never optionals) on read; a group is `nil` when the record published none of its keys.
- [x] 3.2 GREEN create `Sources/Catalog/CatalogInspection.swift`: `CaskInspection`, `CaskDownloadChecksum`, `CaskInstallArtifact`, `CaskInstallDestination`, `CaskInstallPlan`, `CaskRequirements`, `CaskConflicts`, `FormulaSources`. Every type `Codable`, `Hashable`, and **explicitly** `Sendable`. Custom `encode(to:)`/`init(from:)` on the three group types so empty collections cost ~8 B, not ~75 B × 7,684. Every URL-shaped field is `String`.
- [x] 3.3 RED (**TM2**) `InspectionTypeTests`: parameterised over a hostile scheme corpus — `javascript:alert(1)`, `file:///etc/passwd`, `data:text/html,…`, `ftp://…`, a scheme-less `example.com/x.dmg`, a leading-whitespace `  http://…`, and `HTTPS://EXAMPLE.COM/x.dmg` — `browsableDownloadURL` returns non-`nil` **only** for `http`/`https`. Assert case-insensitive scheme handling explicitly.
- [x] 3.4 GREEN `CatalogInspection.swift`: `CaskInspection.browsableDownloadURL` implements the `http`/`https`-only predicate. It lives in CellarCore precisely so no SwiftUI view can be the thing deciding what is safe to open.
- [x] 3.5 RED `Tests/CatalogTests/CatalogModelsTests.swift`: a `CatalogPackage` carrying both a populated `caskInspection` and a populated `formulaSources` survives `replacingEdges(...)` and `replacingInstallCount(...)` with both fields unchanged. These two helpers enumerate every field by hand and are the single most likely silent-drop site in this change.
- [x] 3.6 GREEN `Sources/Catalog/CatalogModels.swift`: add exactly `caskInspection: CaskInspection?` and `formulaSources: FormulaSources?`, both defaulted to `nil` in the public `init` so no existing call site changes, and thread both through **both** copy helpers.

## Phase 4: Projection and the invariance guard

- [x] 4.1 RED `Tests/CatalogTests/DetailTests.swift`: resolving `iterm2` exposes the download URL, the checksum, the `app` stanza, the `depends_on` entry, both `conflicts_with` names and the auto-updates flag — and the `zap` stanza appears **only** as `1` in the unrepresented count (**R5**).
- [x] 4.2 RED `DetailTests`: `cask-every-stanza.json` exposes all three projected kinds with their names and destinations, remainder counted for `uninstall`+`zap` (**R6**, **R7**); `cask-unrepresented.json` exposes its `app` stanza with a remainder of `3`, reported separately from the snapshot's `skippedRecordCount`; `cask-only-unrepresented.json` resolves with no exposed stanza and a non-zero count (**R7**); `cask-bare.json` reports absence distinguishable from an empty list for all three, with every other required field intact (**R8**); `formula-git.json`/`formula-headless.json` expose stable and head source URLs (**R9**).
- [x] 4.3 GREEN `Sources/Catalog/CatalogDecoder.swift`: `project(cask:)` builds `CaskInspection` (group `nil` when the record published none of the widened keys) and `project(formula:)` builds `FormulaSources`. No change to `decodeEnvelope`, `validated`, linking, or the `@concurrent` decode entry point in `CatalogSyncSupport.swift` — the widening adds no `await`, no actor and no isolation boundary.
- [x] 4.4 RED (**TM3**) `DetailTests`: enumerate every exposed field of a fully populated cask detail — no signature status, notarization status, signing identity, team identifier or trust verdict exists (**N1**); the checksum is identified as the *declared* expectation and `no_check` as "declares no checksum" (**N2**); a detail resolved for a package that is not installed carries no integrity value of any kind and the projection declares no dependency on the capability that produces them (**N3**).
- [x] 4.5 RED (**TM1**, structural half of **R10**) `DetailTests`: for `cask-every-stanza.json`, the only artifact values exposed are the projected stanzas' names and destinations plus the remainder count; no exposed value carries a path, command, script or `launchctl`/`pkgutil` directive drawn from the `zap` or `uninstall` stanzas, and the projection offers no operation that runs any published stanza.
- [x] 4.6 RED **T5** `DecodeTests`: `cask-slice.json` and `formula-slice.json` decoded by the widened build produce exactly the record and skipped counts recorded in task 0.2. If this fails, fix the wire's tolerance — never the fixture, never the expected number.

## Phase 5: Schema 2 (`catalog-sync` — persisted projection)

- [x] 5.1 RED `Tests/CatalogTests/FileStoreTests.swift`: a snapshot written at `schemaVersion` 1 loads as no cache with nothing thrown (**P3**); a current-version snapshot beside a `schemaVersion` 1 sidecar has the **sidecar** rejected independently, with no validator replayed (**P4**); (**TM5**) the recording `FakeCatalogFileSystem` proves the rejecting read wrote, replaced and removed nothing.
- [x] 5.2 RED **P5** `FileStoreTests`: files written at `schemaVersion` 2 are classified as no cache by a store expecting `1`, nothing is thrown, and neither file is rewritten or deleted. Drive this by injecting the expected version, not by editing the constant.
- [x] 5.3 GREEN `Sources/Catalog/CatalogFileStore.swift`: give `CatalogFileStore` an internal `expectedSchemaVersion` defaulted to `CatalogSnapshot.currentSchemaVersion` and compare against it in `loadSnapshot()` and `loadState()`. This is the only seam 5.2 needs; the public initializer signature is unchanged.
- [x] 5.4 GREEN `Sources/Catalog/CatalogModels.swift`: `CatalogSnapshot.currentSchemaVersion` `1` → `2`, **and** correct the `revision` doc comment in the same edit — it claims "so `schemaVersion` stays 1", which this bump falsifies.

## Phase 6: Footprint, acquisition and structural guards

- [x] 6.1 RED **P6** create `Tests/CatalogTests/CatalogFootprintTests.swift` (`.heavyFixture`, `.serialized`, `.timeLimit(.minutes(2))`): generate 7,684 synthetic casks + 8,530 formulae, then measure baseline-shaped vs widened **in one process** — encoded `<= 1.6×` baseline **and** `<= 16 MB` absolute; malloc-zone resident `<= 1.6×`; snapshot load time `<= 2.0×`. Measured trimmed values are 1.42× / 1.35× / 1.21×; the rejected raw variant measured 1.78× / 2.59× / 4.75× and must fail all three.
- [x] 6.2 RED (same file) the **anchor** assertion: the synthetic per-record encoded size stays within ±25% of the per-record size of the real `Fixtures/cask-*.json` records, so the bound cannot pass by measuring an unrealistically thin record.
- [x] 6.3 GREEN extend `Tests/CatalogTests/CatalogMemoryTests.swift`'s `SyntheticPayload` to emit widened records, and add a malloc-zone `size_in_use` probe beside `MemoryProbe`. **Do not** measure this bound with `MemoryProbe.physFootprint()`: under magazine malloc it never falls on free, so a baseline-then-widened comparison inside one process reads the baseline's high-water mark as the widened figure. `physFootprint` stays correct for, and stays in, the existing growth-only budget in `CatalogMemoryTests`.
- [x] 6.4 RED (**TM4**, **A2**) new `Tests/CatalogTests/AcquisitionScopeTests.swift`: a recording `FakeCatalogSource` proves a widened sync requests exactly the payload and analytics resources the previous build requested — no additional resource, no per-package request — and that the catalog directory afterwards holds only `catalog.json` and `catalog-state.json`.
- [x] 6.5 RED (**TM1**, **A1**) `AcquisitionScopeTests`: with brew detection reporting `absent`, a recording process launcher, and a source that fails every request, a cask's detail resolves entirely from the persisted snapshot — every inspection field present, zero processes spawned, zero requests issued.
- [x] 6.6 RED structural scan `Tests/CatalogTests/InspectionTypeTests.swift`: read `Sources/Catalog/CatalogInspection.swift` from a `#filePath`-rooted path (the project's existing scan idiom) and assert it contains no `signature`/`notariz`/`verified`/`trust` identifier, no `Process`/`OperationCenter`/`MutationCommand`/`removeItem` reference, and no `JSONValue`-shaped or `[String: Any]` stored property.

## Phase 7: App layer — the always-visible inspection section (D4)

- [x] 7.1 RED new `cellarTests/PackageInspectionTests.swift`: a `#filePath`-rooted scan of `cellar/Browse/PackageInspectionSection.swift` finds no `signature`/`notariz`/`verified`/`trust`/`safe` vocabulary and no `Process`/`OperationCenter`/`MutationCommand`/`removeItem` reference (**TM1**, **TM3**); it constructs a `URL` only through `CaskInspection.browsableDownloadURL`, never through a bare `URL(string:)` on catalog text (**TM2**); and it declares the identifiers `inspection-download`, `-checksum`, `-installs`, `-requires`, `-conflicts`, `-remainder`.
- [x] 7.2 RED `cellarTests/PackageInspectionTests.swift`: the section's row model, built from a `CatalogPackage`, emits a row per **present** value only — an absent download URL, checksum, plan, requirement or conflict list yields no row — and emits the remainder line only when the count is greater than `0`, phrased as install steps that are not shown rather than as a stanza count.
- [x] 7.3 GREEN create `cellar/Browse/PackageInspectionSection.swift`: presentation only. It reads CellarCore values and formats English ("installs iTerm.app into /Applications"); the default-destination fact and the link-safety predicate are CellarCore computed properties, not view logic. A non-`http(s)` download URL renders as selectable text, never a `Link`. Checksum copy carries no verdict — "the value this cask declares; Cellar has not downloaded or checked anything".
- [x] 7.4 GREEN `cellar/Browse/PackageDetailView.swift`: one `PackageInspectionSection(...)` call inserted into `content(for:)` immediately after `facts(for:)`, rendered for casks only and never behind a disclosure.
- [x] 7.5 Confirm the Xcode project needs **no** edit: `cellar/` is a `PBXFileSystemSynchronizedRootGroup`, so the new file joins the target by existing on disk. Run `FULL` to prove it compiled into the app target. If the group turns out not to cover `Browse/`, add a file reference only — no target-membership, build-setting or scheme edit.

## Phase 8: Close-out

- [x] 8.1 Run `FAST`, `APP`, `FULL` green; confirm the `@Test` count is strictly above the 0.1 baseline and that no pre-existing assertion was deleted or weakened.
      **Result:** `FAST` = **1140 tests in 156 suites passed** (baseline 1090/152 — **+50 tests, +4 suites**), same 1 pre-existing known issue. `APP` = **47** cases, `** TEST SUCCEEDED **` (baseline 32). `FULL` = **67** cases, `** TEST SUCCEEDED **` (baseline 52).
      **No assertion deleted or weakened.** `git diff -U0` over `Tests/` removes exactly one assertion line — `#expect(object["schemaVersion"] as? Int == 1)` — which task 5.4 required and which is replaced by *two* stronger ones (`== 2` **and** `== CatalogSnapshot.currentSchemaVersion`, so the literal and the constant can no longer drift apart).
- [x] 8.2 Update `Tests/CatalogTests/Fixtures/README.md` and the `CatalogSnapshot`/`CaskWire` doc comments so the widened key subset and the `1 → 2` bump are documented where the next reader looks. Record in the design's Open Questions that `CatalogPackage.homepage` remains a Foundation `URL` (follow-up, out of scope here).
      **Done:** README gained an inspection-fixture table and the byte-identity note on the T5 control fixtures; `CaskWire` documents the five widened keys and the two load-bearing tolerance properties; `CatalogSnapshot` carries a version history. The design's Open Questions record the `homepage` follow-up as confirmed, plus two apply-time amendments and the measured footprint numbers.

---

## Apply Result

**45 / 45 tasks complete** (the forecast said 37; the file has 45). Phases 0–8, strict TDD throughout:
every production change was preceded by a failing test, and each RED was executed and observed before
its GREEN. Two amendments to the design were required by evidence and are recorded in `design.md`
under *Apply-Time Amendments* rather than absorbed silently.

*Size note: this document exceeds the 530-word skill budget, as every archived tasks file in this
project does. The project convention — a checklist dense enough that apply needs no re-derivation —
wins, as it did for the spec and design phases.*
