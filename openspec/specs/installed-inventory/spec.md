# installed-inventory

Acquiring the installed-package snapshot from a single `brew info --installed --json=v2` probe,
projecting and decoding it off the main actor, deriving outdated / pinned / on-request state,
classifying self-updating casks, joining the snapshot to the catalog, composing installed-state
filters for browse, keeping the inventory fresh under external change, and behaving correctly when
brew is absent. Owned by `Packages/CellarCore` target `BrewClient` — the only target that sees both
`BrewProcess` and `Catalog`, one-directionally.

## Requirements

### Requirement: The installed snapshot comes from one probe, decoded off the main actor

An installed-inventory refresh MUST acquire its data from exactly one `brew info --installed
--json=v2` invocation. Outdated state, pin state, on-request state, install timestamps and the
current published version MUST be derived from that single payload; the system MUST NOT spawn a
second brew invocation (in particular `brew outdated`, `brew outdated --greedy`, or
`brew list --pinned`) to answer them. Decoding MUST run off the main actor and MUST project the
payload down to the fields the inventory uses, so the main actor stays responsive while a snapshot
of realistic size (approximately 160 records today, several hundred in the worst case) is decoded.

#### Scenario: One invocation per refresh

- GIVEN a fake process launcher recording every invocation
- WHEN one inventory refresh completes
- THEN exactly one brew invocation was recorded
- AND its arguments are `info --installed --json=v2`

#### Scenario: Derived facts require no extra invocation

- GIVEN a snapshot payload carrying outdated, pinned and on-request records
- WHEN outdated, pinned and dependency-only state are read from the inventory
- THEN they are all answered
- AND still exactly one brew invocation was recorded

#### Scenario: The main actor stays responsive during decode

- GIVEN a payload of realistic size
- WHEN it is decoded into the inventory projection
- THEN other main-actor work submitted after the decode starts runs to completion before the decode
  finishes

### Requirement: Asymmetric formula and cask installation shapes both decode

Decoding MUST accept the payload's asymmetric shapes: a formula's installed data is an array of keg
records, and a cask's installed data is a plain version string. A formula with more than one
installed keg MUST be represented with all of its kegs, never truncated to one and never dropped. A
cask's `auto_updates` field is tri-state (`true`, `null`, absent, never `false` in observed
payloads) and MUST be preserved as "declared" versus "not declared" at decode time rather than
folded into a plain boolean. A formula's optional linked-keg value MUST be preserved exactly: a
present value identifies the linked version, while absence means unlinked and MUST NOT be replaced
with the newest installed keg. This observable state MUST remain available for disk attribution.

A record's **tap is optional on exactly the same terms**. Homebrew reports `tap: null` for a package
whose tap it withholds — the tap exists but is untrusted, so brew declines to name it. That absence
MUST be preserved as absence: it MUST NOT be collapsed into the empty string, into a placeholder, or
into any other sentinel value, because "brew reported no tap" and "the tap is the empty string" are two
different facts and no single value may stand for both. A record whose tap is absent MUST still decode
and MUST still appear in the inventory; only the tap is unknown, and no other field is affected.

An absent tap MUST NOT compare equal to any tap name. Every consumer that matches a package against a
selected tap MUST treat absence as "no answer" rather than as a match or as an empty-string match, so a
withheld tap can never be silently attributed to a tap that did not publish it. What a consumer *shows*
for an absent tap belongs to that consumer — `tap-management` TM5 owns the tap-inventory reading — but
this capability MUST make the distinction available rather than resolving it at decode time.
(Previously: decoding preserved every installed keg but collapsed an absent linked-keg value to the
newest keg, losing the distinction between linked and unlinked formulae; and a null `tap` was collapsed
into the empty string, losing the distinction between a withheld tap and an unset one.)

#### Scenario: A single-keg formula decodes

- GIVEN a formula record whose installed array holds one keg
- WHEN the payload is decoded
- THEN the formula appears in the inventory with that keg's version and install time
- Verification: `unit`

#### Scenario: A multi-keg formula keeps every keg

- GIVEN a formula record whose installed array holds two kegs with different versions
- WHEN the payload is decoded
- THEN the formula appears once with both installed versions represented
- AND neither keg is dropped
- Verification: `unit`

#### Scenario: A cask's string installed version decodes

- GIVEN a cask record whose installed field is the string `1.2.3`
- WHEN the payload is decoded
- THEN the cask appears in the inventory with installed version `1.2.3`
- Verification: `unit`

#### Scenario: An undeclared auto-update flag is distinguishable from a declared one

- GIVEN one cask record with `auto_updates` true and one with `auto_updates` null
- WHEN both are decoded
- THEN the first is classified as self-updating and the second is not
- AND the null value is recorded as "not declared", not as an explicit false
- Verification: `unit`

#### Scenario: Linked-keg absence remains unlinked

- GIVEN a multi-keg formula with no linked-keg value, and another naming its older keg
- WHEN both are decoded for disk attribution
- THEN the first is unlinked and the second names that older keg as linked
- AND neither is inferred from the newest installed keg
- Verification: `unit`

#### Scenario: A withheld tap decodes as absent, not as empty

- GIVEN formula and cask records whose `tap` is in turn `null`, absent, and `"acme/tools"`
- WHEN each is decoded
- THEN the first two report no tap and the third reports `acme/tools`
- AND neither of the first two reports the empty string or any other placeholder
- Verification: `unit`

#### Scenario: A record with a withheld tap still enters the inventory

- GIVEN an installed cask record with a valid version and `tap: null`
- WHEN the payload is decoded
- THEN that cask appears in the inventory with its version, kind and install data intact
- AND only its tap is unknown
- Verification: `unit`

#### Scenario: An absent tap never matches a selected tap

- GIVEN an inventory holding one package with no tap and one with tap `acme/tools`
- WHEN each is matched against the selected tap `acme/tools`, and separately against the empty string
- THEN only the second matches `acme/tools`
- AND the first matches neither
- Verification: `unit`

### Requirement: On-request and dependency-only are derived, and the default view is on-request

The payload carries no `installed_as_dependency` field. "Installed as a dependency" MUST therefore
be derived as the absence of an on-request marker on the installed record. The default installed
view MUST show on-request packages only; dependency-only packages MUST be shown only when the
dependency toggle is on. A record that carries no on-request signal at all MUST be treated as
on-request, so nothing a user deliberately installed can be hidden by the default view.

#### Scenario: The default view hides dependency-only formulae

- GIVEN an inventory of one on-request formula and one dependency-only formula
- WHEN the installed list is read with default filters
- THEN only the on-request formula is listed

#### Scenario: The toggle reveals dependency-only formulae

- GIVEN the same inventory
- WHEN the dependency toggle is on
- THEN both formulae are listed
- AND each exposes whether it was installed on request

#### Scenario: A record with no on-request signal is treated as on-request

- GIVEN an installed cask, whose records carry no on-request marker
- WHEN the installed list is read with default filters
- THEN the cask is listed

### Requirement: Auto-updating casks never count as outdated

Outdated state MUST be taken from the snapshot's own outdated flag, which already applies brew's
default auto-updates exclusion. A cask classified as self-updating MUST NOT be reported as outdated,
MUST NOT contribute to any outdated count or badge, and MUST be presented separately from the
ordinary outdated set — even when a newer version exists for it. A cask that is not self-updating
MUST be reported as outdated on exactly the same terms as a formula.

#### Scenario: An outdated formula is reported and counted

- GIVEN an installed formula whose snapshot record is outdated
- WHEN the outdated set is read
- THEN the formula is in it and the outdated count includes it

#### Scenario: A self-updating cask behind its published version is never outdated

- GIVEN an installed cask declaring auto-updates, installed `1.2.3`, published version `1.3.1`,
  whose snapshot outdated flag is false
- WHEN the outdated set and the outdated count are read
- THEN the cask is absent from the set
- AND the count does not include it
- AND the cask is classified as self-updating

#### Scenario: A cask without auto-updates is outdated on the same terms as a formula

- GIVEN an installed cask that does not declare auto-updates and whose snapshot record is outdated
- WHEN the outdated set is read
- THEN the cask is in it and the outdated count includes it

### Requirement: A self-updating cask's newer version is derived from the same probe

For a cask classified as self-updating, the inventory MUST expose whether a newer version exists,
derived from the same single payload by comparing the installed version against the published
version on that record. Producing this signal MUST NOT spawn any additional brew invocation. The
signal MUST remain informational: it MUST NOT feed the outdated set, the outdated count, or an
outdated badge.

#### Scenario: The newer-version signal is derived without a second invocation

- GIVEN a self-updating cask with installed `1.2.3` and published version `1.3.1`
- WHEN the inventory is refreshed and the cask is inspected
- THEN it reports that a newer version exists
- AND exactly one brew invocation was recorded

#### Scenario: Matching versions produce no signal

- GIVEN a self-updating cask with installed `1.3.1` and published version `1.3.1`
- WHEN the cask is inspected
- THEN it reports no newer version
- AND it is still absent from the outdated set

### Requirement: Pin state and install date come from the snapshot

The inventory MUST expose pin state, and the pinned version when one is recorded, for both formulae
and casks, read from the snapshot rather than from a separate pin listing. It MUST expose an install
date derived from the record's install timestamp, interpreted as Unix epoch seconds, for both kinds.

#### Scenario: Pin state is exposed for both kinds without an extra invocation

- GIVEN a pinned formula and a pinned cask in the payload
- WHEN their pin state is read
- THEN both report pinned with their recorded pinned version
- AND exactly one brew invocation was recorded

#### Scenario: Install dates come from the recorded timestamps

- GIVEN a formula keg record and a cask record each carrying an epoch-seconds install timestamp
- WHEN their install dates are read
- THEN each date equals its recorded timestamp interpreted as epoch seconds

### Requirement: The catalog join happens above both packages

Installed records MUST be joined to catalog records on the package identity already used by the
catalog — the `(kind, name)` pair — reusing that identity rather than introducing a second one. An
installed package with no matching catalog record (a tap-only or unpublished package) MUST still be
listed with everything the snapshot knows about it, never hidden. The join MUST live above both the
catalog and the brew-process layers: the catalog MUST NOT gain a dependency on brew process
execution, so catalog sync and search continue to work with brew absent.

#### Scenario: A matched package carries catalog metadata

- GIVEN an installed formula `wget` and a catalog record for formula `wget` with a description
- WHEN the joined inventory entry is read
- THEN it carries the installed version and the catalog description

#### Scenario: An unmatched installed package is still listed

- GIVEN an installed formula from a third-party tap with no catalog record
- WHEN the installed list is read
- THEN the formula is listed with its snapshot data and no catalog metadata

#### Scenario: The catalog target does not depend on the brew-process target

- GIVEN the package graph of `Packages/CellarCore`
- WHEN the dependencies of the catalog target are enumerated
- THEN they contain no brew-process target, directly or transitively

### Requirement: Installed-state filters are composed, never pushed into the search index

Browse MUST offer installed, not-installed and outdated filters. Each MUST be answered by
intersecting catalog query results with membership sets supplied by this capability; the catalog
query contract MUST NOT gain an installed, not-installed or outdated predicate. The outdated filter
MUST use the same outdated derivation as the installed list, so self-updating casks are excluded
from it too. When the inventory is unavailable or empty, the filters MUST render disabled and MUST
NOT alter the results a user would otherwise see.

While browse is showing an installed-driven mode — installed or outdated — the catalog-only filter
controls (package kind, deprecated, disabled) MUST either apply to that mode's visible results
exactly as they apply to catalog results, or be rendered disabled for that mode. A control that is
enabled but cannot change the visible results is forbidden: every enabled control MUST be honoured,
and every control that is not honoured MUST be visibly unavailable.

A favorites filter MUST be offered in the same filter bar and MUST be composed on exactly the same
terms: it is answered by intersecting results with the favorite membership set supplied by
`local-package-metadata`, and the catalog query contract MUST NOT gain a favorite predicate. It MUST
be combinable with the other filters rather than replacing them, and MUST render disabled when no
metadata is available. Locally stored note text MUST NOT be added to any search index and MUST NOT be
matched by the installed list's search or by catalog search.

#### Scenario: The installed filter narrows browse results

- GIVEN a catalog containing `wget` and `curl`, and an inventory containing only `wget`
- WHEN browse results are filtered to installed
- THEN only `wget` remains

#### Scenario: The not-installed filter is the complement

- GIVEN the same catalog and inventory
- WHEN browse results are filtered to not-installed
- THEN only `curl` remains

#### Scenario: The outdated filter excludes self-updating casks

- GIVEN an inventory with one outdated formula and one self-updating cask behind its published
  version
- WHEN browse results are filtered to outdated
- THEN only the formula remains

#### Scenario: With no inventory the filters are disabled and results are unchanged

- GIVEN brew detection reports absent and the inventory is empty
- WHEN browse is opened and a query runs
- THEN the installed, not-installed and outdated filters are disabled
- AND the results are identical to the same query with no installed-state filtering

#### Scenario: The catalog filter set still declares no installed predicate

- GIVEN the catalog query's declared filter set
- WHEN it is enumerated
- THEN it contains no installed, not-installed, outdated or favorite predicate

#### Scenario: No catalog filter control is enabled but inert under the installed mode

- GIVEN browse in the installed mode over an inventory holding one formula and one cask, one of them
  deprecated
- WHEN the kind, deprecated and disabled controls are inspected
- THEN each control is either reported unavailable for that mode, or changes the visible results
  when it is applied

#### Scenario: The outdated mode obeys the same rule

- GIVEN browse in the outdated mode over an inventory holding one outdated formula and one outdated
  cask
- WHEN the kind control is applied to casks only
- THEN either the control was reported unavailable for that mode, or only the cask remains

#### Scenario: The favorites filter narrows the list

- GIVEN an inventory containing `wget` and `curl`, with only `wget` marked favorite
- WHEN the favorites filter is applied
- THEN only `wget` remains

#### Scenario: The favorites filter composes with the other filters

- GIVEN an inventory of one outdated favorite, one up-to-date favorite and one outdated
  non-favorite
- WHEN the favorites and outdated filters are both applied
- THEN only the outdated favorite remains

#### Scenario: With no metadata the favorites filter is disabled and results are unchanged

- GIVEN an inventory and no metadata store
- WHEN the filter bar is inspected and a query runs
- THEN the favorites filter is disabled
- AND the results are identical to the same query with no favorites filtering

### Requirement: Brew absent or invalid yields an empty inventory and read-only guidance

When brew detection reports absent, invalid or a missing configured path, the inventory MUST be
empty, MUST NOT attempt a probe, MUST NOT throw or block, and MUST surface read-only guidance
instead of an error state. Catalog browse and search MUST be unaffected. When brew later becomes
available, the inventory MUST populate without restarting the app.

#### Scenario: Absent brew produces an empty inventory with guidance

- GIVEN brew detection reports absent
- WHEN the inventory is read
- THEN it is empty, nothing is thrown, and install guidance is available
- AND no brew process was spawned

#### Scenario: An invalid configured path is guidance, not failure

- GIVEN brew detection reports an invalid configured path
- WHEN the inventory is read
- THEN it is empty and the rejection reason is available as read-only guidance
- AND no brew process was spawned

#### Scenario: The inventory populates when brew appears

- GIVEN an empty inventory because detection reported absent
- WHEN detection transitions to a valid installation and a refresh runs
- THEN the inventory reports the installed packages from the resulting snapshot

### Requirement: External changes invalidate the inventory, debounced and coalesced

An external change to the installed packages MUST be reflected without user action. The change
signal MUST be treated purely as an invalidation trigger: its contents MUST NOT be parsed to derive
inventory state — a re-snapshot is always taken instead. Bursts of signals MUST be coalesced on an
injected clock so that a burst within the quiet window causes exactly one re-snapshot. While a
Cellar-initiated mutation **that invalidates the installed set** is in flight, signals MUST be
suppressed, and exactly one re-snapshot MUST be taken at that mutation's terminal outcome.
Overlapping refresh requests MUST coalesce onto the one refresh genuinely in flight; a request that
arrives after that refresh has settled MUST take a fresh snapshot rather than be handed the settled
one.

Suppression and the owed re-snapshot MUST be scoped to commands that declare they invalidate the
installed set, as `package-mutation` requires each command to declare. A Cellar-initiated operation
that does not declare the installed set MUST NOT suppress external change signals while it runs, and
MUST NOT force an inventory re-snapshot at its terminal outcome; external changes observed while such
an operation runs MUST be handled by the ordinary debounce and coalescing rules above.

Mutation suppression MUST be evaluated at the moment a re-snapshot would actually start, not only
when a signal arrives and when the quiet window opens. A quiet window that opened before an
inventory-invalidating mutation began MUST NOT fire a re-snapshot while that mutation is in flight;
it MUST be folded into the single re-snapshot owed at the mutation's terminal outcome.

An acquisition already in flight MUST NOT be used to answer a change signal that arrived after that
acquisition started: such a signal MUST invalidate the in-flight result for freshness purposes and
cause a further re-snapshot once the quiet window elapses, so the inventory converges on state
observed at or after the newest signal.

Resetting the inventory to a detection-driven state — for example clearing it because detection
reported brew absent — while an acquisition is in flight MUST NOT strand that acquisition. The
inventory MUST remain able to run and publish a later refresh, and MUST NOT stay stuck in the
cleared state after a subsequent successful refresh.
(Previously: suppression and the owed re-snapshot applied to **every** Cellar-initiated mutation
unconditionally, so a mutation that cannot change the installed set both suppressed genuine external
signals and paid a full re-snapshot it could learn nothing from.)

#### Scenario: An external install is reflected without user action

- GIVEN a running inventory and a change source under test control
- WHEN the underlying snapshot gains a package and one change signal is emitted
- THEN after the quiet window the inventory lists the new package
- AND no user action was required

#### Scenario: A burst of signals causes exactly one re-snapshot

- GIVEN a running inventory
- WHEN twenty change signals are emitted within the quiet window
- THEN exactly one additional brew invocation is recorded

#### Scenario: Signals during an inventory-invalidating mutation are suppressed and settled once

- GIVEN a Cellar-initiated mutation declaring the installed set, in flight
- WHEN change signals are emitted continuously until that mutation reaches a terminal outcome
- THEN no re-snapshot runs while the mutation is in flight
- AND exactly one re-snapshot runs at the terminal outcome

#### Scenario: A refresh requested after the one in flight settles is fresh

- GIVEN a refresh that has already completed against a snapshot payload `P1`
- WHEN a refresh is requested afterwards and the payload is now `P2`
- THEN a second invocation is performed
- AND the inventory reflects `P2`

#### Scenario: A window opened before an inventory-invalidating mutation began does not fire during it

- GIVEN a change signal that opened the quiet window
- WHEN a Cellar-initiated mutation declaring the installed set begins before that window elapses, and
  the window then elapses while the mutation is still in flight
- THEN no re-snapshot runs while the mutation is in flight
- AND exactly one re-snapshot runs at the mutation's terminal outcome

#### Scenario: A signal during an acquisition is not answered by that acquisition

- GIVEN an acquisition in flight against snapshot payload `P1`
- WHEN a change signal is emitted after that acquisition started and the underlying payload is now
  `P2`
- THEN a further invocation is performed after the quiet window
- AND the inventory reflects `P2`, not `P1`

#### Scenario: Resetting during an acquisition does not strand the inventory

- GIVEN an acquisition in flight that has not yet settled
- WHEN the inventory is reset to the brew-absent state before it settles, and detection later
  reports a valid installation and a refresh is requested
- THEN that refresh performs an invocation and publishes its snapshot
- AND the inventory does not remain empty

#### Scenario: An operation that does not invalidate the installed set forces no re-snapshot

- GIVEN a Cellar-initiated operation whose declared invalidation scope excludes the installed set
- WHEN it reaches a successful terminal outcome, and separately a failed and a cancelled one
- THEN no inventory re-snapshot is forced in any of the three cases
- AND no `brew info --installed --json=v2` invocation is recorded for them

#### Scenario: External signals are not suppressed by a non-invalidating operation

- GIVEN a Cellar-initiated operation whose declared invalidation scope excludes the installed set, in
  flight, and a change source under test control
- WHEN the underlying snapshot gains a package and one change signal is emitted while that operation
  is still running
- THEN after the quiet window the inventory lists the new package, without waiting for that operation
  to finish

### Requirement: Refresh loops are owned for the app's lifetime

Background refresh loops MUST be owned for the lifetime of the application rather than by any single
window. Closing the window that started the app MUST NOT stop them. Opening an additional window
MUST NOT start a second loop, and reopening a window after all were closed MUST NOT start another
one; at most one loop of each kind runs per launch.

#### Scenario: Closing the starting window does not stop the loops

- GIVEN the app has launched and its refresh loops are running
- WHEN the window that started the app is closed
- THEN the loops are still running
- AND a subsequent refresh still updates the inventory

#### Scenario: A second window does not start a second loop

- GIVEN the app has launched with its refresh loops running
- WHEN a second window is opened, then all windows are closed and a new one is opened
- THEN exactly one loop of each kind is running throughout

### Requirement: Snoozed packages leave the outdated section and its count

A package with a snooze in effect — as defined by `local-package-metadata`, meaning the version
currently offered for it still **equals** the stored snoozed version — MUST be absent from the
outdated set, MUST NOT contribute to the outdated count or badge, and MUST be excluded from the
outdated browse filter on exactly the same terms, so the list and the filter cannot disagree. As soon
as the offered version differs from the stored snoozed one — newer, older, or differing only by a
revision suffix — the package MUST return to the outdated set, the count and the filter without user
action. This capability MUST NOT order or precedence-compare version strings to decide that; it
consumes the equality rule owned by `local-package-metadata`. A snooze MUST NOT remove the package
from the installed list itself.

#### Scenario: A snoozed package is absent from the set and the count

- GIVEN two outdated formulae, one of them snoozed at the version it is outdated toward
- WHEN the outdated set and the outdated count are read
- THEN only the non-snoozed formula is in the set
- AND the count is 1

#### Scenario: A changed offered version returns it to the set and the count

- GIVEN a formula snoozed at version `1.2.3`
- WHEN the offered version becomes `1.3.0`, and separately `1.2.3_1`, and the inventory refreshes
- THEN the formula is in the outdated set again and the count includes it in both cases
- AND no user action was required

#### Scenario: The outdated browse filter agrees with the outdated list

- GIVEN an inventory with one snoozed outdated package and one unsnoozed outdated package
- WHEN browse results are filtered to outdated
- THEN exactly the packages in the outdated set remain, and the snoozed one is absent

#### Scenario: A snooze does not hide the package from the installed list

- GIVEN a snoozed outdated package
- WHEN the installed list is read with default filters
- THEN the package is listed with its installed version

### Requirement: Multi-select is explicit, ordered, and offered only for bulk-eligible verbs

The installed list MUST expose a selection of zero or more packages. The selection MUST preserve the
order in which packages were selected, because that order determines the order their operations are
submitted. A package that leaves the inventory MUST leave the selection at the next refresh, so no
action can be submitted for a package the app no longer lists. Bulk affordances MUST be offered for
upgrade, uninstall, pin, unpin and snooze; favorite and note MUST offer no bulk affordance, and
a bulk control that cannot act on the current selection MUST be unavailable rather than inert.

When more than one package enters the selection in a single action — select-all, or any multi-package
add — they MUST enter it in the order the list displays them: section by section from top to bottom,
and within each section in that section's displayed order. They
MUST NOT enter it in the underlying inventory's order. Because selection order determines submission
order, the order the resulting operations are submitted MUST therefore match the order the user sees.

Pin and unpin MUST be **two independent verbs**, each with its own eligibility. They MUST NOT be
collapsed into a single toggle whose meaning depends on how homogeneous the selection happens to be,
because a selection holding both pinned and unpinned packages has no single correct answer and the
unavailable-rather-than-inert rule forbids guessing. Every verb's eligible set MUST be derived
independently from the selection: upgrade over its upgradable members, uninstall over its
uninstallable members, pin over its formulae that are not pinned, unpin over its formulae that are
pinned, and snooze over its outdated members that are not already snoozed at the offered version. A
verb whose eligible set is empty MUST be unavailable. A verb whose eligible set is non-empty MUST act
on exactly that set, and MUST NOT act on, silently skip past, or guess about the selection's
ineligible members. A cask MUST NOT enter a pin or unpin set, because pinning is formula-only.
Bulk pin and bulk unpin MUST require no confirmation.

Bulk snooze MUST NOT enter the bulk verb vocabulary that produces mutation commands, and MUST NOT be
submitted through the shared mutation spine. It spawns no process, submits no operation and writes no
history entry. It MUST record one snooze per eligible selected package, each scoped to **that
package's own** offered version, on exactly the terms `local-package-metadata` sets; its copy MUST NOT
imply a duration. Its affordance MUST NOT be representable as a case of the bulk mutation vocabulary,
so no consumer of that vocabulary can hold a case it is unable to execute.
(Previously: bulk affordances were offered for upgrade and uninstall **only**, and pin, unpin and
snooze were prohibited alongside favorite and note; nothing was said about per-verb eligibility, about
pin and unpin being separate verbs, or about a bulk affordance that does not travel the mutation
spine.)

#### Scenario: Selection preserves order

- GIVEN an installed list containing `git`, `wget` and `iterm2`
- WHEN `wget`, then `iterm2`, then `git` are selected
- THEN the selection is reported in the order `wget`, `iterm2`, `git`

#### Scenario: A bulk add enters the selection in displayed order

- GIVEN an installed list whose inventory order is `git`, `pcre2`, `iterm2`, and whose displayed
  order — as rendered by its sections, top to bottom — is `iterm2`, then `git`, then `pcre2`
- WHEN all three are added to the selection in one bulk add
- THEN the selection is reported in the order `iterm2`, `git`, `pcre2`
- AND their operations are submitted in that same order, not in inventory order

#### Scenario: Deselecting removes exactly one package

- GIVEN a selection of three packages
- WHEN the second is deselected
- THEN the selection holds the other two, in their original relative order

#### Scenario: A package that leaves the inventory leaves the selection

- GIVEN a selection containing `wget`
- WHEN a refresh produces an inventory that no longer contains `wget`
- THEN the selection no longer contains `wget`

#### Scenario: Upgrade, uninstall, pin, unpin and snooze are offered for a selection

- GIVEN a selection of two outdated, unsnoozed formulae, one of them pinned and one of them not
- WHEN the bulk controls exposed for it are enumerated
- THEN upgrade, uninstall, pin, unpin and snooze are present
- AND no bulk favorite or note control is present

#### Scenario: An empty selection offers no enabled bulk control

- GIVEN an empty selection
- WHEN the bulk controls are inspected
- THEN every bulk control is unavailable

#### Scenario: The bulk mutation vocabulary is exactly upgrade, uninstall, pin and unpin

- GIVEN the vocabulary of bulk verbs that produce mutation commands
- WHEN it is enumerated exhaustively, by case and by displayed title
- THEN it holds exactly upgrade, uninstall, pin and unpin
- AND no snooze, favorite, note or service verb appears in it, by case or by title

#### Scenario: A mixed pinned selection offers pin and unpin over their own subsets

- GIVEN a selection of three formulae, one pinned and two unpinned
- WHEN the pin and unpin controls are inspected
- THEN both are available
- AND pin announces and acts on exactly the two unpinned formulae, and unpin announces and acts on
  exactly the one pinned formula

#### Scenario: A selection with no formula leaves pin and unpin unavailable

- GIVEN a non-empty selection containing only casks
- WHEN the pin and unpin controls are inspected
- THEN both are unavailable rather than present and inert
- AND no pin or unpin operation can be submitted for the selection

#### Scenario: Bulk pin and bulk unpin raise no confirmation

- GIVEN a selection of unpinned formulae, and separately a selection of pinned formulae
- WHEN bulk pin and bulk unpin are submitted
- THEN neither presents a confirmation
- AND each submits exactly one pin or unpin operation per eligible formula, in selection order

#### Scenario: Bulk snooze never enters the mutation spine

- GIVEN a selection of outdated packages and a recording process launcher, operation queue and
  history store
- WHEN bulk snooze is submitted
- THEN no process was spawned, no operation was submitted and no history entry was written
- AND one snooze is recorded per selected package, each naming that package's own offered version

### Requirement: A bulk action's label counts exactly the set it submits

Any control that announces how many packages a bulk action will affect MUST derive that number from
the same projection the action submits. The label and the submitted set MUST be computed from one
source: applying the same filters, the same dependency toggle and the same snooze exclusion. It MUST
be impossible for the control to announce one number and submit a different set.

#### Scenario: The label matches the submitted set under the default filters

- GIVEN an inventory of outdated on-request and outdated dependency-only packages, with the
  dependency toggle off
- WHEN the bulk-upgrade control's announced count is read and the action is then submitted
- THEN the number of operations submitted equals the announced count

#### Scenario: Toggling the dependency filter moves both together

- GIVEN the same inventory
- WHEN the dependency toggle is turned on and the announced count is read and the action submitted
- THEN the announced count changed
- AND the number of operations submitted still equals the announced count

#### Scenario: Snoozed packages are excluded from both the label and the submission

- GIVEN an inventory of three outdated packages, one of them snoozed
- WHEN the bulk-upgrade control's announced count is read and the action is submitted
- THEN the announced count is 2
- AND exactly two operations are submitted, neither naming the snoozed package

#### Scenario: Each new verb's label counts its own eligible set

- GIVEN a selection of two unpinned formulae, one pinned formula and one cask, all of them outdated
  and unsnoozed
- WHEN the announced counts of the pin, unpin and snooze controls are read and each action is
  submitted
- THEN pin announces 2 and submits 2, unpin announces 1 and submits 1, and snooze announces 4 and
  records 4
- AND each count was derived from the same projection its own action submitted

## Provenance

- Established by change `m2-installed-inventory` (archived `2026-08-02`), ADDED-only delta — **11
  requirements / 34 scenarios**, copied verbatim from
  `openspec/changes/archive/2026-08-02-m2-installed-inventory/specs/installed-inventory/spec.md`.
  This is the first main spec for the capability; nothing was modified, removed or renamed. This
  file adds only the header, the `## Requirements` wrapper, and this provenance section.
- Two binding inputs were settled *before* the delta was written and are stated in it as facts, not
  open questions:
  - **Product decisions** (user-confirmed 2026-08-02, Engram `#7079`): the default installed view is
    on-request only; auto-updating casks never badge as outdated; browse installed-state filters
    ship in this change, composed through this capability.
  - **Live probe** (brew 6.0.14, Engram `#7081`): the `info --installed` snapshot already applies
    brew's auto-updates exclusion to a cask's `outdated` flag, and the same record carries both the
    catalog `version` and the `installed` string, so a "newer version exists" signal for a
    self-updating cask is derivable without a second invocation. This is why "A self-updating cask's
    newer version is derived from the same probe" forbids a second brew invocation rather than
    reserving `brew outdated --greedy` as a fallback.
- **`package-search` is deliberately untouched by this capability.** Its requirement "Filters
  answerable from the catalog alone" — including "No filter MUST depend on installed, not-installed,
  or outdated state" — remains correct and byte-identical; composition happens above the index. The
  invariant is re-asserted here as the scenario "The catalog filter set still declares no installed
  predicate", so a future change cannot quietly push installed state into the search index without
  failing a scenario in *this* capability too.
- **Implementation note for "On-request and dependency-only are derived, and the default view is
  on-request"** (recorded at archive, from the docs review of
  `openspec/changes/archive/2026-08-03-m2-mutations-installed/explore.md`): the requirement's premise "the payload
  carries no `installed_as_dependency` field" is the *derivation contract this capability
  implements*, and the derivation is a correct fallback either way. The blanket claim that the field
  does not exist in `brew info --json=v2` is over-generalised — the change's own fixture models the
  field. Read the requirement as "on-request state MUST be derived from the on-request marker", not
  as a schema assertion about Homebrew's JSON.
- **Implementation note for "External changes invalidate the inventory, debounced and coalesced"**
  (native review lineage `review-bbe42e6b3e7d13e7`, WARNINGs, non-blocking): as delivered, the
  mutation gate is checked when a signal arrives and again when the quiet window opens, but not
  re-checked after an already-open window elapses; and `clear(to:)` while a refresh is in flight can
  strand the in-flight acquisition. Both are latent until `m2-mutations-installed` (M2-2) drives the
  `isMutating` flag with real mutations; the requirement text is unchanged and all four scenarios are
  COMPLIANT. Tracked in the M2-1 archive report's follow-up register, not as a spec gap.
  **Closed by `m2-mutations-activity`** — see the amendment below, which specifies the behaviour the
  note described as a gap.
- **Amended by change `m2-mutations-activity` (archived `2026-08-02`, PRD milestone **M2**, slice
  M2-2)**: **2 MODIFIED** requirements replaced as whole blocks, adding **5 scenarios**.
  11 requirements / 34 scenarios → **11 requirements / 39 scenarios**. Nothing was added, removed or
  renamed; the other nine requirements are byte-identical. Both amendments close behavioural gaps the
  M2-1 archive routed to M2-2 — they were latent because nothing drove the mutation gate with a real
  mutation, and M2-2 is the change that does.
  - **"Installed-state filters are composed, never pushed into the search index"** gained the rule
    that catalog-only controls (kind, deprecated, disabled) under the installed and outdated browse
    modes MUST either apply or render disabled, plus 2 scenarios. Previously the requirement governed
    only the three installed-state filters and said nothing about the catalog-only controls shown
    beside them, so those controls rendered **enabled but inert** under installed and outdated modes
    (M2-1 follow-up 1). Delivered as `InstalledBrowse.rows(filters:)` — the parameter is *required*,
    not defaulted, so no call site can silently ignore the controls — with `kinds` read from
    `InstalledPackage.kind` (the inventory is authoritative) and deprecated/disabled applied as
    catalog predicates through the existing catalog-lookup decoration, where **no catalog record ⇒
    not excluded**, preserving this capability's own "an unmatched installed package is still listed"
    principle.
  - **"External changes invalidate the inventory, debounced and coalesced"** gained three paragraphs
    and 3 scenarios covering (a) suppression re-checked at the moment a re-snapshot would start, so a
    window opened before a mutation began cannot fire during it (M2-1 follow-up 3); (b)
    invalidation-after-start, so an in-flight acquisition never answers a signal that arrived after it
    started and the inventory can no longer settle on pre-change state (M2-1 follow-up 2); (c) reset
    during acquisition not stranding the slot, so the inventory cannot stay stuck empty after a later
    successful refresh (M2-1 follow-up 4). Delivered as a stored, cancellable debounce task with a
    post-sleep gate re-check, a monotonic `invalidationCount` with a per-acquisition mark that a
    joiner must match, and a `clear(to:)` that cancels and vacates the in-flight slot **before**
    bumping the publication ordinal.
- **Verification note on the mutation gate's depth** (`m2-mutations-activity` verify ruling 1,
  2026-08-02): "exactly one re-snapshot at that mutation's terminal outcome" is satisfied by a
  **depth-counted** gate — `begin()` per submission, `end()` per terminal, floor zero, always
  yielding. A selected upgrade fans out into N independent operations, so N terminals owe N
  re-snapshots while `isMutating` must still cover the whole batch. One-begin-per-batch would drop
  the depth to zero after the first terminal and reopen suppression mid-batch, violating this
  requirement's suppression clause.
- **Verification note on post-terminal signals** (`m2-mutations-activity` verify ruling 2,
  2026-08-02): a change signal produced by a mutation's own writes but arriving **after** its
  terminal outcome falls outside the suppression clause, which is scoped to "while a mutation is in
  flight". It is then correctly governed by the ordinary external-change clauses — not parsed,
  debounced into exactly one refresh. Conforming, not a violation; a short post-terminal grace window
  would absorb the redundant probe and is carried as a follow-up, not a spec gap.
- **`package-mutation` owns the mutation side of this contract.** Its requirement "Every terminal
  outcome forces one re-snapshot, and cancel is reported honestly" is the counterpart to the
  suppression clause here; the two are written to be read together and must not drift.
- **Verification note for "Installed-state filters are composed, never pushed into the search
  index" and "Refresh loops are owned for the app's lifetime"** (verify WARNING 2, 2026-08-02): the
  rule side (`InstalledBrowse.isFilterEnabled`, `LoopOwner`) is unit-tested in the package; the app
  target's bindings that consume it (`CatalogFilterBar`'s `.disabled(...)`, `cellarApp`'s
  `loops.start(...)` calls) are proven by `xcodebuild test` plus manual screenshot rather than by a
  unit test. Design-sanctioned Phase 9 strategy, recorded as a real coverage boundary.
- **Amended by change `m2-local-metadata-history` (archived `2026-08-03`, PRD milestone **M2**, slice
  M2-3 — the last M2 slice)**: **1 MODIFIED** requirement replaced as a whole block (adding
  **3 scenarios**) and **3 ADDED** requirements (**12 scenarios**). 11 requirements / 39 scenarios →
  **14 requirements / 54 scenarios**. Nothing was removed or renamed; the other ten requirements are
  byte-identical, and the MODIFIED replacement is a strict superset of the text it replaced.
  - **"Installed-state filters are composed, never pushed into the search index"** gained the
    favorites filter, composed on exactly the same terms as the installed-state filters, plus the rule
    that locally stored **note text MUST NOT enter any search index**. 3 scenarios added, and the
    existing "The catalog filter set still declares no installed predicate" scenario now also excludes
    a favorite predicate. Favorites are a filter-bar entry, **not** a sidebar section (product
    decision, user-confirmed 2026-08-02, Engram `#7111`). The no-membership-predicate claim is
    asserted by `Mirror` reflection over the real `SearchFilters` type, so a future change cannot
    quietly add one.
  - **"Snoozed packages leave the outdated section and its count"** is ADDED rather than folded into
    "Auto-updating casks never count as outdated", because it does not alter the existing
    self-updating-cask derivation — it is a projection composed above it. It consumes
    `local-package-metadata`'s equality rule and MUST NOT introduce a version comparator; the list and
    the browse filter are required to agree so they cannot drift.
  - **"Multi-select is explicit, ordered, and offered only for bulk-eligible verbs"** makes selection
    part of the installed list's observable model. Order is load-bearing — it determines submission
    order — so the app keeps the native `List(selection:)` `Set<PackageID>` binding for range
    selection, VoiceOver and Select All, and maintains an ordered `[PackageID]` **beside** it; the
    ordered array is the only thing the bulk surface and the confirmation sheet read. Bulk affordances
    are restricted to upgrade and uninstall; PRD §3.2 also lists pin and snooze as bulk verbs, and
    those were **deliberately narrowed out** (settled 2026-08-02) — the restriction is proven
    exhaustively over `BulkSelection.Action.allCases`.
  - **"A bulk action's label counts exactly the set it submits"** closed M2-2 follow-up 1: the label
    counted the *dependency-filtered* entries while `submitUpgradesForOutdated` filtered the **whole
    inventory**, so the button could promise fewer upgrades than it submitted
    (`InstalledListView.swift:83`). Closed by deriving both from one projection — the count is
    computed from `upgradableIDs`, the exact set the action submits — and the old divergent helper was
    deleted outright.
- ~~**Known follow-up (`m2-local-metadata-history` native review lineage `review-e07590a04c4aff38`,
  SUGGESTION, non-blocking)**: `InstalledListView.reconcileOrder(with:)` appends newly selected ids in
  **flat inventory order**, while a nearby comment claims the three-section displayed order. Selection
  order is still deterministic and reproducible — never `Set` iteration order — so no scenario is
  violated; the divergence is between the code and its own comment for a multi-add gesture.~~
  **CLOSED by `m3-hardening-prelude` (M3-0, archived 2026-08-03)** — see the amendment below, which
  promotes the comment's claim into requirement text and then makes the code honour it.
- **Amended by change `m3-hardening-prelude` (archived `2026-08-03`, PRD milestone **M3**, slice
  M3-0 — the hardening prelude)**: **1 MODIFIED** requirement replaced as a whole block —
  "Multi-select is explicit, ordered, and offered only for bulk-eligible verbs" — adding **1
  scenario**. 14 requirements / 54 scenarios → **14 requirements / 55 scenarios**. Nothing was added,
  removed or renamed; the other thirteen requirements are byte-identical, and the replacement is a
  strict superset of the text it replaced. Previously the requirement fixed selection order only for
  packages selected **one at a time**; the order in which a *bulk* add entered them was unspecified,
  so it followed flat inventory order and operations were submitted in an order the user never saw —
  M2-3 follow-up **S2**.
  - **The scenario deliberately does not enumerate the section names.** The section set belongs to
    the view and has already changed once; naming it in the spec would make a layout change a spec
    change. As rendered today the order is Outdated → Updates itself → All packages / Installed on
    request, and the delivered `InstalledSections` type preserves those titles exactly.
  - Delivered as a package-level `InstalledSections` value (`outdated` / `selfUpdating` / `rest`,
    with a `displayed` concatenation) that the view renders its three `Section`s from and
    `reconcileOrder` maps over — **one projection read twice**, following the `upgradableIDs`
    precedent. Pinned by `InstalledSectionsTests >
    theDisplayedOrderIsOutdatedThenSelfUpdatingThenTheRest` and
    `bulkAddEntersTheSelectionInDisplayedOrderNotInventoryOrder`.
  - **This slice added no bulk verb**, so the exhaustive "only upgrade and uninstall" scenario —
    asserted over `BulkSelection.Action.allCases` — is carried forward unchanged.
- **Known follow-up (`m3-hardening-prelude` native review lineage `review-fa82e5eaa3023fc4`,
  SUGGESTION, non-blocking)**: the app-target `reconcileOrder` expression itself is **unproved by an
  automated test** — `InstalledSectionsTests` composes the reconciliation in-test rather than calling
  the app-target function, which lives outside the package suite. The ordering *rule* is fully proven
  headless; the app-target wiring rests on `xcodebuild build` plus manual check 9.1(c), which
  observed a real one-gesture multi-add submitting in displayed order. Tracked as follow-up **(c)**
  in the M3-0 archive report.
- **Amended by change `m3-services` (archived `2026-08-03`, PRD milestone **M3**, slice M3-1 —
  Service Management)**: **1 MODIFIED** requirement replaced as a whole block — "External changes
  invalidate the inventory, debounced and coalesced" — adding **2 scenarios**. 14 requirements / 55
  scenarios → **14 requirements / 57 scenarios**. Nothing was added, removed or renamed; the other
  thirteen requirements are byte-identical, and the replacement is a strict superset of the text it
  replaced. Previously suppression and the owed re-snapshot applied to **every** Cellar-initiated
  mutation unconditionally, so a mutation that cannot change the installed set both suppressed
  genuine external signals and paid a full `brew info --installed --json=v2` probe (1.27 s / 663 KB)
  it could learn nothing from.
  - **This is the other half of `package-mutation` PM6's typed invalidation scope**, amended in the
    same change. The two requirements were written to be read together and MUST NOT drift: PM6 says
    the command declares what it invalidates; this says what the inventory does with that
    declaration. A services toggle now costs zero inventory re-snapshots.
  - **Delivered with `InstalledChangeObserving.swift` byte-unchanged** — asserted, not assumed
    (`git diff main...HEAD` on that file returns 0 lines). Scoping falls out of `MutationGates` never
    calling `begin()` on the installed gate for a command that does not declare `.installedInventory`,
    so `isMutating` stays false (no suppression) and the `terminals` stream never fires (no forced
    re-snapshot). No new suppression branch was added to the observer at all.
  - **The post-terminal FSEvents grace window (M2-2 follow-up #6) was deliberately NOT specified, and
    an earlier draft that folded it in was wrong.** A grace guard sits exactly where the
    carried-forward clause "An acquisition already in flight MUST NOT be used to answer a change
    signal that arrived after that acquisition started … so the inventory converges on state observed
    at or after the newest signal" fires its further re-snapshot, and **drops** it. For a mutation's
    own echo that is harmless, but the rule cannot tell that echo apart from a genuine external change
    landing in the same window, which would then be silently lost. The draft cited the in-flight
    suppression paragraph as cover; that governs a different moment and a different guarantee.
    Closing #6 requires an explicit amendment **narrowing this requirement's convergence guarantee**,
    which this slice did not take — it stays open, with that amendment named as its precondition.
    Guarded rather than trusted: a repo scan for `isSettling|settleGrace` returns zero.
  - **"Multi-select is explicit, ordered, and offered only for bulk-eligible verbs" is untouched, and
    that is load-bearing.** This slice ships **no** bulk service affordance; `service-management`
    carries a guard scenario asserting the installed list's bulk vocabulary is still exactly upgrade
    and uninstall, so a future services multi-select must be its own type over its own entity rather
    than a third case here.
- **Amended by change `m3-disk-usage` (archived `2026-08-05`, PRD milestone **M3**, slice M3-3 —
  Disk Usage)**: **1 MODIFIED** requirement replaced as a whole block — "Asymmetric formula and cask
  installation shapes both decode" — adding **1 scenario**. 14 requirements / 57 scenarios → **14
  requirements / 58 scenarios**. Nothing was added, removed, or renamed; all other requirements and
  scenarios were preserved. The replacement keeps every existing decoding guarantee and additionally
  requires an absent linked-keg value to remain unlinked rather than being inferred from the newest
  installed keg, so disk attribution can consume the exact payload state.
- **Amended by change `m5-health` (archived `2026-08-07`, PRD milestone **M5** "Pro-parity flows",
  slice 5 of 5 — the slice that **closed M5**): 2 MODIFIED requirements, each replaced as a whole
  block, adding **6 scenarios**. 14 requirements / 58 scenarios → **14 requirements / 64
  scenarios**. Nothing was added, removed or renamed. Delta archived at
  `openspec/changes/archive/2026-08-07-m5-health/specs/installed-inventory/spec.md`.
  - **⚠ This amendment is DESTRUCTIVE, and `openspec/config.yaml` `rules.archive` ("Warn before
    merging destructive deltas") was applied.** The orchestrator issued the required warning and the
    maintainer directed the merge to proceed. "Multi-select is explicit, ordered, and offered only
    for bulk-eligible verbs" (II13) is **not** a strict superset of the text it replaced: a
    prohibition was **removed**, so this block was verified byte-for-byte against the delta rather
    than by superset check.
  - **What was removed, exactly.** (1) The requirement clause "Bulk affordances MUST be offered for
    upgrade and uninstall only; pin, unpin, snooze, favorite and note MUST offer no bulk affordance"
    — the prohibition on pin, unpin and snooze is gone; favorite and note remain prohibited. (2) The
    scenario **"Only upgrade and uninstall are offered for a selection"** and its assertion "AND no
    bulk pin, unpin, snooze, favorite or note control is present", rewritten as "Upgrade, uninstall,
    pin, unpin and snooze are offered for a selection". Five lines in total left the spec; every
    other line of the block is byte-identical.
  - **Why.** The 2026-08-02 narrowing recorded above was a deliberate scope decision, not an
    invariant. The maintainer **reversed it** on 2026-08-07 (decisions **D1**/**D2**, Engram
    `#7532`), so PRD §3.2's full bulk vocabulary ships. The removal is the point of the change, not
    a merge accident.
  - **What the rewrite deliberately preserved, byte-identically**: selection order, the
    displayed-order rule for a multi-package add, the leave-the-inventory rule, and above all **"a
    bulk control that cannot act on the current selection MUST be unavailable rather than inert"** —
    the clause that forbids guessing on a mixed pinned/unpinned selection, and therefore the clause
    that makes pin and unpin two independent verbs rather than one toggle. Four of the six existing
    scenarios are unchanged.
  - **What was added**: per-verb independent eligibility (upgradable / uninstallable / unpinned
    formulae / pinned formulae / outdated-not-already-snoozed); casks never enter a pin or unpin
    set; bulk pin and unpin raise no confirmation; and bulk snooze, which **MUST NOT** enter the
    bulk mutation vocabulary or the mutation spine and is not representable as a case of it.
  - **The earlier "untouched, and that is load-bearing" note above is superseded for its bulk-verb
    half.** `service-management`'s guard survives with its **intent** intact but its assertion
    rewritten: `ServiceSubmissionTests.theInstalledBulkVocabularyIsUnchanged` now proves no
    *service* verb entered the package bulk vocabulary, rather than that the vocabulary is frozen at
    two cases. `BulkSelectionTests.onlyUpgradeAndUninstallAreBulkEligible` was likewise rewritten,
    never deleted, keeping its title scan for `snooze`/`favorite`/`note`.
    `ServiceRowControl.allCases.count == 5` is unaffected.
  - **II14 "A bulk action's label counts exactly the set it submits" is a strict superset**:
    requirement text byte-identical, one scenario added so the new verbs' announced counts (pin 2/2,
    unpin 1/1, snooze 4/4) are covered by the same one-projection rule.
- **Amended by change `m7-tap-trust`** (archived `2026-08-23` —
  `openspec/changes/archive/2026-08-23-m7-tap-trust/`), **1 MODIFIED, 0 added, 0 removed, 0 renamed**
  — **14 req / 64 sc → 14 req / 67 sc**. II2 carried 5 scenarios and was replaced by 8; the other
  thirteen requirements are byte-identical to their prior text, and the destructive-delta warning did
  not fire.
  - **One fact, one value.** `brew info --installed --json=v2` reports `tap: null` for a package whose
    tap Homebrew withholds — the tap exists and is untrusted, so brew declines to name it (obs
    `#7721`). The shipped decoder collapsed that null into the empty string, which made "brew did not
    report a tap" indistinguishable from "the tap is empty" and forced every such package to read
    “Not installed.” in the tap inventory. `InstalledPackage.tap` is now `String?` and the absence is
    preserved, on **exactly the terms this requirement already stated** for a cask's tri-state
    `auto_updates`: not reported is not reported-as-something-else.
  - **The optional is not a compile-error migration, and the change's own framing was corrected to say
    so.** Swift promotes the non-optional operand of `==`, so all three shipped readers keep compiling
    *and* stay semantically correct (`nil` equals nothing). Only the declaration and the two decoder
    sites changed; the readers are pinned by `InstalledDeriveTests ·
    everyTapReaderTreatsAbsenceAsNoMatch` — a test, not the compiler. Anyone reintroducing a `tap ?? ""`
    collapse is caught there and by that test's targeted source scan.
  - **`CatalogPackage.tap` is a different, unchanged property that happens to share the name** (the
    change's risk R8). It was not touched.
  - **II2's `(Previously:)` annotation was extended, not replaced.** The `m5`-era linked-keg note stays
    and the tap clause is appended to it, because both describe the same block's history and neither
    supersedes the other.
  - **No `## Verification classes` table exists in this spec**, so none was hand-updated at archive.
    This change is the first to annotate these scenarios with an inline `- Verification:` line;
    untouched requirements deliberately keep none.
  - **This requirement is independent of the trust surface.** It is a strict honesty improvement, and
    the change's rollback plan lets it stay even if every other piece of `m7-tap-trust` is reverted.
  - The archived delta spec is the verbatim audit trail.
