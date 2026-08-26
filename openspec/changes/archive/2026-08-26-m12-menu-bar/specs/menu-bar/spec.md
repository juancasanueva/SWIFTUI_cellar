# Delta for menu-bar

**New capability** — there is no `openspec/specs/menu-bar/spec.md` yet, so this delta is **ADDED-only**:
**10 requirements / 25 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED, so `rules.archive`'s
destructive-delta warning does not fire.

This capability owns the *optional status item*: the value the surface reads, the opt-in preference
that inserts it, what the popover may and may not do, the services contract it honours, and how it
reaches the main window. It does **not** own outdated-ness — that stays `installed-inventory`'s — and
it does **not** own the services poll, which stays `service-management`'s.

Per `openspec/config.yaml:47`, the **projection** is specified as observable behaviour of a `CellarCore`
value and proved by `unit`; the **scene wiring** is proved by app-target composition and source-scan
assertions (`unit-app`), the split `system-health`, `package-search` and `release-notes` already use.
"Surface", "entry", "row" and "copy" name projected values and their text, not view types.

Bound maintainer decisions, 2026-08-25 (D1–D4 in `proposal.md`, all binding and all carried here):
badge alignment onto the snooze-aware projection; an **uncounted** `Upgrade all` submitting bare
`brew upgrade`; last-known services status with **one** refresh on open and **no** poll; **off by
default**. Five further bound decisions land below: no `0` at zero, top **5** in name order, no
freshness cue, no confirmation and no egress, and `Open Cellar` through the shipped `openWindow(id:)`.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m12-menu-bar/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable `CellarCore` behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` | **12** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions | `xcodebuild test … -only-testing:cellarTests` | **13** |
| `ui` | XCUITest | `xcodebuild test …` | **0** — deliberately. A status item lives in the system status bar, which `XCUIApplication` does not reach reliably, and this project has recorded UI-test flakiness. Every claim below is provable without one |

## Copy pinned by this delta

| Fact | Exact copy | Condition |
|---|---|---|
| Settings row | `Show in menu bar` | always — the one row this change adds |
| Bulk upgrade entry | `Upgrade all` | always, **with no count anywhere in the label** |
| Remainder line | `and M more`, and `and 1 more` in the singular | only when more outdated packages exist than the five presented |
| Main-window entry | `Open Cellar` | always |
| Service controls | **no copy pinned here** — `Stop`, `Restart`, `Start at login` and `Run once` are the shipped `ServiceRowControl` labels, reused byte-for-byte | so one service verb cannot read differently in the popover and in the Services section |
| Zero outdated | **no copy at all** | the status item presents its symbol and nothing else; `0` is not copy this capability owns, because it is never shown |
| Freshness | **no copy at all** | out of scope for this slice; the surface presents last-known state without annotating its age |

## ADDED Requirements

### Requirement: The menu-bar projection is a pure value that delegates outdated-ness rather than recomputing it

The value the menu-bar surface reads MUST be a `nonisolated`, `Sendable` value **totally derived** from
three inputs — an installed browse projection, the metadata lookup that owns snoozes, and a services
snapshot. It MUST perform no I/O, cause no brew invocation, start or schedule no refresh, consult no
catalog value, and take no process launcher, URL session or store as a dependency: there MUST be
nothing of that kind to inject into it.

Its outdated count MUST equal `InstalledBrowse.outdatedCount(metadata:)` for the same inputs, and the
outdated set it exposes MUST be exactly `InstalledBrowse.outdatedIDs(metadata:)` for the same inputs.
It MUST obtain both by **delegating** to that projection. It MUST NOT re-derive outdated-ness by
filtering the installed packages, by reading `InstalledPackage.isOutdated`, by reading the snapshot's
own outdated flag, or by reading `InstalledInventory.outdatedIDs`/`outdatedCount` without the snooze
exclusion. A reimplementation that happened to agree would still violate this requirement: agreement
must be structural, not coincidental — this is the `upgradableIDs` idiom that exists because a label
and a submission once computed one number twice.

An unavailable or empty inventory MUST yield a count of zero, no entries and no remainder, and MUST NOT
throw, present an error, or be distinguishable from a healthy inventory with nothing outdated. This
capability adds **no** freshness cue in this slice: the value states what is known, not how old it is.

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

### Requirement: At most five outdated entries, in the inventory's name order, with a remainder count

The projection MUST expose **at most five** outdated entries, drawn from **exactly** the set its count
counts, in the installed inventory's existing name order — alphabetical by name, the only order this
inventory has. It MUST NOT introduce a severity, recency or size order, because no such order exists
today and inventing one here would make the popover disagree with the Updates list.

When more outdated packages exist than the five presented, the projection MUST expose the remainder
count, so the surface can present the exact copy `and M more`, and `and 1 more` in the singular. When
five or fewer exist, it MUST expose **no remainder at all** — absence preserved as absence, never zero,
never an empty string, never a suppressed line that still occupies the value.

#### Scenario: Twelve outdated packages yield five entries and a remainder of seven

- GIVEN an inventory with twelve outdated packages and no snooze
- WHEN the projection's entries and remainder are read
- THEN exactly five entries are exposed, and they are the first five of the twelve in name order
- AND the remainder is 7
- Verification: `unit`

#### Scenario: Exactly five outdated packages expose no remainder

- GIVEN an inventory with exactly five outdated packages, and separately one with four
- WHEN each projection's entries and remainder are read
- THEN the first exposes five entries and the second four
- AND neither exposes a remainder value at all, rather than a remainder of zero
- Verification: `unit`

#### Scenario: A snoozed package appears in neither the entries nor the remainder

- GIVEN an inventory with seven outdated packages, one of them snoozed and alphabetically first
- WHEN the entries and the remainder are read
- THEN the snoozed package is absent from the entries
- AND the remainder is 1, so entries plus remainder equals the announced count exactly
- Verification: `unit`

### Requirement: The status item carries the count as text, and carries nothing at zero

The count MUST reach the status item as a **title string** beside a symbol. It MUST NOT be composed as
a rendered badge image, and this capability MUST NOT introduce an image renderer, a drawn badge or an
AppKit status-item image path for it.

When the count is zero the title MUST be **absent**: the status item presents its symbol alone. It MUST
NOT show `0`, a dash, an empty title, or any other placeholder standing for "nothing outdated". The
projection MUST expose that absence as absence, so the surface never decides it locally.

#### Scenario: The title is the count, and is absent at zero

- GIVEN projections over inventories with three outdated packages and with none
- WHEN each projection's status title is read
- THEN the first is exactly `3` and the second is absent
- AND the absent one is not the string `0` and not the empty string
- Verification: `unit`

#### Scenario: The scene renders the title and no badge image

- GIVEN the menu-bar scene's declaration and every source file under the menu-bar directory
- WHEN the status item's label and those sources are scanned
- THEN the label is built from the projection's status title and from no locally composed count
- AND no `ImageRenderer`, no `NSImage` composite and no `NSStatusItem` appears in them
- Verification: `unit-app`

### Requirement: Upgrade all is uncounted, submits the bare command, and discloses it

The surface MUST offer exactly one bulk upgrade affordance, labelled with the exact copy `Upgrade all`
and **carrying no count**: no interpolated number, no parenthesised total, no pluralised package
noun. The badge carries the number; the button carries none. This is what satisfies
`installed-inventory`'s "A bulk action's label counts exactly the set it submits" **by construction** —
a label with no count cannot announce a number different from the set `brew upgrade` acts on.

It MUST submit `MutationCommand.upgradeAll` and nothing else. It MUST NOT fan out over the projection's
entries, MUST NOT submit a per-package upgrade, and MUST NOT introduce a new command family, a new argv
shape or a new brew invocation.

It MUST disclose the exact command it will run, taken **verbatim** from the shipped command's own
display command and presented with the shipped copy affordance. The surface MUST NOT compose that
string locally, so the popover and the installed list cannot disclose two different commands for one
submission.

#### Scenario: The label carries no count and the submission is the bare command

- GIVEN a projection announcing a non-zero outdated count, and the menu-bar sources
- WHEN the bulk upgrade affordance's label, its submission and its disclosed command are read
- THEN the label is exactly `Upgrade all` and contains no numeric interpolation
- AND the submission is `MutationCommand.upgradeAll`, with no per-package fan-out and no new command
  family declared
- Verification: `unit-app`

#### Scenario: The disclosed command is the shipped one, worded nowhere here

- GIVEN the menu-bar sources
- WHEN they are scanned for the disclosed command string and for the copy affordance
- THEN the command comes from `MutationCommand.upgradeAll.displayCommand` and the affordance is the
  shipped `CopyCommandButton`
- AND no literal `brew upgrade` string is composed in these sources
- Verification: `unit-app`

### Requirement: Services are shown from last-known state, refreshed exactly once on open, and never polled

The surface MUST present the **last-known** services status. On appearance it MUST perform **exactly
one** services refresh, and MUST NOT start, extend, restart or schedule a poll of any cadence. It MUST
NOT report visibility to the coordinator that owns the services poll, so the shipped visibility
conjunction gains no third half and the Services section's own polling behaviour is byte-unchanged.

That one refresh MUST be skipped entirely while a service mutation is in flight, so a restart in
progress cannot flicker. It is the **only** asynchronous work this surface is permitted to perform.

Closing the popover MUST cancel nothing the Services section owns and MUST leave no poll running. A
services state the surface cannot obtain MUST be presented as the ordinary last-known state, never as
an error and never as an empty list standing for a failure.

#### Scenario: Opening refreshes once and leaves no poll behind

- GIVEN the menu-bar sources and the app's services wiring
- WHEN they are scanned for refresh call sites, poll cadences and visibility reporting
- THEN exactly one services refresh call site exists, on appearance
- AND no cadence, timer or clock advance is scheduled, and no `setVisible` or `setActive` call is made
  from these sources
- Verification: `unit-app`

#### Scenario: A mutation in flight suppresses the one refresh

- GIVEN a service mutation in flight
- WHEN the surface appears
- THEN no services refresh is performed at all
- AND no refresh is queued to run when the mutation reaches its terminal outcome, because the mutation's
  own terminal refresh already answers
- Verification: `unit`

### Requirement: Service controls are two labelled sets, and never one toggle

For a service the shipped status model reports as **running**, the surface MUST offer exactly `Stop` and
`Restart`. For every other service it MUST offer `Start at login` and `Run once` as **two separately
labelled, separately submitted entries**.

It MUST NOT present a single switch, toggle or checkbox whose "on" position starts a service: "on"
would have to silently choose between registering a login item and not registering one, which
`service-management`'s "Start-at-login and run-once are distinct, explicit controls" forbids. Every
status the shipped model can report MUST map to exactly one of the two control sets, so no service is
ever presented with no controls or with both sets.

The four labels MUST be the shipped `ServiceRowControl` labels, reused byte-for-byte rather than
reworded, and no service verb, argv or applicability rule MUST be re-implemented here.

#### Scenario: A running service offers Stop and Restart

- GIVEN a running service in the services snapshot
- WHEN its offered controls are enumerated
- THEN they are exactly `Stop` and `Restart`
- AND neither `Start at login` nor `Run once` is offered
- Verification: `unit`

#### Scenario: A stopped service offers both start controls, separately labelled

- GIVEN a stopped service in the services snapshot
- WHEN its offered controls are enumerated and each one's submission is read
- THEN exactly `Start at login` and `Run once` are offered, as two entries
- AND they submit `services start <name>` and `services run <name>` respectively, so neither is a flag
  on the other
- Verification: `unit`

#### Scenario: Every reportable status maps to exactly one control set

- GIVEN one service in each status the shipped services status model can report
- WHEN the controls offered for each are enumerated
- THEN each service is offered exactly one of the two sets, never both and never neither
- AND no service is offered a single combined start/stop toggle
- Verification: `unit`

### Requirement: The surface reads; it never loads, never egresses, never confirms and shows no artwork

Every source file of this surface MUST contain **none** of the following: a `.task` loader, a `Task {`
block, `Process(`, `URLSession`, `CaskIconLoader` or `PackageIconTile`. Package artwork MUST NOT be
presented, because that pipeline reaches the network and opening a menu would fire it; an entry
presents its name and nothing that must be fetched.

The surface MUST offer **no verb that requires confirmation** — uninstall, zap and every other
confirmation-requiring verb are absent — and MUST NOT reference the shared pending-confirmation channel
at all. The reason is recorded so a later reader does not "fix" this as an oversight: that channel's
only presenter is the main window, so a request raised with no window open would latch unanswered and
block every later confirmation in the app.

The one services refresh named above is the **only** asynchronous work permitted here. These
prohibitions MUST be asserted as **absences** by the shipped source-scanning idiom, not merely
described.

#### Scenario: The menu-bar sources contain none of the forbidden tokens

- GIVEN every `.swift` source file under the menu-bar directory, with comments stripped so a
  prohibition described is never mistaken for one violated
- WHEN they are scanned for `.task`, `Task {`, `Process(`, `URLSession`, `CaskIconLoader` and
  `PackageIconTile`
- THEN none appears in any of them
- Verification: `unit-app`

#### Scenario: No confirmation-raising verb and no confirmation channel

- GIVEN the same sources and the vocabulary of verbs the surface offers
- WHEN every offered verb's confirmation requirement is read and the sources are scanned for the
  pending-confirmation channel
- THEN no offered verb requires confirmation
- AND no source references the pending-confirmation channel or presents a confirmation of its own
- Verification: `unit-app`

### Requirement: The status item is opt-in, off by default, and persisted in an injectable suite

The status item MUST be **absent by default**. With no stored preference, the app MUST behave exactly as
it does without this capability: no status item, no scene inserted, and no other observable difference.

Turning the preference on MUST insert the status item and turning it off MUST remove it, with the scene
inserted **only** under that preference and under nothing else. The choice MUST survive relaunch.

The preference MUST be persisted in `UserDefaults` through a type taking an **injectable suite**, on the
`AutomaticUpdateChecks(defaults:)` precedent, so a UI-test launch never writes the developer's real
preferences. It MUST NOT be stored in SwiftData, which this project reserves for data rather than
preferences.

Settings MUST offer exactly one row for it, with the exact copy `Show in menu bar`, and MUST NOT gain a
row for background schedules or notifications — capabilities that still do not exist. The Settings
source MUST NOT continue to state that a menu bar extra is a capability Cellar does not have.

#### Scenario: With no stored value the app is unchanged

- GIVEN a defaults suite with no stored menu-bar preference
- WHEN the preference is read and the app's scenes are enumerated
- THEN the preference is false and the menu-bar scene is not inserted
- Verification: `unit-app`

#### Scenario: The scene's insertion is bound to the preference and to nothing else

- GIVEN the app's scene declarations
- WHEN the menu-bar scene's insertion binding is read
- THEN it is bound to the menu-bar preference alone, with no other condition
- AND the preference is constructed with an injectable defaults suite rather than the standard suite
  directly
- Verification: `unit-app`

#### Scenario: Settings gains one row and stops asserting the capability is absent

- GIVEN the Settings sources
- WHEN their rows and their documentation are read
- THEN exactly one new row exists, with the exact copy `Show in menu bar`
- AND no row exists for a background schedule or a notification, and no comment states that a menu bar
  extra is a capability Cellar does not have
- Verification: `unit-app`

### Requirement: Open Cellar opens the main window, including with every window closed

The surface MUST offer an entry with the exact copy `Open Cellar` that opens the app's **main** window,
including when every window is closed. The main window scene MUST therefore carry an identifier, and the
entry MUST open it through the shipped `openWindow(id:)` route the About window already uses.

It MUST NOT introduce an AppKit activation path, an `NSApplication` or `NSApp` reference, or a second
main-window scene. Opening the main window MUST NOT be a precondition for any other entry on this
surface: the other entries work with no window open.

#### Scenario: The entry opens the main window by its scene identifier

- GIVEN the app's scene declarations and the menu-bar sources
- WHEN the main window scene's identifier and the entry's action are read
- THEN the main window scene declares an identifier and the entry opens exactly that identifier
- AND the sources contain no `NSApplication` or `NSApp` activation call
- Verification: `unit-app`

#### Scenario: No entry depends on a window being open

- GIVEN the menu-bar sources
- WHEN every entry's action is enumerated
- THEN no action other than `Open Cellar` opens, requires or checks for a window
- Verification: `unit-app`

### Requirement: The menu bar is a scene, not a section, and repeats the environment it reads

The status item MUST be a **scene** alongside the existing window scenes. It MUST NOT introduce a new
app section: the shell's section vocabulary, its case count and the main content view's switch count MUST
be unchanged, and a diff to either literal is a defect in this change rather than a licensed edit.

The scene MUST repeat every environment value its content reads — the theme store, the accent tint and
the preferred colour scheme — exactly as the About window scene repeats them, because environment
injection is per-scene rather than per-app. A scene that omits them renders in the system appearance
while the rest of the app is the design's dark surface.

The surface MUST NOT introduce a store, a refresh loop or duplicated state. It reads the same app-level
instances the main window reads, which is what makes "the menu bar and the sidebar cannot disagree" a
property of one value rather than of two view files that happen to concur.

#### Scenario: No new section and no shell literal moves

- GIVEN the shell's section vocabulary and the main content view's switch count
- WHEN both are enumerated after this change
- THEN the section case count and the exact rawValue list are unchanged
- AND the main content view's asserted switch count is unchanged, and no new section case exists
- Verification: `unit-app`

#### Scenario: The scene repeats the theme environment and owns no store

- GIVEN the menu-bar scene's declaration
- WHEN its environment modifiers and its stored properties are read
- THEN it applies the theme store, the accent tint and the preferred colour scheme, exactly as the About
  window scene does
- AND it constructs no store and no refresh loop, reading only the app-level instances the main window
  reads
- Verification: `unit-app`
