# Exploration: M4 Security (`m4-security`)

Exploration for PRD M4 (PRD.md §7 line 213; feature detail §3.5; risk "CVE false positives" §8;
open question 3 §9). Repository evidence read at clean `main` `0bd1f72` (M3 cleanup merged).
Artifact store is hybrid; the persisted Engram mirror of this file is topic
`sdd/m4-security/explore` (observation 7447).

**Executor note:** the exploration agent had no file-write tool. This OpenSpec copy was written
by the orchestrator verbatim from the Engram observation; only the Engram copy was persisted
directly by the phase agent.

---

### Headline Finding — the PRD's primary CVE data source does not cover the primary use case

PRD §3.5 and §4.2 specify "OSV.dev batch query API (primary), NVD 2.0 as enrichment/fallback for
CVSS". Verified against OSV documentation:

- **There is no Homebrew ecosystem in OSV.** Covered ecosystems are PyPI, Go, Rust/crates.io,
  Haskell, CRAN/Bioconductor, opam, npm, NuGet, RubyGems, Maven, Packagist, Pub, Hex, Julia,
  SwiftURL, GitHub Actions, plus Linux distributions (Debian, Ubuntu, Alpine, Rocky, AlmaLinux),
  OSS-Fuzz, GIT and the Linux kernel.
- **`POST /v1/query` and `/v1/querybatch` require an ecosystem whenever `package.name` is used.**
  Ecosystem-less version queries are not supported. `purl` may replace `name`+`ecosystem`, but
  requires a purl type OSV indexes; `pkg:brew` is not one.
- **OSV's C/C++ coverage is commit-ranged, not version-ranged.** Advisories for general C/C++
  projects express vulnerable ranges as GIT commit ranges. OSV's own guidance is to match those by
  commit hash, or to infer a version first via the experimental `determineversion` gRPC endpoint
  (binary content hashing against an OSS-Fuzz-derived index). Neither is reachable from
  `(formula name, "8.4.0")`.
- `ecosystem=GIT` REST queries are reported as returning "Invalid ecosystem" (osv.dev issue #2576).

A typical `brew list` is dominated by C/C++ upstream tools and libraries — curl, git, openssl@3,
ffmpeg, sqlite, libpng, nginx, zlib. Essentially none of these are addressable in OSV by
`(name, ecosystem, version)`. Debian/Ubuntu/Alpine records *do* carry these source-package names,
but their version ranges live in distro version space (`7.88.1-10+deb12u5`), so matching a Homebrew
`8.4.0` against them would be arithmetically wrong, not merely imprecise.

**Consequence:** an OSV-primary implementation, faithfully built, most likely ships a Security view
that reports zero findings for the majority of a real user's installed formulae. That is a silent
false negative — strictly worse than the false-positive risk PRD §8 anticipated, because the UI
would look healthy while covering nothing. This is a genuine product fork and must be resolved
before proposal.

**Verified NVD 2.0 facts (the realistic primary):** `GET https://services.nvd.nist.gov/rest/json/cves/2.0`
supports `cpeName` (requires non-wildcard part/vendor/product/version), `virtualMatchString`
(partial CPE, combinable with `versionStart`/`versionEnd` + `versionStartType`/`versionEndType` of
`including`/`excluding`), `keywordSearch`, `cveId`, `cveIds` (up to 100), and
`lastModStartDate`/`lastModEndDate` (max **120-day** window). `resultsPerPage` default and max is
**2000**. CVSS lives at `metrics.cvssMetricV31[]/V30[]/V40[]/V2[].cvssData.baseScore` and
`.baseSeverity`. Rate limits: **5 requests / rolling 30 s without a key, 50 with a key**; NVD
recommends ~6 s between unauthenticated requests.

---

### Current State (architecture seams M4 must slot into)

`Packages/CellarCore/Package.swift` declares products BrewProcess, Catalog, DiskUsage, BrewClient,
Persistence (+ non-product `CellarTestSupport`). Edges: `Catalog` and `BrewProcess` are leaves,
`DiskUsage → {BrewProcess, Catalog}`, `BrewClient → {BrewProcess, Catalog, DiskUsage}`,
`Persistence → BrewClient` as the deliberate outermost node. Every target is
`.swiftLanguageMode(.v6)`, platform `macOS 26.0`.

Reusable seams, all already proven in shipped milestones:

| Concern | Existing seam | M4 reuse |
|---|---|---|
| HTTP acquisition | `CatalogSource` protocol + `HTTPCatalogSource` (`URLSessionConfiguration.ephemeral`, `urlCache = nil`, `reloadIgnoringLocalCacheData`, `If-None-Match`/`If-Modified-Since`, `session.download(for:)` streaming to disk, 304 classified *before* the temp file is opened, byte-limit guard, atomic staging) | Same protocol shape for an advisory feed; the 304-before-open lesson applies verbatim |
| Sync lifecycle | `actor CatalogSyncEngine` — single-flight by token, drain-then-restart for cancelled runs, `AsyncStream<CatalogSyncEvent>` for one observer, `syncIfStale()`, `runRefreshLoop()`, `CatalogRefreshPolicy` | A scheduled daily re-scan is the same machine, not a new one |
| Snapshot adoption | `CatalogStore.adopt` — revision-ordinal monotonicity, off-main build via `@concurrent`, duplicate joins rather than returns, single main-actor assignment | A `SecurityStore` adopting scan results needs the identical discipline |
| Store pattern | `@MainActor @Observable` with `@ObservationIgnored` internals, `private(set)` state, closed load-state enum, last-good survival on failure (`InstalledStore`), per-scope generation/task maps (`CleanupStore`) | `SecurityStore` follows `CleanupStore`'s per-scope shape |
| Tolerant decoding | `InstalledDecoder` — malformed *envelope* fails, malformed *record* is skipped **and counted** (`skippedRecordCount`); `CatalogDecoder` projects only covered taps | An OSV/NVD record whose shape drifted must cost that record, not the scan |
| Typed honesty | `CleanupEvidence` (`CleanupReportedTotal.reportedFooter \| .unknown`, `CleanupOrphans.known/.notApplicable/.unknown`, `unknownLines: [Data]`, `issues: Set<CleanupParseIssue>`, `isPartial`), `CleanupParserProvenance.parserVersion`, `CleanupEvidenceFingerprint` (SHA-256 over a canonical encoding), `isEqualForAuthorization` comparing typed facts not a hash | The exact vocabulary M4 needs for "severity unknown", "no fix version published", "package not covered by any source" |
| Confirmation | `OperationCenter.requestCleanup` / `confirmCleanup` + `MutationLaunchAuthorizing` (`CleanupLaunchAuthorizer` re-runs the preview at the FIFO front and denies on `.evidenceChanged` / `.evidenceUnavailable`) | Quarantine clearing needs exactly this fail-closed re-validation |
| Mutation spine | `BrewMutating` (`arguments`, `verb`, `packageID`, `requiresConfirmation`, `invalidates: InvalidationScope`, `diskAreas`), `AnyBrewMutation`, `MutationName.isSafe` argv gate | "Upgrade to the fixed version" is `MutationCommand.upgrade(target)` — already exists, no new family |
| Persistence | `SchemaV1: VersionedSchema` with `PackageMeta`/`Snooze`/`HistoryEntry`; primitives only, no `@Relationship`, no `@Transient`, `#Unique` composite keys, `kindRaw` string not a Codable enum, absence-is-empty-string; value projections (`PackageMetadata`) cross module boundaries, never `@Model` instances; `MetadataLookup` closure typealias is the cross-target seam | `DismissedCVE` is a `SchemaV2` lightweight-stage addition following every one of those rules |
| Filesystem scan | `DiskUsageEngine.scan` — `@concurrent`, `AsyncThrowingStream` with incremental `.progress`/`.warning`/`.rootCompleted`, `Task.checkCancellation()` per unit, per-area failure isolated into `DiskUsageWarning`, `DiskUsageSnapshot.isComplete` gating cache writes | A quarantine/codesign scan over `/Applications` + Caskroom is the same engine shape |
| App shell | `ContentView` exhaustive three-column `NavigationSplitView` over `AppSection`, per-section selection `@State`, `.safeAreaInset` activity bar, `.mutationConfirmation` modifier | A `.security` section, its own selection, one store, one gate |
| Fixtures | `Tests/BrewClientTests/Fixtures/Cleanup/` — byte-exact captures, `README.md` recording brew version + exact argv + exit code, `probe-manifest.txt` of the environment, SHA-256 of every stream, intentional empty files documented as intentional | Any HTTP fixture must be captured to the same standard |

**Network is not new machinery, but it is new *reach*.** `HTTPCatalogSource` is today the only
network egress and it talks to one host. M4 adds two more (`api.osv.dev`, `services.nvd.nist.gov`).

**Catalog gap:** `CatalogPackage` (from `CatalogDecoder.project`) carries kind, name, displayName,
desc, homepage, license, version, tap, dependencies, buildDependencies, dependents, caveats,
deprecation/disable, autoUpdates, installCount365d. It does **not** carry `urls.stable.url`,
`head.url`, or `sha256`. Any upstream-repository-based matching (or cask artifact provenance) needs
a `CatalogPackage`/decoder widening, which touches the shipped `catalog-sync` capability.

**Installed version source:** `InstalledPackage` exposes `catalogVersion`, `kegs: [InstalledKeg]`,
`primaryKeg` (linked keg wins over newest, per `InstalledDecoder.primaryKeg`), `snapshotOutdated`,
`isPinned`, `pinnedVersion`. Multiple kegs per formula is normal — a scan must decide whether it
scans the linked keg only or every keg on disk. Old unlinked kegs are exactly the ones cleanup
removes and exactly the ones most likely to be vulnerable.

**Load-bearing precedent — `PackageMetadata.isSnoozed`:** snooze suppression is deliberately
**string equality**, with a documented ruling that no Homebrew version comparator exists in that
capability and a structural test asserting none has been added. Rationale: an ordering comparator
misreads `1.2.3_1`, `2023-10-01`, `r5`, `9e`, and its failure mode is silent permanent suppression.
**M4's "fixed in version X" comparison is precisely the ordering comparator that ruling forbade.**
This is the single hardest technical constraint in the milestone and must be confronted explicitly,
not smuggled in.

---

### Approach comparison — vulnerability data source

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | **OSV-primary as written in the PRD** (`querybatch` by name+ecosystem) | Free, no key, batched (1000/req, response is `{id, modified}` only, ordering guaranteed, pagination at >1000/query or >3000/set), matches PRD text | Near-zero coverage for typical Homebrew formulae; requires an ecosystem OSV does not have; ships a silently empty differentiator | Medium build, low value |
| B | **NVD-primary via CPE match** (`virtualMatchString` + `versionStart/End`, CVSS from `metrics`) | Actually covers C/C++ upstream projects; authoritative CVSS; version ranges are first-class | Needs formula-name → `cpe:2.3:a:vendor:product` resolution (name-based — *the* PRD §8 risk); 5 req/30 s unauthenticated (≈20 min for 200 formulae) vs 50/30 s keyed; optional user API key becomes near-mandatory | High |
| C | **Local advisory index** (bulk OSV export and/or NVD `lastModStartDate` deltas, matched offline) | Zero per-package egress → best possible privacy; works offline; one HTTP shape the `CatalogSyncEngine`/ETag machinery already implements; scan latency becomes local CPU | Large initial download and on-disk index; 120-day delta window caps catch-up; index build/migration is real work; freshness must be surfaced honestly | High |
| D | **Honest hybrid, narrow v1**: OSV `querybatch` for the subset with a confident ecosystem/purl mapping, NVD by `cveId`/`cveIds` (≤100 per call) for CVSS enrichment only, and an explicit typed **`.notCovered`** state for every package no source can answer | Small, truthful, matches the codebase's typed-honesty discipline exactly; cheap NVD usage (enrichment only, not discovery); ships something real | Coverage in v1 is genuinely thin and the UI must say so prominently; risks reading as "feature doesn't work" | Medium |
| E | **Defer the CVE scanner; ship the local security surface** (codesign/notarization/quarantine/insecure-source insights) as M4, move CVE to M4b | Removes all three network dependencies, all rate limits, all false-positive risk from the milestone; every input is local and fixture-capturable | Does not deliver the PRD's stated headline differentiator; reshapes the roadmap | Low–Medium |

**Recommended:** **D as the shipping shape for v1, with C as the declared strategic path**, and E
held as the fallback if the maintainer decides thin coverage is worse than no claim. Concretely:

1. Model coverage as a first-class typed fact. `CVEScanOutcome` per package is
   `.covered(findings:)` / `.covered(clean:)` / `.notCovered(reason:)` / `.unavailable(error:)`.
   Never collapse "no source could answer" into "no vulnerabilities". This is the direct analogue of
   `CleanupReportedTotal.unknown` and `CleanupOrphans.unknown` and of the existing rule that row
   sizes are never substituted for a total brew did not report.
2. Keep OSV `querybatch` as the discovery transport for the mapped subset; it is the only free,
   batched, keyless option and its response shape (ids + modified) plus a `/v1/vulns/{id}` hydrate
   is cheap.
3. Use NVD strictly by `cveIds` for severity/reference enrichment of already-discovered CVE IDs —
   never as a per-package discovery loop. That keeps request volume proportional to *findings*
   (usually single digits), not to *installed packages* (hundreds), which makes the unauthenticated
   5/30 s limit livable and the optional API key a genuine convenience rather than a requirement.
4. Ship the ecosystem mapping as **data, not inference**: a small curated, in-repo, fixture-tested
   table (formula name → OSV ecosystem + package name), auditable and correctable, with everything
   absent from it reported as `.notCovered`. Heuristic name matching is what produces the distrust
   PRD §8 names.

---

### CVE matching engine

- **Conservative matching.** Match only on an exact `(ecosystem, package name)` the mapping table
  asserts, plus a version OSV/NVD itself places in a declared affected range. Never fuzzy-match
  names, never infer a vendor, never treat a description keyword hit as a finding.
- **Version comparison is the crux.** OSV `affected[].ranges` use typed `ECOSYSTEM`/`SEMVER`/`GIT`
  events; NVD uses `versionStartIncluding/Excluding` + `versionEndIncluding/Excluding`. Homebrew
  version strings (`1.2.3_1`, `3.4.1-1`, `2024-01-05`, `r5`, `8e`) are *not* SemVer. Three options:
  (a) implement Homebrew's own `Version`/`Token` comparator faithfully and fixture-test it against
  Homebrew's Ruby test corpus; (b) compare only when both sides parse as strict SemVer and report
  `.severityKnownVersionUnknown` otherwise; (c) prefix/equality only, as `PackageMetadata.isSnoozed`
  does. Option (b) is the honest middle and preserves the M2 ruling's *spirit* (never silently
  suppress) while enabling the fix-version feature where it is safe. Whatever is chosen, the
  existing structural test asserting no version comparator exists in `local-package-metadata` must
  be reconciled deliberately — a comparator in `SecurityKit` must not become a comparator the snooze
  path can reach.
- **Severity tiers.** Prefer CVSS v3.1/v4.0 `baseSeverity` from NVD; fall back to OSV
  `database_specific.severity` or `severity[]` (CVSS vector strings). When no source publishes a
  score, the tier is `.unrated`, rendered as such — never defaulted to medium.
- **Fix version.** Only from a declared `fixed` event / `versionEndExcluding`. "No fix published" is
  a distinct state from "fix unknown". The one-click upgrade must offer the *available* Homebrew
  version (`InstalledPackage.catalogVersion`), and must state plainly that it is offering Homebrew's
  current version, not the advisory's fixed version, when those differ.
- **Dismissal.** `SchemaV2` adds `DismissedCVE` (primitives only: `cveID`, `kindRaw`, `name`,
  `version`, `dismissedAt`, optional `note`; `#Unique` on the four-part key; no `@Relationship`),
  reached from `SecurityKit` through a `DismissalLookup` closure typealias mirroring
  `MetadataLookup`. Scoping the dismissal to the exact installed version means an upgrade
  re-surfaces the finding — the same "equality, visibly wrong in the safe direction" logic as snooze.
- **Caching.** Per-`(source, package, version)` with TTL plus the advisory's own `modified`
  timestamp, persisted alongside the disk-usage cache. Scan timestamp and per-package source
  provenance surface in the UI, following `CleanupParserProvenance`.

---

### Codesign / notarization insights

- **Prefer Security.framework over subprocesses.** `SecStaticCodeCreateWithPath` +
  `SecCodeCopySigningInformation` (`kSecCSSigningInformation | kSecCSRequirementInformation`) yields
  identifier, team identifier, authority chain, timestamp, CDHash and flags — everything
  `codesign -dv --verbose=4` prints, without parsing stderr. `SecStaticCodeCheckValidity` against
  `SecRequirementCreateWithString("notarized")` and `anchor apple generic` answers the notarization
  question; `SecAssessmentTicketLookup` covers stapled/online tickets. All are assessment-only and
  need no privileges (unlike `SecAssessmentUpdate`, which needs root).
- **This also dodges a deprecation trap.** `spctl`'s mutating subcommands have been progressively
  removed across recent macOS releases; assessment survives, but binding the feature to a CLI whose
  surface Apple is actively shrinking is avoidable. It further satisfies the repo rule "define
  protocol boundaries for every external dependency" without adding a second process family beside
  `BrewRunner`.
- **Cost:** Gatekeeper assessment may hit the network to look up a non-stapled notarization ticket,
  so it must be off-main, cancellable, per-item, and streamed like `DiskUsageEngine` — never a
  synchronous blocking sweep over `/Applications`.
- **Scope:** cask-installed apps are locatable from the Caskroom and from cask artifact metadata.
  Scanning all of `/Applications` is M5's Apple-Silicon-migration territory; M4 should stay on
  brew-managed artifacts to keep the blast radius honest.

---

### Quarantine manager — feasibility is materially worse than the PRD assumed

Three independent findings, each of which alone would justify reshaping this feature:

1. **Homebrew is removing the bypass.** `--no-quarantine` is being deprecated (Homebrew issue
   #20755, opened 2025-09-23, PR #20973), and **Homebrew will require all casks to pass Gatekeeper
   from 2026-09-01** — roughly one month after the current date. Maintainers state the flag
   "intentionally bypasses macOS security mechanisms, which we already actively discourage."
   Shipping a GUI whose selling point is bulk-clearing those flags puts Cellar on the opposite side
   of its own ecosystem, one month before enforcement.
2. **Clearing quarantine may be blocked by TCC.** Since macOS 14, modifying app bundles in
   `/Applications` requires the user-granted **App Management** permission. Whether `removexattr` on
   a bundle's `com.apple.quarantine` counts as a "modification" under that policy on macOS 26 is
   **not documented and could not be established from public sources** — it needs an empirical probe.
   If it is covered, the feature requires a TCC prompt, an admin password, and a graceful
   permission-denied path.
3. **Clearing it often achieves nothing.** From macOS 13, a modified notarized app is blocked on
   first launch *even with the quarantine attribute removed*, and a validly notarized app would have
   been admitted anyway. The residual value is confined to unsigned / ad-hoc-signed apps — precisely
   the case where clearing is least defensible.

**Recommended reshape:** make M4's quarantine feature **read-only visibility** — enumerate
brew-managed artifacts carrying `com.apple.quarantine` (and, on macOS 13+, `com.apple.provenance`),
decode and explain the attribute, and cross-reference it with the codesign/notarization verdict so
the user learns *why* an app is being blocked. Clearing, if offered at all, should be a single-item,
individually-confirmed action behind the existing `MutationLaunchAuthorizing` fail-closed
re-validation, with the plain-language explanation PRD §3.5 already demands — never a bulk sweep.
Reading is `getxattr`/`listxattr`, needs no privileges outside TCC-protected user directories, and
requires no `xattr` subprocess, honouring the PRD's "direct `removexattr`, no shell dependency" note.
The attribute value shape (`flags;hexTimestamp;agentName;UUID`) and its flag-bit semantics must be
fixture-verified rather than asserted; the flag encoding is not officially documented.

---

### Architecture fit — where `SecurityKit` goes

`SecurityKit` should depend on **`Catalog` only** (for `PackageID`/`PackageKind`), keeping it
brew-free the way `Catalog` is (the CS1 discipline). It owns the advisory sources, the pure matching
engine, the codesign/quarantine inspectors behind protocols, the value projections, and the
`DismissalLookup` typealias. `Persistence` then gains a second inward edge
(`Persistence → {BrewClient, SecurityKit}`) to store `DismissedCVE`, mirroring exactly how it
already reaches `BrewClient` for `HistoryDraft`. `BrewClient` gains **no** dependency on
`SecurityKit`: "upgrade to the fixed version" is an ordinary `MutationCommand.upgrade(target)` that
the app target submits to the existing `OperationCenter`, and the *recommendation itself* is a pure
value computed in `SecurityKit`. No new mutation family, no `BrewMutating` change, no new
`InvalidationScope` bit unless the quarantine action ships as a mutation.

App target: a `.security` case in `AppSection`, its own selection state in `ContentView`, one
`SecurityStore` constructed in `cellarApp`, and views under `cellar/Security/`.

---

### Privacy posture (new, and material)

PRD §1 principle 3 is "Local-first, private. No accounts, no telemetry, no backend." A CVE scan that
posts the user's installed package names and versions to `api.osv.dev` transmits a fairly precise
fingerprint of the machine's software inventory to a third party. That is not telemetry, but it is
not nothing, and the PRD does not currently acknowledge it. Requirements this implies: the scan is
**opt-in on first use** with a plain statement of exactly what leaves the machine and to whom; the
setting is reversible; findings work from cache offline; nothing is sent on launch before consent.
Approach C (local index) is the only option that removes the disclosure entirely, which strengthens
the case for declaring it the strategic path. An NVD API key, if the user supplies one, is a
credential and belongs in the Keychain, never in `UserDefaults`/`@AppStorage` or a plist.

---

### Affected areas

- `Packages/CellarCore/Package.swift` — new `SecurityKit` target + product, new `SecurityKitTests`
  test target with `resources: [.copy("Fixtures")]`, new `Persistence → SecurityKit` edge.
- **New** `Packages/CellarCore/Sources/SecurityKit/` — `AdvisorySource` protocol + `OSVSource`,
  `NVDSource`; wire DTOs; `CVEMatcher` (pure); `VulnerabilityFinding`, `SeverityTier`,
  `CVEScanOutcome`, `ScanProvenance`; `EcosystemMapping` (curated data); `SecurityStore`;
  `CodeSignatureInspecting` + Security.framework implementation; `QuarantineInspecting` +
  `getxattr`/`listxattr` implementation; `DismissalLookup`.
- `Packages/CellarCore/Sources/Persistence/SchemaV1.swift` → new `SchemaV2.swift` + migration stage,
  `DismissedCVE` model, `DismissalStore`. V1 was authored as genesis with a migration plan present
  precisely so this arrives as `.lightweight`.
- `Packages/CellarCore/Sources/Catalog/CatalogDecoder.swift` / `CatalogModels` — **only if**
  upstream-URL-based matching or cask artifact provenance is adopted; touches shipped `catalog-sync`.
- `Packages/CellarCore/Sources/BrewClient/InstalledModels.swift` — consumed as-is; decide linked-keg
  vs all-kegs scanning without changing the projection.
- `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellar/cellarApp.swift` — Security
  section, selection, store construction, root injection.
- **New** `cellar/Security/` — findings list, severity chips, finding detail with source links and
  "reported for" framing, dismissal affordance, signature/notarization panel, quarantine list.
- `cellar/Activity/MutationConfirmation.swift` — only if quarantine clearing ships as a confirmed
  mutation; reuse the typed-disclosure pattern, do not switch on rendered strings.
- **New** `Packages/CellarCore/Tests/SecurityKitTests/Fixtures/` — OSV and NVD JSON captures plus a
  `README.md` and `probe-manifest.txt` recording endpoint, exact query, capture date, and SHA-256 of
  every file, to the `Fixtures/Cleanup` standard.

---

### Product decisions required before proposal

1. **Given that OSV cannot answer for most Homebrew formulae, what does M4 ship?**
   Recommended: D — honest hybrid with a first-class `.notCovered` state and a curated mapping table,
   declaring C (local index) as the v1.1 path. Tradeoff: real but visibly partial coverage versus
   either a silently empty view (A), a rate-limited name-matching engine users will not trust (B), or
   dropping the headline differentiator from M4 (E).
2. **Casks in scope? (PRD §9 open question 3.)**
   Recommended: **no** for CVE scanning — OSV/NVD coverage for GUI applications is sparse and
   cask-token → product identity is even weaker than formula → product. Casks are in scope for the
   *local* security surface (signature, notarization, quarantine), which is where they actually carry
   information. Tradeoff: the Security view covers different package kinds with different features,
   which needs clear framing.
3. **Version comparison policy for "fixed in".**
   Recommended: strict-SemVer-both-sides comparison only, everything else reported as
   "fix version published, comparison not possible for this version scheme". Tradeoff: fewer
   one-click upgrades, but no silent wrong verdict, and the M2 no-comparator ruling stays coherent.
4. **Does the quarantine manager clear flags at all in v1?**
   Recommended: read-only visibility plus explanation; if clearing ships, single-item only, confirmed,
   fail-closed re-validated, never bulk. Tradeoff: less parity with TapHouse, but aligned with
   Homebrew's 2026-09-01 Gatekeeper requirement and defensible if App Management blocks the write.
5. **Is the CVE scan opt-in, and does the NVD key belong in Keychain?**
   Recommended: yes to both, with a first-run disclosure naming exactly what is transmitted.
   Tradeoff: one more onboarding step against a measurable privacy promise the PRD already made.
6. **Delivery shape.** M4 exceeds the 2,000-line budget by a wide margin; chained PRs are all but
   mandatory. Recommended slices: **M4-1** acquisition + fixture-tested matching engine (no UI);
   **M4-2** Security view, severity tiers, `SchemaV2` dismissals, fix-version upgrade; **M4-3**
   codesign/notarization + quarantine visibility.

---

### Probe gates needed before design (following the M3 U-gate convention)

- **U1** OSV `querybatch` against a real installed-formula list — measure how many packages any
  ecosystem answers for. This single number decides question 1 and should be captured as a fixture.
- **U2** NVD `cveIds` enrichment round-trip: response shape, CVSS metric availability across v2/v3/v4,
  observed rate-limit behaviour unauthenticated.
- **U3** `SecStaticCodeCheckValidity` + `SecAssessmentTicketLookup` against a brew-installed cask app:
  latency, network dependence, unprivileged success.
- **U4** `getxattr`/`removexattr` of `com.apple.quarantine` on a cask app in `/Applications` under
  macOS 26 **without** App Management permission — does it return `EPERM`? This is the decisive
  feasibility question for the quarantine manager and cannot be answered from documentation.
- **U5** Homebrew version-string corpus for the comparator decision, taken from the installed
  inventory plus Homebrew's own version test cases.

This exploration ran no probes: the executor had no shell access.

---

### Risks

- **Coverage collapse.** The PRD's primary source cannot address the primary package population.
  Building to the PRD text as written produces a differentiator that reports nothing.
- **False positives (PRD §8) are now the *second* risk.** The first is false negatives presented as
  clean. Any design must make "not covered" as visible as "vulnerable".
- **Version comparison is a documented landmine** in this codebase; the snooze ruling exists because
  a comparator already caused harm reasoning. A `SecurityKit` comparator must not become reachable
  from the snooze path, and the existing structural guard must be reconciled explicitly.
- **NVD rate limits** make any per-package discovery loop unusable unauthenticated; keying the design
  to enrichment-only is what keeps it viable without a user-supplied key.
- **Quarantine clearing may be technically blocked (App Management/TCC) and is ecosystem-hostile**
  one month before Homebrew's Gatekeeper enforcement date.
- **Privacy regression** against PRD §1 principle 3 if the scan is not opt-in and disclosed.
- **Schema migration** is the first real `SchemaV1 → V2` step; it must stay `.lightweight` and honour
  every V1 rule (primitives, no relationships, `#Unique`, absence-is-empty-string).
- **Catalog widening** for upstream URLs would modify a shipped, archived capability.
- **No CI**: green suites remain local snapshots. Pre-existing project risk, not M4 scope.

---

### Size forecast

| Bucket | Estimate | Basis |
|---|---:|---|
| CellarCore + app source | 2,000–2,800 | two advisory sources, wire DTOs, matcher, mapping data, store, two inspectors, SchemaV2 + migration, Security views, wiring |
| Swift Testing source | 2,600–3,600 | OSV/NVD fixtures, matcher tables, coverage-state matrix, version-comparison corpus, store single-flight/ordinal/last-good, dismissal persistence, migration, inspector fakes, structural guards |
| **Authored source + tests** | **4,600–6,400** | ~1.5× the m3-taps band; three new subsystems rather than one |
| Pre-apply SDD artifacts | 2,000–2,800 | this exploration, proposal, new + modified spec deltas, design, TDD tasks |
| Verify/archive/follow-ups | 800–1,400 | lifecycle burden |
| **Single-PR lifecycle total** | **7,400–10,600** | authored lines; RDD disabled so no generated receipts |

Note (orchestrator): the exploration agent assumed the previous 2,000-line session budget; this
session's preflight set `review_budget_lines: 5000`. Against 5,000, authored source+tests straddle
the budget and the full lifecycle exceeds it. The review workload guard resolves this after
`sdd-tasks`; no size exception or slicing decision is granted by this document.

---

### Likely spec capabilities

- **ADDED `vulnerability-scanning`** — advisory acquisition and caching; the typed coverage state
  (`covered` / `notCovered` / `unavailable`) and its prohibition on collapsing into "clean";
  conservative matching rules; severity tiering including `.unrated`; fix-version semantics and the
  version-comparison policy; per-CVE dismissal scoped to `(cveID, kind, name, version)`; scan
  provenance and timestamp; offline and rate-limited degradation; opt-in and transmission disclosure.
- **ADDED `artifact-integrity`** — code-signing identity, notarization verdict, quarantine and
  provenance attribute visibility for brew-managed artifacts; unprivileged-only operation; explicit
  "could not assess" states; whether and how a clear action is offered.
- **MODIFIED `local-package-metadata`** — reconcile the no-version-comparator structural guard with a
  comparator existing in `SecurityKit`; snooze semantics themselves stay byte-identical.
- **MODIFIED `installed-inventory`** — only if the scan requires all kegs rather than the linked keg.
- **MODIFIED `catalog-sync`** — only if upstream URL/`sha256` fields are added to `CatalogPackage`.
- **MODIFIED `package-mutation`** — only if quarantine clearing ships as a confirmed mutation.
- **Likely unchanged**: `operation-activity`, `brew-execution`, `brew-detection`, `package-detail`,
  `service-management`, `tap-management`, `disk-usage`, `installation-history` (an upgrade triggered
  from a finding is an ordinary `upgrade` entry).

---

### Ready for Proposal

**Yes, but only after an interactive decision round**, because decision 1 changes what M4 *is*, not
merely how it is built. The six product decisions above go to the user, leading with the OSV
coverage finding; probes U1 and U4 should run before design — U1 sizes the CVE feature and U4
decides whether the quarantine manager can exist as specified. Proposal must not silently grant the
required size exception or slicing decision.
