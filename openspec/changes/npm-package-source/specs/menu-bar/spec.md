# Delta for menu-bar

Existing capability — `openspec/specs/menu-bar/spec.md` (**10 requirements / 25 scenarios**). This delta
is **1 ADDED, 1 modified, 0 removed, 0 renamed**. MB1 is replaced as a whole block, a strict superset:
it gains a fourth pure input (the npm freshness state) and lifts the "no freshness cue in this slice"
clause for npm only. MB2–MB10 are byte-identical; MB4's bare `brew upgrade` and no-fan-out rule is
deliberately kept. The capability becomes **11 requirements / 29 scenarios**.

## ADDED Requirements

### Requirement: The status item counts both sources and says when npm was not checked

The count MUST include npm entries exactly as the delegated projection reports them, so the status
item and the Updates lens cannot disagree. The projection MUST expose the per-source updates summary
`installed-inventory` defines; when npm is `notChecked` or `failed`, the popover MUST carry the copy
`npm not checked` (with the reason when known) and MUST NOT present "up to date". When npm outdated
entries exist, the popover MUST state beside `Upgrade all` that npm packages update from the Updates
list, because that affordance submits bare `brew upgrade` and nothing else. When the npm source is off
or undetected, no npm copy MUST appear and the surface MUST be byte-identical to the shipped one.

#### Scenario: npm outdated entries reach the count and the entries

- GIVEN two outdated brew packages and one outdated npm package, all fresh and unsnoozed
- WHEN the projection is read
- THEN the title is `3` and the npm package is among the entries in name order
- Verification: `unit`

#### Scenario: Offline npm is stated, not hidden

- GIVEN no outdated brew package and npm `failed(network)`
- WHEN the projection is read
- THEN the title is absent, the copy carries `npm not checked`, and no "up to date" copy is produced
- Verification: `unit`

#### Scenario: npm off leaves the surface unchanged

- GIVEN the npm source off
- WHEN the projection is read
- THEN it carries no npm component and equals the shipped projection over the same brew inputs
- Verification: `unit`

## MODIFIED Requirements

### Requirement: The menu-bar projection is a pure value that delegates outdated-ness rather than recomputing it

The value the menu-bar surface reads MUST be a `nonisolated`, `Sendable` value **totally derived** from
four inputs — an installed browse projection, the metadata lookup that owns snoozes, a services
snapshot, and the npm outdated freshness state. It MUST perform no I/O, cause no brew or npm
invocation, start or schedule no refresh, consult no catalog value, and take no process launcher, URL
session or store as a dependency: there MUST be nothing of that kind to inject into it.

Its outdated count MUST equal `InstalledBrowse.outdatedCount(metadata:)` for the same inputs, and the
outdated set it exposes MUST be exactly `InstalledBrowse.outdatedIDs(metadata:)` for the same inputs.
It MUST obtain both by **delegating** to that projection. It MUST NOT re-derive outdated-ness by
filtering the installed packages, by reading `InstalledPackage.isOutdated`, by reading the snapshot's
own outdated flag, or by reading `InstalledInventory.outdatedIDs`/`outdatedCount` without the snooze
exclusion. A reimplementation that happened to agree would still violate this requirement: agreement
must be structural, not coincidental — this is the `upgradableIDs` idiom that exists because a label
and a submission once computed one number twice.

An unavailable or empty inventory MUST yield a count of zero, no entries and no remainder, and MUST NOT
throw, present an error, or be distinguishable from a healthy inventory with nothing outdated. The only
freshness cue this capability carries is the npm one stated above; brew freshness remains uncued.
(Previously: three inputs, and no freshness cue of any kind.)

#### Scenario: The count equals the snooze-aware projection under a snooze

- GIVEN an inventory with two outdated formulae, one snoozed at the version it is outdated toward, and
  the metadata lookup that records the snooze
- WHEN the projection's outdated count and outdated set are read
- THEN the count is 1 and the set contains only the non-snoozed formula
- AND both equal `InstalledBrowse.outdatedCount(metadata:)` and `InstalledBrowse.outdatedIDs(metadata:)`
  for the same inputs
- Verification: `unit`

#### Scenario: A self-updating cask is excluded without this capability deciding so

- GIVEN an inventory whose snapshot reports an outdated self-updating cask and one outdated formula
- WHEN the projection's count and set are read
- THEN the count is 1 and the cask is absent from the set
- AND the exclusion came from the delegated projection, with no auto-update rule stated here
- Verification: `unit`

#### Scenario: An unavailable or empty inventory is an ordinary zero

- GIVEN an inventory that is empty, and separately one that is unavailable because brew is absent
- WHEN the projection is composed over each
- THEN each yields a count of zero, no entries and no remainder
- AND nothing is thrown and neither presents an error state
- Verification: `unit`

#### Scenario: The projection has no effectful dependency to inject

- GIVEN the projection's initializer and every input it takes
- WHEN its inputs are enumerated and it is composed twice over identical inputs
- THEN no input is a process launcher, a URL session, a store refresh or a clock
- AND the two compositions are equal, so the value is pure over its inputs
- Verification: `unit`

#### Scenario: The npm freshness input is a value, not a store

- GIVEN the projection composed over an npm freshness of `notChecked`, and again over `fresh`
- WHEN both are composed with no store, launcher or clock available
- THEN both compose, and only the first carries the `npm not checked` copy
- Verification: `unit`
