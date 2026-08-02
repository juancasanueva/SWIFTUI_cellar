# Exploration: M2 — Mutations & Installed

PRD milestone M2 (§3.2, §3.10, §4.1–4.2, §7). Investigation only.

Artifact store: hybrid — mirrored in Engram topic `sdd/m2-mutations-installed/explore` (#7064).
Live brew probes captured by the orchestrator on 2026-08-02 (Homebrew 6.0.14, /opt/homebrew).

## 1. Current State

### CellarCore (`Packages/CellarCore/Package.swift`, tools 6.0, `.macOS("26.0")`, `.swiftLanguageMode(.v6)` on all four targets)

Two library products, deliberately unlinked:

- `BrewProcess` — process execution + brew detection.
- `Catalog` — sync/decode/index/search. **No dependency on BrewProcess** (catalog-sync CS1: sync must work with brew absent).

Test targets `BrewProcessTests` (86 `@Test`) and `CatalogTests` (128) = 214 at M1 close.

### BrewRunner — the M2 extension point

`Packages/CellarCore/Sources/BrewProcess/BrewRunner.swift` — an `actor`.

- `start(_ command: BrewCommand) async throws(BrewProcessError) -> BrewOperation`.
- `BrewCommand` (`BrewCommand.swift`) is argv + `Kind{.read,.mutate}`; static `.read([String])` / `.mutate([String])`. **argv only** — never a shell string.
- `.read` launches immediately. `.mutate` joins a FIFO gate implemented as a chain of `Task`s (`mutationTail`), read-and-replaced synchronously before any `await` (invariant I2).
- Streaming: `AsyncStream<LogLine>.makeStream()` created in `start`, handed to the caller inside `BrewOperation.lines`, fed by `startPump` which runs `LineSplitter` over `process.output` (`AsyncStream<OutputChunk>` of `.stdout(Data)`/`.stderr(Data)`) and `finish()`es at EOF.
- Terminal result: `BrewOperation.exit() async -> BrewExit` — never throws, resolves only after the pump drained (ordering contract). `BrewOperation.fault() async -> BrewProcessError?` for out-of-band faults.
- Cancellation (`cancel(_:)`): SIGINT → grace → SIGTERM → grace → give up with `.cancelledUnresponsive`. **SIGKILL is banned by design D4.** Grace races the pump against an injected `any Clock<Duration>`. Cancelling the task consuming `lines` triggers the same escalation via `continuation.onTermination`.
- A mutation cancelled while still queued resolves to `BrewExit(status: 128+SIGINT, reason: .cancelled(signal: SIGINT))` and never spawns.
- `SystemProcess` (`SystemProcess.swift`) confines `Foundation.Process` + both `Pipe`s in a single `Mutex` (design D1), zero `@unchecked Sendable`. Invariant I1: one continuation, `finish()` exactly once after both pipes EOF **and** the process is reaped.

**Gap M2 must close**: `operations` is a private dict. There is **no API to enumerate in-flight or queued operations**, no queue-position, no per-operation label/command echo, no observable queue state. PRD §3.10 requires "an operation queue with visible pending items" and "every mutation shows the exact brew command". That is a genuine additive extension to `BrewProcess`, not just app-side work.

**Second gap**: `SystemProcess.init` sets `process.standardInput = FileHandle.nullDevice` ("brew must never block waiting for input Cellar cannot give"). Correct for M1 reads; for M2 this means **any cask whose installer requires a sudo password will fail rather than prompt**. Needs an explicit product decision + error surface.

### Catalog / app wiring

- `CatalogStore` (`Sources/Catalog/CatalogStore.swift`) — `@MainActor @Observable`, lives in the *package* not the app target (design D1), because the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (verified in `cellar.xcodeproj/project.pbxproj:447,479`) which would silently main-isolate anything written beside it and take it out of the `swift test` loop.
- `start()` is scene-lifetime: `loadCache()` then a `withTaskGroup` running the event observer + `engine.runRefreshLoop()`. Guarded by `isRunning` so a second window does not start a second iterator.
- `adopt(_:)` rebuilds `PackageSearchIndex` and calls `rerank()` **synchronously on the main actor** — this is follow-up #1.
- `rerank()` runs `index.search` synchronously on `@MainActor` by design D4 (measured p95 1.02 ms vs an 8 ms ceiling).
- App target (`cellar/`): `cellarApp.swift` owns `BrewDetectionStore` + `CatalogStore` as `@State`; **no `ModelContainer`, no SwiftData anywhere**. The template `Item.swift` was deleted in `m1-catalog-browse`. `ContentView.swift` is a `NavigationSplitView` over `AppSection{.home,.browse}`; detail column is driven by `PackageID?` so a snapshot swap re-resolves rather than showing a stale copy. `BrowseView` binds straight to `catalog.results` with `.searchable`; `CatalogFilterBar` carries kind/deprecated/disabled toggles and a comment explaining why there is deliberately no installed/outdated toggle.
- `BrewDetectionStore` is the store pattern M2 should mirror: `@MainActor @Observable`, single-flight `refresh()` via `@ObservationIgnored private var inFlight: Task<…>`, publishes only on change.

## 2. Live brew facts (Homebrew 6.0.14, /opt/homebrew)

Measured from the two captured probe files. Anything not directly readable there is marked UNVERIFIED.

### `brew info --installed --json=v2` — 663,106 B, 21,708 pretty-printed lines, 1.27 s wall, 156 formulae + 3 casks

Envelope: `{"formulae":[…],"casks":[…]}` — same envelope as the catalog dumps, so the M1 wire-model shape is reusable.

Formula record fields M2 needs:
`name`, `full_name`, `tap`, `desc` (nullable), `license`, `homepage`, `versions.stable`, `revision`, `version_scheme`, `keg_only`, `keg_only_reason`, `caveats` (nullable), `linked_keg`, `pinned`, `outdated`, `deprecated`/`deprecation_date`/`deprecation_reason`, `disabled`/`disable_date`/`disable_reason`, `service`, and:

```
"installed": [
  { "version": "20260107.1", "used_options": [], "built_as_bottle": true,
    "poured_from_bottle": true, "time": 1781243179,
    "runtime_dependencies": [], "installed_on_request": false }
]
```

**Verified corrections to assumed field lists:**

- There is **no `installed_as_dependency` key anywhere** in the payload (grep: 0 matches). "Installed as a dependency" must be *derived* as `installed_on_request == false` on the relevant keg record. Any spec text or task naming that field would be describing an API that does not exist.
- `installed` for a **formula** is an **array of keg objects**; `installed` for a **cask** is a **plain String** (`"installed": "0.46.0"`). Asymmetric decoding is mandatory.
- `installed[].time` (formula) and `installed_time` (cask) are Unix epoch **seconds** → "installed on" date with no extra probe.
- `pinned` and `pinned_version` are present on **both** formula and cask records. `brew list --pinned` is therefore redundant for reading pin state.
- `outdated: true` appears **12 times**, exactly matching the 12 formulae in `brew outdated --json=v2`. Combined with `versions.stable` giving the same value as outdated's `current_version` (spot-checked `ada-url`: info `versions.stable` 4.0.0 / outdated `current_version` 4.0.0; installed 3.4.4), **one `brew info --installed --json=v2` call answers the whole Installed list including outdated** — no second spawn needed for formulae.
- `installed_on_request: true` appears 56 times out of 156 formulae — i.e. ~100 are dependency-only. The request/dependency split is a load-bearing default filter, not a nicety.
- No formula on this machine has more than one keg in `installed` (multiline grep: 0 matches for a two-element array). Multi-version kegs are therefore **UNVERIFIED**, but the schema is an array and `brew` genuinely supports it, so decode as a list.

Cask record fields:
`token`, `full_token`, `old_tokens`, `tap`, `name` (**array of strings**, same M1 quirk), `desc` (nullable), `homepage`, `url`, `version`, `installed` (String), `installed_time`, `bundle_version`, `bundle_short_version`, `pinned`, `pinned_version`, `outdated`, `sha256`, `artifacts` (heterogeneous array of dicts: `app`/`binary`/`font`/`uninstall`/`zap`, each with an optional `target`), `caveats`, `depends_on`, `conflicts_with`, `auto_updates`, `deprecated`/`disabled` families.

- `auto_updates` is **tri-state**: `true` on 1 of 3 casks, `null` on the other 2 — **never `false`**. PRD §3.2 wants auto-updating casks visually separated, so decode as `Bool?` and treat `nil` as "not declared" (behaviourally false) rather than folding it at decode time.
- `artifacts` is deeply heterogeneous (arrays mixing strings and dicts). M2 does not need it — defer to M5 pre-install cask inspection and drop it from the slim projection.

### `brew outdated --json=v2` — 2,211 B, 0.45 s

`{"formulae":[{"name","installed_versions":[String],"current_version","pinned","pinned_version"}],"casks":[]}`. Strictly a subset of what `info --installed` already carries.

**Where `outdated` is still needed**: `brew outdated` has greedy semantics (`--greedy`, `--greedy-latest`, `--greedy-auto-updates`) that by default *exclude* casks with `auto_updates`/`version :latest`. Whether `info --installed`'s cask `outdated` flag applies the same exclusion is **UNVERIFIED** — zero outdated casks existed on the probe machine. This must be resolved during design/apply with a live probe on a machine that has an outdated cask.

### `brew list --pinned` — empty (no pinned packages)

Pin/unpin round-trips cannot be verified against live state without mutating. Read path is covered by `pinned` in the info snapshot.

### Command flags (docs.brew.sh Manpage, fetched)

- `brew install [--cask|--formula] [--force] [--dry-run/-n] [--adopt] [--zap] [--skip-cask-deps] [--ignore-dependencies] …`
- `brew uninstall|remove|rm [--force/-f] [--cask|--formula] [--ignore-dependencies] [--zap]`
- `brew reinstall [--force/-f] [--cask|--formula] [--zap] [--adopt] [--dry-run/-n] …`
- `brew upgrade [--cask|--formula] [--greedy/-g] [--greedy-latest] [--dry-run/-n] [--force/-f] [--zap] …` — no arguments means "upgrade everything".
- `brew pin [--formula] [--cask] installed_formula|installed_cask …` / `brew unpin …` — **cask pinning exists in 6.x**, matching the `pinned` field on cask records.
- `brew outdated [--cask|--formula] [--json] [--greedy/-g] [--greedy-latest] [--greedy-auto-updates]`
- `brew info|abv [--json] [--installed] [--cask|--formula]`
- `brew list|ls [--pinned] [--versions] [--multiple] [--full-name]`

Always pass `--formula`/`--cask` explicitly rather than relying on token disambiguation — the catalog already knows `PackageKind`, and `docker` exists in both namespaces.

## 3. Existing specs — contradiction analysis

Five main specs under `openspec/specs/`. M2 must not silently break any of them.

| Spec | M2 impact |
|---|---|
| `catalog-sync` | **Untouched.** M2 adds no catalog behaviour. |
| `brew-detection` | **Untouched behaviourally.** M2 must render the `absent`/`invalid` states as read-only guidance in the Installed section (the spec already says absence gates nothing). Optional fold-in: the still-open S1 vocabulary nit (`native`/`rosettaCarryOver` vs code `BrewPrefix.appleSilicon`/`.intelCarryOver`) — `m1-catalog-browse` explicitly declined it because it touches `BrewProcess`; **M2 does touch `BrewProcess`, so M2 is the right change to close it.** |
| `brew-execution` | **MODIFIED — required.** "Serialized mutations with concurrent reads" stays valid but is silent on observability. M2 needs ADDED requirements for: enumerable queue state (pending/running/terminal per operation), stable operation identity carrying its argv for "copy command", and a decision on stdin (currently `/dev/null`, which breaks sudo-prompting casks). |
| `package-search` | **Direct contradiction.** "Filters answerable from the catalog alone" states verbatim: *"No filter MUST depend on installed, not-installed, or outdated state — the persisted catalog cannot answer those"*, with a scenario asserting the filter set contains no such predicate. PRD §3.1 wants installed/not-installed/outdated filters in Browse. See §9B. |
| `package-detail` | Likely **untouched**. Installed state and actions are a *different* projection layered over detail, not a change to "Required detail projection". Keep the M1 requirement intact and let a new capability own the overlay. |

Proposed new capabilities for M2: `installed-inventory`, `package-mutation`, `operation-activity`, `local-package-metadata`, `installation-history`.

## 4. FS watching

PRD §4.2 says "File-system watcher (DispatchSource) on the Cellar/Caskroom". The constraint that CellarCore is "platform-independent-ish" is **not real**: `Package.swift` declares `platforms: [.macOS("26.0")]` only, so CoreServices is fully available. The real constraint is the repo's protocol-boundary convention (every external dependency behind a seam with a fake).

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **A. `DispatchSource.makeFileSystemObjectSource` on the two roots** | Pure libdispatch, trivially injectable, what the PRD names | **Non-recursive.** `.write` on `/opt/homebrew/Cellar` fires when a direct child appears/disappears (install/uninstall) but **not** when a new version directory is created inside `Cellar/<formula>/` — i.e. it misses every upgrade, the single most common external mutation. Covering that needs one fd per installed formula (156 today) with re-arming after each vnode replacement | Low, but wrong |
| **B. `FSEventStream` (CoreServices) rooted at both paths** (recommended) | Recursive by construction; one stream covers both roots; built-in coalescing via the latency parameter; survives directory recreation; `FSEventStreamSetDispatchQueue` integrates with GCD; `kFSEventStreamEventFlagMustScanSubDirs` tells you when to just re-snapshot | C API with a callback + context pointer, so the `Sendable`/lifetime plumbing needs care under Swift 6; needs a real seam to stay testable | Medium |
| **C. No watcher — refresh on focus + after every terminal mutation** | Zero new API surface; covers the overwhelmingly common case (Cellar itself mutated, or user tabs back after using Terminal) | Misses live external changes while Cellar is foregrounded; falls short of PRD §4.2 | Very low |

**Recommendation: B behind a seam, with C as the always-on baseline.** Define `protocol InstalledChangeObserving: Sendable { var changes: AsyncStream<Void> { get } }` with an `FSEventsInstalledObserver` production impl and a fake for tests, exactly mirroring `ProcessLaunching`/`CatalogSource`. Crucially, **do not parse events** — the watcher is a pure invalidation signal that triggers a re-run of `brew info --installed --json=v2`.

Two non-negotiable behaviours around it:

1. **Debounce.** A `brew upgrade` writes to the Cellar continuously for minutes. At 1.27 s and 663 KB per snapshot, an un-debounced watcher is a self-inflicted DoS. Coalesce on an injected `any Clock<Duration>` with a quiet window (≥2 s), same pattern as `CatalogRefreshPolicy`.
2. **Suppress while a mutation is in flight.** Cellar already knows it is the one mutating; re-snapshot exactly once at the terminal outcome instead of continuously during the operation.

## 5. SwiftData placement

Current reality: **zero SwiftData in the repo.** No `@Model`, no `ModelContainer`, no `Persistence` target. PRD §4.1 names a `Persistence` module inside CellarCore; §4.2 names the models `PackageMeta` (favorites, notes), `Snooze`, `HistoryEntry`, `DismissedCVE`, `Settings`, no CloudKit.

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **A. `Persistence` target in CellarCore (recommended)** | Matches PRD §4.1; testable in the fast headless `swift test` loop with `ModelConfiguration(isStoredInMemoryOnly: true)`; escapes the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so background writes can use `@ModelActor` honestly; mirrors the shipped D1 precedent (`CatalogStore` in `Catalog`, `BrewDetectionStore` in `BrewProcess`) | `@Model` classes must be `public`; `.modelContainer(…)` still wires at the app scene | Medium |
| B. SwiftData in the app target | Least ceremony; `@Query` and models co-located | Only reachable from `xcodebuild test`, not `swift test` — breaks the strict-TDD inner loop the project runs on; everything beside it silently becomes `@MainActor` | Low |
| C. No SwiftData — Codable file store like `CatalogFileStore` | Perfectly consistent with M1; trivially testable; no schema-migration surface | Contradicts PRD §4.1/§4.2; hand-rolls querying, relationships, and change notification that `@Query` gives free; M4 `DismissedCVE` and M6 `Settings` make the hand-rolled path progressively worse | Low now, high later |

**Recommendation: A.** Gotchas to carry into design: `ModelContext` is not `Sendable` (pass `PersistentIdentifier` across boundaries, never `@Model` instances); `@ModelActor` methods must call `save()` explicitly; version the schema with `VersionedSchema` from day one even at V1 so M4/M6 additions are lightweight stages; all `@Transient` properties need defaults.

The joint key for local metadata is `PackageID` (kind + name) — reuse the M1 type rather than inventing a second identity. Snoozes must store the version they apply to (PRD §3.2: "until next version"), which means `HistoryEntry`/`Snooze` need the version string alongside the ID.

## 6. M1 follow-up register — fold-in assessment

| # | Follow-up | Verdict | Rationale |
|---|---|---|---|
| 1 | Main-actor index rebuild blocks UI (~16k records, violates D2) | **Prelude** | M2 adds a second `@Observable` store that adopts a snapshot and joins against the search index. Fix the pattern before it is copied. ~150 lines |
| 2 | `refreshNow()` double-adopts (index built twice) | **Prelude** | Same file, same fix session, ~20 lines. Wasteful on the exact hot path M2 will hit harder |
| 3 | `CatalogSyncEngine` single-flight joins finished/cancelled task | **Prelude** | Same defect class as the known `BrewDetectionStore` stale-join. M2's `InstalledStore` will copy that pattern verbatim — fix both so there is one correct exemplar to copy. ~80 lines + tests |
| 4 | Payload cap enforced only after full download | **Defer** | Catalog-only, no M2 coupling |
| 5 | `CatalogRefreshPolicy.payloadByteLimit` unwired | **Defer** | Bundle with #4 in a later catalog-hardening change |
| 6 | Empty snapshot persistable as success (defence-in-depth) | **Defer, bundle with #7** | Cheap; both are "treat degenerate snapshot as no cache" |
| 7 | Zero-package poisoned snapshot has no recovery path | **Prelude (with #6)** | User-visible: a pre-fix machine is stuck on an empty catalog, and M2's Installed join against an empty catalog degrades badly. ~40 lines |
| 8 | Refresh-loop ownership dies when owning window closes | **In M2 slice 1, as a design decision** | M2 introduces a *second* scene-lifetime loop (installed refresh + FS watcher) with the same `.task`-scoped ownership. Solve ownership once — app-level owner rather than first-scene owner — and both loops benefit. Do not fix it twice |
| 9 | Event-stream single-subscription reattach doubt | **Bundle with #8** | Same ownership surface |
| 10 | `TestClock` ignores cancellation (both copies) | **Prelude** | M2 adds clock-driven debounce for the watcher and would create a *third* copy. Fix both and extract a shared test-support target in the same breath. ~60 lines |

Prelude bundle (#1, #2, #3, #6, #7, #10) ≈ **450–700 authored lines** — the only slice that comfortably fits the 1,500-line budget without an exception.

## 7. Slicing recommendation

Session delivery strategy is `single-pr` with a 1,500 changed-line review budget. M1 shipped two changes at ~3.6k and ~7.6k authored lines, **both requiring an explicitly accepted `size:exception`**. M2 is materially larger than either.

Scope discipline first: PRD **§3.2 is broader than the §7 M2 exit criterion.** §7 says M2 is *"Install/uninstall/reinstall with live logs, cancel, operation queue; Installed list with outdated detection; upgrade single/selected/all; pin, favorites, notes, snooze; installation history."* Therefore **out of M2**: release-notes preview, adopt-existing-apps, size on disk, last-used heuristics (§7 assigns these to M5). Holding that line is worth roughly 2k lines on its own.

### Recommended: one prelude + three feature slices

| # | Slice | Contents | Forecast (authored, src+tests) | Budget |
|---|---|---|---|---|
| **M2-0** | `m2-catalog-hardening` (prelude) | Follow-ups #1, #2, #3, #6, #7, #10; extract shared `TestSupport` clock | **450–700** | Fits 1,500 |
| **M2-1** | `m2-installed-inventory` | New `BrewClient` target; slim wire models for `info --installed --json=v2` (asymmetric formula-keg-array / cask-string); `InstalledSnapshot` projection; outdated + request-vs-dependency + pin derivation; join with the catalog; `@MainActor @Observable InstalledStore`; Installed sidebar section, list, filters, badges; `InstalledChangeObserving` seam + FSEvents impl + debounce; focus + post-mutation refresh; loop-ownership decision (#8/#9) | **2,200–2,800** | Needs exception |
| **M2-2** | `m2-mutations-activity` | Typed mutation commands (install/uninstall/reinstall/upgrade/pin/unpin) with explicit `--formula`/`--cask`; queue observability added to `BrewRunner` (enumerable pending/running state, argv echo); `OperationCenter`/activity store; bottom activity bar + expandable streamed-log drawer; cancel UX + partial-state messaging; "copy command"; upgrade single / selected / all; destructive-action confirmations | **2,000–2,600** | Needs exception |
| **M2-3** | `m2-local-metadata-history` | `Persistence` target with `VersionedSchema` V1 (`PackageMeta`, `Snooze`, `HistoryEntry`); favorites/notes/snooze UI; snooze-aware outdated badge; installation history view + search; bulk multi-select operations | **1,600–2,200** | Needs exception |

Total ≈ **6.3k–8.3k authored lines**, in line with M1's actuals for a comparable milestone.

Alternative if exceptions are unwelcome: split M2-1 into *snapshot+decode* / *UI+watcher*, M2-2 into *runner queue observability+commands* / *activity UI*, and M2-3 into *persistence+metadata* / *history+bulk* — six slices of roughly 1,100–1,500 lines each, at the cost of three extra review cycles and two slices that ship no user-visible behaviour on their own.

**Recommendation: the four-slice plan, with M2-0 merged first and unconditionally.** M2-0 is the only slice that both fits the budget and de-risks the other three, because slices 1–3 each replicate a pattern that M2-0 corrects.

## 8. Risks

1. **stdin is `/dev/null`.** `SystemProcess` hard-wires `standardInput = FileHandle.nullDevice`. Casks whose installers require a sudo password will fail or hang with no way for the user to respond. High impact, needs an explicit product decision (detect and explain vs. escalate vs. document) before M2-2 apply.
2. **Cancel mid-`brew upgrade` can leave an unlinked keg or a partially-staged cask.** D4 bans SIGKILL, so escalation stops at SIGTERM. Needs honest UX copy plus a forced re-snapshot at the terminal outcome.
3. **`brew`'s own lock is process-external.** `BrewRunner` serialises within Cellar only. A concurrent Terminal `brew install`, or a second Cellar instance, will make a mutation fail on the lock. The exact error surface is UNVERIFIED and must be probed during design.
4. **Do not add real-brew mutation integration tests.** `BrewIntegrationTests` currently exercises reads. Mutation tests against live brew would mutate the developer's and CI machines. All mutation behaviour must go through `FakeProcessLauncher`.
5. **Cask `outdated` greedy semantics UNVERIFIED.** Whether `info --installed`'s cask `outdated` flag matches `brew outdated`'s default auto-updates exclusion could not be checked (0 outdated casks on the probe machine). Getting this wrong means either nagging users about casks that self-update or silently hiding real cask updates.
6. **Snapshot cost scales with install count.** 1.27 s / 663 KB for 156 formulae. A 500-formula machine extrapolates to ~3–4 s and ~2 MB (UNVERIFIED). Decode must be off-main (the M1 slim-projection + `@concurrent` pattern) and the watcher must be debounced.
7. **Review budget.** ~7k forecast against a 1,500-line `single-pr` budget. Every feature slice needs an accepted `size:exception` before apply, exactly as both M1 changes did.
8. **`package-search` requirement PS4 explicitly forbids installed/outdated filters.** Resolve architecturally (compose in a new capability) rather than by weakening a shipped requirement — see §9B.
9. **`BrewClient` dependency direction.** `Catalog` must stay free of `BrewProcess` (CS1). `BrewClient` depending on both `BrewProcess` and `Catalog` is one-directional and safe, and lets `PackageID`/`PackageKind` be reused instead of duplicated. The alternative — a pure `BrewClient` plus a separate `Inventory` join target — is cleaner on paper and one more target to carry.
10. **`@Model` + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` mismatch.** Models declared `nonisolated` in the package, consumed by a MainActor-default app target. Works, but every background write must go through `@ModelActor` and pass `PersistentIdentifier`, never model instances.

## 9. Key approach decisions to carry into `sdd-propose`

**A. One probe, not two.** Build the Installed list from a single `brew info --installed --json=v2`. Verified: it already carries `outdated`, `pinned`, `installed_on_request`, `linked_keg`, install timestamps, and `versions.stable`. Reserve `brew outdated --json=v2` for the cask-greedy question only, and only if the live probe confirms a divergence.

**B. Installed/outdated filters live in a new capability, not in `package-search`.** Keep the M1 requirement verbatim — the persisted catalog genuinely cannot answer those predicates, and that requirement is *correct*. Add an `installed-inventory` capability that owns the join and exposes a composed query; the Browse filter bar then composes catalog results with the inventory instead of pushing installed-state predicates down into the pure index. This preserves `package-search` unmodified, keeps the search p95 assertion meaningful, and keeps the "catalog works with brew absent" invariant intact (with brew absent, the inventory is simply empty and the filters render disabled).

**C. Slim-project the installed snapshot immediately,** exactly as M1 did with the catalog. The raw payload carries `bottle`, `urls`, `artifacts`, `ruby_source_checksum` — none of which M2 needs. Decode straight into an `InstalledPackage` projection.

**D. The watcher is an invalidation signal, not an event parser.** Coalesce, suppress during in-flight mutations, re-snapshot once.

**E. Fold in the brew-detection S1 vocabulary nit.** `m1-catalog-browse` declined it solely because that change did not touch `BrewProcess`. M2 does.
