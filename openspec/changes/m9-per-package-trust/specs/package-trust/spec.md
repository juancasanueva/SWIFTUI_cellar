# Delta for package-trust

**New capability.** No main spec exists at `openspec/specs/package-trust/spec.md`; this ADDED-only
delta establishes it, on the house precedent by which `package-detail`, `package-mutation` and
`tap-management` were each established by an ADDED-only delta. **8 ADDED requirements / 32 scenarios**,
0 modified, 0 removed, 0 renamed, so `rules.archive`'s destructive-delta warning does not fire.

**Purpose.** Reading, storing, attributing and surfacing Homebrew's **per-package** trust grants,
read-only. Homebrew 6 grants trust at two independent granularities. `tap-management` owns the tap's
own state, read from `brew tap-info --installed --json`. This capability owns the second granularity,
published only by `brew trust --json v1`, which `tap-info` does not carry. It **shows** grants; it
creates, changes and removes none.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m9-per-package-trust/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decisions consumed** (maintainer, 2026-08-24, Engram `sdd/m9-per-package-trust/scope-decisions`
obs `#7759`): the surface is **read-only** — no grant or revoke control for a package; unattributed
grants get a **dedicated section in Taps**; the `commands` namespace is **decoded and counted as
"other"**, never dropped; the count line lives on the tap **row and detail header**, both from one
projection value; package detail gets the **“Trusted individually”** marker beside its existing Tap
fact (owned by the `package-detail` delta in this same change).

**Measured Homebrew 6 facts this capability rests on** (do not re-derive; Engram `#7721`, `#7722`,
`#7724`, and the verbatim payload capture `#7764`): the payload's top-level keys are `taps`,
`formulae`, `casks`, `commands`, each an array of strings; entries are fully qualified; a `formulae`
entry is not always `owner/repo/name` — `https://github.com/cloudmanic/spice-edit/spice-edit` was
observed on a real Mac; the **same** qualified identifier can appear in both `formulae` and `casks`
(`gentleman-programming/tap/engram`), so the namespaces are **not disjoint**; a package name can carry
`@` (`guria/tap/nehir@rc`); `commands` can be present and **empty**; the bare read is **side-effect
free** (`trust.json` byte-identical before and after); per-package grants are independent of tap grants
and **survive an untap**; naming a `/`-qualified package to brew's trust machinery **is** the grant.

## Verification classes

Every scenario below declares exactly one verification class.

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` ("observable behavior of CellarCore types without referencing SwiftUI views") | `swift test --package-path Packages/CellarCore` | **30** |
| `manual-evidence` | no harness can exist — the fact is a property of a real `trust.json` written by a real `brew` on a real Mac | the maintainer, on a Mac running Homebrew 6; transcript captured in the verify report. **Binding: never run `brew upgrade` without `--dry-run` on that Mac** | **2** |

What stays **design-owned and is deliberately absent here**: view hierarchy, section placement and
ordering, rendered styling of any marker or line, which type holds each projection, and the wording of
any label not pinned below as exact copy.

## ADDED Requirements

### Requirement: Per-package grants are read from brew, into a three-valued state

Per-package grants MUST be acquired by spawning brew with compile-time-constant argv exactly
`trust --json v1`. No element of that argv MUST be interpolated, joined or split into existence, and it
MUST carry no package identity, no tap identity and no kind flag — it asks for the whole report and
nothing else.

The report MUST NOT be obtained by reading `trust.json`, or any other Homebrew state file, from disk.
Its location varies by configuration, its format is Homebrew's private business, and Cellar's standing
rule is to ask `brew` for what `brew` knows. This MUST hold on every path, including a fallback after a
failed spawn.

A package's per-package trust state MUST be **three-valued** and MUST NOT be reduced to a boolean:

1. `granted` — a decoded report contains an entry attributable to this exact package identity.
2. `noGrantRecorded` — a decoded report exists and contains no such entry.
3. `unreported` — no decoded report exists: brew has no `trust` verb, the spawn failed, or the payload
   could not be decoded.

`unreported` MUST be distinguishable from `noGrantRecorded` in the model and in every rendering, and
MUST NOT be collapsed into it. A Homebrew that cannot answer has reported nothing; it has not reported
zero. `noGrantRecorded` MUST NOT be named, rendered or described as "untrusted": a package under a
trusted tap is loadable with no per-package entry at all, so absence from the report is not a fact
about trust.

#### Scenario: The read's argv is constant and names nothing

- GIVEN the per-package trust read is built, for a machine with any number of taps and packages
- WHEN its argv elements are enumerated
- THEN they are exactly `trust`, `--json`, `v1`
- AND none carries a package name, a tap name, a kind flag or a qualified token
- Verification: `unit`

#### Scenario: The state has three distinct values

- GIVEN a decoded report listing cask `acme/tools/widget`, the same report for formula `acme/tools/helper` which it does not list, and a machine with no decoded report at all
- WHEN each package's per-package state is read
- THEN they are `granted`, `noGrantRecorded` and `unreported`, respectively
- AND no two of the three compare equal
- Verification: `unit`

#### Scenario: A Homebrew without the trust verb is unreported, never zero

- GIVEN the read fails in turn with a non-zero exit and an unknown-command message, with a launch failure, and with a payload that does not decode
- WHEN the resulting state is read for any package and for the report as a whole
- THEN every case is `unreported`
- AND no case reports a grant count of `0`, an empty grant set, or `noGrantRecorded`
- Verification: `unit`

#### Scenario: No trust file is read from disk

- GIVEN every path this capability can take to obtain a report, including each failure path
- WHEN the file-system accesses each path performs are enumerated
- THEN none opens `trust.json`, `~/.homebrew`, or any path derived from `XDG_CONFIG_HOME`
- AND the only acquisition is the spawned `brew` read
- Verification: `unit`

### Requirement: The grant store keeps the tap store's discipline and rides the taps domain

The report MUST be held by a store with the same discipline `tap-management`'s tap store already
proves: concurrent refresh requests MUST coalesce into **one** in-flight spawn; a failed refresh MUST
retain the last good report rather than replacing it with an empty one or an error state that loses it;
and an answer that arrives out of order MUST NOT be adopted over a newer one.

The report MUST refresh **whenever the taps domain refreshes**, and this capability MUST NOT introduce
a new declared invalidation domain on the shared mutation spine. **No command MUST declare a
per-package trust domain**, because no command Cellar can issue mutates a per-package grant: a grant is
created only by naming a `/`-qualified token, which `package-mutation` PM10 forbids everywhere. The
commands that change the ledger's `taps` namespace — tap trust, tap untrust, and the revocation
`tap-management` TM7 and TM8 pin behind an accepted removal — reach the report through the taps domain
they **already** declare, and a tap add or untap reaches it the same way because it changes which
entries attribute. A domain no Cellar command could ever invalidate would be dead declaration surface
across every command family, and Cellar genuinely takes no new invalidation domain here: it takes a
second probe and a second store, and nothing more.

The two reads MUST be issued as part of one taps refresh without either blocking the other, and the
**tap** read alone MUST decide that refresh's outcome. A degraded or failing grant read MUST NOT turn a
successful tap refresh into a failed one, MUST NOT change how many times the taps domain is refreshed,
and MUST NOT delay the tap snapshot's adoption.

Refreshing the grant read MUST NOT refresh, invalidate or re-derive the tap snapshot, the installed
snapshot or the catalog, and MUST NOT be a precondition for any of them: a machine where the read
always fails MUST keep every shipped surface working exactly as it does today.

#### Scenario: Concurrent refreshes coalesce into one spawn

- GIVEN three refreshes requested while one is in flight
- WHEN they settle
- THEN exactly one process was spawned and all four requests observe the same report
- Verification: `unit`

#### Scenario: A failed refresh keeps the last good report

- GIVEN a store holding a decoded report, and a subsequent refresh that fails
- WHEN the state is read
- THEN the last good report is still served, alongside a visible failure
- AND it is not replaced by an empty report, by `unreported`, or by a zero count
- Verification: `unit`

#### Scenario: A stale answer is not adopted over a newer one

- GIVEN two refreshes whose answers arrive out of order
- WHEN both settle
- THEN the newer answer is retained and the older one is discarded
- Verification: `unit`

#### Scenario: No per-package invalidation domain exists

- GIVEN every invalidation domain any command family on the shared mutation spine can declare
- WHEN every declared value is enumerated
- THEN the set is exactly the shipped one, with no member for per-package trust
- AND no command declares a per-package trust domain
- Verification: `unit`

#### Scenario: The grant read rides the taps domain, once per refresh

- GIVEN tap trust, tap untrust and the revocation behind an accepted removal, each reaching success, failure, launch failure and cancellation in turn
- WHEN the spawns and the domain refreshes are counted
- THEN each terminal refreshes the taps domain exactly once, and that refresh issues exactly one tap read and one grant read
- AND the two reads overlap rather than running one after the other, and neither refreshes installed inventory or the catalog
- Verification: `unit`

#### Scenario: A failing grant read never fails a tap refresh

- GIVEN a refresh in which the tap read succeeds and the grant read fails, and separately one in which the grant read never answers
- WHEN each refresh settles
- THEN the refresh outcome is the successful one the tap read produced, in both cases
- AND the taps domain is still refreshed exactly once, the tap snapshot is adopted undelayed, and the grant state degrades to `unreported` or the last good report
- Verification: `unit`

### Requirement: Attribution rests on published qualified identity, never on splitting a string

An entry MUST be attributed to an installed tap only when that tap **publishes** the exact
`(kind, token)` the entry names, decided by the same published-identity rules `tap-management` already
uses to relate a qualified token to a tap record. Attribution MUST NOT be performed by splitting the
entry on `/` and reading the first two components as a tap: a real `formulae` entry is URL-shaped, and
splitting it yields components that are not a tap and were never published by one.

An entry that does not attribute MUST NOT be attributed to the nearest, first, or most likely tap, and
MUST NOT be discarded. It MUST become an unattributed entry under the accounting requirement below.

A bare name MUST NOT match a qualified entry. A grant for `acme/tools/widget` MUST NOT mark
`homebrew/core/widget`, an installed `widget` whose tap is a different tap, or a package whose tap the
installed snapshot withholds. Where the identity cannot be established exactly, the state MUST be
`noGrantRecorded`, never `granted`.

#### Scenario: A qualified entry attributes to the tap that publishes it

- GIVEN installed tap `acme/tools` publishing cask token `acme/tools/widget`, and a report listing that exact cask entry
- WHEN attribution runs
- THEN the entry attributes to `acme/tools`, and that cask's state is `granted`
- Verification: `unit`

#### Scenario: A URL-shaped formula entry is never split into a tap

- GIVEN a report whose `formulae` list contains `https://github.com/cloudmanic/spice-edit/spice-edit`
- WHEN attribution runs against every installed tap
- THEN no tap is derived from its first two slash-separated components
- AND the entry is carried forward as unattributed rather than dropped
- Verification: `unit`

#### Scenario: A same-named package under another tap is not claimed

- GIVEN a report listing formula `acme/tools/widget`, and installed formula `widget` from tap `other/tools`, and catalog formula `widget` from `homebrew/core`
- WHEN each package's state is read
- THEN both are `noGrantRecorded`
- AND neither is marked from the bare name `widget`
- Verification: `unit`

### Requirement: Every decoded entry is accounted for, including namespaces Cellar does not model

Decoding MUST cover all four published top-level namespaces — `taps`, `formulae`, `casks` and
`commands`. Every decoded entry MUST land in exactly one accounted category: **attributed** to an
installed tap; **excluded** (a `taps` entry for an installed tap, which is a *tap* grant and MUST NOT
feed any package count, marker or badge — `tap-management` TM12 keeps a tap's own state coming from
`tap-info` alone); or one of the unattributed categories — an **orphan tap grant** (a `taps` entry for
a tap that is not installed), an **unmatched package grant** (a `formulae` or `casks` entry no
installed tap publishes), or **other** (every `commands` entry, and every entry whose namespace this
capability does not model). The categories MUST partition the decoded set: their totals MUST sum to the
number of entries decoded, and no entry MUST be dropped silently. The exclusion MUST be a **stated**
exclusion, asserted by test; a documented exclusion is not a drop.

The namespaces MUST NOT be assumed disjoint. The same qualified identifier can appear in **both**
`formulae` and `casks` — measured on a real Mac (`gentleman-programming/tap/engram`, Engram `#7764`) —
and each occurrence is a distinct entry about a distinct package kind. Both MUST be decoded, accounted
and rendered independently; neither MUST deduplicate, displace, overwrite or mask the other, and a
grant for one kind MUST NOT mark the other kind. An entry name MUST NOT be assumed to exclude `@`
(`guria/tap/nehir@rc` is a real entry), and a namespace present with an **empty** array MUST be
distinguished from a namespace that is absent: an empty `commands` array is a report of nothing, not a
missing key.

The unattributed categories MUST be a **shipped surface**, presented in a dedicated section of the Taps
surface rather than only counted internally. A payload carrying a top-level key this capability does
not model MUST NOT fail the decode, and its entries MUST be counted as **other** when they decode as a
list of qualified strings, on exactly the unknown-key tolerance `tap-management` TM2 already applies.

#### Scenario: The accounting partitions the decoded set

- GIVEN a report with two `taps` entries (one installed, one not), three `casks` entries (two published by installed taps), one URL-shaped `formulae` entry and one `commands` entry
- WHEN the accounting is produced
- THEN the totals are: attributed 2, excluded tap grants 1, orphan tap grants 1, unmatched package grants 2, other 1
- AND those totals sum to the 7 entries decoded, every entry appears in exactly one category, and no `taps` entry contributes to any package count
- Verification: `unit`

#### Scenario: The same identifier in two namespaces is two entries

- GIVEN a report whose `formulae` and `casks` lists both contain `gentleman-programming/tap/engram`, and whose `casks` list also contains `guria/tap/nehir@rc`
- WHEN the accounting is produced and each package's state is read
- THEN both `engram` entries are decoded and accounted separately, one as a formula and one as a cask
- AND neither deduplicates or masks the other, a grant for one kind does not mark the other kind, and the `@` in `nehir@rc` neither truncates the name nor fails the decode
- Verification: `unit`

#### Scenario: The commands namespace is counted, never dropped

- GIVEN a report whose only entries are in `commands`, and separately a report whose `commands` is an empty array while other namespaces carry entries
- WHEN the accounting is produced and the unattributed section is presented
- THEN the first counts those entries as other and the section is non-empty
- AND the second is accounted as a report of nothing in `commands`, distinguishably from a payload with no `commands` key, and neither report is presented as empty
- Verification: `unit`

#### Scenario: An unmodelled namespace does not fail the decode

- GIVEN a payload carrying `taps`, `formulae`, `casks`, `commands` and an additional top-level key whose value is a list of qualified strings
- WHEN it is decoded
- THEN the decode succeeds, the four known namespaces are accounted for as usual, and the additional key's entries are counted as other
- AND no entry from the additional key is discarded without being counted
- Verification: `unit`

#### Scenario: A real report on a real Mac accounts for every entry

- GIVEN a Mac running Homebrew 6 whose `brew trust --json v1` lists entries in more than one namespace
- WHEN the raw payload is captured, the read is run again, and the payload is compared with the accounting Cellar produces from it
- THEN the entry count Cellar accounts for equals the entry count the payload carries
- AND Homebrew's trust ledger is byte-identical before and after the read, so the read granted nothing
- AND the captured payload and both counts appear in the verify report
- Verification: `manual-evidence`

### Requirement: One projection value supplies the count, and the marker states an exact fact

Exactly **one** projection value MUST supply the per-tap count consumed by both the tap list row and
the tap detail header, so the two cannot drift — the same one-projection rule `tap-management` TM12
applies to the badge. That value MUST count only the entries attributed to **that** tap, and MUST NOT
include an unattributed entry, an entry belonging to another tap, or an orphan grant.

Where present, the count line's exact copy MUST be “\(n) trusted individually”. It MUST be **absent**
— not `0`, not a placeholder, not an empty row — when the tap's attributed count is zero and when the
report is `unreported`.

A package the report marks `granted` MUST carry the exact marker copy “Trusted individually” on the
tap detail package row for that package. A package whose state is `noGrantRecorded` or `unreported`
MUST carry **no marker at all**. The marker MUST be additive: it MUST NOT replace, suppress or reword
the three install states `tap-management` TM1 pins for those rows.

#### Scenario: Row and header read one value

- GIVEN a tap with two attributed grants
- WHEN the count consumed by the list row and by the detail header is compared
- THEN both come from the same projection value and both render exactly “2 trusted individually”
- Verification: `unit`

#### Scenario: Zero and unreported both render no count line

- GIVEN one tap with a decoded report and no attributed grants, and the same tap with the report `unreported`
- WHEN each is projected
- THEN neither carries a count line
- AND no rendering contains “0 trusted individually”
- Verification: `unit`

#### Scenario: The count is scoped to its own tap

- GIVEN taps `acme/tools` and `other/tools`, a report granting one package published by each, one orphan tap grant and one unmatched package grant
- WHEN each tap's count is projected
- THEN each is exactly 1
- AND neither includes the orphan grant nor the unmatched grant
- Verification: `unit`

#### Scenario: The marker is additive on the package row

- GIVEN a tap detail row for a package that is `granted` and installed, and a second row for a package that is `granted` and reports the withheld-tap middle state
- WHEN both rows are projected
- THEN each carries the exact marker copy “Trusted individually”
- AND each still carries its own unchanged install-state copy and its Show in Installed handoff
- Verification: `unit`

### Requirement: Per-package copy is positive-only and is never a verdict

Every user-facing string this capability produces about a package MUST state a grant Homebrew records.
There MUST be no rendering for "this package has no individual grant" — no badge, no marker, no muted
row, no tooltip and no empty state — because absence from the report is not a fact about trust. No
string MUST state or imply that a package is untrusted, unsafe, unverified, or less safe than another.

This capability MUST NOT inspect, analyse, score or judge a package's contents, and MUST NOT derive a
recommendation for or against granting, revoking or installing anything — the same rule
`tap-management` TM11 already binds the tap surface to. Everything it presents MUST be either the state
brew reported or an accounting of it.

The two report-level states MUST be distinguishable in copy, and those strings are about the **report**,
not about any package: an `unreported` report MUST carry the exact copy “This Homebrew does not report
per-package trust.” and a decoded report with no entries MUST carry the exact copy “Homebrew records no
packages trusted individually.”

#### Scenario: Every per-package string is positive

- GIVEN every user-facing string this capability can produce about a package
- WHEN they are enumerated
- THEN each states a grant Homebrew records
- AND none states or implies that a package is untrusted, unsafe, unverified or unprotected
- Verification: `unit`

#### Scenario: A package with no individual grant renders nothing

- GIVEN a package whose state is `noGrantRecorded`, and a package whose state is `unreported`
- WHEN every surface this capability contributes to is projected for each
- THEN neither contributes any marker, badge, row, note or placeholder for that package
- Verification: `unit`

#### Scenario: Unreported and reported-empty are distinguishable in copy

- GIVEN a machine whose report is `unreported`, and a machine whose decoded report carries no entries
- WHEN the per-package trust surface is presented for each
- THEN the first renders exactly “This Homebrew does not report per-package trust.”
- AND the second renders exactly “Homebrew records no packages trusted individually.”
- AND neither renders the other's copy, and neither renders a count of `0` for the other's state
- Verification: `unit`

#### Scenario: Nothing derives a verdict or a recommendation

- GIVEN everything this capability presents
- WHEN each item is enumerated
- THEN each is either the state brew reported or an accounting of it
- AND nothing inspects, scores, or recommends for or against a package or a grant
- Verification: `unit`

### Requirement: This capability grants and revokes nothing

No control, affordance, menu item, recovery, retry or automatic path in this capability MUST submit a
trust or untrust command naming a package. The prohibition is a property of the whole surface, not of
any one screen, and MUST be asserted as an **absence** by test rather than left to review.

The reason is mechanical, not stylistic: Homebrew treats *naming* a `/`-qualified package to its trust
machinery **as the grant**, which is why `package-mutation` PM10 forbids a qualified token in any argv
the shared mutation spine spawns. That prohibition MUST remain unchanged by this capability, and no
argv element anywhere MUST gain a second `/`. This capability's own read carries none.

This capability MUST NOT be used to decide whether another capability may act. It MUST NOT gate,
disable, delay or pre-block a mutation, an install, an upgrade or a tap action on a package's
per-package state; `package-mutation` PM10 owns that prohibition and this change extends its
source-scanning absence to the type names introduced here.

#### Scenario: No path submits a package trust command

- GIVEN every control, affordance and automatic path this capability exposes, including each surface it contributes to
- WHEN every command each can submit is enumerated
- THEN none is a trust or untrust command naming a package
- AND the enumeration is non-vacuous: it covers every control the capability exposes
- Verification: `unit`

#### Scenario: No argv element gains a second slash

- GIVEN every argv this capability can build, together with every argv the shared mutation spine can build
- WHEN every element is enumerated
- THEN no element contains two or more `/` characters
- AND the assertion that proves it over the mutation spine is unchanged by this capability
- Verification: `unit`

#### Scenario: The surface exposes display only

- GIVEN the per-package trust surface, including the unattributed grants section
- WHEN every interactive element it offers is enumerated
- THEN each is a navigation, filter, copy or refresh affordance
- AND none grants, revokes, installs, upgrades or removes anything
- Verification: `unit`

### Requirement: Orphan grants are surfaced plainly, and the surface does not claim to close them

A `taps` entry for a tap that is not installed MUST be presented as an **orphan grant**, in the
unattributed section, with the tap it names. Per-package grants survive an untap, so `tap-management`
TM7's revocation — which exists precisely so that a re-tap cannot silently re-arm a dormant grant —
does not reach them, and a later re-tap re-arms an orphan grant without new consent.

The surface MUST say that plainly rather than implying it has closed the hole. Its exact copy MUST be
“Homebrew still records these grants. Cellar shows them; it does not remove them.” It MUST NOT offer,
imply or hint at a control that would remove one, and MUST NOT describe the grant as expired, stale,
inactive or harmless.

#### Scenario: A grant for an uninstalled tap is an orphan

- GIVEN a report whose `taps` list names a tap the installed tap snapshot does not contain
- WHEN the accounting is produced
- THEN that entry is presented as an orphan grant naming that tap
- AND it is counted in the unattributed totals, not in any tap's count
- Verification: `unit`

#### Scenario: The orphan copy is exact and offers nothing

- GIVEN a non-empty set of orphan grants
- WHEN the section is presented and its controls are enumerated
- THEN it renders exactly “Homebrew still records these grants. Cellar shows them; it does not remove them.”
- AND no control it offers would remove, revoke or alter a grant
- Verification: `unit`

#### Scenario: A per-package grant survives an untap on a real Mac

- GIVEN a Mac running Homebrew 6 with a third-party tap installed and one of its packages granted individually, listed by `brew trust --json v1`
- WHEN that tap is untapped from inside Cellar and the report is read again
- THEN the package entry is still listed
- AND Cellar presents it as an orphan or unmatched grant rather than dropping it
- Verification: `manual-evidence`

## Notes for archive

- This delta **establishes** `openspec/specs/package-trust/spec.md`. Promote the eight ADDED
  requirements in order as PT1–PT8, add the file header, the `## Requirements` wrapper and a
  `## Provenance` section recording this change, its binding decisions and what they rejected:
  per-package grant/revoke controls (they require a `/`-qualified token in argv, which PM10 forbids as
  an absence, and the `brew untrust <qualified>` probe is unmeasured), extending `tap-info` rather than
  adding a second read (it does not publish per-package grants), a dedicated invalidation domain
  (design decision **DD-3**: no Cellar command can mutate a per-package grant, so the domain would be
  dead declaration surface across every command family — the grant read rides `.taps` instead), and any
  negative per-package copy.
- Record the measured payload facts PT4 rests on (Engram `#7764`), because they are cheap to lose and
  expensive to re-derive: the namespaces are **not disjoint**, a package name can carry `@`, a
  namespace can be present-and-empty, and the bare read is side-effect free. The captured payload is
  the apply-phase fixture; it MUST NOT be re-invented.
- The `README.md:44-47` qualified-token sweep folded into this change is **doc-only**. It writes no
  spec delta: `release-distribution` D-2's canonical three-line install is untouched, and no requirement
  in that capability is added, modified, removed or renamed by it.
- `BrewfileDiff.isPresent` (**R15**) is deliberately **not** in this change and writes no delta here.
