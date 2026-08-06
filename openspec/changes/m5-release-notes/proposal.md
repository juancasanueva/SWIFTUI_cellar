# Proposal: M5 Release Notes (`m5-release-notes`)

Anchors PRD.md **M5** (§7); feature §3.2 (release notes preview), §4.1 (`ReleaseNotes` target),
§4.3 (api.github.com, 60 req/h unauthenticated, optional PAT). Slice **3 of 5** per the recorded M5
decision round (Engram obs 7477). Exploration: `openspec/changes/m5-pro-parity/explore.md` (obs
7476). Slices 1 and 2 archived; slice 1 landed the formula URL projection this slice consumes.

## Intent and Users

Cellar tells a user that `git 2.43.0` can become `2.44.0` and offers a button. It does not tell them
**what changes** — so the only honest options are to upgrade blind or to leave the terminal-free
workflow the app exists to provide and go read a changelog by hand. That matters most for the
packages people are most careful about: language runtimes, build tools, database clients, anything
whose minor bump has broken a project before. This slice serves the user at the moment *before* an
upgrade they cannot easily undo, and it is the first Cellar surface that turns "there is a newer
version" into "here is what you get". The catalog already carries every input needed to find the
changelog and discards them today; slice 1 projected `urls.stable`/`urls.head` for exactly this.

## Product Rules (user-approved, binding)

- **On-demand, per sheet, never fanned out.** Opening one release-notes sheet may cause at most one
  GitHub request. A bulk upgrade of 30 packages issues **zero**. 60 req/h is a product constraint
  the design obeys, not a tuning knob it optimises around.
- **Consent before egress.** No request leaves this Mac before an explicit, dated grant. A missing
  grant is a typed refusal the sheet shows, never a silent no-op (the `ScanConsent.authorise()`
  reasoning, applied verbatim).
- **"Not found" is four different states, and the sheet says which.** No GitHub repository could be
  resolved / the repository publishes no releases / no release matches this version / the fetch
  failed or was rate-limited. Each is a typed case with its own copy. None of them is an empty
  string, a blank sheet, or a spinner that never resolves.
- **Never guess a repository.** Resolution is deterministic, derived only from URLs the catalog
  already publishes, and every resolved repo names which URL produced it. No GitHub search, no
  name-similarity matching, no "probably `owner/name`".
- **Exactly one request per sheet.** Rendered Markdown loads no remote images and follows no link
  automatically; a release body cannot turn into a second, unconsented egress.
- **No new brew invocation anywhere**, and no change to `CatalogPackage`, `CatalogSnapshot` or
  `currentSchemaVersion` — slice 1's footprint bound has 2.4% headroom and this slice spends none
  of it.
- **The PAT is a secret.** Keychain only; never `UserDefaults`, `@AppStorage`, a plist, a log, or
  the request log; never echoed back into the field after it is stored.

## Scope

**In:** a new `ReleaseNotes` SwiftPM target + library product + test target (fixtures as resources),
depending on **`Catalog` only**, mirroring SecurityKit's brew-free leaf discipline; GitHub repository
resolution from `homepage`, `formulaSources.stableURL`, `formulaSources.headURL` and
`caskInspection.downloadURL`, with typed provenance and a typed unresolvable case; a releases client
over the `HTTPCatalogSource` acquisition discipline (ephemeral configuration, `urlCache = nil`,
conditional requests, byte-limit guard) with rate-limit exhaustion as a first-class typed outcome
carrying its reset time; a TTL cache in its own file under the `AdvisoryCache` precedent; tag→release
matching; a consent gate and an optional GitHub PAT in the Keychain; a `@MainActor @Observable`
release-notes store with per-package cancellable work and last-good survival; a Markdown sheet in the
app reachable from the upgrade decision point.

**Out (non-goals):** the M6 Settings screen itself; release notes from any host other than GitHub
(GitLab, SourceForge, kernel.org mirrors and tarball hosts resolve to "no repository"); aggregating
multiple releases between the installed and available versions; offline reading beyond the cache TTL;
any prefetch, background refresh, or fetch triggered by anything but an explicit user action; any
brew command; any change to `CatalogPackage`/`CatalogSnapshot`/schema version; bulk pin and snooze,
Brewfile and Health (slices 4–5).

## Capabilities

- **New `release-notes`** — repository resolution and its provenance rules, the fetch and
  conditional-request discipline, rate-limit and failure outcomes, TTL caching and its schema gate,
  tag→release matching, the four typed absence states, the consent gate, PAT storage, and the
  Markdown rendering limits.
- **Modified capabilities:** None. The entry point is app-side presentation; no shipped CellarCore
  behaviour changes.
- **Unchanged:** all 17 shipped capabilities.

## Approach

**The dependency law forces two seams to be re-declared, not shared.** `ScanConsent`,
`ScanConsentProviding` and `AdvisoryCredentialStoring` all live in **SecurityKit**, and
`ScanConsent.authorise()` throws `AdvisoryError`. `ReleaseNotes` depends on `Catalog` only, so it
cannot import them, and making it depend on SecurityKit would couple release notes to the CVE
scanner for two small value types. `ReleaseNotes` therefore declares its own consent value and its
own credential protocol with the **same shape and the same rules** — one dated constructor, a
throwing `authorise()`, a generic-password item with `kSecAttrAccessibleAfterFirstUnlock` and
`kSecAttrSynchronizable = false`, under a distinct service name. This is one mechanism applied twice,
not a second mechanism (D1, D2). Extracting a shared consent/credentials micro-target is rejected: a
SwiftPM target for two structs, and each secret keeping exactly one way to read it is the property
the M4 store's design was written to preserve.

**Resolution is a pure function**, testable without a network: the **union** of all candidate URLs →
a `GitHubRepository` plus the URL that produced it, or a typed `unresolvable`. U5 settled the shape
(see below): a repository is resolved if *any* field yields one, and `homepage → head → stable →
cask url` is a **tie-break order only**, not a precedence that can lose coverage. The releases client
reuses the proven HTTP discipline but `data(for:)` rather than `download(for:)` — release bodies are
kilobytes, not 31 MB — and treats `403` with an exhausted rate-limit header as its own outcome, never
as "not found"; conflating them would tell a user a project publishes no changelog when in fact
Cellar ran out of budget.

**The cache is its own file**, schema-version gated with the CS6 idiom (missing, corrupt or
mismatched all mean "cached nothing"), with a bounded entry count. It never touches the catalog
snapshot. Decoding is `@concurrent static func` over `Data` — attribute before the modifier.

| Area | Impact |
|---|---|
| `Packages/CellarCore/Package.swift` | **Modified — new target, product and test target** |
| `Sources/ReleaseNotes/` — resolution, client, cache, models, consent, PAT store, store | New |
| `Tests/ReleaseNotesTests/` + `Fixtures/GitHub/` | New — byte-exact captures to the `Fixtures/Cleanup` standard |
| `cellar/Installed/` — release-notes sheet + entry action | New/Modified |
| `cellar/cellarApp.swift` | Modified — store construction, consent + credential injection |
| `cellar.xcodeproj` | **Modified — the app target links the new library product** |

## Probe Gate — U5, reported (design gate open)

**U5 reported positive** (Engram obs 7503; 170 installed packages plus the full catalog, URL-shape
only, no API calls). **Verdict: the feature earns its target.**

| Measurement | Result |
|---|---|
| Union of all fields, formulae the user explicitly installed (`installed_on_request`) | **81.4%** |
| Union of all fields, all installed | **59.4%** (dependency-only formulae 48%) |
| Catalog-wide union — representativeness check | 63.6% |
| Fields disagreeing on owner/repo | **0** among installed, **<0.5%** catalog-wide |

Per-field solo, installed formulae: `urls.stable.url` **54.7%** (the coverage workhorse — GitHub
release tarballs), `urls.head.url` 39.6%, `homepage` 24.5% (weakest everywhere); casks: `url` 45.5%,
`homepage` 9.1%.

**The U5-informed input the design MUST adopt:** union resolution, with `homepage → head → stable →
cask url` used **purely as a tie-break**. Because the fields never disagreed on owner/repo,
precedence affects coverage, not correctness — and a naive homepage-first precedence would discard
the field that actually carries the coverage. Cask `downloadURL` earns its place (45.5% solo against
homepage's 9.1% for casks).

Non-resolvers cluster in self-hosted infrastructure (GNU, X.org, freedesktop) and a handful of big
self-hosted names (python.org, nodejs.org, go.dev, videolan.org), so the typed "no release notes
found" state will be uncommon on user-facing screens. **Caveat carried into design:** this is a
URL-shape ceiling — some resolved repositories may be mirrors, or may not use GitHub Releases at
all, so the "repository publishes no releases" and "no release matches this version" states remain
load-bearing, not theoretical.

D6 is therefore not triggered, but stands as the standing rule for any later coverage shortfall.

## Risks

| Risk | L | Mitigation |
|---|---|---|
| 60 req/h exhausted by a fan-out or a retry loop | High | On-demand-only is a spec requirement with a test asserting zero requests during bulk upgrade; rate-limit exhaustion is a typed outcome, not a retry trigger |
| Rate-limit refusal shown as "no release notes" | High | Four distinct typed absence states; a scenario per state |
| Low resolution hit-rate makes the feature feel broken | **Retired** | U5 reported 81.4% on explicitly-installed formulae with union resolution; D6 stands as the standing rule |
| A resolved repo is a mirror, or does not use GitHub Releases | Med | U5's stated ceiling: URL shape only. The "no releases" and "no matching release" states carry this and must be exercised by fixtures |
| A second Keychain item and a second consent value read as a second mechanism | Med | Same shape, same rules, distinct service name; spec-level statement of why the dependency graph forbids sharing |
| `AttributedString(markdown:)` mangles GFM tables, task lists and @mentions | Med | Known limits stated in the spec, with a readable-degradation requirement rather than a bug report later |
| Remote content in a release body causes unconsented egress | Med | One-request-per-sheet rule; no remote image loading, no automatic link following |
| Reverting leaves a user's PAT in the Keychain | Low | Removal offered from the consent surface; rollback plan names it explicitly |
| Formula `checksum` vs cask `sha256` naming trap (recorded at slice 1) | Low | Not consumed here; resolution reads URLs only |
| First `cellar.xcodeproj` product-link edit since M4 | Med | Rollback plan below; `xcodebuild build` after revert as the check |

## Rollback Plan

Additive, and revertible by `git revert` of the slice PR. Two of the three moving parts need naming
because they are not plain source files.

1. **`Packages/CellarCore/Package.swift`.** The slice adds one `.library(name: "ReleaseNotes")`
   product, one `.target` and one `.testTarget`, plus `Sources/ReleaseNotes/` and
   `Tests/ReleaseNotesTests/`. **No existing target gains a dependency on `ReleaseNotes`** — the
   core graph is unchanged, so removing the three entries and the two directories cannot break
   `Catalog`, `BrewClient`, `SecurityKit` or `Persistence`. `swift build --package-path
   Packages/CellarCore` is the check.
2. **`cellar.xcodeproj`.** The app target must link the new package product, so unlike slices 1–2
   this slice *does* edit target membership: one package-product dependency and one entry in the
   `cellar` target's frameworks build phase. Rollback removes exactly those two entries; no build
   setting, scheme or signing change is made. New app sources live under `cellar/Installed/`, a
   `PBXFileSystemSynchronizedRootGroup` root confirmed at slices 1–2 to need **no** pbxproj edit, so
   they revert as file deletions. `xcodebuild build -scheme cellar` after revert is the check.
3. **User state.** The cache file is orphaned and inert after a revert, and is re-created if the
   slice is re-applied; no catalog cache is invalidated in either direction and no schema version
   moves. A stored PAT survives a revert in the Keychain with nothing left to read it — the consent
   surface offers removal, and the rollback procedure is to remove the key *before* reverting.

## Delivery

Session budget **5,000** lines, `single-pr`, strict TDD. Forecast **1,600–2,400** authored
source+tests, **3,000–4,200** including lifecycle artifacts. No size exception is requested; the
review workload guard resolves after `sdd-tasks`. (`openspec/config.yaml` still records
`review_budget_lines: 2000` from M3; the session value 5,000 governs, as it did for slices 1–2.)

## Success Criteria

- [ ] A user about to upgrade an outdated package can read that version's changelog without leaving
      Cellar.
- [ ] A bulk upgrade of N packages issues **zero** GitHub requests — asserted, not assumed.
- [ ] No request leaves the machine before an explicit dated grant, and refusal is visible.
- [ ] The four absence states are distinguishable in the UI, and a rate-limit refusal never reads as
      "no release notes".
- [ ] A PAT entered by the user is in the Keychain and in no other store — asserted structurally.
- [ ] `CatalogFootprintTests` passes **unchanged**, and `CatalogPackage` gained no field.
- [ ] Union resolution with the U5 tie-break order is a test, not a comment, and a package resolvable
      only via `urls.stable` still resolves.
- [ ] D1–D6 are each traceable to a spec requirement before design closes.

## Resolved Decisions (user-approved, binding)

Answered in the proposal question round. These are decisions, not assumptions; specs derive from them
and MUST NOT re-open them. Each names what was rejected, so a later phase cannot reintroduce a
rejected alternative as a fresh idea.

- **D1 — Release notes get their own consent grant, in the existing consent vocabulary.** A separate
  dated grant, presented with the same disclosure shape as M4's (what is sent, what is not, which
  host and why). Rationale: a different host (`api.github.com`), different disclosed data (a
  repository name, which reveals that this Mac has that package installed and is about to upgrade
  it), and different timing (user-initiated, not scheduled). **Rejected:** reusing the security-scan
  grant — a user who consented to CVE scanning would silently acquire a second egress destination,
  which is exactly what dating the grant exists to prevent. **Also rejected:** no consent at all
  because "it is only a repo name".
- **D2 — `ReleaseNotes` re-declares the consent and credential seams rather than importing
  SecurityKit.** Identical shape and identical rules, under a distinct Keychain service name. The
  binding reading of "no second consent mechanism" is **no second set of rules**, not no second code
  path: the dependency graph (`ReleaseNotes → Catalog` only, and `ScanConsent.authorise()` throwing
  SecurityKit's `AdvisoryError`) makes sharing the types impossible without paying more than the
  duplication costs. **Rejected:** a `ReleaseNotes → SecurityKit` edge, which would couple release
  notes to the CVE scanner for two value types; and a shared consent/credentials micro-target, which
  is a SwiftPM target for two structs and would dissolve the property that each secret has exactly
  one way to be read.
- **D3 — Two-tier TTL.** A matched release body caches for **7 days** (a published release for a
  fixed tag does not meaningfully change); every negative answer — unresolvable, no releases, no
  matching tag — caches for **24 hours**, so a newly published changelog appears within a day
  without re-spending budget on every sheet open. Rate-limit refusals are **not** cached as answers;
  they are transient and carry a reset time. **Rejected:** one uniform TTL, and caching negatives
  indefinitely.
- **D4 — Entry points: the outdated row and package detail, both explicit.** Primary is the upgrade
  decision point (the outdated package's action menu — "What's new?"); secondary is a section in
  package detail for any package with a resolvable repository. Never on hover, appear, or selection.
  **Rejected:** fetching when a detail view appears, and an outdated-row-only entry that would make
  the feature invisible to someone browsing.
- **D5 — The PAT field ships in this slice, in the release-notes consent surface.** PRD §4.3 places
  it "in Settings", and Settings is M6 — but M4 already shipped the NVD key inside
  `SecurityConsentSheet` rather than waiting, and a user who hits the 60/h wall otherwise has no exit
  for a whole milestone. M6's Settings screen consolidates both later. **Rejected:** building and
  testing a Keychain store with no way to fill it.
- **D6 — A coverage shortfall narrows the entry point, never the honesty.** Where resolution fails,
  the action appears only for packages whose repository actually resolved, rather than everywhere
  with a mostly-empty result. **Rejected:** GitHub search or name-similarity fallback to raise the
  rate, and shipping an always-visible action that usually ends in "not found". U5 has since
  reported 81.4% on explicitly-installed formulae under **union resolution** — so the shortfall
  branch is not taken, and the union rule with the `homepage → head → stable → cask url` tie-break
  is the binding resolution strategy the design adopts. Naive homepage-first precedence is
  **rejected**: `homepage` is the weakest field everywhere (24.5% formulae, 9.1% casks) and
  precedence affects coverage, not correctness, because the fields never disagreed on owner/repo.
