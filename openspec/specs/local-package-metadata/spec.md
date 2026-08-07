# local-package-metadata

Locally persisted, machine-local per-package metadata keyed by the `(kind, name)` package identity
the catalog and the inventory already use: a favorite flag, a free-text note, and a version-scoped
snooze — plus the rule by which a snooze suppresses the outdated badge and by which any different
offered version revives it. Owned by `Packages/CellarCore` target `Persistence`.

This capability owns **storage and the badge-suppression rule**. Where favorites compose into the
browse filter bar, and where snoozed packages leave the outdated section and its count, is owned by
`installed-inventory` and referenced here, never restated.

## Requirements

### Requirement: Local metadata is keyed by the identity the app already uses

Locally stored metadata MUST be keyed by the `(kind, name)` package identity already used by the
catalog and the inventory; the capability MUST NOT introduce a second package identity. Metadata MUST
survive an app relaunch. Metadata MUST NOT be deleted because its package stopped being installed: a
favorite, note or snooze recorded for a package MUST still apply if that package is reinstalled
later.

#### Scenario: Metadata survives a relaunch

- GIVEN a favorite, a note and a snooze recorded for the formula `wget`
- WHEN the store is closed and reopened against the same location
- THEN all three are readable for the formula `wget` with the same values

#### Scenario: Kind is part of the key

- GIVEN the formula `docker` is marked favorite and the cask `docker` is not
- WHEN metadata is read for each identity
- THEN the formula reports favorite and the cask does not

#### Scenario: Metadata outlives an uninstall

- GIVEN a note recorded for an installed package
- WHEN that package is no longer present in the inventory, and later present again
- THEN the note is unchanged and still readable for it throughout

### Requirement: Favorite is a local flag with no effect on Homebrew

A package MUST expose a favorite flag that can be toggled on and off. Toggling MUST be idempotent —
setting the same value twice leaves one stored state — and MUST NOT spawn any brew process, submit
any operation, or change installed state in any way. A package with no stored metadata MUST report
"not favorite" rather than an absent or error value.

#### Scenario: The favorite flag round-trips

- GIVEN a package with no stored metadata
- WHEN it is marked favorite, read, unmarked, and read again
- THEN the first read reports favorite and the second reports not favorite

#### Scenario: Toggling favorite spawns nothing

- GIVEN a recording process launcher
- WHEN a package is marked and unmarked favorite
- THEN no brew invocation was recorded
- AND no operation was submitted to the queue

#### Scenario: An unknown package is not favorite

- GIVEN a package for which nothing has ever been stored
- WHEN its favorite flag is read
- THEN it reports not favorite and nothing is thrown

### Requirement: A note is plain text stored verbatim and never searched

A package MUST expose a single free-text note. The note MUST be stored and returned verbatim: no
length cap MUST be imposed, no Markdown or other markup MUST be interpreted or rendered, and
internal whitespace and newlines MUST be preserved exactly. Storing an empty note MUST be equivalent
to having no note. Note contents MUST NOT be matched by the Installed list's search, nor by any
catalog search — searching for a word that appears only in a note MUST NOT surface its package.

#### Scenario: A note round-trips verbatim

- GIVEN the note text "line one\n\n  # not a heading  \nline two"
- WHEN it is stored for a package and read back
- THEN the returned text is byte-identical to the stored text
- AND no markup was interpreted or stripped

#### Scenario: An empty note is no note

- GIVEN a package carrying a note
- WHEN the note is set to the empty string
- THEN the package reports no note

#### Scenario: Search does not match note contents

- GIVEN an installed package named `wget` whose note contains the word `zeppelin`, and no package
  whose name or description contains `zeppelin`
- WHEN the Installed list is searched for `zeppelin`
- THEN no results are returned

### Requirement: A snooze is scoped to a version, never to a duration

Snoozing a package MUST record the exact version the snooze applies to — the version the package is
currently outdated toward — and nothing else. The capability MUST NOT accept, store or require a
duration, an expiry date, or any reading of the clock, so snooze behaviour is reproducible without a
clock seam. Snoozing an already-snoozed package MUST replace the stored version rather than
accumulate a second snooze. Unsnoozing MUST remove the stored snooze entirely.

Snoozing more than one package in a single user action MUST record **one snooze per package, each
naming that package's own currently offered version**. Such an action MUST NOT record a shared
version, MUST NOT reuse one package's offered version for another, and MUST NOT introduce a batch
identity, a group record, or any notion of a snooze that spans packages: the stored result MUST be
indistinguishable from having snoozed each package individually, in any order. A package in the batch
with no offered version to snooze toward MUST record nothing, rather than a placeholder, an empty
string or a neighbour's version. The action MUST NOT compare, order or rank the versions it records.

Copy that offers a snooze — for one package or for many — MUST NOT state or imply a duration, a
period, an expiry, or a "remind me later" interval. It MUST state what the snooze actually does: it
lasts until a different version is offered. A stored snooze's creation timestamp is **provenance
only**: it MUST NOT be read as policy, MUST NOT govern when a snooze ends, and MUST NOT reach any
projection that decides whether a badge is suppressed.
(Previously: the requirement governed snoozing a package and said nothing about snoozing several
packages in one action, nor about the copy that offers a snooze.)

#### Scenario: Snoozing records the version it applies to

- GIVEN an installed package outdated toward published version `1.2.3`
- WHEN it is snoozed
- THEN the stored snooze names version `1.2.3`

#### Scenario: A snooze carries no time component

- GIVEN a stored snooze
- WHEN its stored fields are enumerated
- THEN they carry no duration, no expiry and no timestamp that governs when the snooze ends

#### Scenario: Re-snoozing replaces rather than accumulates

- GIVEN a package snoozed at version `1.2.3` that is now outdated toward `1.3.0`
- WHEN it is snoozed again
- THEN exactly one snooze is stored for it, naming `1.3.0`

#### Scenario: Snoozing many records each package's own version

- GIVEN three outdated packages offered `1.2.3`, `2026-08-01` and `4.0.0_1` respectively
- WHEN all three are snoozed in one action
- THEN three snoozes are stored, naming `1.2.3`, `2026-08-01` and `4.0.0_1` respectively
- AND no shared version, batch identity or group record was stored

#### Scenario: A multi-package snooze is indistinguishable from individual ones

- GIVEN the same three packages
- WHEN they are snoozed in one action, and separately snoozed one at a time in a different order
- THEN the stored snoozes are equal in both cases, field for field apart from provenance

#### Scenario: A package with nothing to snooze toward records nothing

- GIVEN a batch containing one outdated package and one package with no offered version
- WHEN the batch is snoozed
- THEN exactly one snooze is stored, naming the outdated package's version
- AND no placeholder, empty or borrowed version was stored for the other

#### Scenario: The snooze copy implies no duration

- GIVEN every copy that offers a snooze, for one package and for many
- WHEN it is read
- THEN none of it states or implies a duration, a period, an expiry or an interval
- AND each states that the snooze lasts until a different version is offered

### Requirement: A snooze suppresses the outdated badge until the offered version changes

While a package has a stored snooze, the outdated badge for that package MUST be suppressed for
exactly as long as the version currently offered for it **equals** the stored snoozed version,
compared as an exact string. Any different offered value — newer, older, or differing only by a
revision suffix — MUST revive the badge, without user action and without the snooze having to be
cleared manually. The capability MUST NOT order, rank or precedence-compare Homebrew version strings,
and MUST NOT depend on any version comparator: equality is the whole rule. Unsnoozing MUST restore
the badge immediately, on the same refresh. Suppression MUST be a projection over the inventory's
outdated state and the stored snooze: it MUST NOT alter the inventory's own outdated derivation, and
it MUST NOT hide the package from the Installed list.

A strict-SemVer comparator MAY exist elsewhere in the app, confined to `vulnerability-scanning`. It
MUST remain structurally unreachable from this capability: this capability's sources MUST declare no
dependency on the module that owns it, MUST NOT import it, and MUST NOT accept a comparison result,
comparator, ordering closure or "is newer" value from it in any snooze input, stored field or
projection. The absence MUST stay enforced structurally rather than by convention: the existing
structural guard MUST continue to scan this capability's real sources with comments stripped, MUST
continue to assert the same forbidden comparator tokens absent and to carry its positive equality
anchor so the scan cannot pass vacuously, and MUST additionally assert that no import of, or
reference to, the comparator-owning module appears in those sources. The guard's scope narrows from
"no comparator exists in the repository" to "no comparator is reachable from this capability"; it
MUST NOT be deleted, weakened to a comment, or satisfied by an allow-list.

Because that scope is enumerated exhaustively rather than derived from a target boundary, it MUST
cover **every** source that participates in recording or projecting a snooze, including a source
outside this capability's own target — such as a surface that snoozes several packages in one action.
A new snooze caller MUST NOT be able to evade the guarantee by living outside the enumerated list:
adding such a caller MUST either place it in the guard's scope, or route its snoozes only through a
source already in that scope. A caller outside the scope that constructs, compares or orders a version
string itself MUST fail the guard rather than pass it silently.
(Previously: the rule was identical for snooze behaviour, but the no-comparator guarantee was
repository-wide; it is now scoped to this capability's reachability, because `m4-security`
introduces a strict-SemVer comparator inside `vulnerability-scanning`. This revision adds only the
rule that the enumerated scope must follow every snooze caller, including one outside this
capability's target.)

#### Scenario: The badge is suppressed while the offered version is unchanged

- GIVEN a package snoozed at version `1.2.3` and still outdated toward `1.2.3`
- WHEN its badge state is read
- THEN no outdated badge is shown for it

#### Scenario: A newer offered version revives the badge

- GIVEN a package snoozed at version `1.2.3`
- WHEN the offered version becomes `1.3.0` and the inventory refreshes
- THEN the outdated badge is shown again
- AND no user action was required to clear the snooze

#### Scenario: A revision-suffixed or older offered version also revives the badge

- GIVEN a package snoozed at version `1.2.3`
- WHEN the offered version is `1.2.3_1`, and separately an older `1.2.2`
- THEN the outdated badge is shown again in both cases — the accepted, visible false positive of an
  equality rule
- AND no ordering comparison of version strings was performed to reach either result

#### Scenario: Unsnoozing restores the badge immediately

- GIVEN a snoozed package whose badge is suppressed
- WHEN the snooze is removed
- THEN the outdated badge is shown on the next read, with no refresh of the inventory required

#### Scenario: A snoozed package is still listed as installed

- GIVEN a snoozed, outdated package
- WHEN the Installed list is read with default filters
- THEN the package is listed with its installed version

#### Scenario: The security comparator is structurally unreachable from snooze

- GIVEN a strict-SemVer comparator exists in the module owning `vulnerability-scanning`
- WHEN the structural guard scans this capability's sources with comments stripped, and its declared
  dependencies are enumerated
- THEN the forbidden comparator tokens are absent, the positive equality anchor is present, and
  neither an import of nor a reference to the comparator-owning module appears
- AND snooze behaviour is byte-identical to its behaviour before that comparator existed

#### Scenario: A snooze caller outside this capability cannot evade the guard

- GIVEN a surface outside this capability's own target that records snoozes for several packages in
  one action
- WHEN the structural guard's enumerated scope is read
- THEN that surface is either named in the scope, or records its snoozes only through a source that is
- AND the forbidden comparator tokens are absent from every source the scope names

### Requirement: A cold or unavailable metadata store degrades to the pre-existing behaviour

Every projection this capability contributes MUST degrade cleanly. With an empty store, the Installed
list, the outdated set, the outdated count and the browse filters MUST behave exactly as they did
before this capability existed. If the store cannot be opened or read, the app MUST still list the
inventory, MUST NOT throw into the inventory path, and MUST NOT block the main actor waiting for it;
favorites, notes and snoozes are then simply absent.

#### Scenario: An empty store changes nothing

- GIVEN an inventory of installed packages and a store containing no metadata
- WHEN the Installed list, the outdated set and the outdated count are read
- THEN each is identical to the same read performed with no metadata store at all

#### Scenario: An unreadable store does not break the inventory

- GIVEN a metadata store that fails to open
- WHEN the Installed list is read
- THEN it lists the inventory normally, nothing is thrown, and no package reports favorite, note or
  snooze

### Requirement: Metadata is machine-local and survives a schema upgrade

Stored metadata MUST remain on the machine that created it: the capability MUST NOT synchronise,
upload or transmit it, and MUST NOT expose any sync surface. The stored schema MUST be versioned, and
opening a store written by an earlier schema version MUST migrate it without losing previously stored
favorites, notes or snoozes.

#### Scenario: No sync or network surface exists

- GIVEN the capability's stored configuration and its public surface
- WHEN they are enumerated
- THEN neither declares a sync, cloud or remote destination
- AND no network request is made when metadata is read or written

#### Scenario: An earlier schema version migrates without data loss

- GIVEN a store written at schema version 1 holding a favorite, a note and a snooze
- WHEN it is opened by a later schema version that adds new fields
- THEN all three previously stored values are still readable with their original values

## Provenance

- Established by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**,
  slice M2-3 — the last M2 slice), ADDED-only delta — **7 requirements / 21 scenarios**, promoted
  verbatim from
  `openspec/changes/archive/2026-08-03-m2-local-metadata-history/specs/local-package-metadata/spec.md`.
  This is the first main spec for the capability; nothing was modified, removed or renamed. This file
  adds only the header, the `## Requirements` wrapper and this provenance section. **No archive
  reconciliation was needed** — the promoted text is byte-identical to the delta's requirement and
  scenario bodies.
- Binding product decisions settled **before** the delta was written (user-confirmed 2026-08-02,
  Engram `#7111`), stated in it as facts rather than open questions:
  - **Snooze is "until next version" only.** PRD §3.2 also lists 1 day / 1 week / 1 month; those were
    deliberately narrowed out of this slice, so no duration and no clock dependency exists anywhere
    in the capability.
  - **Notes are plain text**, with no length cap and no Markdown rendering, and the Installed list's
    search MUST NOT match note contents.
  - **Favorites are a filter**, not a sidebar section.
- **G5 ruling — revival is version inequality, never version ordering** (user-confirmed 2026-08-03,
  Engram `#7117`). Homebrew version strings (`1.2.3_1`, date-based, tap-specific) cannot be ordered
  reliably, and a comparator bug would *silently suppress a real update*. Plain string inequality
  fails visibly instead: a republished older version revives the badge, an accepted false positive.
  The absence of a comparator is enforced structurally, not by convention —
  `SnoozeProjectionTests > noVersionComparatorExists` reads the real sources with comments stripped,
  asserts nine forbidden tokens absent, and carries the positive anchor
  `#expect(source.contains("snoozedVersion == candidate"))` so the scan cannot pass vacuously. Verify
  independently re-scanned the whole repo (2026-08-03) and confirmed no version comparator exists.
- **`installed-inventory` consumes this rule and must not fork it.** That capability's "Snoozed
  packages leave the outdated section and its count" is written as a consumer of the equality rule
  established here; it MUST NOT introduce a second notion of when a snooze is in effect.
- **Delivery note**: shipped as a `Persistence` SPM target (SwiftData `VersionedSchema` V1 +
  `SchemaMigrationPlan` from day one, three independent `@Model` types with no relationships). The
  target is the **outermost** node in `Packages/CellarCore` — nothing in the package depends back on
  it, and `BrewClient` never links SwiftData — so this capability can be deleted without touching the
  execution or catalog layers.
- **Amended by change `m4-security` (archived `2026-08-06`, PRD milestone **M4** — Security)**:
  **1 MODIFIED** requirement replaced as a whole block — "A snooze suppresses the outdated badge until
  the offered version changes" — adding **1 scenario**. 7 requirements / 21 scenarios → **7
  requirements / 22 scenarios**. Nothing was added, removed or renamed; the other six requirements are
  byte-identical, all five pre-existing snooze scenarios survive unchanged, and the replacement is a
  strict superset of the text it replaced.
  - **Snooze behaviour did not change.** Equality is still the whole rule: exact string comparison, no
    ordering, no clock. What changed is the *scope of the no-comparator guarantee*. `m4-security`
    introduces a strict-SemVer comparator inside `vulnerability-scanning`, so the repository-wide
    absence claim of the G5 ruling above became false. Rather than delete the guarantee, the
    requirement narrows it from "no comparator exists in the repository" to "no comparator is
    reachable from this capability", and states the reachability prohibition explicitly: no dependency
    declaration, no import, and no comparison result, comparator, ordering closure or "is newer" value
    accepted into any snooze input, stored field or projection.
  - **The structural guard was extended, not weakened.** `SnoozeProjectionTests` keeps the
    comment-stripped source scan, the same forbidden comparator tokens, and the positive
    `snoozedVersion == candidate` anchor, and gains an assertion that no import of or reference to the
    comparator-owning module (`SecurityKit`, `StrictSemVer`, `FixVersionComparison`,
    `HomebrewRevision`) appears in this capability's sources. `PackageGraphTests` additionally asserts
    `BrewClient` declares no SecurityKit dependency and cannot reach it transitively.
  - **The rule is file-scoped, not target-scoped**, and the scope is enumerated exhaustively rather
    than by allow-list: `Sources/BrewClient/PackageMetadata.swift`,
    `Sources/BrewClient/InstalledFilterMode.swift`, `Sources/Persistence/MetadataStore.swift`,
    `Sources/Persistence/LocalStores.swift`, `Sources/Persistence/SchemaV1.swift` and
    `Sources/Persistence/SchemaV2.swift`. `Sources/Persistence/DismissalStore.swift` implements
    `vulnerability-scanning`, not this capability, and is excluded — so the guard asserts positively
    that it is the **only** file in `Sources/Persistence/` containing `import SecurityKit`. A second
    import anywhere in that target fails the suite.
  - **`SchemaV2` is additive.** The `Snooze`, `PackageMeta` and `HistoryEntry` models are byte-identical
    to V1; V2 only adds `DismissedCVE`, which belongs to `vulnerability-scanning`. Verified live against
    a real user store (MV-4): history survived the migration. The snooze half of that live check is
    **vacuously satisfied** — the user held zero snoozes pre-migration — and is covered instead by
    `MigrationTests` against real SQLite.
- **Amended by change `m5-health` (archived `2026-08-07`, PRD milestone **M5** "Pro-parity flows",
  slice 5 of 5 — the slice that **closed M5**): 2 MODIFIED requirements, each replaced as a whole
  block that is a **strict superset** of the text it replaced, adding **5 scenarios**. 7
  requirements / 22 scenarios → **7 requirements / 27 scenarios**. Nothing was added, removed or
  renamed; every pre-existing sentence and all 22 pre-existing scenarios survive byte-identically,
  verified by byte-slicing the replaced ranges against the delta. Delta archived at
  `openspec/changes/archive/2026-08-07-m5-health/specs/local-package-metadata/spec.md`.
  - **Snooze behaviour did not change, again.** Equality is still the whole rule: exact string
    comparison, no ordering, no clock, no duration. What changed is that a snooze can now be
    recorded for **several packages in one user action** (decision **D2**, Engram `#7532`).
  - **LPM4 answers "whose version does each row record?" — its own.** N packages are outdated toward
    N *different* version strings, so a batch that shared one version would mis-scope N−1 snoozes
    and suppress badges for versions those packages were never outdated toward. The requirement now
    forbids a shared version, a reused neighbour's version, and any batch identity or group record:
    the stored result MUST be indistinguishable from individual snoozes in any order, and a package
    with no offered version records **nothing** rather than a placeholder. It also promotes the copy
    rule to requirement level — "snooze" is the one verb in the app whose ordinary English meaning
    is a duration and whose implementation deliberately is not — and pins `createdAt` as provenance
    only, never reaching a suppression projection.
  - **LPM5 closes a vacuous-pass gap the bulk surface would otherwise have opened.** The
    no-comparator guard is deliberately **file-scoped and enumerated exhaustively** rather than
    target-scoped, so a bulk-snooze surface living outside this capability's target would have been
    a new snooze caller the enumerated list did not name — the guarantee would have held vacuously
    for it. The requirement now compels the enumerated scope to follow **every** snooze caller,
    including one outside the target: such a caller must either be placed in scope or route only
    through an in-scope source, and one that constructs, compares or orders a version itself must
    **fail** the guard rather than pass silently. The guard was **extended, not weakened**: the
    comment-stripped source scan, the forbidden comparator tokens and the positive
    `snoozedVersion == candidate` anchor all stay. In apply this was discharged by re-rooting
    `SnoozeGuardTests.source(at:)` from `Packages/CellarCore` to the repository root so it can open
    `cellar/Installed/BulkActionBar.swift`, keeping the per-file anchor so a read-nothing scan
    fails.
  - The `(Previously: …)` annotation on LPM5 is the one line in either block that was rewritten
    rather than appended to: it gained a closing sentence recording this revision. It is a
    provenance annotation, not normative text, so both blocks remain strict supersets of everything
    normative they replaced.
