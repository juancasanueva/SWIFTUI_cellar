# package-detail

The projection a single catalog package must expose — required fields, dependency and dependent
edges, deprecation status, analytics semantics, and the third-party-tap exclusion. Owned by
`Packages/CellarCore` target `Catalog`.

## Requirements

### Requirement: Required detail projection

A package detail resolved by `(kind, name)` MUST expose: display name, kind, description, homepage,
license, version, caveats, tap of origin, direct build dependencies, direct runtime dependencies,
dependents, deprecation status, disabled status, and install count. Fields the payload publishes as
`null` or omits MUST be exposed as absent, distinct from an empty string. A lookup for a package not
in the snapshot MUST return not-found rather than throwing.

A cask detail MUST additionally expose, when the payload publishes them: the download URL, the
published `sha256` checksum, what the cask installs, the cask's declared dependencies
(`depends_on`), the packages it declares a conflict with (`conflicts_with`), and its auto-updates
flag. A formula detail MUST additionally expose its stable source URL and its head source URL. Each
of these MUST follow the same absence rule as every other optional field: a cask that publishes no
`depends_on` MUST report absence, distinct from an empty list, and a value the payload omits MUST NOT
be substituted with a default.

What a cask installs MUST be exposed as a closed, typed set of artifact stanza kinds — exactly `app`,
`binary` and `pkg` — together with a count of every published stanza the projection does not
represent. The set is deliberately this narrow: these three answer "what gets installed where", and
nothing else is projected. A `zap` stanza, an `uninstall` stanza, and every other published stanza
kind MUST be counted in that remainder rather than projected, and their contents MUST NOT be carried
by this projection at all. The count MUST be a value a consumer can render directly (an "N not shown"
remainder), MUST be `0` rather than absent when every published stanza was represented, and MUST be
distinct from the snapshot's skipped-record count. A published stanza MUST NOT be discarded without
being counted.

Every artifact value this projection exposes MUST be data describing what an installer declares it
will place on the machine, never an instruction this system carries out. Because no `zap`,
`uninstall` or other directive stanza content is projected, the projection MUST carry nothing that
could be executed or acted on: no command, no script, no `launchctl` or `pkgutil` directive, and no
path that a removal would delete. It MUST NOT expose an action that runs any published stanza. The
counted remainder MUST remain a count — it MUST NOT carry the content of the stanzas it counted.

Exposure MUST be uniform across records: a field this projection carries MUST be present for every
package that publishes it and absent for every package that does not. A field MUST NOT appear for one
record and silently vanish for another that published the same key.
(Previously: the projection covered the fourteen fields above with the same absence rule, and carried
no cask inspection field, no artifact stanzas, no counted remainder, no formula source URLs, and no
nothing-runnable or uniformity rule.)

#### Scenario: Formula detail exposes every required field

- GIVEN a snapshot containing formula `wget`
- WHEN its detail is resolved
- THEN it reports description `Internet file retriever`, homepage, license `GPL-3.0-or-later`,
  version, tap `homebrew/core`, kind `formula`, and its dependency, dependent, deprecation, disabled
  and install-count fields

#### Scenario: Cask detail exposes every required field

- GIVEN a snapshot containing cask `iterm2`
- WHEN its detail is resolved
- THEN it reports display name `iTerm2`, kind `cask`, version, homepage and tap `homebrew/cask`

#### Scenario: Absent optional fields are absent, not empty

- GIVEN a record whose payload had `"desc": null`, `"caveats": null` and no license
- WHEN its detail is resolved
- THEN description, caveats and license are absent and are not empty strings

#### Scenario: Unknown package is not-found, not an error

- GIVEN a snapshot without `nosuchpackage`
- WHEN a detail lookup for `(formula, nosuchpackage)` runs
- THEN it returns not-found and nothing is thrown

#### Scenario: Cask detail exposes its inspection fields

- GIVEN a snapshot containing cask `iterm2`, whose published record carries a download URL, a
  `sha256`, an `app` stanza targeting `/Applications/iTerm.app`, a `zap` stanza listing paths, a
  `depends_on` entry and a `conflicts_with` list naming `iterm2@beta` and `iterm2@nightly`
- WHEN its detail is resolved
- THEN the download URL, the checksum, the `app` stanza, the dependency and both conflict entries are
  exposed, each matching the published payload
- AND the `zap` stanza is not exposed — it appears only as `1` in the count of unrepresented stanzas
- AND the auto-updates flag is exposed

#### Scenario: Every projected stanza kind is exposed

- GIVEN a cask whose `artifacts` list publishes an `app`, a `binary` and a `pkg` stanza and nothing
  else
- WHEN its detail is resolved
- THEN all three stanzas are exposed under their own kinds, each carrying the name it was published
  with and its destination where one was published
- AND the count of unrepresented stanzas is `0` and is not absent

#### Scenario: Every unprojected stanza kind is counted, never silently dropped

- GIVEN a cask whose `artifacts` list publishes an `app` stanza plus a `zap`, an `uninstall` and a
  stanza of a kind that did not exist when this build shipped
- WHEN its detail is resolved
- THEN the `app` stanza is exposed and the count of unrepresented stanzas is `3`
- AND that count is reported separately from the snapshot's skipped-record count
- AND a second cask publishing only unprojected stanzas resolves with no exposed stanza and a
  non-zero count

#### Scenario: A cask publishing no dependencies reports absence, not emptiness

- GIVEN a cask publishing neither `depends_on` nor `conflicts_with`, and no `artifacts`
- WHEN its detail is resolved
- THEN all three are absent and are distinguishable from an empty list
- AND the detail resolves successfully with every other required field intact

#### Scenario: Formula source URLs are exposed

- GIVEN a snapshot containing formula `git`, whose payload publishes `urls.stable.url` and
  `urls.head.url`
- WHEN its detail is resolved
- THEN both source URLs are exposed
- AND a formula publishing no `urls.head` reports an absent head URL

#### Scenario: Nothing the projection exposes is runnable

- GIVEN a cask publishing an `app` stanza, a `zap` stanza listing paths and `launchctl` directives,
  and an `uninstall` stanza carrying a script
- WHEN its detail is resolved and every exposed value is enumerated
- THEN the only artifact values exposed are the `app` stanza's name and destination, plus an
  unrepresented-stanza count of `2`
- AND no exposed value carries a path, command, script or directive drawn from the `zap` or
  `uninstall` stanza
- AND the projection offers no operation that executes any published stanza, deletes any listed path,
  or mutates the machine

### Requirement: Dependencies are flat and direct

Detail MUST list direct build dependencies and direct runtime dependencies as two separate flat
lists, in the order the payload declares them. It MUST NOT flatten a recursive dependency closure
into these lists and MUST NOT deduplicate across the two lists. Each entry MUST carry enough
identity to resolve to another catalog package when that package exists in the snapshot.

#### Scenario: Direct dependencies only

- GIVEN formula `git` declaring runtime dependencies `[pcre2, gettext]` and build dependencies
  `[gettext, pkgconf]`, where `pcre2` itself declares further dependencies
- WHEN `git`'s detail is resolved
- THEN its runtime list is exactly `[pcre2, gettext]` and its build list is exactly
  `[gettext, pkgconf]`
- AND no transitive dependency of `pcre2` appears in either list

#### Scenario: A dependency outside the snapshot is still listed

- GIVEN a formula declaring a dependency on a name not present in the snapshot
- WHEN its detail is resolved
- THEN the dependency is listed by name and is marked as not resolvable to a catalog package

### Requirement: Dependents are derived by inverting dependency edges

Dependents ("required by") MUST be derived by inverting the dependency edges of the snapshot at sync
time, not requested from the network and not computed per query. The inversion MUST be complete and
symmetric over the snapshot: if `A` declares a build or runtime dependency on `B`, then `A` MUST
appear in `B`'s dependents. A package with no inbound edge MUST report an empty dependents list, not
an absent value.

#### Scenario: Inversion is symmetric

- GIVEN a snapshot where `git` declares a runtime dependency on `pcre2`
- WHEN `pcre2`'s detail is resolved
- THEN its dependents include `git`

#### Scenario: Build-only dependents are included

- GIVEN a snapshot where `wget` declares `pkgconf` only as a build dependency
- WHEN `pkgconf`'s detail is resolved
- THEN its dependents include `wget`

#### Scenario: A leaf package reports an empty dependents list

- GIVEN a snapshot where no record depends on cask `iterm2`
- WHEN its detail is resolved
- THEN its dependents list is empty and is not absent

#### Scenario: Edges to absent packages create no dependents

- GIVEN a formula declaring a dependency on a name not present in the snapshot
- WHEN the inversion runs
- THEN no dependents entry is created for that absent name and the sync still succeeds

### Requirement: Deprecation and disabled status carry reasons and dates

Detail MUST expose deprecation and disabled as two independent statuses, each with its flag and,
when the payload supplies them, its reason and its date. A package that is neither MUST report both
flags false with absent reasons and dates. Deprecated or disabled status MUST NOT remove a package
from the catalog or from detail resolution.

#### Scenario: Deprecated package exposes reason and date

- GIVEN a record with `deprecated: true`, a deprecation reason and a deprecation date
- WHEN its detail is resolved
- THEN the deprecation flag is true and the reason and date are exposed

#### Scenario: Disabled package exposes reason and date

- GIVEN a record with `disabled: true`, a disable reason and a disable date
- WHEN its detail is resolved
- THEN the disabled flag is true and the reason and date are exposed

#### Scenario: Healthy package reports both statuses false

- GIVEN a record with `deprecated: false` and `disabled: false`
- WHEN its detail is resolved
- THEN both flags are false and all four reason and date fields are absent

### Requirement: Install count is an opt-in lower bound

The install count MUST be exposed together with the facts needed to describe it honestly: the window
is 365 days, the metric is installs on request (formulae) or installs (casks), the population is
Homebrew users who did not opt out of analytics, and the value is therefore a lower bound. An absent
count MUST be distinguishable from a count of zero. The projection MUST NOT present the count as an
absolute install total.

#### Scenario: Count is exposed with its window and lower-bound semantics

- GIVEN a package whose 365-day count is 2,808,879
- WHEN its detail is resolved
- THEN the value is `2808879`, the window is 365 days, and the value is flagged as a lower bound
  over opted-in users

#### Scenario: Absent count is distinguishable from zero

- GIVEN a package with no analytics entry and a package with a recorded count of `0`
- WHEN both details are resolved
- THEN the first reports an absent count and the second reports `0`

### Requirement: Third-party tap packages are outside catalog scope

The catalog covers the `homebrew/core` and `homebrew/cask` taps only. A package published by any
other tap MUST be absent from the snapshot, MUST NOT appear in search results, and a detail lookup
for it MUST return the ordinary not-found result. Its absence MUST NOT be reported as a sync
failure, a decode failure, or an error state.

#### Scenario: A third-party tap package is a normal not-found

- GIVEN a successful sync and a package name published only by a third-party tap
- WHEN a detail lookup for it runs
- THEN it returns not-found, the sync status remains successful, and no error is raised

#### Scenario: Every snapshot record belongs to a covered tap

- GIVEN a successfully persisted snapshot
- WHEN each record's tap is inspected
- THEN every record reports `homebrew/core` or `homebrew/cask`

### Requirement: No pre-install signature or notarization verdict

Catalog data supports no claim about a package's code signature or notarization status, so this
projection MUST NOT derive, expose, or make expressible any such claim. It MUST NOT carry a
signature status, a notarization status, a signing identity, a team identifier, a trust verdict, or
any value whose meaning is "this download is verified". The published `sha256` MUST be exposed only
as the checksum the cask declares for its download — an expectation stated by the published record,
not the result of any check this system performed, and not evidence about the origin's identity. A
cask that publishes `no_check` in place of a digest MUST be exposed as declaring no checksum,
distinguishably from a cask that declares one; that literal MUST NOT be exposed as though it were a
digest, and MUST NOT be silently dropped.

Post-install signature and notarization inspection remains the property of the capabilities that own
it; this projection MUST NOT accept, reuse, or forward a verdict from them for a package that is not
installed. A field that would tempt a consumer to render a verdict MUST NOT exist, so the prohibition
is enforced by the projection's shape rather than by a consumer's discipline.

#### Scenario: A fully populated cask detail yields no signature claim

- GIVEN a cask whose payload publishes every widened key, including `url` and `sha256`
- WHEN its detail is resolved and every exposed field is enumerated
- THEN no field reports a signature status, a notarization status, a signing identity, a team
  identifier, or a verification verdict

#### Scenario: The checksum is a published expectation, not a verification result

- GIVEN a cask detail exposing a `sha256`, and a second cask whose payload publishes `"sha256":
  "no_check"`
- WHEN each value's semantics are inspected
- THEN the first is identified as the checksum the published record declares for the download
- AND the second is identified as declaring no checksum, and its literal is not exposed as a digest
- AND no field states or implies that either download was fetched, hashed, or verified

#### Scenario: No post-install verdict reaches an uninstalled package

- GIVEN a machine holding post-install integrity results for an installed cask, and a second cask
  that is not installed
- WHEN the second cask's detail is resolved
- THEN it carries no integrity, signature or notarization value of any kind
- AND the projection declares no dependency on the capability that produces those results

### Requirement: A per-package grant is shown beside the tap of origin, resolved by exact identity

Where a package detail is presented and the `package-trust` capability reports that package's state as
`granted`, the detail MUST carry the exact marker copy “Trusted individually”, positioned beside the
existing tap-of-origin fact, because the grant is a fact *about that origin* and is unreadable apart
from it.

The state MUST be resolved by **exact identity** — kind, name and tap of origin together, matched
against the grant entry's published qualified identity. A bare name MUST NOT match a qualified entry:
a grant for `acme/tools/widget` MUST NOT mark `homebrew/core/widget`, and MUST NOT mark a package whose
tap the detail does not know exactly. Where identity cannot be established exactly, the marker MUST be
absent.

The marker MUST be **positive-only**. A package whose state is `noGrantRecorded` or `unreported` MUST
carry no marker, no placeholder, no muted variant and no note — absence from the report is not a fact
about that package, and `unreported` is not zero.

The marker MUST NOT become a field of the detail projection this capability owns: PD1's exposed field
set is unchanged, and PD7's prohibition on a signature status, notarization status, signing identity,
team identifier or trust verdict existing as a field MUST remain enforced by the projection's shape.
The marker MUST NOT state or imply that the package's download was fetched, hashed, verified, signed or
notarized; it states only that Homebrew records a grant for this exact package. It MUST offer no
control: nothing on this surface MUST grant, revoke or alter a grant.

#### Scenario: A grant marks only the exact package it names

- GIVEN a report granting cask `acme/tools/widget`
- WHEN details are resolved for a package named `widget` whose tap is `homebrew/cask`, and for a package named `widget` whose tap is `other/tools`
- THEN neither carries the marker
- AND the marker is produced only for a detail whose kind, name and tap of origin match the entry exactly
- Verification: `unit`

#### Scenario: No grant and no report both render nothing

- GIVEN a package detail whose per-package state is in turn `noGrantRecorded` and `unreported`
- WHEN the detail is presented
- THEN neither renders a marker, a placeholder, a muted marker or an explanatory note
- AND neither renders any string containing “trusted”
- Verification: `unit`

#### Scenario: The marker is not a projection field

- GIVEN the package detail projection this capability owns
- WHEN every field it exposes is enumerated, with a decoded grant report present
- THEN the field set is exactly the one PD1 pins, unchanged
- AND no field carries a trust state, a grant, a verdict, or a value whose meaning is “this download is verified”
- Verification: `unit`

#### Scenario: The marker states a grant and offers nothing

- GIVEN a package detail whose state is `granted`
- WHEN its marker copy and every control on that surface are read
- THEN the copy is exactly “Trusted individually”
- AND no control grants, revokes or alters a grant, and nothing states or implies that the download was verified, signed or notarized
- Verification: `unit`

## Provenance

- Established by change `m1-catalog-browse` (archived `2026-08-01`), ADDED-only delta — 6
  requirements / 17 scenarios, copied verbatim from
  `openspec/changes/archive/2026-08-01-m1-catalog-browse/specs/package-detail/spec.md`. This is the
  first main spec for the capability; nothing was modified or removed.
- Note on "Dependencies are flat and direct": the first verification run flagged its covering
  assertion as tautological (`!X || X`); commit `1c5331c` replaced it with a falsifiable assertion
  against `formula-slice.json`, and re-verification recorded the requirement as COMPLIANT. Spec text
  unchanged.
- **Amended by change `m5-catalog-inspection` (archived `2026-08-06`, PRD milestone **M5**
  "Pro-parity flows", slice 1 of 5 — pre-install cask inspection)**: **1 MODIFIED** requirement
  replaced as a whole block — "Required detail projection" (4 → 10 scenarios) — and **1 ADDED**
  requirement, "No pre-install signature or notarization verdict" (3 scenarios). 6 requirements /
  17 scenarios → **7 requirements / 26 scenarios**. Nothing was added beyond that, removed or
  renamed; the other five requirements are byte-identical, all four pre-existing scenarios survive
  unchanged, and the replacement is a **strict superset** of the text it replaced — zero lines
  deleted.
  - **The projected artifact set is exactly `app`, `binary` and `pkg`.** Probe **U4** measured the
    alternative and decision **D5** triggered: `zap` alone costs +1.23 MB encoded — **+34% over the
    entire accepted widening** — and is a directive map (`trash`, `rmdir`, `delete`, `launchctl`,
    `pkgutil`, `signal`, `login_item`, `script`) rather than a name list, so representing it
    faithfully re-introduces the heterogeneous tree U4 rejected. `zap`, `uninstall`, `font` and every
    unmodelled kind are **counted in the remainder and their contents are not projected at all**.
    The three projected kinds answer the binding success criterion "what gets installed where" for
    0.15 MB; `zap` answers a different question (what an *uninstall* would remove), answerable at
    uninstall time where `MutationCommand.uninstall(…, zap:)` already lives.
  - **D2's five-kind list and D4's "zap and uninstall render faithfully" are superseded by D5 *as
    triggered*** — the mechanism D5 exists to provide. This is a narrowing of a narrowing: D5's own
    written fallback was to drop `artifacts` entirely. The D5 floor is met — cask `url`, `sha256`,
    `depends_on` and `conflicts_with` are all retained.
  - **`target` is not a stanza kind.** It is a companion key attached to the stanza it modifies
    (Homebrew's `app "X.app", target: "Y"` serialisation), so it is neither projected nor counted.
    Counting it would make `cask-iterm2.json`'s remainder `2` where this requirement binds it to `1`.
  - **The nothing-runnable rule replaced displayed-never-executed, and is strictly stronger.**
    Because no directive stanza content is projected at all, the projection carries nothing that
    *could* be executed or acted on — no command, no script, no `launchctl` or `pkgutil` directive,
    no path a removal would delete — and exposes no action that runs a published stanza. The counted
    remainder must remain a count.
  - **The signature prohibition is enforced by the projection's shape, not by consumer discipline.**
    No signature status, notarization status, signing identity, team identifier or trust verdict may
    exist as a field. `sha256` is exposed only as the checksum the cask **declares** for its
    download; a cask publishing `no_check` is exposed as declaring no checksum, distinguishably from
    one that declares a digest, and that literal is neither rendered as a digest nor silently
    dropped. Post-install inspection stays with `artifact-integrity`, and no verdict is forwarded for
    an uninstalled package.
- The archived delta spec is the verbatim audit trail; this file adds only the header, the
  `## Requirements` wrapper, and this provenance section.
- **Amended by change `m9-per-package-trust`** (archived `2026-08-24` —
  `openspec/changes/archive/2026-08-24-m9-per-package-trust/`), **1 ADDED, 0 modified, 0 removed, 0
  renamed** — **7 req / 26 sc → 8 req / 30 sc**. The ADDED block is appended after PD7 and promoted as
  **PD8**, *"A per-package grant is shown beside the tap of origin, resolved by exact identity"* (4
  scenarios). `rules.archive`'s destructive-delta warning did not fire, and **PD1–PD7 are
  byte-identical** to their prior text — verified at archive by byte-slicing the untouched range
  against a pre-merge copy. Delivered in PR **#73**, merged `2026-08-24` at `ddb9661`.
  - **PD8 is expected to render nothing on today's shipped surface, and that is the point.** PD6 keeps
    third-party tap packages out of the catalog snapshot, search and detail, and `tap-management` TM1
    forbids a third-party detail fallback — while per-package grants exist only for third-party
    packages. So every package detail this view can currently resolve carries **no** marker. The
    requirement was written anyway, and its scenarios are mostly negative, because the failure mode is
    real and cheap to ship by accident: a bare-name match against a qualified grant entry would light
    the marker on `homebrew/core/widget` the moment some unrelated tap's `widget` is granted. **PD8
    exists to make that rendering impossible to get wrong, not to add a visible feature**, and it
    should not be read as dead text when a third-party detail surface eventually arrives.
  - **Why ADDED and not MODIFIED.** The marker is **not** a field of the catalog detail projection.
    PD1's field set is unchanged and PD7's shape prohibition — no signature status, notarization
    status, signing identity, team identifier or trust verdict may *exist* as a field — is unchanged
    and stays enforced by shape. The marker is a value the `package-trust` capability produces from a
    different read, joined at presentation beside the existing Tap fact. Folding it into PD1 would have
    put a non-catalog value inside a catalog projection and quietly weakened PD7.
  - **PD7 and PD6 need no delta, each verified against its own text.** PD8 restates the
    download-verification disclaimer explicitly, so a reviewer meeting "trust verdict" in PD7 finds the
    boundary drawn rather than assumed; and PD8's exact-identity rule is precisely what keeps a
    third-party grant from reaching an official-tap record.
  - **Delivered as `PackageDetailView`'s sixth store** (`trustGrants: TrustGrantStore`, beside
    `diskUsage`), not an injected closure — design **DD-10**. The marker must update when the store
    refreshes, so the view needs the `@Observable` reference; a closure or a pre-computed `Bool` would
    not re-render. **Rejected:** the `m7-tap-trust` DD-12 `@MainActor` closure idiom, which stays
    correct for that change's one-shot lookup at press time.
  - `package-trust` **PT5** owns the marker's exact copy (“Trusted individually”) and its absence
    rules; this requirement owns where it sits and how identity is resolved.
  - The archived delta spec is the verbatim audit trail.
