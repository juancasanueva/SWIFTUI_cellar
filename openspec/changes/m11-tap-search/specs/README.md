# Spec index — `m11-tap-search`

Three delta files. Hybrid store: these files are canonical; Engram topic `sdd/m11-tap-search/spec` is
the searchable mirror.

| Capability | Op | Block | Scenarios | Net |
|---|---|---|---|---|
| `package-search` | **ADDED** — packages published by installed third-party taps are searchable as a composed source | new, promotes as **PS8** | +16 (12 `unit`, 4 `unit-app`) | 7 → **8** requirements, 19 → **35** scenarios |
| `package-detail` | **MODIFIED** — **PD6** | whole block, all three existing scenarios byte-identical | +1 (`unit`) | 8 requirements unchanged, 31 → **32** scenarios |
| `tap-management` | **MODIFIED** — **TM5** and **TM11** (main-spec markers) | both whole blocks, all 12 existing scenarios byte-identical | +2 (`unit`) | 13 requirements unchanged, 58 → **60** scenarios |

**Totals: 1 ADDED, 3 MODIFIED blocks across 2 capabilities, 0 REMOVED, 0 RENAMED — 19 new scenarios
(15 `unit`, 4 `unit-app`).** No requirement is removed or renamed, so `rules.archive`'s
destructive-delta warning does not fire.

**One catalog read is permitted, and only one.** PD6's added paragraph allows the composed section to
read the catalog for **membership alone** — whether a hit's bare token is also carried by the catalog
for the same kind — because that is what produces the collision fact and the ambiguity that makes an
installed hit non-routable. That read creates no catalog record, adds nothing to the snapshot or the
index, and draws no catalog value into the hit beyond the collision itself. PS8 declares the same
membership answer as an input of the projection, used for that fact and for nothing else.

## Verification classes

Both names are already established in this repository; this change introduces none.

| Class | Meaning | Runner |
|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` |

None of the three target specs carries a `## Verification classes` table today (only `app-updates` and
`release-distribution` do), so **no class table is promoted at archive**. Each delta's table is
delta-local provenance; the per-scenario inline `- Verification:` lines promote with their
requirements, following the precedent `2026-08-23-m7-tap-trust` recorded at
`openspec/specs/installed-inventory/spec.md:1122-1184`.

## Copy pinned by these deltas

| Fact | Exact copy | Condition |
|---|---|---|
| Section title | `From your taps` | always, whenever the composed source is presented |
| Catalog collision note | `Also in the catalog. Homebrew installs the catalog package.` | the hit's bare token is also carried by the catalog for the same kind; supplied by the projection, never composed by the surface |
| Install state — installed | `Installed.` | the installed record reports the same tap. **New copy, not a shipped string**: TM5 expresses this state as the **Show in Installed** control rather than as copy, so this delta pins it here and requires the projection to produce it |
| Install state — tap withheld | `Installed. Homebrew withholds its tap while this tap is untrusted.` | TM5's exact shipped string, reused byte-for-byte |
| Install state — not installed | `Not installed.` | TM5's exact shipped string, reused byte-for-byte |

The four install-state and collision strings MUST be produced by the **projection**, never composed by
the presenting surface; the section title is the surface's own. The two TM5 strings are reused rather
than reworded so the same install state cannot read differently on Taps and on the query surface. The collision note is a neutral statement of Homebrew's own
resolution: no recommendation, no warning styling, and no suggestion to disambiguate — because PM10
forbids qualifying the argv, so there is nothing for the user to act on beyond knowing which package
brew will install.

## Presentation decisions consumed

Maintainer/orchestrator, 2026-08-24, Engram `sdd/m11-tap-search/state` obs `#7795`, all binding and all
carried into PS8:

| Decision | Where it lands in PS8 |
|---|---|
| Section renders **below** the catalog rows | presentation paragraph + `unit-app` title/position scenario |
| Collision shown with a neutral note, never suppressed | collision paragraph + `unit` collision scenario |
| Tap name only — no `Untrusted` badge, no trust control | install paragraph + `unit-app` no-trust-gate scan |
| Not-installed rows non-selectable; installed hits route to the m10 receipt pane | install-state paragraph + both routing scenarios. **Refined by the orchestrator gate**: an installed hit whose identity is ambiguous — colliding bare token, or two emitted hits sharing a `PackageID` — is also non-routable, because the catalog-first resolution would open a different package; it stays presented and installable (`unit` ambiguity scenario) |
| Section renders only for a non-empty query | non-empty-query paragraph + `unit` empty-query scenario |
| "Hide installed" subtracts from the section; Outdated hides it entirely | filters paragraph + `unit` composed-controls scenario |
| Prompt count stays catalog-only | filters paragraph |
| Matching via the index's normalisation, exact/prefix/substring ladder | matching paragraphs + three `unit` scenarios (ladder, token-awareness, total order). **Refined by the orchestrator gate**: the ladder is token-aware (`gentle-ai` → tokens `gentle ai`, so `ai` is an exact-token match), matching applies to the published qualified name as well as the bare token, and a qualified-name-only match ranks no higher than substring |
| Section absent, never an error, when the tap inventory is unavailable | availability paragraph + `unit` unavailable scenario |
| PS6's ceiling not regressed; no new brew invocation | latency paragraph + `unit` latency scenario + `unit-app` process-layer scan |

## `package-mutation`: activated, not changed — no delta

m11 adds **no** `package-mutation` delta. PM10 (`openspec/specs/package-mutation/spec.md:619-768` —
the whole requirement block; the clauses cited below are its prohibition paragraphs and scenarios)
binds the new install path exactly as written today and is **activated** by it:

| PM10 clause | How m11 activates it |
|---|---|
| No argv on the shared mutation spine carries a `/`-qualified package token (`:647-652`, scenario `:713-719`) | The tap hit's mutation target is the bare `PackageID` the tap projection already produces, so the install is the **existing** family with the **existing** argv shape. The enumeration gains no family and needs no edit — including for a colliding hit, where qualifying to disambiguate is exactly what the clause forbids. |
| The refusal MUST NOT become a pre-launch gate (`:659-662`) | Install is offered unconditionally for every hit; brew decides. PS8 restates the prohibition for this surface as an absence and asserts it by source scan. |
| The same prohibition holds for per-package grant state (`:664-670`) | The composed source reads no trust report, store or projection at all. |
| Enforced structurally by the shipped source-scanning assertion (`:672-676`) | The new projection and the new surface are added to what that idiom covers; PS8's `unit-app` scenario is the assertion. |
| Typed refusal copy and Trust recovery (`:640-645`, `:705-711`) | Unchanged and reused end to end: an untrusted tap surfaces through the shipped refusal, not a Cellar-side block. |

A `package-mutation` MODIFIED block would restate a requirement that already says the right thing, so
`sdd-spec` found **no genuine gap** and wrote none. Record this at archive as *activated, not changed*.

## `installed-inventory`: activated, not changed — no delta

| Requirement | How m11 activates it |
|---|---|
| **II7** — the catalog target does not depend on the brew-process target | The projection lives in `BrewClient`, which already imports `Catalog`; the direction is unchanged, which is precisely why index ingestion (explore Approach C) was rejected. |
| **II8** — installed-state filters are composed, never pushed into the search index | PS8 extends the same discipline to a second result source; the hide-installed subtraction and the outdated-only mode compose above it on II8's terms. |
| **II15** — the installed receipt supplies a reduced detail for a package the catalog does not carry | An installed tap hit routes there by exact `PackageID` through the existing resolution order; no routing branch is added. |

## Numbering and marker drift, recorded once

- `openspec/specs/package-search/spec.md` and `openspec/specs/package-detail/spec.md` carry **no
  `<!-- PS# -->` / `<!-- PD# -->` markers** — `tap-management` is the only spec that uses marker
  comments. PS8 and PD6 are ordinal labels used in prose; the blocks are matched by heading.
- `explore.md` and `proposal.md` call the tap-management adjacent-capabilities requirement **TM10** and
  the trust-presentation requirement **TM11**. The file's markers are **`<!-- TM11 -->`** (`:532`) and
  **`<!-- TM12 -->`** (`:560`). These deltas use the file's markers. "TM11 untouched" in the decision
  record means the main spec's **TM12** — and it is untouched.

## Excluded from these deltas, deliberately

- **Any tap-source read**, and therefore any description, version, homepage, license, dependency list,
  install count, deprecation flag or size for a not-installed tap hit. TM5 forbids the read
  unconditionally, and PS8 restates the resulting five-fact ceiling.
- **A merged ranked list.** PS3's order is broken by 365-day install count, which a tap package does
  not have. The two orders stay independent, which is also what keeps the hits visibly a different kind
  of result rather than degraded catalog rows.
- **A name-only detail pane for a not-installed hit.** Not-installed rows are non-selectable in this
  slice; the minimal pane is a clearly scoped follow-up.
- **Any `SearchFilters` member for this source.** PS4's declared-filter-set scenario stays true by
  construction: the section is composed, not filtered.
- **A `package-trust` delta.** Nothing on this surface reads, presents or decides on a grant.
