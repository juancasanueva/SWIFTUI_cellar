# Proposal: M1 — Catalog sync, package search, Browse UI

**PRD milestone**: M1 — Core & Catalog (second and final slice; closes the M1 exit criterion
"search 14k packages instantly, view any package's full details").

## Intent

`m1-brewrunner-core` shipped the substrate — a `BrewRunner` actor and brew detection — but the app
still renders the Xcode template: a `@Query [Item]` sidebar over a placeholder SwiftData model. There
is no package data, no search, and nothing a user can do. This change turns Cellar! into something
that answers a real question ("what is this package, and should I install it?") without Terminal,
and it does so entirely offline-capable and independent of whether `brew` is installed — the
`absent` state the detection spec declares must gate nothing.

Every later milestone reads from this catalog: Installed (M2) joins against it, Security (M4) matches
CVEs by name+version, Discover (M5) ranks it. Getting the acquisition seam, the on-disk projection,
and the search contract right now avoids retrofitting all three.

## Scope

### In Scope

1. **Catalog sync** — HTTPS fetch of `formula.json` + `cask.json` from formulae.brew.sh behind a
   `CatalogSource` protocol seam; streamed to disk (`download(for:)`, ≥40 MB combined budget);
   conditional revalidation via `If-Modified-Since` (and `If-None-Match` if the origin confirms an
   `ETag` during apply); atomic persistence of a **slim decoded projection** plus a
   `catalog-state.json` sidecar in `~/Library/Application Support/com.juancasanueva.cellar/Catalog/`;
   24 h background refresh + manual refresh; a failed sync MUST NOT erase a good cached catalog;
   tolerant decoding (cask `name` is `[String]`, nullable `desc`/`caveats`, `uses_from_macos` mixed
   String/Object, unknown keys ignored, lossy arrays).
2. **Analytics** — 365-day install-on-request counts for formulae and casks from the flat ranked
   endpoints; comma-grouped string counts parsed locale-independently; counts surfaced as
   **opt-in-only lower bounds** (Homebrew analytics are opt-out), per PRD principle 3.
3. **Search** — in-memory linear byte scan over pre-normalised ASCII-folded text (~1 MB for ~15.5k
   records). Ranking: exact token > prefix > name substring > desc substring; ties broken by install
   count. Index keyed on `(kind, name)` with a formula/cask badge. A Swift Testing p95 < 8 ms
   assertion over a real-sized fixture is the escalation tripwire; PRD's trigram index is documented
   as the fallback and **not built**.
4. **Browse UI** — `NavigationSplitView` shell with real sections only (Browse + a home for the
   existing detection status); as-you-type search; filters that the catalog can actually answer
   (formula/cask, deprecated, disabled); package detail: description, homepage, license, version,
   direct build/runtime dependencies, dependents, analytics count, caveats, deprecation/disabled
   status, tap of origin.
5. **Structure** — a new `Catalog` target in `CellarCore`, **independent of `BrewProcess`** (network,
   decode, index only), plus `CatalogTests` with fixtures captured from live endpoints; a
   `@MainActor @Observable CatalogStore` app-side mirroring `BrewDetectionStore`; template
   `ContentView`/`Item.swift`/`Schema([Item.self])` dead code removed.
6. **Fold-in (docs only)** — reconcile two archive-review spec-wording nits (see Modified
   Capabilities). No code, no behaviour change.

### Out of Scope

- **Installed / not-installed and outdated filters.** The bulk API dumps are generated server-side:
  `installed` is always empty and `outdated` always false. These filters are not "minimal work" —
  they require the authoritative `brew info --installed --json=v2` snapshot, i.e. `BrewClient`,
  which is M2. The Browse filter bar ships without them rather than shipping a lying control.
- **Recursive dependency tree UI.** v1 renders a flat list of direct build + runtime dependencies and
  of dependents; each row navigates to that package's detail, so the graph is walkable by navigation.
  Tree rendering with cycle handling is M2+.
- Discover tab, ⌘K quick-open, pre-install cask inspection (M5); install/uninstall/upgrade actions
  (M2); third-party tap packages (absent from the bulk dumps — documented as a limitation, not a bug);
  SwiftData for the catalog; onboarding UI.

## Capabilities

### New Capabilities

- `catalog-sync`: acquiring, revalidating, persisting and refreshing the Homebrew catalog — source
  seam, conditional requests, atomic snapshot swap, cache-preserving failure, decode tolerance,
  freshness state.
- `package-search`: the in-memory index and query contract — normalisation, `(kind, name)` identity,
  ranking order, filter predicates, and the measured latency ceiling.
- `package-detail`: the detail projection a package must expose — required fields, dependents derived
  by inverting catalog dependency edges, analytics join and lower-bound semantics, deprecation and
  disabled status, tap origin, and the explicit third-party-tap exclusion.

### Modified Capabilities

Editorial reconciliation only — **no behavioural requirement changes**; `sdd-spec` should emit
minimal deltas, not rewrites.

- `brew-execution`: the "Terminal result and exit handling" requirement enumerates three terminal
  outcomes (normal exit, cancelled, spawn failure) but the following clause treats *unresponsive
  cancellation* as a fourth, distinct error outcome. Reconcile the enumeration with the clause.
- `brew-detection`: in "Disappearing configured path transitions away", the THEN block mixes an
  outcome enumeration with a disambiguation rule. Split them so the scenario reads as one assertion
  plus one stated distinction.

**Declined fold-in**: the S1 vocabulary nit (spec `native`/`rosettaCarryOver` vs. code
`BrewPrefix.appleSilicon`/`.intelCarryOver`) is *not* a one-line docs edit — it either renames shipped
public API or rewrites vocabulary across several requirements. It belongs to a change that touches
`BrewProcess`; this one deliberately does not.

## Approach

1. **Acquisition behind a seam first.** `CatalogSource` is a protocol with a live HTTPS implementation
   and fakes. This keeps the door open for the cheaper `$(brew --cache)/api/*.jws.json` path later
   without re-plumbing, while keeping M1 working when `brew` is absent.
2. **Decode once, persist slim.** The 40 MB raw dumps are transient. Only Browse+detail fields survive
   into an `Encodable` projection (dropping `bottle`, `variations`, `patches`, `ruby_source_checksum`
   removes most of the bytes), written atomically via temp file + `FileManager.replaceItemAt`. Wire
   models are `Decodable`-only, defensively shaped.
3. **Measure before optimising.** Linear scan over ~1 MB is a single memory sweep on Apple Silicon.
   The performance test is the contract; trigrams are a documented escalation, not a deliverable.
4. **Off-main by construction.** All catalog work lives in `CellarCore`, whose SwiftPM default
   isolation is `nonisolated`; only `CatalogStore` crosses to the UI. Zero catalog logic in the app
   target, whose `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would main-isolate it silently.
5. **Strict TDD** against captured fixtures — decode tolerance, 304 revalidation, failed-sync
   preservation, ranking order, and the latency assertion all start RED.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `Packages/CellarCore/Package.swift` | Modified | `Catalog` library product + target + `CatalogTests` |
| `Packages/CellarCore/Sources/Catalog/` | New | Wire models, `CatalogSource`, file store, analytics, `SearchIndex` |
| `Packages/CellarCore/Tests/CatalogTests/` | New | Fixtures + decode/index/ranking/latency suites |
| `cellar.xcodeproj/project.pbxproj` | Modified | Link the `Catalog` product into target `cellar` |
| `cellar/` (app target) | Modified | Browse shell, detail view, `CatalogStore`; delete `Item.swift` and the template `ContentView` |
| `cellar/cellarApp.swift` | Modified | Drop `Schema([Item.self])`; inject `CatalogStore` |
| `openspec/specs/brew-*/spec.md` | Modified | Two editorial reconciliations |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| **Review budget overrun** — forecast ~2,500–3,500 authored lines vs. a cached 800-line budget on `single-pr` | **High** | `sdd-tasks` must forecast explicitly and propose three autonomous slices (sync/decode → index/search → Browse UI). Either the strategy moves to chained PRs or the user accepts an explicit `size:exception` **before** apply — as M1's first slice did at 3.6k lines |
| Decode memory spike over 40 MB of JSON | Med | Slim `Decodable` shape + memory-mapped `Data`; measure peak RSS during apply |
| Schema drift in the Homebrew API | Med | `decodeIfPresent` + defaults + lossy arrays + an unknown-key tolerance fixture test |
| `URLCache` silently converting 304 → synthesised 200 | Med | `.reloadIgnoringLocalCacheData` + manual validators; check `statusCode == 304` before touching the downloaded file |
| Origin unavailability (live 503/404 observed while exploring) | Med | Retry with backoff, skip 4xx except 429, never invalidate a good cache on failure |
| Analytics counts read as absolute truth | Med | UI copy labels them as reported by opted-in Homebrew users over 365 days |
| Removing `Item` from the SwiftData schema breaks an existing local store | Low | No shipped users; delete the dev store if it fails to open. Documented in the rollback plan |
| Payload growth beyond the 40 MB budget | Low | Sizing, timeouts and progress copy assume growth; state is versioned via `schemaVersion` |

## Rollback Plan

Single revert of the merge commit restores `main`. Partial rollback: `Packages/CellarCore/Sources/Catalog/`
and `Tests/CatalogTests/` are purely additive — delete both directories plus the `Catalog` product,
target and test target from `Package.swift`. The `project.pbxproj` change is one product dependency;
revert it with `git checkout main -- cellar.xcodeproj/project.pbxproj`. App-target deletions
(`Item.swift`, template `ContentView`) come back with the same revert; a local SwiftData store that
still contains `Item` rows is disposable — delete the store file. On-disk catalog cache is removed by
deleting `~/Library/Application Support/com.juancasanueva.cellar/Catalog/`; nothing else reads it.
No migrations, no user data, no network state to unwind.

## Dependencies

- Network access to `formulae.brew.sh` for capturing fixtures (tests themselves run offline).
- `ETag`/`If-None-Match` support on the origin — **unverified**; confirm with `curl -sI` during apply
  and fall back to `If-Modified-Since` alone (which Homebrew's own `api.rb` proves works).
- No dependency on `brew` being installed, and none on `BrewProcess`.

## Success Criteria

- [ ] A cold launch with no cache downloads both dumps, persists a slim snapshot, and lists packages.
- [ ] A second sync within 24 h revalidates conditionally and does not re-download the payloads.
- [ ] A sync failure (offline, 503, malformed body) leaves the previously cached catalog intact and usable.
- [ ] Malformed or unknown-shaped records do not prevent the remaining ~15.5k from decoding.
- [ ] As-you-type search over the real-sized fixture holds p95 < 8 ms and returns the specified ranking order.
- [ ] Any package's detail shows description, homepage, license, version, direct dependencies,
      dependents, analytics count, caveats, deprecation/disabled status, and tap.
- [ ] Analytics figures are labelled as opt-in-only lower bounds.
- [ ] `swift test --package-path Packages/CellarCore` passes with no GUI; every behaviour above was written test-first.
- [ ] No template `Item` code remains in the app target.
