# Spec index — `m10-third-party-detail`

Three delta files. Hybrid store: these files are canonical; Engram topic
`sdd/m10-third-party-detail/spec` is the searchable mirror.

| Capability | Op | Block | Scenarios | Net |
|---|---|---|---|---|
| `installed-inventory` | **ADDED** — the installed receipt supplies a reduced detail for a package the catalog does not carry | new, promotes as **II15** | +12 (7 `unit`, 5 `unit-app`) | 14 → **15** requirements, 67 → **79** scenarios |
| `package-detail` | **MODIFIED** — **PD6** | whole block, both existing scenarios byte-identical | +1 (`unit`) | 8 requirements unchanged, 30 → **31** scenarios |
| `tap-management` | **MODIFIED** — **TM5** | whole block, all nine existing scenarios byte-identical | +1 (`unit`) | 13 requirements unchanged, 57 → **58** scenarios |

**Totals: 1 ADDED, 2 MODIFIED, 0 REMOVED, 0 RENAMED — 14 new scenarios (9 `unit`, 5 `unit-app`).**
No requirement is removed or renamed, so `rules.archive`'s destructive-delta warning does not fire.

## Verification classes

Both names are already established in this repository; this change introduces none.

| Class | Meaning | Runner |
|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` |

None of the three target specs carries a `## Verification classes` table today (only `app-updates` and
`release-distribution` do), so **no class table is promoted at archive**. Each delta's table is
delta-local provenance; the per-scenario inline `- Verification:` lines promote with their requirements,
following the precedent `2026-08-23-m7-tap-trust` recorded at `openspec/specs/installed-inventory/spec.md:948`.

## Copy pinned by these deltas

| Fact | Exact copy | Condition |
|---|---|---|
| Formula link state | `Linked` / `Not linked` | both states, always |
| Formula other kegs | `N other versions installed`; `1 other version installed` singular | more than one keg; no fact for a single keg |
| Cask auto-updates | `Updates itself` (shipped, `PackageDetailView.swift:578-579`) / `Updated by Homebrew` | declared `true` / declared `false`; **no fact** when undeclared |
| Grant marker | `Trusted individually` | `granted` by exact identity; produced by the `package-trust` projection |
| Footer | `This installed package is not in Cellar’s core/cask catalog.` (U+2019) | always |

The primary keg's version MUST be exposed for **both** linked and unlinked formulae. No "latest",
"current" or "published" version fact exists on this surface (design DD-5): the version story belongs to
the shared identity header, because the receipt's current-version value falls back to the installed
keg's own version in `InstalledDecoder` (`:77`, `:109`).

## `package-trust`: activated, not changed — no delta

m10 adds **no** `package-trust` delta. The following requirements bind the new surface exactly as
written today and are **activated** by it rather than amended:

| Requirement | How m10 activates it |
|---|---|
| **PD8** — grant marker beside the tap of origin, by exact identity | The reduced detail is the first surface to render a tap-of-origin fact for a package the catalog does not carry, so the marker finally has the anchor PD8 requires. Resolved through the existing `TapProjection.grantsIndividually(_:publishedBy:in:)` path; the marker still is not a projection field. |
| **PT3** — attribution rests on published qualified identity | The receipt's `tap` is optional. Where it is absent the identity cannot be established exactly, so the state is `noGrantRecorded` and no marker is produced. |
| **PT5** — one projection supplies the copy | The marker copy comes from the `package-trust` projection. The new surface composes no copy of its own; `cellarTests/PerPackageTrustCompositionTests.swift` already fails the build if it does. |
| **PT6** — per-package copy is positive-only | A package with no grant carries no badge, no muted marker, no tooltip and no empty state on the new surface. |
| **PT7** — this capability grants and revokes nothing | The new surface offers no trust control at all, asserted as an absence by a `unit-app` scenario. |

The `§8` probe (`explore.md`, maintainer's Mac, 2026-08-24) measured that Homebrew reports a non-null
`tap` for individually granted, installed packages, so PD8 activates from the receipt alone. The
withheld-tap state remains real for packages with no grant, and the reduced detail renders no origin
fact and no marker in that case.

## Provenance correction: m9 cited TM1 where the clause is TM5

The `2026-08-24-m9-per-package-trust` archive states in at least three places
(`archive-report.md:440`, `tasks.md:72`, `specs/package-detail/spec.md:20`) that **TM1** forbids a
third-party detail fallback. That is a **mis-citation**:

- **TM1** — "One structured snapshot supplies tap list and detail" — is a one-invocation rule about
  acquiring *tap* detail from `brew tap-info --installed --json`. It contains no detail-fallback clause.
- The clause is **TM5**'s, at `openspec/specs/tap-management/spec.md:147-149`, and this change narrows
  it to its meaning.

TM1 does contribute a genuine constraint that m10 honours: **no additional brew invocation may be
introduced to complete a detail.** That is asserted by scenarios in both the `installed-inventory` and
`tap-management` deltas.

## Excluded from these deltas, deliberately

- **An install-date fact.** `InstalledDecoder.date(_:)` collapses a missing timestamp to the Unix
  epoch, so the fact would print 1 January 1970. II15 forbids the fact; preserving decoder absence is a
  follow-up delta against `installed-inventory`.
- **Receipt-backed release notes** (`release-notes` D4 territory: explicit entry point and egress
  consent).
- **Any claim about a third-party tap.** A catalog miss has at least four causes, so the existing
  scoped footer copy is pinned byte-exact instead of "improved".
