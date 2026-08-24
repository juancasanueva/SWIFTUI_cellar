# Delta for package-detail

Existing capability — `openspec/specs/package-detail/spec.md` (**7 requirements / 26 scenarios**,
established by `2026-08-01-m1-catalog-browse` and amended by `2026-08-06-m5-catalog-inspection`). This
delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**: **4 scenarios** are added, taking the
capability to **8 requirements / 30 scenarios**.

Nothing is removed, modified or renamed, so `rules.archive`'s destructive-delta warning does not fire
and every existing requirement stays byte-identical.

**Why ADDED and not MODIFIED, stated plainly.** The marker is **not** a field of the catalog detail
projection. PD1's field set is unchanged and PD7's shape prohibition — no signature status, no
notarization status, no trust verdict may *exist* as a field — is unchanged and MUST stay enforced by
shape. The marker is a value the `package-trust` capability produces from a different read, joined at
presentation beside the existing `Tap` fact. Writing it as a new requirement keeps that boundary
explicit; folding it into PD1 would put a non-catalog value inside a catalog projection and quietly
weaken PD7.

**The honest limit of this requirement.** PD6 keeps third-party tap packages out of the catalog
snapshot, search and detail, and `tap-management` TM1 forbids a third-party detail fallback. Per-package
grants exist for third-party packages. So on today's shipped surface, every package detail this view
can resolve is expected to render **no** marker. The requirement is written anyway, and its scenarios
are mostly negative, because the failure mode is real and cheap to ship by accident: a bare-name match
against a qualified grant entry would light the marker on `homebrew/core/widget` the moment some
unrelated tap's `widget` is granted. Pinning the identity rule before the marker exists is the point.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`,
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decision consumed** (maintainer, 2026-08-24, Engram obs `#7759`): package detail **does** get
the “Trusted individually” marker beside its existing Tap fact.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **4** |

## ADDED Requirements

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

## Notes for archive

- The ADDED block is appended after PD7 and promoted as **PD8**. PD1–PD7 are byte-identical.
- **PD7 needs no delta, verified against its text.** Its prohibition is on what the *projection* may
  carry as a field, and it is enforced by the projection's shape. The marker is neither derived from
  catalog data nor exposed as a projection field, and PD8 restates the download-verification
  disclaimer explicitly so a reviewer reading “trust verdict” in PD7 finds the boundary drawn rather
  than assumed.
- **PD6 needs no delta, verified.** Third-party packages remain outside catalog scope; this change adds
  no third-party detail fallback and PD8's identity rule is precisely what keeps a third-party grant
  from reaching an official-tap record.
- Record in provenance that PD8 is expected to render **nothing** on today's shipped surface (PD6), and
  that it exists to make the rendering impossible to get wrong rather than to add a visible feature.
