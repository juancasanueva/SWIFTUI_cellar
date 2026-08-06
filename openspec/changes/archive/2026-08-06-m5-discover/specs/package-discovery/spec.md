# Delta for package-discovery

New capability — there is no `openspec/specs/package-discovery/spec.md` yet, so this delta is
**ADDED-only**: **6 requirements / 23 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED.

This capability owns what Discover *shows*: the two ranked ladders, the curated list and its counted
skips, the "new to you" projection, and the typed per-section states that make "Discover never opens
empty" checkable. It owns none of the durable state those projections read — the known-package roster
and the dated arrivals log are persisted by `catalog-sync` and specified in that delta. Every
requirement here is behaviour of `CellarCore` values; no SwiftUI view is specified anywhere in this
file.

Traceability: **D1** → "The curated list ships with the build" and "A curated entry that no longer
resolves"; **D2** → "New to you means first observed by this machine, within 30 days"; **D3** → "Two
separate ladders, fifty deep, absent is not zero"; **D4** is a shell/navigation decision with no
CellarCore behaviour and is carried by `tasks`, not by a requirement here; **D5** → "Every section
reports a typed state, and Discover never opens empty".

## ADDED Requirements

### Requirement: Two separate ladders, fifty deep, absent is not zero

Ranked projections MUST be produced per package kind and MUST NOT be merged into one ladder:
formulae rank by their `installsOnRequest` metric and casks by their `installs` metric, and the two
counts MUST NOT be compared with each other. Each ladder MUST contain at most 50 entries, ordered by
descending install count.

A package whose install count is absent MUST be ineligible for its ladder — it MUST NOT be ranked
last, and its count MUST NOT be substituted with `0`. A package that is deprecated or disabled MUST
be ineligible for either ladder. A ladder with fewer than 50 eligible packages MUST be shorter than
50 and MUST NOT be padded with ineligible entries.

The ordering MUST be a deterministic total order: two packages with equal counts MUST be ordered by a
stable secondary key, so the same snapshot always yields byte-identical ladders. Ranking MUST read
only the snapshot it is given, including counts that snapshot carried forward from an earlier sync.

#### Scenario: Formulae and casks rank on separate ladders

- GIVEN a snapshot whose highest-counted cask outranks every formula
- WHEN the ranked projections are produced
- THEN the formula ladder contains only formulae and the cask ladder contains only casks
- AND no entry from one ladder appears in the other

#### Scenario: A package with no analytics entry is absent, not last

- GIVEN a snapshot containing formula `obscure` whose install count is absent
- WHEN the formula ladder is produced
- THEN `obscure` appears nowhere in the ladder
- AND no entry in the ladder reports a count of `0` derived from an absent count

#### Scenario: Deprecated and disabled packages are ineligible

- GIVEN a snapshot in which the two highest-counted formulae are respectively deprecated and disabled
- WHEN the formula ladder is produced
- THEN neither appears, and the ladder starts at the highest-counted formula that is neither

#### Scenario: A short catalog yields a short ladder

- GIVEN a snapshot holding exactly 7 eligible casks
- WHEN the cask ladder is produced
- THEN it holds exactly 7 entries and nothing was padded to reach 50

#### Scenario: Equal counts order deterministically

- GIVEN a snapshot with three formulae carrying the same install count
- WHEN the formula ladder is produced twice from that same snapshot
- THEN both runs return the same entries in the same order

#### Scenario: Carried-forward counts still rank

- GIVEN a snapshot published by a sync whose payloads revalidated as unchanged, carrying the install
  counts of the previous snapshot
- WHEN both ladders are produced
- THEN they rank on those carried-forward counts and are non-empty

### Requirement: Discover costs no new acquisition

Every value this capability projects MUST be derived from the snapshot the catalog has already
adopted, from resources shipped inside the application bundle, and from the durable state
`catalog-sync` already persists. Producing any Discover projection MUST NOT issue a network request,
MUST NOT spawn a `brew` process, and MUST NOT trigger a sync as a consequence of a section being
rendered.

#### Scenario: Opening Discover issues no request

- GIVEN a fake `CatalogSource` that records each request and an adopted snapshot
- WHEN every Discover projection is produced
- THEN the recorder saw no request at all

#### Scenario: Discover resolves offline and without brew

- GIVEN brew detection reporting `absent`, a source that fails every request, and an adopted snapshot
- WHEN every Discover projection is produced
- THEN each one resolves from the snapshot and the shipped resources
- AND no brew process was spawned

### Requirement: The curated list ships with the build and decodes tolerantly

The curated list MUST be readable from a resource shipped inside the built application through the
accessor the shipping code uses, with the network unreachable; it MUST NOT be fetched or refreshed
remotely. An entry MUST carry all three of a package token (kind and name), a category, and a blurb;
an entry missing any of the three MUST be skipped and counted rather than rendered with a substituted
value. A blurb MUST come from the resource and MUST NOT fall back to the package's own `desc`.

Decoding MUST be tolerant in the same sense the catalog decoder is: keys the decoder does not model
MUST be ignored rather than failing, and one unusable entry MUST NOT fail the list. A token declared
more than once MUST resolve to at most one entry — the first declaration wins — and each redundant
declaration MUST be counted rather than silently dropped. Category order and within-category entry
order MUST be the order the resource declares, never re-sorted.

The shipped list MUST declare at least 3 and at most 5 categories and at least 20 and at most 30
entries, and that MUST be asserted by an automated test over the shipped resource rather than stated
as a comment.

#### Scenario: The shipped resource loads through the shipping accessor

- GIVEN the built product and no network
- WHEN the curated list is loaded through the accessor the app uses
- THEN it decodes, and its category count and entry count are within the declared bounds

#### Scenario: Unknown fields and malformed entries are tolerated

- GIVEN a curated resource whose entries carry keys the decoder does not model, and one entry with no
  blurb
- WHEN it is decoded
- THEN the unknown keys are discarded, the blurb-less entry is skipped and counted, and every other
  entry decodes

#### Scenario: A duplicate token resolves once

- GIVEN a curated resource declaring token `ripgrep` in two categories
- WHEN it is decoded
- THEN `ripgrep` appears exactly once, in the category that declared it first
- AND the redundant declaration is counted

#### Scenario: Declared order survives decoding

- GIVEN a curated resource whose categories and entries are not in alphabetical order
- WHEN it is decoded
- THEN categories and entries are exposed in the order the resource declared them

### Requirement: A curated entry that no longer resolves is skipped and counted

Each curated entry MUST be resolved against the adopted snapshot by `(kind, name)`. An entry whose
token is not in the snapshot MUST be skipped, MUST be counted, and MUST NOT be exposed as a
renderable row of any kind. The count MUST be `0` rather than absent when every entry resolved, and
MUST be distinct from the snapshot's own skipped-record count. A category whose every entry was
skipped MUST be absent from the resolved list rather than exposed as an empty category.

#### Scenario: A removed token never becomes a dead row

- GIVEN a curated resource naming formula `gone`, and a snapshot that does not contain `gone`
- WHEN the curated list is resolved
- THEN no entry for `gone` is exposed and the skipped count is `1`

#### Scenario: A fully resolving list counts zero skips

- GIVEN a curated resource whose every token is present in the snapshot
- WHEN the curated list is resolved
- THEN every entry is exposed and the skipped count is `0`, not absent

#### Scenario: A category emptied by skips disappears

- GIVEN a category whose every token is absent from the snapshot
- WHEN the curated list is resolved
- THEN that category is absent from the result, and the other categories are unaffected

#### Scenario: Curated skips are their own count

- GIVEN a snapshot reporting 3 skipped records and a curated resource with 2 unresolvable tokens
- WHEN the curated list is resolved
- THEN the curated skip count is `2` and the snapshot's skipped-record count is still `3`

### Requirement: New to you means first observed by this machine, within 30 days

The arrivals projection MUST expose exactly those packages whose first observation **by this
installation** falls within the last 30 days, measured from the dated arrivals log `catalog-sync`
persists. It MUST NOT be derived from any publication, release or version date, and the projection
MUST NOT expose any field that presents the date as such. Each entry MUST carry its first-observed
date so a consumer can state the claim honestly, and entries MUST be ordered newest first.

The honest phrasing is a requirement of this capability, not a UI note: the explanatory text
accompanying the projection MUST be supplied by `CellarCore`, MUST describe the value as first seen
by this Mac, and MUST NOT assert that a package is new to Homebrew or newly released. An arrivals
entry naming a package absent from the adopted snapshot MUST NOT be projected.

#### Scenario: A package first seen inside the window is listed with its date

- GIVEN an arrivals log recording formula `newpkg` first observed 3 days ago, and a snapshot
  containing `newpkg`
- WHEN the arrivals projection is produced
- THEN it contains `newpkg` carrying a first-observed date of 3 days ago

#### Scenario: An entry beyond the window is not projected

- GIVEN an arrivals log recording formula `oldarrival` first observed 31 days ago
- WHEN the arrivals projection is produced
- THEN `oldarrival` is absent from it

#### Scenario: A package that left the catalog is not projected

- GIVEN an arrivals log entry from 5 days ago naming a package the current snapshot no longer contains
- WHEN the arrivals projection is produced
- THEN that entry is absent and nothing is thrown

#### Scenario: The shipped explanation claims first observation, not publication

- GIVEN the explanatory text this capability supplies for the arrivals section, populated and empty
- WHEN it is inspected
- THEN it describes the packages as first seen by this Mac
- AND it contains no claim that a package was newly released or is new to Homebrew

### Requirement: Every section reports a typed state, and Discover never opens empty

Each Discover section's availability MUST be exposed as a typed value that distinguishes a populated
result from an empty one *and names why it is empty*. An empty section MUST NOT be represented as an
empty collection paired with an empty string, nor as a failure, nor as a pending/loading state when
the catalog is in fact available.

When a usable snapshot has been adopted, the arrivals section is the only section that MAY report
empty for the ordinary reason that nothing has arrived yet, and that state MUST carry the distinct
"newness is measured from this sync onward" identity. The ranked and curated sections MUST be
populated whenever their eligible input exists; if either is nonetheless empty, it MUST report its
own named reason (no eligible ranked package; every curated entry unresolvable) together with its
count. The projection MUST NOT produce a result in which every section is empty and none of them
explains itself.

When no usable snapshot has been adopted, every section MUST report the ordinary awaiting-catalog
state, which MUST NOT be reported as an error.

#### Scenario: First run explains the empty arrivals section and still shows the rest

- GIVEN a first successful sync, so the arrivals log is empty and a full snapshot is adopted
- WHEN the Discover projections are produced
- THEN the arrivals section reports the empty "measured from this sync onward" state, not a failure or
  a pending state
- AND both ladders and the curated list are populated

#### Scenario: An empty section names its reason rather than blanking

- GIVEN a snapshot in which every package's install count is absent
- WHEN the ranked sections are produced
- THEN each reports the empty "no eligible ranked package" state with a count of `0`
- AND the curated section is still populated, so at least one section carries content

#### Scenario: No usable catalog is awaiting, not failed

- GIVEN no adopted snapshot
- WHEN the Discover projections are produced
- THEN every section reports the awaiting-catalog state, nothing is thrown, and no section reports a
  failure
