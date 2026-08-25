# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (**15 requirements / 79 scenarios**,
established by `2026-08-02-m2-installed-inventory`, amended by `2026-08-23-m7-tap-trust`,
`2026-08-24-m9-per-package-trust` and `2026-08-24-m10-third-party-detail`). This delta is **1 MODIFIED,
0 added, 0 removed, 0 renamed**: the modified block keeps all **12** scenarios it carries today, **11**
of them byte-identical, and **amends the twelfth in place**. The capability stays at **15 requirements /
79 scenarios** — round 8 moves no count.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited.
Every textual change is confined to **II15's mutation-verb clause and its verb scenario**, each carrying
its own `(Previously: …)` line. Nothing about the projection, the fact groups, the absence rules, the
grant marker, the trust prohibition or the footer copy moves: those clauses are reproduced verbatim.

**Maintainer UI feedback, 2026-08-25 (round 8) — binding, and this delta's whole reason.** Observed in
the running app, comparing the catalog detail pane against the two tap-backed panes: the catalog pane
presents its verbs as an **Actions** section at the bottom of the pane — a section header, one labelled
button per applicable verb, the primary `brew …` command beneath them with a copy affordance, and the
runner-unavailable guidance under that. The receipt-backed pane II15 owns instead hung the list row's
`⋯` menu in the header's primary-button slot. The maintainer rejected that placement and that shape:
the panes must show the **same Actions section**, in the same position. This is a **presentation**
change and nothing more — no verb is added, removed or re-implemented, no argv shape changes, the
confirmation rule is untouched, and the trust prohibition below is reproduced word for word.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr` with an accepted `size:exception`, `review_budget_lines=5000`,
`strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `#filePath` source-scan idiom | `xcodebuild test … -only-testing:cellarTests` | **1** (amended in place, not added) |

## MODIFIED Requirements

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
- The surface MUST present its mutation verbs as the **same Actions section the catalog detail pane
  presents**, obtained from that **one shared component** rather than restated here, so the two panes
  cannot drift. That section MUST render each applicable verb as its own labelled button, MUST show the
  primary `brew …` command beneath them together with the shared copy affordance, and MUST carry the
  shared runner-unavailable guidance when there is no runner. It MUST sit at the **bottom of the pane**,
  after the pane's own facts and footer content, exactly where the catalog pane places it. The pane's
  identity header MUST carry **no** mutation menu and no mutation button in its primary slot: one pane
  offers exactly one place to act. No verb, no argv and no applicability rule MUST be re-implemented for
  this surface.
  (Previously: the clause required the same verbs "obtained from the same shared mutation surface" as
  the installed **list row** — the `⋯` menu — which this pane rendered in its header's primary-button
  slot. The verbs were right and the presentation was not: the catalog pane answers the same question
  with a labelled Actions section at the foot of the pane, so two detail panes offered one package's
  verbs in two shapes and two places.)
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

#### Scenario: The surface offers the catalog pane's Actions section and no trust control

- GIVEN a package the catalog does not carry, presented as a reduced detail
- WHEN every control on that surface is enumerated
- THEN its mutation verbs are exactly those the catalog detail pane's Actions section offers for that
  package, obtained from that one shared component, with the primary `brew …` command and its copy
  affordance coming from the same component and worded nowhere on this pane
- AND the pane's identity header carries no mutation menu and no mutation button, and the pane declares
  no verb label, no command family and no mutation target of its own
- AND no control grants, revokes or alters a tap trust or a per-package grant
- Verification: `unit-app`
  (Previously: the scenario read “The surface offers the installed row's verbs and no trust control”
  and asserted the verbs were "exactly those the installed list row offers … obtained from the same
  shared mutation surface", which pinned the `⋯` menu and its header slot. The trust half is
  byte-unchanged.)

#### Scenario: The catalog-miss copy stays scoped to the catalog

- GIVEN a reduced detail presented for a package the catalog does not carry
- WHEN its footer copy and every other string on the surface are read
- THEN the footer is exactly “This installed package is not in Cellar’s core/cask catalog.”, with a
  typographic apostrophe
- AND no copy states or implies a third-party tap, an untrusted origin, or an unverified package
- Verification: `unit-app`
