# Exploration: M5 Pro-parity flows (`m5-pro-parity`)

Exploration for PRD M5 (PRD.md §7; feature detail §3.1, §3.2, §3.4, §3.7). Repository evidence read
at clean `main` `af0c940` (M4 security archived). Artifact store is hybrid; this is the OpenSpec copy
(Engram topic `sdd/m5-pro-parity/explore`, observation 7476).

**Scope note:** the user trimmed M5 before this exploration. **Apple Silicon Migration and Adopt
Existing Apps are REMOVED** and appear nowhere below. Six features remain: Health dashboard,
pre-install cask inspection, release notes preview, Brewfile import/export, bulk-operations polish,
Discover tab.

---

## Current State

### CellarCore target graph (verified in `Packages/CellarCore/Package.swift`)

Products: `BrewProcess`, `Catalog`, `DiskUsage`, `BrewClient`, `SecurityKit`, `Persistence`, plus
non-product `CellarTestSupport`. Edges: `Catalog` and `BrewProcess` are leaves;
`DiskUsage → {BrewProcess, Catalog}`; `BrewClient → {BrewProcess, Catalog, DiskUsage}`;
`SecurityKit → {Catalog}`; `Persistence → {BrewClient, SecurityKit}` as the deliberate outermost
node. Every target is `.swiftLanguageMode(.v6)`, platform `macOS 26.0`.

**PRD §4.1 declares a `ReleaseNotes` target. It does not exist.** M5 creates it.

### App shell

`cellar/Shell/AppSection.swift` has eight cases: `home, browse, installed, taps, services, cleanup,
security, history`. There is **no** `health` and **no** `discover`. `cellar/Home/HomeView.swift` is
today a two-block summary (brew detection + catalog freshness) — it is not a health dashboard and
does not read any inventory.

Shipped spec capabilities (16): `brew-detection`, `brew-execution`, `catalog-sync`,
`package-search`, `package-detail`, `package-mutation`, `installed-inventory`, `operation-activity`,
`installation-history`, `local-package-metadata`, `service-management`, `tap-management`,
`disk-usage`, `cleanup-operations`, `vulnerability-scanning`, `artifact-integrity`.

### brew CLI surfaces already wrapped

| Invocation | Owner | Kind |
|---|---|---|
| `info --installed --json=v2` | `BrewInfoPayloadSource` | read |
| `services list --json`, `services info --json <name>` | `ServicesListPayloadSource`, `ServiceInfoPayloadSource` | read |
| `services start\|run\|stop\|restart` | `ServiceCommand` | mutate |
| `tap-info --installed --json` | `BrewTapPayloadSource` | read |
| `tap <name>`, untap (+ force) | `TapCommand` | mutate |
| `cleanup [--dry-run] [--prune=all] [name]`, `autoremove [--dry-run]` | `CleanupCommand` | both |
| `install/uninstall/reinstall/upgrade/pin/unpin`, `uninstall --cask --zap`, bare `upgrade` | `MutationCommand` | mutate |
| `--version` | detection | read |

**Not wrapped, and needed by M5:** `brew doctor`, `brew bundle *`, and a "last `brew update`"
signal. `brew outdated` is deliberately absent and stays absent — outdated state already arrives on
the `info --installed --json=v2` record (`InstalledDecoder` → `snapshotOutdated`).

### Reusable seams (all shipped and proven)

| Concern | Seam | M5 reuse |
|---|---|---|
| argv safety | `BrewCommand` (argv only, never a shell string), `MutationName.isSafe`, `PackageTarget`/`FormulaID`/`CaskID` making an unvalidated command **unrepresentable** | Brewfile names, doctor, bundle |
| Mutation spine | `BrewMutating` (`arguments`, `verb`, `packageID`, `requiresConfirmation`, `invalidates: InvalidationScope`, `diskAreas`), `AnyBrewMutation`, `OperationCenter` FIFO gate | Any new mutation, or fan-out instead |
| Bulk fan-out | `OperationCenterBulk.submitUpgrades/submitBulk/commands`; recorded ruling — a selection fans out into N ordinary submissions so each gets its own queue item, log, cancel and terminal outcome | Brewfile selective apply, bulk polish |
| HTTP acquisition | `CatalogSource` + `HTTPCatalogSource` (ephemeral config, `urlCache = nil`, `reloadIgnoringLocalCacheData`, ETag/`If-Modified-Since`, `download(for:)` to disk, 304 classified before the temp file is opened, byte-limit guard, atomic staging) | GitHub Releases client |
| Credentials | `AdvisoryCredentialStoring` + `KeychainAdvisoryCredentialStore` (generic password, `kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable = false`, query asserted in tests but calls untested) | Optional GitHub PAT — a second service name, not a second mechanism |
| Network consent | `ScanConsent` (M4 opt-in + transmission disclosure) | Release-notes egress must reuse this vocabulary |
| Typed honesty | `CleanupEvidence`/`CleanupReportedTotal.unknown`/`CleanupOrphans.known\|notApplicable\|unknown`/`unknownLines: [Data]`/`issues: Set<CleanupParseIssue>`; `CVEScanOutcome` `.notCovered`; `skippedRecordCount` | Health score inputs, Brewfile skipped lines |
| Store shape | `@MainActor @Observable`, `@ObservationIgnored` internals, `private(set)` state, closed load-state enum, last-good survival, per-scope generation/task maps (`CleanupStore`, `SecurityStore`) | Every new store |
| Off-main decode | `@concurrent static func decode(...)` — attribute **before** the modifier (the other order does not compile; recorded as having cost an apply cycle in M1) | Brewfile parse, releases decode |
| Fixture standard | `Tests/BrewClientTests/Fixtures/Cleanup/` — byte-exact captures, `README.md` with brew version + exact argv + exit code, `probe-manifest.txt`, SHA-256 per stream | doctor, bundle, GitHub captures |

---

## Feature-by-feature: what exists, what is new

### 1. Health dashboard + score (PRD §3.4) — mostly composition, two genuinely new inputs

Five of the seven dashboard rows are **already computable from shipped stores**:

| Row | Existing source |
|---|---|
| Outdated count, formula/cask split | `InstalledStore` inventory + `InstalledSections(entries:outdatedIDs:)`, which already separates `outdated` from `selfUpdating` (casks that update themselves) and is fed the snooze-narrowed `outdatedIDs` |
| Vulnerable count | `SecurityStore.state(for:)` → `SecurityScanResult`, plus `coverage(for:) -> CoverageTotals` |
| Orphaned dependencies | `CleanupCommand(scope: .autoremove).previewCommand` is already `brew autoremove --dry-run`; `CleanupParser.parseAutoremove` yields `CleanupOrphans.known(names:reportedCount:currentlyOnDiskBytes:)` / `.unknown` |
| Duplicate old versions | `DiskUsageSnapshot.packages[].versions: [DiskVersionUsage]` with `FormulaLinkState` — multiple versions per package are already enumerated and sized |
| Cache size | `DiskUsageSnapshot.cache: DiskObservation` (`allocatedBytes`, `logicalBytes`), root `~/Library/Caches/Homebrew` from `HomebrewRoots.cache` |

Remediation actions all exist too: `MutationCommand.upgradeAll`, `CleanupCommand(.autoremove)`,
`CleanupCommand(.global)`.

**Genuinely new, and hostile:**

- **`brew doctor`.** Verified: doctor writes its warnings to **stderr** and exits **non-zero when
  warnings exist**. Every existing payload source encodes exactly the opposite rule —
  `InstalledPayload`, `ServicesPayload` and `TapPayload` all treat a non-zero exit as an error and
  all deliberately exclude stderr from the document ("stderr never enters the document, at any
  position"). A doctor source built on that template would report a perfectly healthy machine as a
  failed command, and would then discard the only output that matters. Doctor needs its own,
  explicitly documented payload rule. PRD §9 open question 5 ("raw output vs structured grouping —
  start raw") should be settled in this milestone rather than carried.
- **Last `brew update` time.** No brew JSON publishes it and no wrapped surface produces it. Under
  API mode the candidate artefacts are the brew repo's `.git/FETCH_HEAD` mtime and
  `$(brew --cache)/api/*.jws.json` mtime. Which is authoritative under API-only updates is a probe,
  not a documented fact (U2 below).
- **The composite score.** This is a number users will trust. The M4 lesson applies directly: if the
  score counts `.notCovered` packages as clean, the false-negative failure M4 fought re-enters in a
  more prominent place. The score must be a pure value function over typed inputs that can each be
  `unknown`, and the "transparent breakdown" PRD §3.4 requires is what makes that testable.

**Architectural caution:** every shipped store owns its own acquisition. A `HealthStore` that polls
would double every existing refresh. Health should be a **pure projection** (`HealthSnapshot` value +
score calculator) fed by state the app already holds, owning only the two new acquisitions.

### 2. Pre-install cask inspection (PRD §3.1) — no new brew call, one decoder widening

Verified against the repo's own fixture `Tests/CatalogTests/Fixtures/cask-iterm2.json`: the published
cask record already carries `url`, `sha256`, `artifacts` (`app`, `zap.trash`, and the other artifact
stanzas), `depends_on`, `conflicts_with` and `auto_updates`. Nothing needs `brew info`.

`CaskWire` declares only 14 keys and lets the parser skip everything else — that key-subset is the
documented mechanism that makes the 31 MB dump decode into a few megabytes (`CatalogDecoder` D8).
`CatalogDecoder.project(cask:)` currently projects `auto_updates` and drops the rest.

So the work is: widen `CaskWire` + `CatalogPackage` with `url`, `sha256`, `artifacts`, `depends_on`,
and decide the **memory tradeoff** for projecting an artifacts array across ~8k cask records. Options:
project eagerly (simplest, measurable regression risk), or keep the current resident profile and
re-read one record on demand. This MODIFIES the shipped `catalog-sync` and `package-detail`
capabilities.

Signature/notarization: PRD §3.1 already says this is checked post-download or surfaced after
install. M4's `ArtifactIntegrityEngine` + `CodeSignatureInspecting` answer it post-install. **A
pre-install signature verdict is not derivable from the catalog and must not be claimed.**

### 3. Release notes preview (PRD §3.2) — new target, inputs already on the wire

Inputs are present in the payloads and unprojected. Verified in `Tests/CatalogTests/Fixtures/formula-git.json`:
`urls.stable.url` (`https://mirrors.edge.kernel.org/...`) and `urls.head.url`
(`https://github.com/git/git.git`). `homepage` is already projected. GitHub repo resolution therefore
needs the same `catalog-sync` widening as feature 2 — which is why these two share a slice.

New: a `ReleaseNotes` target (PRD §4.1 names it), depending on `Catalog` only, mirroring SecurityKit's
brew-free discipline. Contents: repo resolution from homepage/urls, a releases client over the
`CatalogSource` conditional-request discipline, a TTL cache (`AdvisoryCache` precedent), tag→release
matching, and a graceful "no release notes found" outcome as a **typed state**, not an empty string.

- **Rate limit:** api.github.com is 60 req/h unauthenticated. A per-package fetch during a bulk
  upgrade of 30 outdated packages burns half the hourly budget in one action. Fetching must be
  on-demand per sheet, cached, and never fanned out.
- **PAT:** `KeychainAdvisoryCredentialStore` is the exact precedent — a second service name under the
  same protocol shape, never `UserDefaults`/`@AppStorage`.
- **Markdown:** `AttributedString(markdown:)` needs no third-party dependency, but GitHub release
  bodies are GFM (task lists, tables, autolinks, @mentions) which it does not fully support. That
  limit belongs in the spec, not in a bug report later.
- **Privacy:** a release-notes fetch discloses a repo name to GitHub. M4 established opt-in consent +
  disclosure (`ScanConsent`) for network egress; this should extend that vocabulary rather than
  invent a second one.

### 4. Brewfile import/export (PRD §3.7) — the largest new brew surface

`brew bundle` is **built into Homebrew** (no `homebrew/bundle` tap). Subcommands: `dump`, `install`,
`check`, `cleanup`, `list`, `edit`, `add`, `remove`, `exec`, `sh`, `env`.

- **Export** = `brew bundle dump` writing to a user-chosen path. `--file=-` (stdout) is documented but
  has an upstream breakage history (homebrew-bundle #405, #426); a real path avoids it entirely.
- **Import diff preview** = `brew bundle check --verbose --file <path>` — a read that reports what is
  missing and changes nothing.
- **Selective apply is the hard part.** `brew bundle --file` applies the whole file; there is no
  "apply only these entries" flag. Two honest shapes:
  - (a) Cellar writes a filtered temporary Brewfile and runs `brew bundle install --file <temp>`.
    Introduces a Cellar-authored Brewfile *writer* with its own quoting/escaping surface.
  - (b) Fan the selection out into ordinary `MutationCommand.install(...)` submissions through the
    existing `OperationCenter`. Per-package queue item, log, copy-command, cancel, terminal outcome
    and history entry come free, and it reuses the recorded M2 fan-out ruling verbatim.
  **(b) is strongly preferred** and is consistent with the design decision already written into
  `MutationCommand.swift` (there is no `upgradeSelected` case, for exactly this reason).
- **Brewfile parsing is new.** A small Ruby-DSL-shaped grammar (`tap`, `brew`, `cask`, `mas`,
  `vscode`, `whalebrew`, with optional args/hashes). PRD excludes `mas` in v1 — those lines must be
  reported as skipped and counted, following the `skippedRecordCount` precedent, never silently
  dropped.
- **Threat-model widening.** This is the **first** path where a package name reaching argv comes from
  a file the user supplied, rather than from brew's own snapshot or the catalog. `MutationName.isSafe`
  and the `PackageTarget`/`FormulaID`/`CaskID` unrepresentability gate already exist and cover it —
  but the comment block at the head of `MutationCommand.swift` explicitly reasons from "names come
  from brew's own snapshot or from the catalog, never from free text". That reasoning changes here
  and must be restated deliberately.

### 5. Bulk operations polish (PRD §3.2) — small, but it reverses a recorded ruling

`BulkSelection` ships with exactly two actions and `Action` is `CaseIterable` **on purpose**, so that
the absence of bulk pin, unpin, snooze, favorite and note is a *test assertion* rather than a
convention (installed-inventory II13 sc4). Selection order is preserved end-to-end and reconciled
against the live inventory; `InstalledSections.displayed` is the single source of both render order
and selection order.

PRD §3.2 asks for multi-select → upgrade, uninstall, **pin**, **snooze**. Closing that gap means
deliberately reversing II13 sc4 and rewriting the structural test that guards it. That is a spec
MODIFICATION to `installed-inventory` (and `local-package-metadata` for snooze), requiring a user
decision — not a UI tweak. Note the two additions have different shapes: bulk pin is formula-only
(`FormulaID`, N brew mutations); bulk snooze touches no brew at all (pure SwiftData metadata).

### 6. Discover tab (PRD §3.1) — two thirds free, one third has no data source

- **Most-installed:** free. `HTTPCatalogSource` already downloads `analytics/install-on-request/365d.json`
  and `analytics/cask-install/365d.json`; `AnalyticsIndex` decodes them (with a deliberate
  locale-independent digit parser) and `CatalogSyncEngine` joins counts into
  `CatalogPackage.installCount365d`, carrying stale counts forward when an endpoint fails. A ranked
  list is a sort of the snapshot already in memory. Zero new egress.
- **Curated JSON:** an app-bundle resource plus a decoder. Small.
- **"New in the last 30 days" has no first-party source.** formulae.brew.sh publishes no
  date-added/`created_at` field — verified against the API documentation and against this repo's own
  formula and cask fixtures. Options:
  - (a) GitHub API over `Homebrew/homebrew-core` commit history per formula path — 60 req/h
    unauthenticated, unusable at catalog scale.
  - (b) Diff successive catalog snapshots locally. `CatalogStore.adopt` already enforces
    revision-ordinal monotonicity, so "packages that appeared since your last sync" is free, local
    and private — but it means "new to you", not "new in the last 30 days", and it is empty on first
    run.
  - (c) Drop the section.
  **(b) with honest labelling is recommended**, and the PRD wording should be amended rather than
  silently reinterpreted.

---

## Actor isolation and concurrency implications

- New stores follow the shipped shape: `@MainActor @Observable`, `@ObservationIgnored` internals,
  `private(set)` state, closed load-state enum, last-good survival on failure, per-scope
  generation/task maps for cancellable work.
- All parsing/decoding is `@concurrent static func` over `Data` — attribute before the modifier.
- `brew doctor` is a `.read` (bypasses the mutation gate, may run concurrently with an install).
  `brew bundle install`, if it ships at all, is a `.mutate` needing a `BrewMutating` conformer with
  `invalidates: [.installedInventory, .diskUsage]` and a `diskAreas` set. The recommended fan-out
  approach means **no new mutation family and no new `InvalidationScope` bit**.
- Health composes `BrewClient`, `DiskUsage` and `SecurityKit` state. **No core target may see both
  `BrewClient` and `SecurityKit`** except `Persistence` (deliberate, documented in `Package.swift`).
  Keep the score calculator pure over injected scalar inputs in a dependency-free position and
  compose the inputs in the app target — exactly how M4 composed the two.
- `ReleaseNotes` depends on `Catalog` only, preserving the brew-free leaf discipline.
- Discover projections belong in `Catalog` (it already owns the analytics join).

---

## Affected areas

- `Packages/CellarCore/Package.swift` — new `ReleaseNotes` target + product + test target with
  `resources: [.copy("Fixtures")]`.
- `Sources/Catalog/Wire/CaskWire.swift`, `Wire/FormulaWire.swift`, `CatalogDecoder.swift`,
  `CatalogModels.swift` — widen for `urls.stable`/`urls.head` and cask `url`/`sha256`/`artifacts`/
  `depends_on`. **Touches shipped `catalog-sync` and `package-detail`.**
- `Sources/Catalog/AnalyticsIndex.swift` + a new ranked-projection file — Discover.
- **New** `Sources/BrewClient/DoctorPayloadSource.swift` + parser — its own payload rule.
- **New** `Sources/BrewClient/BundleCommand.swift`, Brewfile parser, `bundle check` preview source.
- `Sources/BrewClient/BulkSelection.swift` — only if the II13 sc4 ruling is reversed.
- **New** `Sources/ReleaseNotes/` — repo resolution, releases client, cache, models, PAT store.
- **New** health-score value type + `HealthSnapshot` projection.
- `cellar/Shell/AppSection.swift` — `.health` and `.discover` cases; `cellar/ContentView.swift`
  (selection state, exhaustive switch); `cellar/cellarApp.swift` (store construction, injection).
- **New** `cellar/Health/`, `cellar/Discover/`, `cellar/Brewfile/`, release-notes sheet under
  `cellar/Installed/`; cask-inspection section in `cellar/Browse/PackageDetailView.swift`.
- **New** fixtures: `Fixtures/Doctor/`, `Fixtures/Bundle/`, `Fixtures/GitHub/`, each to the
  `Fixtures/Cleanup` standard (README with brew version + exact argv + exit code, probe-manifest,
  SHA-256 per stream).

---

## Approach comparison — slicing strategy

Evidence: M2 shipped as 4 archived changes, M3 as 5, **M4 as 1 change that measured 23,156 changed
lines and required a user-reconfirmed `size:exception`**. Session review budget is 5,000 lines,
delivery strategy `single-pr`, strict TDD on.

Dependency coupling between the six M5 features is almost nil. The **only** ordering edge is
*catalog decoder widening → {pre-install cask inspection, release notes}*. Everything else is
independent.

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | **One change** (`m5-pro-parity`) | One proposal/design/tasks lifecycle; matches M4 precedent | Forecast 7–10k authored lines, 11–16k full lifecycle: needs a size exception larger than M4's; a doctor-parsing defect and a Brewfile-argv defect land in the same reviewable unit; no incremental rollback | High |
| B | **Six changes**, one per PRD bullet | Maximum granularity | Bulk-ops polish is ~300–600 lines and cannot justify a full SDD lifecycle; six proposal/design/tasks/verify cycles is more artifact burden than review saved | Medium-High |
| C | **Five sequential changes**, grouped by dependency and risk | Each slice 700–2,800 authored lines — within or near the 5,000 budget individually; the one real dependency edge is isolated into slice 1; the highest-risk surface (untrusted argv from a Brewfile) gets its own review; each slice has an autonomous exit and a clean rollback | Five lifecycles of SDD artifact overhead; the Health slice must wait for the others to be worth composing | Medium |

**Recommended: C.**

| Order | Change | Scope | Authored source + tests |
|---|---|---|---:|
| 1 | `m5-catalog-inspection` | `CaskWire`/`FormulaWire`/`CatalogPackage` widening (`urls.stable`, `urls.head`, cask `url`/`sha256`/`artifacts`/`depends_on`), resident-memory decision + regression test, pre-install cask inspection UI in `PackageDetailView` | 900–1,400 |
| 2 | `m5-discover` | Ranked projections over the existing analytics join, curated JSON bundle resource, `.discover` section + views, honest "new to you" labelling | 700–1,200 |
| 3 | `m5-release-notes` | New `ReleaseNotes` target: repo resolution, releases client, TTL cache, Keychain PAT, Markdown sheet, typed not-found fallback, consent reuse | 1,600–2,400 |
| 4 | `m5-brewfile` | `brew bundle dump` export, Brewfile parser with counted skips, `bundle check` diff preview, selective apply via `MutationCommand` fan-out, untrusted-argv hardening | 1,800–2,600 |
| 5 | `m5-health` | Doctor payload source (new payload rule) + parser, last-update probe, `HealthSnapshot` + pure score engine with transparent breakdown, `.health` section, per-row remediation, **plus bulk pin/snooze polish** | 1,800–2,800 |

Rationale for the order: slice 1 unblocks 3; slice 2 is the lowest-risk way to land the
new-sidebar-section pattern; slice 4 carries the security-relevant surface and deserves an
uncontaminated review; slice 5 composes everything and therefore lands last. Bulk-ops polish is too
small for its own change and belongs where "remediate everything outdated" lives — slice 5 — but its
ruling reversal is a spec MODIFICATION needing an explicit user decision, not an implementation
detail.

**Forecast:** authored source + tests 6,800–10,400; full lifecycle including SDD artifacts
11,000–16,000. Against the 5,000-line session budget no single-PR shape fits; five slices each land
at roughly 700–2,800 authored lines. `single-pr` is a *per-change* delivery strategy, so five
sequential changes each delivered as one PR is consistent with it. This document grants no size
exception and no slicing decision — the review workload guard resolves that after `sdd-tasks`.

---

## Risks

- **`brew doctor` contradicts every existing payload rule.** Warnings go to stderr and the exit
  status is non-zero when warnings exist; `InstalledPayload`/`ServicesPayload`/`TapPayload` all treat
  that combination as a failed command with a discarded document. Reusing the template ships a
  dashboard that calls a healthy machine broken.
- **PRD §3.1 "new in the last 30 days" is not implementable as written** — no first-party date-added
  data exists. Reinterpreting it silently would be a spec that does not describe the product.
- **Cask `artifacts` widening is a resident-memory regression risk** over ~8k records. The decoder's
  key-subset discipline exists precisely to prevent this; the widening must be measured, not assumed.
- **Brewfile import is the first untrusted-argv source in the app.** The gates exist, but the
  reasoning written into `MutationCommand.swift` explicitly excludes free-text input and must be
  restated.
- **Bulk pin/snooze contradicts a recorded ruling (II13 sc4) with a structural test defending it.**
  Reversal is a user decision.
- **The health score is a trusted number.** Counting `.notCovered` packages as clean reintroduces the
  M4 false-negative failure on the app's most prominent surface.
- **GitHub 60 req/h unauthenticated.** Any fan-out of release-notes fetches exhausts it in one bulk
  action.
- **`brew bundle dump --file=-` has upstream breakage history**; prefer a real path.
- **`brew bundle` argv is not fixture-covered anywhere in the repo**; exit-code and stream-split
  behaviour on Homebrew 6.x must be captured, not assumed.
- **No CI.** Green suites remain local snapshots — pre-existing project risk, not M5 scope.

---

## Probe gates needed before design (U-gate convention from M3/M4)

- **U1** `brew doctor` on this machine, with and without warnings: exit code, stdout/stderr split,
  and how stable the `Warning:` grouping is across runs. Decides the payload rule and PRD §9 Q5.
- **U2** Last-`brew update` timestamp under API mode: brew repo `.git/FETCH_HEAD` mtime vs
  `$(brew --cache)/api/*.jws.json` mtime — which moves on an API-only update.
- **U3** `brew bundle dump` / `check --verbose` / `install --no-upgrade` on Homebrew 6.x: exact argv
  accepted, exit codes, stream split. Capture byte-exact fixtures.
- **U4** Resident memory of a full catalog snapshot with cask `artifacts` projected vs today.
- **U5** GitHub-repo resolution hit-rate over the real installed inventory, from `homepage` +
  `urls.stable.url` + `urls.head.url`. Sizes whether the release-notes feature is worth a target.

This exploration ran no probes: the executor has no shell access.

---

## Product decisions required before proposal

1. **Discover "new in the last 30 days"** — accept "new since your last catalog sync" (local, free,
   private, empty on first run), spend GitHub API budget on homebrew-core history, or drop the
   section? *Recommended: relabel to "new to you" and amend the PRD.*
2. **Cask `artifacts` memory tradeoff** — project eagerly into every cask record, or keep the
   resident profile and read one record on demand? *Recommended: measure first (U4), then decide.*
3. **Bulk pin and bulk snooze** — reverse installed-inventory II13 sc4 and rewrite its structural
   test, or keep bulk at upgrade/uninstall and amend the PRD? *No recommendation without the
   maintainer; the ruling was deliberate.*
4. **`brew doctor` depth** (PRD §9 Q5) — raw output with a warning count, or parsed and grouped?
   *Recommended: raw output plus a counted `Warning:` grouping, with unparsed lines carried as
   `unknownLines` in the `CleanupEvidence` idiom.*
5. **Brewfile selective apply** — fan out into `MutationCommand`s, or write a filtered temp Brewfile
   and run `brew bundle install`? *Recommended: fan-out; it reuses the recorded M2 ruling and adds no
   Brewfile writer.*
6. **Slicing** — five sequential changes as tabled above, or one change with a size exception larger
   than M4's? *Recommended: five.*

---

## Ready for Proposal

**Yes, after a short decision round.** Decisions 1, 3 and 6 change what M5 *is* rather than how it is
built, and decision 1 contradicts the PRD text as written. Probes U1 and U3 should run before design:
U1 decides the doctor payload rule and U3 decides whether `brew bundle` can be wrapped at all in the
shape PRD §3.7 assumes.
