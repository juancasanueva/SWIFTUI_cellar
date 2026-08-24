# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (**14 requirements / 67
scenarios**, established by `2026-08-02-m2-installed-inventory` and amended through M6). This delta is
**1 ADDED, 0 modified, 0 removed, 0 renamed**: **12 scenarios** are added, taking the capability to
**15 requirements / 79 scenarios**.

Nothing is removed, modified or renamed here, so `rules.archive`'s destructive-delta warning does not
fire and every existing requirement stays byte-identical.

**Why ADDED and why here.** II7 already promises that an installed package with no matching catalog
record "MUST still be listed with everything the snapshot knows about it". The list keeps that promise;
the detail surface does not. This requirement extends the same promise to the detail surface without
touching II7's join rule. It lives in `installed-inventory` because that capability owns
`InstalledPackage` and is the only target that sees both `BrewProcess` and `Catalog` one-directionally;
`package-detail` scopes itself to "a single **catalog** package", so a receipt-backed detail cannot live
there without inverting the dependency II7's own scenario asserts.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m10-third-party-detail/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decisions consumed** (maintainer/orchestrator, 2026-08-24, Engram
`sdd/m10-third-party-detail/state` obs `#7780`): fact groups ordered identity → origin → install state;
a multi-keg formula shows its primary keg plus a count of the others; the homepage is presented as a
link; the existing scoped copy stays as a footer; the surface never claims "third-party tap".

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` ("observable behavior of CellarCore types without referencing SwiftUI views") | `swift test --package-path Packages/CellarCore` | **7** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions (`openspec/specs/app-updates/spec.md:17`) | `xcodebuild test … -only-testing:cellarTests` | **5** |

## ADDED Requirements

### Requirement: The installed receipt supplies a reduced detail for a package the catalog does not carry

Where the installed snapshot reports a package and no catalog record exists for its `(kind, name)`
identity, this capability MUST supply a **reduced detail** composed from that snapshot record alone, so
II7's promise reaches the detail surface and not only the list. Its receipt-derived part MUST be a
pure, `nonisolated`, `Sendable` value **totally derived from one installed record**: it MUST take no
other input, perform no I/O, consult no catalog value, and cause no brew invocation. Facts that other
capabilities already own for the same `PackageID` — size on disk, and whether the package was installed
on request — MAY be joined to it at presentation from the stores that already answer them, and joining
them MUST likewise cause no brew invocation and MUST NOT start a scan. The whole detail is therefore
composed from data already resident, on exactly the one-probe terms this capability's first requirement
states.

The exposed facts MUST be ordered in three groups — **identity**, then **origin**, then **install
state**:

1. **Identity** — the package kind, and the published homepage when the receipt carries one. The
   homepage MUST be exposed as a URL value rather than as free text, so a consumer can present it as a
   link without re-parsing it. The published description, when the receipt carries one, MUST also be
   exposed with its absence preserved; whether it is a member of the identity group or a sibling member
   of the same value is not fixed here, because it is presented as its own block rather than as a
   labelled fact row. This requirement is **member-name-neutral**: it constrains which facts exist and
   in which order they are presented, not how the value names them.
2. **Origin** — the tap of origin the receipt reports, and nothing else. This group MUST NOT carry a
   trust verdict, a signature claim, or any value whose meaning is "this package is verified".
3. **Install state** — whether the package was installed on request or as a dependency, its size on
   disk once the disk-usage capability has answered for it, pin state with the pinned version when the
   receipt reports one, and the kind-specific facts below.

The **display name and the version story are not facts of this projection**. Both are already rendered
by the shared identity header the catalog pane and this pane have in common, and the version story
there (installed version, the offered version when the two are distinguishable, and outdated state) is
that header's property. In particular this projection MUST NOT expose a "latest", "current" or
"published" version fact: the decoder falls the receipt's current-version value back to the installed
keg's own version, so such a row would assert a published-version claim the receipt never made — the
same class of false claim that disqualifies synthesizing a catalog record. Outdated state MUST NOT be
restated as a fact row for the same reason.

A fact MUST be exposed **only for the kind that can publish it**.

A formula's reduced detail MUST expose its **link state**, in both states, with the exact copy `Linked`
when the receipt names a linked keg and `Not linked` when it does not. It MUST expose the **primary
keg's version** whether or not the formula is linked — an unlinked formula still has a primary keg, and
its version MUST NOT be withheld because no keg is linked. When more than one keg is installed it MUST
additionally report the count of the other installed kegs with the exact copy `N other versions
installed`, and `1 other version installed` in the singular; the other kegs MUST NOT be truncated away
or dropped, and a single-keg formula MUST expose no such fact at all.

A cask's reduced detail MUST expose the receipt's tri-state auto-updates declaration as **three
distinguishable outcomes**: the exact shipped copy `Updates itself` when the receipt declares `true`,
the exact copy `Updated by Homebrew` when it declares `false`, and **no fact at all** when the receipt
declares nothing — "not declared" is not "declared false", exactly as this capability's decoding
requirement already mandates.

Neither kind MUST expose the other's facts: a cask MUST NOT expose a keg count, a primary-keg version,
a linked-keg state or a link state, and a formula MUST NOT expose an auto-updates declaration.

**Absence MUST be preserved as absence.** An optional receipt field that is absent MUST yield **no fact
at all** — never the empty string, never `unknown`, never a dash or any other placeholder. In
particular, a record whose tap Homebrew withholds MUST expose **no origin fact**, and a record with no
published description or homepage MUST expose neither.

The reduced detail MUST NOT expose an install date or install timestamp. This capability's decoder
currently collapses a missing timestamp to the Unix epoch, so an install-date fact would state
1 January 1970 as though it were a fact about this Mac. Until that absence is preserved through the
decoder, no such fact may exist.

Where the reduced detail is presented:

- Its origin fact MUST carry the `package-detail` per-package grant marker under that requirement's
  exact-identity rule, produced by the `package-trust` projection that owns the marker copy. The
  presenting surface MUST NOT compose that copy locally. Where the tap of origin is absent, the
  identity cannot be established exactly, so the marker MUST be absent too — and its absence MUST NOT
  be marked, muted or explained.
- The surface MUST offer the **same mutation verbs** the installed list row offers for the same
  package, obtained from the same shared mutation surface, so the two cannot drift. No verb MUST be
  re-implemented for this surface.
- The surface MUST offer **no trust control**: nothing on it MUST grant, revoke or alter a tap trust or
  a per-package grant, and nothing MUST state or imply that the package is untrusted, unverified,
  unsigned or unnotarized.
- The surface MUST retain the exact copy “This installed package is not in Cellar’s core/cask
  catalog.” as a footer, and MUST NOT state or imply that the package comes from a third-party tap. A
  catalog miss has at least four causes — a third-party tap, an unpublished or locally built package, a
  cold or never-synced catalog, and a package the current catalog dropped — so the copy MUST remain a
  statement about Cellar's catalog rather than a claim about the package's origin.

#### Scenario: A package the catalog does not carry is detailed from its receipt alone

- GIVEN an installed formula published by tap `acme/tools`, carrying a description, a homepage and one
  installed keg, with no catalog record for its `(kind, name)`
- WHEN its reduced detail is composed
- THEN it exposes identity facts, then the origin fact, then install-state facts, in that group order
- AND every exposed value equals the snapshot's value, and no catalog value is consulted
- Verification: `unit`

#### Scenario: Composing the reduced detail reaches no process layer

- GIVEN the source of the type that composes the reduced detail and the source of the surface that
  presents it
- WHEN both are scanned for any reference to the brew-process execution layer, to `Process`, or to a
  store refresh triggered by presenting the detail
- THEN neither contains one
- AND the composition takes exactly one installed record as its input, with no process-launcher
  dependency to inject
- Verification: `unit-app`

#### Scenario: Facts do not cross between formula and cask

- GIVEN an installed formula and an installed cask, neither carried by the catalog
- WHEN every fact each one exposes is enumerated
- THEN the formula exposes no auto-updates declaration
- AND the cask exposes no keg count, no primary-keg version, no linked-keg state and no link state
- Verification: `unit`

#### Scenario: A cask's auto-updates declaration has three distinguishable outcomes

- GIVEN three installed casks whose receipts declare auto-updates `true`, declare it `false`, and
  declare nothing, none of them carried by the catalog
- WHEN each reduced detail's facts are enumerated
- THEN the first reports exactly `Updates itself` and the second exactly `Updated by Homebrew`
- AND the third exposes no auto-updates fact at all, so "not declared" is never presented as
  "declared false"
- Verification: `unit`

#### Scenario: A linked multi-keg formula reports its primary keg and a count of the others

- GIVEN an installed formula with three installed kegs, one of them linked, and no catalog record
- WHEN its reduced detail is composed
- THEN the install-state group reports exactly `Linked` and names the primary keg's version
- AND reports exactly `2 other versions installed`, rather than truncating to one keg or dropping them
- Verification: `unit`

#### Scenario: An unlinked formula still reports its primary keg, and a single other keg is singular

- GIVEN an installed formula with two installed kegs and no linked keg, and a second unlinked formula
  with exactly one keg, neither carried by the catalog
- WHEN their reduced details are composed
- THEN both report exactly `Not linked` and both name their primary keg's version
- AND the first reports exactly `1 other version installed`, in the singular
- AND the second exposes no other-versions fact at all
- Verification: `unit`

#### Scenario: A withheld tap yields no origin fact and no marker

- GIVEN an installed package whose receipt reports no tap, and a grant report granting a package of the
  same kind and name under some tap
- WHEN its reduced detail is composed
- THEN it exposes no origin fact
- AND it carries no per-package grant marker, no placeholder for either, and no explanatory note
- Verification: `unit`

#### Scenario: An absent description or homepage is absent, not empty

- GIVEN an installed package whose receipt publishes neither a description nor a homepage, and no
  catalog record exists for it
- WHEN every exposed fact is enumerated
- THEN no description value and no homepage fact exist, in whatever member each would occupy
- AND no exposed value is the empty string, `unknown`, or any other placeholder standing for absence
- Verification: `unit`

#### Scenario: No fact reports an install date

- GIVEN the source of the type that composes the reduced detail and the source of the surface that
  presents it, and an installed package whose receipt omits its install timestamp
- WHEN both sources are scanned for an install-date fact and every exposed fact is enumerated
- THEN no label, no value and no source line reports an install date or an install timestamp
- AND no exposed value derives from the Unix epoch
- Verification: `unit-app`

#### Scenario: The grant marker sits beside the origin fact and is never composed locally

- GIVEN an installed package published by tap `acme/tools` whose exact `(kind, name, tap)` identity is
  granted in the decoded trust report, with no catalog record
- WHEN its reduced detail is presented
- THEN the exact marker copy “Trusted individually” is presented beside the origin fact
- AND it is produced by the `package-trust` projection, with no such copy composed by the presenting
  surface itself
- Verification: `unit-app`

#### Scenario: The surface offers the installed row's verbs and no trust control

- GIVEN a package the catalog does not carry, presented as a reduced detail
- WHEN every control on that surface is enumerated
- THEN its mutation verbs are exactly those the installed list row offers for that package, obtained
  from the same shared mutation surface
- AND no control grants, revokes or alters a tap trust or a per-package grant
- Verification: `unit-app`

#### Scenario: The catalog-miss copy stays scoped to the catalog

- GIVEN a reduced detail presented for a package the catalog does not carry
- WHEN its footer copy and every other string on the surface are read
- THEN the footer is exactly “This installed package is not in Cellar’s core/cask catalog.”, with a
  typographic apostrophe
- AND no copy states or implies a third-party tap, an untrusted origin, or an unverified package
- Verification: `unit-app`

## Notes for archive

- The ADDED block is appended after the capability's current last requirement and promoted as **II15**.
  II1–II14 are byte-identical.
- **No `package-trust` delta accompanies this change.** PD8, PT3, PT5, PT6 and PT7 are **activated** by
  this surface, not changed: PD8's marker finally has a tap-of-origin fact to sit beside, PT3's exact
  identity rule is what makes the withheld-tap case marker-free, PT5 keeps the copy in one projection,
  PT6 keeps the absence unmarked, and PT7 is asserted here as an absence of controls.
- The excluded install-date fact is a **decoder** defect, not a rendering choice: `InstalledDecoder`
  maps a missing timestamp to `Date(timeIntervalSince1970: 0)`. Preserving that absence is a follow-up
  delta against this same capability.
- **The verification-class table above is NOT promoted.** `openspec/specs/installed-inventory/spec.md`
  carries no `## Verification classes` table today — `2026-08-23-m7-tap-trust` recorded that fact
  explicitly at its own archive (main spec `:948`) and deliberately left untouched requirements without
  one. This delta follows that precedent: the table is delta-local provenance, the per-scenario inline
  `- Verification:` lines promote with the requirement, and no table is hand-added to the main spec.
- The class name is **`unit-app`**, the established name for a `cellarTests` source-scan/composition
  assertion (`openspec/specs/app-updates/spec.md:17`), not a new `composition` class. `unit` keeps its
  ordinary meaning; nothing here narrows it.
- **The excluded version facts are a reconciliation with design DD-5, not an omission.** The receipt's
  current-version value falls back to the installed keg's version in `InstalledDecoder` (`:77`, `:109`),
  so a "Latest version" row on this branch could assert a published-version fact the receipt never made.
  The version story stays the shared header's property. `Size on disk` and `Installed as` are named as
  install-state facts even though design DD-7 keeps them view-side, because this requirement constrains
  which facts the surface presents, not which member of which type supplies them.
