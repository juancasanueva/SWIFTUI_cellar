# disk-usage

Owned by `Packages/CellarCore` capability `DiskUsage`; excludes mutation and installed inventory.

## Requirements

### Requirement: Validated roots are independent

The system MUST scan only validated standard or custom roots. Missing Cellar, Caskroom, or cache
roots MUST be independent empty areas.

#### Scenario: Validated roots remain independent
- GIVEN validated standard or custom roots with any subset absent
- WHEN scanning completes
- THEN only present roots are measured and absent areas are empty

#### Scenario: Brew is unavailable
- GIVEN Homebrew is absent or invalid
- WHEN disk usage is opened
- THEN no scan runs and installation guidance is shown

### Requirement: Accounting is allocated and link-safe

“On disk” allocated bytes MUST lead; logical size MAY appear secondarily. Measurement MUST
use metadata only, MUST NOT follow symlinks/aliases, and MUST deduplicate hard links per root.

#### Scenario: Accounting remains safe and honest
- GIVEN files, hard links, cross-root symlinks, and shared APFS blocks
- WHEN measurement and presentation complete
- THEN contents remain unread, hard links count once, symlinks remain unfollowed, and no reclaimable/exclusive claim appears

### Requirement: Package and version attribution is exact

Immediate Cellar/Caskroom children MUST identify formulae/casks; the next component MUST identify
unparsed versions. Formula state MUST preserve exact linked/unlinked state.

#### Scenario: Attribution is exact
- GIVEN formula/cask trees and present or absent linked-keg state
- WHEN attribution completes
- THEN kind, package, version, and linked/unlinked values match their sources

### Requirement: Presentation is package-first and stable

Expandable package rows MUST lead to versions; cache MUST be separate. Identity MUST be stable.
Default order MUST be bytes descending, then kind, package, and version ascending.

#### Scenario: Incremental rows remain deterministic
- GIVEN a selected package while tied or earlier-sorting rows arrive
- WHEN results are adopted and the package expands
- THEN ordering repeats, selection keeps its identity, and that package’s versions appear

### Requirement: Cache is stale while revalidating

Complete cache MUST appear immediately as stale while revalidating. Snapshots MUST identify version
and roots. Complete matching current revalidation MUST atomically replace visible/persisted data;
other generations MUST NOT.

#### Scenario: Cache adoption is complete and atomic
- GIVEN a valid complete cache and mismatched, cancelled, partial, or older candidates
- WHEN the surface opens and candidates seek adoption
- THEN valid data appear stale with incremental revalidation, while invalid candidates replace nothing

### Requirement: Work is cancellable, current, and responsive

The system MUST offer cancellation, reject stale results, and remain responsive. Progress MUST be
monotonic and bounded by package/version units, never inode events.

#### Scenario: Cancellation stays responsive
- GIVEN scanning pauses, then is cancelled or superseded
- WHEN interaction, progress, and late results are observed
- THEN interaction completes, progress stays unit-bounded, late results are ignored, and accepted data remain

### Requirement: Partial errors preserve trustworthy data

Unreadable/disappearing entries MUST show scoped warnings. Completed results MUST remain; failed areas MUST retain
last-good data when available, never fabricated zeroes.

#### Scenario: Failure and recovery are explicit
- GIVEN one area succeeds while another is unreadable or disappears
- WHEN that scan settles and a later scan succeeds
- THEN trustworthy/last-good data remain warned, then fresh data replace them and clear the warning

### Requirement: Invalidation is scoped

Root changes MUST invalidate only their disk areas. Relevant mutation terminals MUST invalidate disk
usage. Disk invalidation MUST NOT itself request installed refresh.

#### Scenario: Invalidation stays scoped
- GIVEN independent root changes and relevant mutation terminals
- WHEN each invalidation occurs
- THEN affected disk areas revalidate without installed refresh unless its own scope requires one

### Requirement: Visibility does not become cleanup

The system MUST NOT offer cleanup actions, recommendations, dry-run interpretation, or reclaimable
claims. Installed MUST NOT add size columns.

#### Scenario: Storage remains read-only
- GIVEN disk usage and Installed
- WHEN controls, claims, and columns are enumerated
- THEN disk usage is storage-only and Installed has no size column
