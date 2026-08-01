# Delta for package-detail

New capability — no existing spec. All requirements are ADDED.

Scope: the projection a single catalog package must expose — required fields, dependency and
dependent edges, deprecation status, analytics semantics, and the third-party-tap exclusion.

## ADDED Requirements

### Requirement: Required detail projection

A package detail resolved by `(kind, name)` MUST expose: display name, kind, description, homepage,
license, version, caveats, tap of origin, direct build dependencies, direct runtime dependencies,
dependents, deprecation status, disabled status, and install count. Fields the payload publishes as
`null` or omits MUST be exposed as absent, distinct from an empty string. A lookup for a package not
in the snapshot MUST return not-found rather than throwing.

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
