# Delta for installed-inventory

**2 MODIFIED** requirements, each replaced as a whole block, adding **6 scenarios** in total. Nothing
is ADDED, REMOVED or RENAMED. 14 requirements / 58 scenarios → **14 requirements / 64 scenarios**.

> **⚠ DESTRUCTIVE DELTA — `openspec/config.yaml` `rules.archive` ("Warn before merging destructive
> deltas") applies.** The II13 replacement is **not** a strict superset of the text it replaces: a
> prohibition is being **removed**. Bulk pin, bulk unpin and bulk snooze were deliberately narrowed
> out on 2026-08-02, and the shipped Provenance records that narrowing as settled. **The maintainer
> has reversed that ruling** (decision **D1**/**D2**, Engram `#7532`, 2026-08-07), so PRD §3.2's full
> bulk vocabulary ships. The requirement text and one scenario are **rewritten, not extended**.

**What the rewrite preserves, deliberately and in full.** Everything II13 carried that is *not* being
reversed survives byte-identically: selection order, the displayed-order rule for a multi-package add,
the leave-the-inventory rule, and above all **"a bulk control that cannot act on the current selection
MUST be unavailable rather than inert"** — the exact clause that forbids guessing on a mixed
pinned/unpinned selection, and therefore the clause that makes pin and unpin two verbs rather than one
toggle. **Favorite and note remain prohibited.** Four of the six existing scenarios are unchanged; one
is rewritten; five are added.

**Two shipped tests pin the reversed clause and both are REWRITTEN, never deleted.**
`BulkSelectionTests.onlyUpgradeAndUninstallAreBulkEligible()` asserts the two-case vocabulary *and*
scans the joined lowercased titles for `pin`/`unpin`/`snooze`/`favorite`/`note` — that title scan
fails on a `pin` case even after the count is corrected, so it is rewritten against the new
vocabulary. `ServiceSubmissionTests.theInstalledBulkVocabularyIsUnchanged()` is a **services** test
(`service-management` SM4 sc5) that re-asserted the same two cases to prove no service verb leaked
into the package bulk vocabulary; **its intent survives the widening** and is preserved as an
assertion that no *service* verb entered the enum, not that the enum is frozen. The new scenario "The
bulk mutation vocabulary is exactly upgrade, uninstall, pin and unpin" is what both rewritten tests
answer to. `ServiceRowControl.allCases.count == 5` in the same file is unaffected.

**II14 is a strict superset.** Its requirement text is **byte-identical**; one scenario is added so
the new verbs' announced counts are covered by the same one-projection rule the shipped verbs are.

## MODIFIED Requirements

<!-- II13 -->
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

<!-- II14 -->
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
