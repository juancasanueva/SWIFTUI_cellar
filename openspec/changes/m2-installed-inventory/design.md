# Design: M2-1 — Installed Inventory

## Technical Approach

One new target, `BrewClient`, is the only place in the package that sees both `BrewProcess` and
`Catalog`. It turns a single `brew info --installed --json=v2` invocation into an immutable, `Sendable`
`InstalledInventory`, and publishes it through a `@MainActor @Observable InstalledStore` built from the
two exemplars M2-0 corrected: the token-keyed single-flight slot (M2-0 D3) and the ordinal-guarded
off-main adoption (M2-0 D1).

The unifying idea is **the inventory is self-sufficient**. The info payload already carries `desc`,
`homepage`, `versions.stable`, `outdated`, `pinned`, `installed_on_request` and install timestamps
(explore §2), so the Installed list never needs the catalog to render, exactly as the catalog never
needs brew to sync (CS1). The two indexes meet only through `PackageID`, in two O(visible) directions.

Decisions are numbered `D1…D12`; M2-0's are cited as `M2-0 D1`, `M2-0 D3`.

    BrewRunner(.read) ──▶ [LogLine] ──▶ payload(from:exit:) ──▶ Data
                                                                 │  @concurrent
                                       InstalledInventory ◀──────┘  decode + project + derive
                                                │ ordinal guard
                                       InstalledStore (@MainActor)
                                          ╱            ╲
                          Installed list  │            │  membership sets
                          (authoritative) │            │  ∩ catalog.results (Browse)
                                          ╲            ╱
                                    CatalogStore.package(id)  ── decoration only

## Architecture Decisions

### D1 — `BrewClient` is one target depending on both libraries; nothing depends back

`.target(name: "BrewClient", dependencies: ["BrewProcess", "Catalog"])`, plus a `BrewClientTests`
target with a `Fixtures` resource copy. The edge is one-directional: `Catalog` gains no dependency, so
catalog-sync CS1 stays enforced *structurally by the package graph*, not by convention. `PackageID` and
`PackageKind` are imported, never re-declared.

| Option | Tradeoff |
|---|---|
| Installed logic inside `BrewProcess` | Forces `BrewProcess` → `Catalog`, or a duplicate `PackageID`; both worse than one new target |
| Pure `BrewClient` + separate `Inventory` join target | Cleaner on paper; a second target to carry for a join that is two dictionary lookups (D5) |
| **One `BrewClient` (chosen)** | One new target, reuses catalog identity, keeps CS1 provable from `Package.swift` |

Public surface: `InstalledPackage`, `InstalledKeg`, `InstalledInventory`, `InstalledInventoryError`,
`InstalledLoadState`, `InstalledStore`, `InstalledChangeObserving`, `FSEventsInstalledObserver`,
`InstalledRefreshCoordinator`, `LoopOwner`. Everything else is internal.

### D2 — Acquisition is a thin streaming adapter over a pure parse function

The snapshot is fetched through `BrewRunner.start(.read(["info", "--installed", "--json=v2"]))` — the
`.read` kind exists precisely so a re-snapshot can run alongside M2-2's mutation gate without queueing
behind it. `BrewInfoPayloadSource` (production) does nothing but drain `operation.lines`, `await
operation.exit()`, and hand both to a pure, synchronous function:

```swift
static func payload(from lines: [LogLine], exit: BrewExit) throws(InstalledInventoryError) -> Data
```

which joins `.stdout` line text, maps a non-zero exit to `.commandFailed(status:message:)` carrying the
`.stderr` tail, and maps empty stdout to `.malformedPayload`. All acquisition semantics are therefore
unit-testable with no process and no fake launcher; the adapter that remains is ~20 lines of glue.

Rejected: reusing `BrewProcessTests`' `FakeProcessLauncher`. It conforms to a `BrewProcess` protocol, so
it cannot move into `CellarTestSupport`, which declares *no* dependencies by design (M2-0 D5). Copying
it would be ~150 duplicated lines to test glue a pure function already covers. Also rejected: adding a
"collect output" API to `BrewRunner` — additive runner surface is M2-2's scope.

Cost note: rejoining 21,708 lines into ~663 KB of `String` then `Data` runs entirely inside the
`@concurrent` decode (D3), so the main actor never sees it. Peak is ~3× payload — 2 MB today, ~6 MB at
the 500-formula extrapolation (explore risk 6).

### D3 — Slim projection, asymmetric decoding, kegs as a list

`InstalledDecoder.decode(_:)` is `@concurrent` (attribute before modifier — M1's apply-time finding) and
mirrors `CatalogDecoder`: envelope → `LossyArray`-style per-record tolerance → projection. Dropped at
decode: `bottle`, `urls`, `artifacts`, `ruby_source_checksum`, `runtime_dependencies`, `used_options`,
`sha256`, `service`, `depends_on`, `conflicts_with`.

Formula `installed` is an **array of keg objects**; cask `installed` is a **plain String** (verified,
explore §2). Two wire types, two `init(from:)`, one projection target:

```swift
public struct InstalledKeg: Sendable, Hashable {   // formula: one per keg; cask: exactly one, synthesised
    public let version: String
    public let installedAt: Date       // epoch seconds: formula `installed[].time`, cask `installed_time`
    public let installedOnRequest: Bool
}
```

`InstalledPackage.kegs` is always a list, so a multi-version formula is *represented*, never dropped —
the case no probe machine could produce. `versions.stable` (formula) / `version` (cask) is kept as
`catalogVersion`; `linked_keg` selects `primaryKeg`, falling back to the newest `installedAt`.
`auto_updates` decodes as `Bool?` and is folded at *derivation*, not decode, so "declared false" and
"absent" stay distinguishable in the wire layer.

### D4 — Every badge is derived from the one payload; the auto-updates exclusion is asserted twice

| Signal | Rule | Source |
|---|---|---|
| `isOutdated` (formula) | wire `outdated` verbatim | matches `brew outdated` exactly (explore §2) |
| `isOutdated` (cask) | `wire.outdated && !isSelfUpdating` | probe #7081: info already applies the auto-updates exclusion; the conjunction is belt-and-braces so a future brew change cannot make Cellar nag |
| `isSelfUpdating` | `autoUpdates == true` (`nil` ⇒ false, "not declared") | product Q3 |
| `hasNewerVersion` | `installed != version`, **self-updating casks only** | probe #7081 — the greedy signal without a second spawn. Informational; never badges, never counted |
| `isOnRequest` | formula: `kegs.contains(\.installedOnRequest)`; cask: always `true` | no `installed_as_dependency` key exists |
| `isPinned` / `pinnedVersion` | wire `pinned` / `pinned_version`, both namespaces | `brew list --pinned` is redundant |
| `installedAt` | `primaryKeg.installedAt` | epoch seconds |

`outdatedCount` — the badge — counts `isOutdated` only. A self-updating cask with a newer version is
therefore visible in its own section and invisible to the badge, which is exactly Q3.

### D5 — The inventory is the authority; the catalog is decoration. Both joins are O(visible)

Two directions, neither of which walks the 16k catalog:

1. **Installed list → catalog.** Resolved lazily per rendered row via the existing
   `CatalogStore.package(id)` (O(1) dictionary hit, ~30 visible rows) purely to *decorate* with install
   counts and analytics. A cold, empty or poisoned catalog costs decoration, never a missing row.
2. **Browse → inventory.** `InstalledInventory` publishes `installedIDs: Set<PackageID>` and
   `outdatedIDs: Set<PackageID>`, built once in the same off-main pass. Browse intersects against a
   ≤200-row page.

Rejected: an eager join producing `[PackageID: (InstalledPackage, CatalogPackage)]` at snapshot time. It
couples two independent refresh cadences and makes the Installed list wait for a catalog it does not
need.

### D6 — `InstalledStore`: request-keyed single flight, ordinal-guarded adoption, last-good-survives

The M2-0 D3 recipe verbatim — token slot, `defer { vacate(token) }` *inside* the task body so no caller
can join settled work — with the fix M2-0 deferred here: **the slot is keyed by the request**, i.e. the
`BrewInstallation.executableURL` it was started for. A refresh issued after the user repoints `brew`
cannot join an in-flight snapshot of the *previous* installation and adopt its answer. (Scope delta: the
same three-line fix is applied to `BrewDetectionStore.refresh()`, closing M2-0's first open question in
the change that M2-0 nominated for it.)

Adoption copies M2-0 D1: `@concurrent` decode → a `Sendable` `InstalledInventory` → **one** main-actor
assignment, admitted only if its ordinal still exceeds `installedSequence`, so a slow large snapshot
overtaken by a fast one is discarded rather than installed on top of fresher data.

```swift
public func refresh(using installation: BrewInstallation?) async
```

`nil` (brew absent or invalid) clears to an empty inventory and `state = .brewAbsent` without spawning
anything. On failure the **last good inventory stays resident** and `state = .failed(error)` — the
catalog's discipline. `InstalledInventoryError` is closed: `.brewUnavailable`, `.commandFailed(status:
message:)`, `.malformedPayload`, `.cancelled`.

### D7 — Browse composition sits above the index; `SearchFilters` and PS4 are byte-identical

`CatalogFilterBar` gains an `InstalledFilterMode { all, installed, notInstalled, outdated }` picker
resolved **in the app target**. `SearchFilters`, `PackageSearchIndex` and `openspec/specs/package-
search/spec.md` are untouched.

The mode is not a uniform post-filter, because `catalog.results` is already capped at `resultLimit`
(200): intersecting an empty-query page with ~160 installed IDs would render ~0 rows.

| Mode | Source |
|---|---|
| `all` | `catalog.results`, unchanged |
| `installed` / `outdated` | the **inventory** (≤ few hundred records), name/desc-matched against the live query and sorted by name — no index needed at that size — decorated per D5 |
| `notInstalled` | `catalog.results` minus `installedIDs`; a ≤1%-of-catalog subtraction removes ~2 rows from a 200-row page, so the cap interaction is negligible here |

With `state == .brewAbsent` the picker is forced to `all` and rendered `.disabled(true)`; catalog browse
and search are otherwise unaffected.

### D8 — `InstalledChangeObserving`: a pure invalidation signal, C-confined, zero `@unchecked`

```swift
public protocol InstalledChangeObserving: Sendable {
    /// Coalesced "something under the watched roots changed". Never parsed.
    func changes() -> AsyncStream<Void>
}
```

`FSEventsInstalledObserver` watches `<prefix>/Cellar` and `<prefix>/Caskroom`, derived from
`installation.executableURL.deletingLastPathComponent().deletingLastPathComponent()` — uniform across
all three `BrewPrefix` cases, so no `BrewProcess` API is added. FSEvents is chosen over
`DispatchSource.makeFileSystemObjectSource` because the latter is non-recursive and would miss every
upgrade (explore §4).

**Confinement invariant (Swift 6 strict concurrency, no `@unchecked Sendable` anywhere):**
`FSEventStreamContext.info` carries `Unmanaged<Box>.passRetained(...).toOpaque()`, where `Box` is a
`final class Sendable` whose only stored property is a `let continuation: AsyncStream<Void>.Continuation`
(itself `Sendable`). The `@convention(c)` callback is a file-scope function that captures nothing,
recovers the box with `Unmanaged.fromOpaque(info).takeUnretainedValue()`, and does exactly one thing:
`continuation.yield()`. It never reads event paths or flags. The stream runs on a private
`DispatchQueue` via `FSEventStreamSetDispatchQueue`; the box is retained before `FSEventStreamStart` and
released only after `Stop` → `Invalidate` → `Release`, all serialised by a `Mutex` holding the stream
ref — the `SystemProcess` D1 precedent. Creation flags are the deferred default (no `NoDefer`), so the
OS coalesces bursts before our own debounce ever sees them.

### D9 — `InstalledRefreshCoordinator` owns cadence; the observer owns nothing but the signal

All timing logic lives outside CoreServices so it is testable through a fake:

- **Debounce** — a quiet window of **2 s** on an injected `any Clock<Duration>`; a `brew upgrade`
  writing for minutes produces exactly one refresh, at the end.
- **Suppression** — while `isMutating` is true (a simple injected flag object M2-2 will drive), signals
  are swallowed; one re-snapshot fires at the terminal outcome.
- **Baseline (always on, watcher or not)** — refresh at launch and on
  `NSApplication.didBecomeActiveNotification`, mirroring the existing `brewDetection.refresh()` wiring.

### D10 — App-level loop ownership: an idempotent `LoopOwner` holding unstructured tasks (#8/#9)

```swift
@MainActor @Observable public final class LoopOwner {
    public func start(_ id: String, _ body: @escaping @MainActor () async -> Void)  // idempotent per id
    public func isRunning(_ id: String) -> Bool
}
```

Dependency-free (closures, not stores), so it lives in `BrewClient` and is fully unit-testable in the
`swift test` inner loop. `cellarApp` holds it as `@State` — App-level state outlives every scene — and
each scene calls `loops.start("catalog") { await catalog.start() }` / `loops.start("installed") { … }`
from `.task`. Because the tasks are **owned by the object, not by the scene's task tree**, closing the
window that started the app no longer cancels them (#8), and the event stream is never re-subscribed
(#9). The per-id guard preserves the "second window must not start a second loop" semantics; open →
close → open re-enters `start`, finds the loop running, and returns.

### D11 — `BrewPrefix` rename is source-only

`case appleSilicon → native`, `case intelCarryOver → rosettaCarryOver`; `.custom(URL)` unchanged.
`BrewPrefix` is `Sendable, Equatable` and **not `Codable`**, so nothing persisted moves. Call sites:
`DefaultBrewLocator.standardCandidates` (2) plus test references. `Advisory.rosettaPrefix` is out of
scope for the nit and stays. No behaviour change; the `brew-detection` spec text S1 is realigned by the
spec phase.

### D12 — Everything through fakes; one thin adapter untested by design

No live-brew mutation test is added, and no test spawns `brew` (explore risk 4). The FSEvents adapter is
the single untested-by-design surface: a ~40-line bridge with no branch beyond "yield". Compensating
controls: (i) every coalescing, suppression and baseline behaviour is tested through
`FakeInstalledChangeObserver` + the shared `TestClock`; (ii) `payload(from:exit:)` isolates the other
untestable boundary into a pure function; (iii) tasks carries one manual verification step — install
something in Terminal, observe exactly one refresh.

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift` | Modify | `BrewClient` target + product, `BrewClientTests` with `Fixtures` |
| `Sources/BrewClient/InstalledWire.swift` | Create | Formula/cask wire records, asymmetric `installed` decoding |
| `Sources/BrewClient/InstalledModels.swift` | Create | `InstalledPackage`, `InstalledKeg`, `InstalledInventory`, error, load state |
| `Sources/BrewClient/InstalledDecoder.swift` | Create | `@concurrent` decode + projection + D4 derivation |
| `Sources/BrewClient/InstalledPayloadSource.swift` | Create | Protocol, pure `payload(from:exit:)`, `BrewInfoPayloadSource` |
| `Sources/BrewClient/InstalledStore.swift` | Create | D6 store |
| `Sources/BrewClient/InstalledChangeObserving.swift` | Create | Seam + `InstalledRefreshCoordinator` |
| `Sources/BrewClient/FSEventsInstalledObserver.swift` | Create | D8 adapter |
| `Sources/BrewClient/LoopOwner.swift` | Create | D10 |
| `Sources/BrewProcess/BrewLocation.swift` | Modify | D11 rename (`BrewPrefix` lives here, not in a `BrewPrefix.swift`) |
| `Sources/BrewProcess/DefaultBrewLocator.swift` | Modify | Two renamed call sites |
| `Sources/BrewProcess/BrewDetectionStore.swift` | Modify | Request-keyed slot (D6 scope delta) |
| `Tests/BrewClientTests/**` + `Fixtures/installed-info.json` | Create | Trimmed fixture: multi-keg formula, dependency-only formula, outdated formula, self-updating cask with `installed != version`, plain cask |
| `cellar/cellarApp.swift` | Modify | `LoopOwner`, `InstalledStore`, activation-driven refresh |
| `cellar/ContentView.swift` | Modify | Installed sidebar section + detail routing |
| `cellar/Installed/{InstalledListView,InstalledFilterBar,InstalledRow,InstalledEmptyState}.swift` | Create | List, dependency toggle, badges, self-updating section, brew-absent guidance |
| `cellar/Browse/{CatalogFilterBar,BrowseView}.swift` | Modify | D7 mode picker and row source |
| `cellar.xcodeproj/project.pbxproj` | Modify | Link `BrewClient` into the app target |

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit — payload | Non-zero exit → `.commandFailed` with the stderr tail; empty stdout → `.malformedPayload`; interleaved stderr never enters the JSON | `payload(from:exit:)` with synthesised `[LogLine]`, no process |
| Unit — decode | Formula keg array and cask String both decode; a multi-keg formula keeps every keg; one corrupt record is skipped, not fatal | Fixture + hand-built records |
| Unit — derive | Each D4 row, including a self-updating cask with `installed != version` asserting `isOutdated == false`, `hasNewerVersion == true`, `outdatedCount` unchanged | Parameterised over fixture records |
| Unit — inventory | `installedIDs` / `outdatedIDs` membership; sort order; empty inventory is a valid value, not an error | Direct construction |
| Unit — store | Two overlapping refreshes run once; a refresh arriving after the previous settled starts new work; a refresh under a *different* installation does not join | Counting `FakeInstalledPayloadSource` |
| Unit — store | Out-of-order adoption: the newer inventory is resident, the older is discarded | Two scripted payloads with controlled completion order |
| Unit — store | A failed refresh keeps the last good inventory and surfaces `.failed`; `nil` installation yields empty + `.brewAbsent` and spawns nothing | Scripted failure, launch counter |
| Unit — coordinator | A burst of 20 signals inside the quiet window produces exactly one refresh; a signal during `isMutating` produces none, then exactly one at the terminal outcome; baseline refresh fires with no observer at all | `FakeInstalledChangeObserver` + `TestClock` |
| Unit — loops | `start` twice for one id runs one loop; open → close → open does not restart or double-start; a closed scene does not cancel a running loop | `LoopOwner` with counting closures |
| Unit — detection | The renamed `BrewPrefix` cases still classify both standard prefixes and carry `.rosettaPrefix` | Existing `DetectionTests`, renamed only |
| Integration (app, xcodebuild) | Installed section renders empty guidance with brew absent; the Browse mode picker is disabled there | Build-level only; no new live-brew test |
| Regression | Full suite green; `openspec/specs/package-search/spec.md` byte-identical | `swift test --package-path Packages/CellarCore`; `git diff --exit-code` on the spec file |

Every component is RED-first: the failing test precedes its production change.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A — no file is classified or executed by this change | — | — |
| Git repository selection | N/A — no VCS invocation | — | — |
| Commit state | N/A — no VCS invocation | — | — |
| Push state | N/A — no VCS invocation | — | — |
| PR commands | N/A — no PR automation | — | — |
| **Subprocess argument composition** | **Applicable** — one new `brew` invocation | argv only, via `BrewCommand.read(["info", "--installed", "--json=v2"])`; fixed vector, zero user-supplied or catalog-supplied tokens, no shell, no string joining, `.read` kind so it never enters the mutation gate; environment from the existing `BrewEnvironment.current()` | Assert the recorded `ProcessSpec.arguments` equals that exact vector and that `kind == .read` |
| **Untrusted subprocess payload** | **Applicable** — stdout is arbitrary bytes of arbitrary size | Non-zero exit is an error, never an empty inventory (which would read as "nothing installed"); malformed JSON is `.malformedPayload` and keeps the last good inventory; per-record tolerance skips a corrupt entry instead of failing the snapshot; decode is off-main so a pathological payload cannot freeze the UI | Non-zero exit; truncated JSON; corrupt single record; stderr interleaving |

No new file location, no network call, no persisted format, and no privilege boundary is introduced.
`SystemProcess`'s `standardInput = /dev/null` is unchanged — this slice issues reads only.

## Migration / Rollout

No migration. Nothing persisted changes: `BrewPrefix` is not `Codable`, the inventory is derived data
held in memory only, and `CatalogSnapshot`'s schema version stays at 1. Rollback is `git revert` of the
single merge commit, which removes the target, the app-target link and all Installed UI at once.

## Review Budget Forecast

**~2,300–2,700 authored lines** (production ~1,050, tests ~900, app UI ~500) against the accepted
`size:exception` for one PR (product decision Q4, #7079). If the exception is withdrawn at the tasks
forecast, the clean cut is D8+D9+D10 (watcher, coordinator, loop ownership ≈ 700 lines) as a second PR,
leaving D1–D7 + D11 shippable on focus-and-launch refresh alone.

## Open Questions

- [ ] **`brew`'s external lock.** A concurrent Terminal `brew install` can make our read fail on
      Homebrew's own lock. `.commandFailed` already keeps the last good inventory, but the exact stderr
      shape is UNVERIFIED (explore risk 3) and may deserve a friendlier surface. Deferred to M2-2, which
      owns mutation error UX.
- [ ] **Quiet window of 2 s.** Chosen as the explore §4 floor. If a 500-formula machine makes a
      snapshot cost 3–4 s, the window should probably scale with the last observed snapshot duration.
      Left fixed and injected so it can change without touching the coordinator's logic.
