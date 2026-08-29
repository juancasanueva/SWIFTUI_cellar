# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (**16 requirements / 82 scenarios**).
This delta is **3 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is untouched and
byte-identical. The capability becomes **19 requirements / 93 scenarios**.

Why ADDED only: "The installed snapshot comes from one probe" counts **brew** invocations, and npm
acquisition is not a brew invocation, so it stays true. "Every surface that announces the outdated count
derives it from one snooze-aware projection" already binds npm entries the moment they enter the same
inventory, which is the point of hybrid approach C.

## ADDED Requirements

### Requirement: npm globals enter the one inventory under identity `(npm, name)`

When the npm source is enabled and detected, the installed inventory MUST contain one entry per npm
global package under the existing `PackageID` identity with kind `npm`, alongside brew entries, with no
second inventory type and no app-level union. Each npm entry MUST report its installed version, installed
on request, unpinned, no tap, no auto-updates declaration and no keg. Favorites, notes, snooze and
history MUST key on that identity through the existing `kindRaw` string `npm` with **no persistence
migration**; a build without the npm kind MUST decode such rows as absent rather than fail. The catalog
join MUST treat kind `npm` as never present in the catalog, so an npm entry is always listed with its
snapshot data alone. The dependency toggle MUST be a no-op for npm entries. A brew acquisition failure
MUST NOT drop npm entries and vice versa: each source's entries are replaced only by that source's next
successful acquisition.

#### Scenario: A merged inventory lists both sources under one identity type

- GIVEN a brew snapshot with formula `wget` and an npm listing with `typescript`
- WHEN the inventory is read with default filters
- THEN both are listed, `typescript` as `(npm, typescript)` with installed on request true and no tap
- AND exactly one brew invocation and one npm `ls -g` invocation were recorded
- Verification: `unit`

#### Scenario: npm identity round-trips through metadata and history without migration

- GIVEN a favorite, a snooze and a history entry stored for `(npm, typescript)`
- WHEN the stores are closed and reopened
- THEN each is read back with kind `npm`, and the schema version is unchanged
- Verification: `unit`

#### Scenario: Toggle off or npm absent leaves the inventory brew-only

- GIVEN a brew snapshot and, in turn, the npm source off and npm `absent`
- WHEN the inventory is read
- THEN it holds exactly the brew entries and no npm invocation was recorded
- Verification: `unit`

#### Scenario: One source's failure does not evict the other

- GIVEN a populated merged inventory
- WHEN the next npm acquisition fails and the next brew acquisition succeeds
- THEN the brew entries reflect the new snapshot and the npm entries are unchanged
- Verification: `unit`

### Requirement: The Source filter and the npm tag are `CellarCore` projections gated on availability

The installed filter model MUST gain a source dimension — all, Homebrew, npm — composed by intersecting
results with membership by `PackageID.kind`, combinable with the kind, dependency, favorites and lens
filters. The source control MUST be reported unavailable, with a typed reason (`disabled`, `absent`,
`invalid`), whenever the npm source is off or not detected, and MUST NOT alter results while unavailable.
Each entry MUST expose a tag projection naming its source so a row can present `NPM` beside the existing
cask tag from the same projection; the tag MUST derive from `kind` and nowhere else.

#### Scenario: The npm source filter narrows to npm entries

- GIVEN a merged inventory of `wget`, `iterm2` and `typescript`
- WHEN the source filter is set to npm, then to Homebrew
- THEN only `typescript` remains, then only `wget` and `iterm2`
- Verification: `unit`

#### Scenario: The source control is unavailable with a reason when npm is off

- GIVEN the npm source off, and separately npm `absent`
- WHEN the filter availability is read and a query runs
- THEN the source control reports unavailable with `disabled`, then `absent`
- AND the results equal the same query with no source filtering
- Verification: `unit`

#### Scenario: The tag projection follows kind

- GIVEN entries of kind formula, cask and npm
- WHEN each entry's tag is read
- THEN only the cask carries the cask tag and only the npm entry carries the `NPM` tag
- Verification: `unit`

### Requirement: The updates summary is per source, and an unchecked npm never reads as up to date

The capability MUST expose an updates summary value, pure over the inventory, the metadata lookup and
the npm outdated freshness state, reporting per source: the outdated count from
`InstalledBrowse.outdatedCount(metadata:)` restricted to that source, and for npm the freshness state
(`fresh`, `notChecked`, `failed`). When brew has nothing outdated and npm is `notChecked` or `failed`,
the summary MUST NOT report "up to date"; it MUST report brew up to date and npm not checked, naming
the failure reason when there is one. When the npm source is off or undetected the summary MUST omit
npm entirely rather than report it as checked, unchecked or zero. The total announced by any surface
MUST still equal `InstalledBrowse.outdatedCount(metadata:)` over the merged inventory.

#### Scenario: Brew clean and npm offline is not up to date

- GIVEN no outdated brew package and an npm freshness of `failed(network)`
- WHEN the summary is read
- THEN brew reports 0 outdated, npm reports not checked with the network reason
- AND the summary's overall state is not "up to date"
- Verification: `unit`

#### Scenario: Both fresh and both clean is up to date

- GIVEN no outdated brew package and an npm freshness of `fresh` with none outdated
- WHEN the summary is read
- THEN the overall state is up to date and the total is 0
- Verification: `unit`

#### Scenario: npm off omits npm from the summary

- GIVEN the npm source off and two outdated brew packages
- WHEN the summary is read
- THEN it carries a brew count of 2, no npm component at all, and a total of 2 equal to the projection
- Verification: `unit`

#### Scenario: A snoozed npm package leaves the npm count

- GIVEN `typescript` outdated toward `5.7.0` and snoozed at `5.7.0`, and `corepack` outdated toward `0.31.0`
- WHEN the summary and the outdated set are read
- THEN the npm count is 1 and only `corepack` is in the set
- Verification: `unit`
