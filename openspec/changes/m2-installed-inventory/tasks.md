# Tasks: M2-1 — Installed Inventory

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 2,400–2,800 authored (phase sums ≈ 2,600; design forecast 2,300–2,700) |
| Default review budget | 400 lines |
| Repo `review_budget_lines` (`openspec/config.yaml`) | 800 lines |
| Session `review_budget_lines` | 1,500 lines |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR under the accepted `size:exception`; Phases 6+7 (D8+D9+D10, ≈ 700 lines) are the pre-agreed cut point |
| Delivery strategy | single-pr with an accepted `size:exception` (effective `exception-ok`) |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

**Honest reading, for the orchestrator to re-confirm.** The forecast is ~1.7× the 1,500-line
session budget and ~3.3× the repo's own `review_budget_lines: 800`. The `size:exception` for one
PR is already accepted (product decision Q4, Engram #7079), so apply is *not* blocked — but the
overrun is large enough to deserve a deliberate re-confirmation rather than silent consumption.
If the exception is re-scoped, take the design's clean cut: **Phases 6 + 7** (watcher,
coordinator, loop ownership) ship as PR 2, leaving Phases 0–5 + 8 + 9 shippable on
focus-and-launch refresh alone.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Target graph, `BrewPrefix` rename, detection request-keyed fix (Phases 1–2) | PR 1 | `FAST --filter "PackageGraph\|Detection\|BrewDetectionStore"` | Point Settings at a second brew, then at the first, mid-evaluation: the published state must match the path last asked for | `git revert` the rename commit; `BrewPrefix` is not `Codable`, nothing persisted moves |
| 2 | Acquisition, decode, derivation, store (Phases 3–5, 8) | PR 1 | `FAST --filter "InstalledPayload\|InstalledDecode\|InstalledDerive\|InstalledInventory\|InstalledStore\|InstalledFilter"` | Launch with brew present: the Installed list renders from one probe; launch with brew renamed away: empty + guidance, no spawn | Delete `Sources/BrewClient/**` + `Tests/BrewClientTests/**`, revert `Package.swift` |
| 3 | Watcher, coordinator, loop ownership (Phases 6–7) — the cut point | PR 1 (or PR 2 if cut) | `FAST --filter "InstalledRefresh\|LoopOwner"` | `brew install <small formula>` in Terminal: exactly one refresh after the quiet window; `brew upgrade` does not re-snapshot repeatedly | Delete `FSEventsInstalledObserver.swift`, `InstalledChangeObserving.swift`, `LoopOwner.swift`; keep launch/activation refresh |
| 4 | App wiring and Installed/Browse UI (Phase 9) | PR 1 | `FULL` | Close the window that started the app, reopen: loops still running, inventory still refreshing | Revert `cellar/Installed/**`, the `CatalogFilterBar`/`BrowseView` hunks and the `project.pbxproj` link hunk |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Requirement tags: `II1..II11` (installed-inventory ADDED, delta-file order), `BD1..BD4`
  (brew-detection MODIFIED, delta-file order). Design decisions are `D1..D12`.
- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `openspec/` or `cellar.xcodeproj/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests`.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass.
  No production line without a red test. App-target SwiftUI (Phase 9) is xcodebuild-only and is
  outside the `FAST` inner loop — which is exactly why Phase 8 keeps the *filter resolution rule*
  in `BrewClient` (config `rules.design`: "the app target holds views, scenes, and DI wiring only").
  This refines D7, which said the mode is "resolved in the app target": the **picker** stays in the
  app target, the **rule** moves down so II8 can be RED-first.
- `CellarTestSupport` (M2-0 D5) was **cut** and never landed, so `TestClock` still exists only as
  two copies. Task 6.1 makes a third copy in `Tests/BrewClientTests/Fakes/` rather than reviving
  the deferred extraction inside this change.

---

## Phase 0: Baseline (blocking, no production change)

- [x] 0.1 Record the green baseline on `main`: `FAST`, `FULL`, `swiftlint`. Capture the `@Test`
  count so Phase 10 can prove nothing was deleted.
  **Baseline (2026-08-02, `main` @ `ebac63d`)**: `FAST` = 243 tests / 36 suites passed.
  `FULL` = `** TEST SUCCEEDED **` (`cellarTests/example()`). `swiftlint` = exit 0, 65 warnings /
  8 errors, all pre-existing (no `.swiftlint.yml` in repo, so default rules; `file_length` warns
  at 400).

## Phase 1: Target graph and vocabulary (D1, D11 — II7, BD1, BD2, BD3) — ≈ 90 lines

- [x] 1.1 RED `Tests/CatalogTests/PackageGraphTests.swift`: parse `Package.swift` relative to
  `#filePath` and assert the `Catalog` target declares no dependency on `BrewProcess`, directly or
  transitively (II7 scenario 3). It must pass now and still pass after 1.2 — this is the structural
  guard for CS1, not a new behaviour.
- [x] 1.2 GREEN `Package.swift`: add `.target(name: "BrewClient", dependencies: ["BrewProcess", "Catalog"], swiftSettings: [.swiftLanguageMode(.v6)])`, the matching `.library` product (the app target must link it), and
  `.testTarget(name: "BrewClientTests", dependencies: ["BrewClient"], resources: [.copy("Fixtures")])`.
  The edge is one-directional. Verify: `FAST` compiles with `BrewClient` empty and 1.1 still green.
- [x] 1.3 RED `Tests/BrewProcessTests/DetectionTests.swift`: rename every `BrewPrefix.native` /
  `.rosettaCarryOver` reference to `.appleSilicon` / `.intelCarryOver` (BD1 scenarios 1–2, BD2, BD3
  scenarios 4–5). The suite fails to compile — that is the RED.
  **NO-OP, verified at apply time.** `rg 'rosettaCarryOver|BrewPrefix\.native'` over the whole repo
  returns nothing: the code has always used `.appleSilicon` / `.intelCarryOver`. The S1 nit was
  **spec-side only** — `openspec/specs/brew-detection/spec.md` carried `native` /
  `rosettaCarryOver`, and the delta at `specs/brew-detection/spec.md` already realigns it to the
  code's names. No RED was possible and none was faked.
- [x] 1.4 GREEN `Sources/BrewProcess/BrewLocation.swift` (case rename) and
  `Sources/BrewProcess/DefaultBrewLocator.swift` (two call sites in `standardCandidates`). Source-only;
  `BrewPrefix` is not `Codable` and `Advisory.rosettaPrefix` is deliberately unchanged.
  Verify: `FAST --filter Detection`.
  **NO-OP for the same reason** — both files already read `.appleSilicon` / `.intelCarryOver`.
  Design D11's arrow direction (`case appleSilicon → native`) is written backwards; the spec delta,
  the tasks legend and the code all agree on `appleSilicon` / `intelCarryOver` as the target
  vocabulary. Phase 1 therefore costs ~0 lines instead of the forecast ~90.

## Phase 2: Detection request-keyed single flight (D6 scope delta — BD4) — ≈ 110 lines

- [x] 2.1 RED `Tests/BrewProcessTests/BrewDetectionStoreTests.swift`: with a gated
  `FakeBrewLocator`, an evaluation in flight for configured path `A`, then the path changes to `B`
  and a re-evaluation is requested — the locator is probed for `B` and the published state is `B`'s,
  not `A`'s (BD4 scenario 7). Two callers for the *same* path still coalesce onto one probe
  (BD4 scenario 8). Existing scenarios 4–6 (settled re-probes, abandoned caller, concurrent coalesce)
  must stay green **unchanged**.
- [x] 2.2 GREEN `Sources/BrewProcess/BrewDetectionStore.swift`: key the M2-0 token slot by the
  request — the configured path the evaluation was started for — so a differing request never joins.
  Add the ordinal guard on publication so the resident state corresponds to the request **most
  recently asked for** (the spec's wording is load-bearing: a stale winner is a bug even when it
  probed). `defer { vacate(token) }` stays inside the task body. Verify: `FAST --filter BrewDetection`.

## Phase 3: Acquisition and decode (D2, D3 — II1 sc3, II2; threat rows) — ≈ 700 lines

- [x] 3.1 RED `Tests/BrewClientTests/InstalledPayloadTests.swift` — **threat: untrusted subprocess
  payload**. Against `payload(from:exit:)` with synthesised `[LogLine]` and no process: a non-zero
  exit yields `.commandFailed(status:message:)` carrying the `.stderr` tail and **never** an empty
  inventory; empty stdout yields `.malformedPayload`; interleaved `.stderr` lines never enter the
  joined JSON.
- [x] 3.2 GREEN `Sources/BrewClient/InstalledPayloadSource.swift`: the `InstalledPayloadSourcing`
  protocol, the closed `InstalledInventoryError` (`.brewUnavailable`, `.commandFailed(status:message:)`,
  `.malformedPayload`, `.cancelled`), and the pure
  `static func payload(from:exit:) throws(InstalledInventoryError) -> Data`.
- [x] 3.3 RED `Tests/BrewClientTests/InstalledArgvTests.swift` — **threat: subprocess argument
  composition**. Assert the composed command is `BrewCommand.read(["info", "--installed", "--json=v2"])`:
  the recorded argument vector equals that exact fixed vector, `kind == .read` (so it never enters
  M2-2's mutation gate), and no user-supplied or catalog-supplied token can reach it — no shell, no
  string joining.
- [x] 3.4 GREEN `InstalledPayloadSource.swift`: `BrewInfoPayloadSource` — ~20 lines of glue that drain
  `operation.lines`, `await operation.exit()`, and hand both to 3.2's pure function.
- [x] 3.5 Author `Tests/BrewClientTests/Fixtures/installed-info.json`, trimmed by hand: a multi-keg
  formula, a dependency-only formula, an outdated formula, a pinned formula, a self-updating cask
  with `installed != version`, a plain outdated cask, a pinned cask, and a tap-only formula with no
  catalog counterpart. No production code in this task.
- [x] 3.6 RED `Tests/BrewClientTests/InstalledDecodeTests.swift`: a single-keg formula decodes with
  its version and install time (II2 sc1); a two-keg formula appears **once with both kegs**, neither
  dropped (II2 sc2); a cask's String `installed` decodes as `1.2.3` (II2 sc3); `auto_updates` true vs
  `null` stay distinguishable as "declared" vs "not declared" at the wire layer, never folded to a
  plain `false` (II2 sc4); and — **threat: untrusted payload** — truncated JSON is `.malformedPayload`
  while one corrupt record among good ones is skipped, not fatal.
- [x] 3.7 GREEN `Sources/BrewClient/InstalledWire.swift` (two wire types, two `init(from:)` for the
  asymmetric `installed` shapes, `LossyArray`-style per-record tolerance),
  `Sources/BrewClient/InstalledModels.swift` (`InstalledKeg`, `InstalledPackage`,
  `InstalledInventory`, `InstalledLoadState`), and `Sources/BrewClient/InstalledDecoder.swift`
  (envelope → projection; drop `bottle`, `urls`, `artifacts`, `ruby_source_checksum`,
  `runtime_dependencies`, `used_options`, `sha256`, `service`, `depends_on`, `conflicts_with`;
  `linked_keg` selects `primaryKeg`, falling back to the newest `installedAt`).
- [x] 3.8 RED `InstalledDecodeTests`: over a realistic-size payload, main-actor work submitted after
  the decode starts runs to completion **before** the decode finishes (II1 sc3) — the M2-0 D1
  yield-counting shape.
- [x] 3.9 GREEN `InstalledDecoder.decode(_:)` becomes `@concurrent` — attribute **before** the
  modifier (M1 apply-time finding). Verify: `FAST --filter "InstalledPayload\|InstalledArgv\|InstalledDecode"`.

## Phase 4: Derivation (D4 — II3, II4, II5, II6) — ≈ 330 lines

- [x] 4.1 RED `Tests/BrewClientTests/InstalledDeriveTests.swift`, parameterised over the fixture: an
  outdated formula is in the outdated set and counted (II4 sc1); a cask that does not declare
  auto-updates is outdated on the same terms (II4 sc3); a self-updating cask installed `1.2.3`
  against published `1.3.1` with a false wire flag is **absent** from the set, absent from
  `outdatedCount`, and classified self-updating (II4 sc2).
- [x] 4.2 GREEN derivation in `InstalledModels.swift`: `isOutdated` = wire `outdated` verbatim for a
  formula, `wire.outdated && !isSelfUpdating` for a cask (belt-and-braces over brew's own exclusion);
  `isSelfUpdating` = `autoUpdates == true` (`nil` ⇒ false, "not declared"); `outdatedCount` counts
  `isOutdated` only.
- [x] 4.3 RED `InstalledDeriveTests`: `hasNewerVersion` is true for a self-updating cask with
  `installed != version` and no second invocation is recorded (II5 sc1); it is false when the versions
  match, and the cask is still absent from the outdated set (II5 sc2). The signal must never reach
  the set, the count or a badge.
- [x] 4.4 GREEN `hasNewerVersion`, self-updating casks only, derived from the same record.
- [x] 4.5 RED `InstalledDeriveTests`: the default view lists the on-request formula only (II3 sc1);
  with the dependency toggle on both are listed and each exposes whether it was on-request (II3 sc2);
  an installed cask, whose records carry no on-request marker at all, is listed by the default view
  (II3 sc3 — nothing deliberately installed may be hidden).
- [x] 4.6 GREEN `isOnRequest`: formula = `kegs.contains(\.installedOnRequest)`; cask = always `true`
  (no `installed_as_dependency` key exists in the payload); plus the `InstalledInventory` filtering
  entry point taking the dependency toggle.
- [x] 4.7 RED `InstalledDeriveTests`: a pinned formula and a pinned cask both report pinned with their
  recorded pinned version (II6 sc1); install dates equal their recorded timestamps interpreted as
  Unix epoch seconds for both kinds (II6 sc2). Both with exactly one recorded invocation.
- [x] 4.8 GREEN `isPinned` / `pinnedVersion` from the wire `pinned` / `pinned_version` in both
  namespaces; `installedAt` from `primaryKeg.installedAt`. `brew list --pinned` is never spawned.
- [x] 4.9 RED `Tests/BrewClientTests/InstalledInventoryTests.swift`: `installedIDs` and `outdatedIDs`
  membership over `PackageID`; `outdatedIDs` excludes self-updating casks; sort order is by name; an
  empty inventory is a valid value, not an error.
- [x] 4.10 GREEN both sets built once in the same off-main pass as the projection.
  Verify: `FAST --filter "InstalledDerive\|InstalledInventory"`.

## Phase 5: `InstalledStore` (D6 — II1 sc1–2, II9, II10 sc4) — ≈ 330 lines

- [x] 5.1 RED `Tests/BrewClientTests/InstalledStoreTests.swift` (`@MainActor`), with a counting
  `FakeInstalledPayloadSource`: one completed refresh records **exactly one** invocation, whose
  arguments are `info --installed --json=v2` (II1 sc1); reading outdated, pinned and dependency-only
  state afterwards answers all three and the count is **still one** (II1 sc2).
- [x] 5.2 GREEN `Sources/BrewClient/InstalledStore.swift`:
  `@MainActor @Observable public final class InstalledStore` with
  `public func refresh(using installation: BrewInstallation?) async`.
- [x] 5.3 RED `InstalledStoreTests`: two overlapping refreshes perform one acquisition and observe
  the same inventory; a refresh requested **after** the previous settled against `P1` performs a
  second invocation and the inventory reflects `P2` (II10 sc4); a refresh under a *different*
  `BrewInstallation` does not join the one in flight.
- [x] 5.4 GREEN: the M2-0 D3 token slot **keyed by `installation.executableURL`**, with
  `defer { vacate(token) }` inside the task body so no caller can join settled work.
- [x] 5.5 RED `InstalledStoreTests`: two scripted payloads with controlled completion order — older
  `A` and newer `B` where `B` completes first — leave `B` resident and discard `A`'s late adoption.
- [x] 5.6 GREEN: the M2-0 D1 monotonic ordinal stamped before the `await`; **one** main-actor
  assignment, admitted only while the ordinal still exceeds `installedSequence`.
- [x] 5.7 RED `InstalledStoreTests`: a failed refresh keeps the **last good inventory** resident and
  sets `.failed(error)`; a `nil` installation clears to an empty inventory with `.brewAbsent`,
  throws nothing, and the launch counter stays at zero (II9 sc1); an invalid configured path is the
  same, with the rejection reason available as read-only guidance (II9 sc2); a store that reported
  absent, then given a valid installation and a refresh, reports the snapshot's packages without a
  restart (II9 sc3).
- [x] 5.8 GREEN the load-state and brew-absent paths in `InstalledStore`.
  Verify: `FAST --filter InstalledStore`.

## Phase 6: Freshness (D8, D9 — II10) — ≈ 380 lines — **cut point with Phase 7**

- [x] 6.1 Add `Tests/BrewClientTests/Fakes/`: `TestClock.swift` (third copy — M2-0 D5's
  `CellarTestSupport` extraction was cut and is still pending), `FakeInstalledChangeObserver.swift`,
  `FakeInstalledPayloadSource.swift`. No production code.
- [x] 6.2 RED `Tests/BrewClientTests/InstalledRefreshTests.swift`: with a running coordinator, the
  underlying snapshot gains a package and one signal is emitted — after the quiet window the
  inventory lists it, with no user action (II10 sc1); twenty signals inside the quiet window record
  **exactly one** additional invocation (II10 sc2). The signal is never parsed; a re-snapshot is
  always taken.
- [x] 6.3 GREEN `Sources/BrewClient/InstalledChangeObserving.swift`: the
  `func changes() -> AsyncStream<Void>` seam plus `InstalledRefreshCoordinator` debouncing on an
  injected `any Clock<Duration>` with a 2 s quiet window.
- [x] 6.4 RED `InstalledRefreshTests`: with a Cellar-initiated mutation in flight, signals emitted
  continuously produce **no** re-snapshot; exactly one runs at the mutation's terminal outcome
  (II10 sc3).
- [x] 6.5 GREEN suppression against the injected `isMutating` flag object M2-2 will drive.
- [x] 6.6 RED `InstalledRefreshTests`: the baseline refresh fires at launch and on activation with
  **no observer attached at all** — the watcher is an optimisation, never the only path.
- [x] 6.7 GREEN the baseline hook in `InstalledRefreshCoordinator`.
- [x] 6.8 `Sources/BrewClient/FSEventsInstalledObserver.swift` (D8) — the single **untested-by-design**
  surface, ~40 lines, no branch beyond "yield". It MUST carry a header comment stating the
  confinement invariant: `final class Sendable Box` holding only a `let continuation`, passed as
  `Unmanaged.passRetained(...).toOpaque()`; a file-scope `@convention(c)` callback that captures
  nothing and only yields, never reading event paths or flags; the private dispatch queue via
  `FSEventStreamSetDispatchQueue`; `Stop` → `Invalidate` → `Release` serialised by a `Mutex`
  (the `SystemProcess` D1 precedent); deferred creation flags; and **zero** `@unchecked Sendable`.
  Watched roots are `<prefix>/Cellar` and `<prefix>/Caskroom`, derived from
  `installation.executableURL.deletingLastPathComponent().deletingLastPathComponent()`.
  Verify: `FAST --filter InstalledRefresh`.

## Phase 7: Loop ownership (D10 — II11) — ≈ 110 lines — **cut point with Phase 6**

- [x] 7.1 RED `Tests/BrewClientTests/LoopOwnerTests.swift` with counting closures: `start` twice for
  one id runs exactly one loop; open → close → open re-enters `start`, finds it running, and does not
  restart or double-start (II11 sc2); a closed scene does not cancel a running loop, and a subsequent
  refresh still updates (II11 sc1).
- [x] 7.2 GREEN `Sources/BrewClient/LoopOwner.swift`: `@MainActor @Observable public final class`
  with idempotent `start(_ id:_ body:)` and `isRunning(_:)`. Dependency-free — closures, not stores —
  so it stays inside the `FAST` inner loop. Verify: `FAST --filter LoopOwner`.

## Phase 8: Browse composition and catalog decoration (D5, D7 — II7, II8) — ≈ 200 lines

- [ ] 8.1 RED `Tests/BrewClientTests/InstalledFilterTests.swift`: with a catalog holding `wget` and
  `curl` and an inventory holding only `wget`, `installed` leaves only `wget` (II8 sc1) and
  `notInstalled` leaves only `curl` (II8 sc2); with one outdated formula and one self-updating cask
  behind its published version, `outdated` leaves only the formula (II8 sc3); with `.brewAbsent` and
  an empty inventory the mode is forced to `all`, the picker reports itself disabled, and the rows
  are **identical** to the same query with no installed-state filtering (II8 sc4).
- [ ] 8.2 GREEN `Sources/BrewClient/InstalledFilterMode.swift`: the
  `InstalledFilterMode { all, installed, notInstalled, outdated }` case set and the pure resolution
  rule — `all` → `catalog.results` unchanged; `installed`/`outdated` → sourced from the **inventory**
  (name/desc-matched against the live query, sorted by name), because `catalog.results` is capped at
  `resultLimit` 200 and intersecting an empty-query page with ~160 IDs would render ~0 rows;
  `notInstalled` → `catalog.results` minus `installedIDs`.
- [ ] 8.3 RED `Tests/CatalogTests/FilterTests.swift`: the catalog query's declared filter set,
  enumerated, contains no installed, not-installed or outdated predicate (II8 sc5).
- [ ] 8.4 GREEN: **no production change expected** — `SearchFilters` and `PackageSearchIndex` are
  untouched. A failure here means composition leaked into the index. Also assert
  `git diff --exit-code -- openspec/specs/package-search/spec.md` stays clean.
- [ ] 8.5 RED `InstalledFilterTests`: an installed formula `wget` matched to a catalog record carries
  both the installed version and the catalog description (II7 sc1); an installed formula from a
  third-party tap with no catalog record is still listed with its snapshot data and no catalog
  metadata, never hidden (II7 sc2).
- [ ] 8.6 GREEN the per-row decoration resolver over the existing `CatalogStore.package(id)` — O(1)
  per rendered row, joined on the existing `(kind, name)` `PackageID`, never re-declared. A cold,
  empty or poisoned catalog costs decoration, never a row.
  Verify: `FAST --filter "InstalledFilter\|Filter"`.

## Phase 9: App wiring and UI (xcodebuild only, outside the `FAST` loop) — ≈ 520 lines

- [ ] 9.1 `cellar.xcodeproj/project.pbxproj`: link the `BrewClient` product into the `cellar` target.
  Verify: `xcodebuild build`.
- [ ] 9.2 `cellar/cellarApp.swift`: hold `LoopOwner` as `@State` (App-level state outlives every
  scene), construct `InstalledStore` and `InstalledRefreshCoordinator`, and move both existing
  scene-owned loops to `loops.start("catalog") { … }` / `loops.start("installed") { … }` from
  `.task`. Wire `NSApplication.didBecomeActiveNotification` to the baseline refresh, mirroring the
  existing `brewDetection.refresh()` wiring. Closes M1 follow-ups #8 and #9.
- [ ] 9.3 `cellar/ContentView.swift` + `cellar/Shell/AppSection.swift`: Installed sidebar section and
  detail routing.
- [ ] 9.4 Create `cellar/Installed/{InstalledListView,InstalledFilterBar,InstalledRow,InstalledEmptyState}.swift`:
  the list, the dependency-only toggle (default off), badges, the **separate** self-updating section
  showing `hasNewerVersion` without an outdated badge, and the brew-absent read-only guidance state.
- [ ] 9.5 `cellar/Browse/CatalogFilterBar.swift` + `cellar/Browse/BrowseView.swift`: the
  `InstalledFilterMode` picker bound to Phase 8's rule (view-side only), replacing the existing
  "deliberately absent" comment; `.disabled(true)` and forced to `all` when the store reports
  `.brewAbsent`.
- [ ] 9.6 Integration checks via `FULL`: the Installed section renders empty guidance with brew
  absent, and the Browse mode picker is disabled there. Build-level only — **no new live-brew test**.

## Phase 10: Manual verification and gate

- [ ] 10.1 **Manual verification (D12 compensating control iii, for the untested FSEvents adapter).**
  With the app running and brew present: `brew install <small formula>` in Terminal → observe
  **exactly one** refresh after the quiet window; then `brew upgrade` → observe **one** refresh at
  the end, not a stream. Record both observations verbatim in the apply report. This is the only
  evidence `FSEventsInstalledObserver` gets; if it does not fire, the coordinator's baseline
  (launch + activation) must still keep the inventory correct.
- [ ] 10.2 Full gate: `FAST` green with the Phase 0 `@Test` count intact plus the new suites (none
  deleted), `FULL` green, `swiftlint` clean on changed files. Record every command and its exact
  result.
- [ ] 10.3 Scope guard: `git diff --stat main` touches only the files in design "File Changes";
  `Catalog` still declares no `BrewProcess` dependency (1.1 green); `openspec/specs/package-search/spec.md`
  byte-identical; `CatalogSnapshot.currentSchemaVersion` still 1; no `@unchecked Sendable` anywhere in
  `Sources/BrewClient/`; nothing from M2-2 (mutations, queue, activity UI) or M2-3 present.
- [ ] 10.4 Record the actual authored line count against the 2,400–2,800 forecast and the accepted
  `size:exception`. If it overruns materially, cut Phases 6+7 to PR 2 (feature-branch-chain,
  base = PR 1 branch) rather than expanding the exception again.
