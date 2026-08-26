# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (**15 requirements / 79 scenarios**,
established by `2026-08-02-m2-installed-inventory`, amended by `2026-08-23-m7-tap-trust`,
`2026-08-24-m9-per-package-trust`, `2026-08-24-m10-third-party-detail` and `2026-08-25-m11-tap-search`).

This delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**. **Every shipped requirement and every one
of the 79 shipped scenarios is untouched and byte-identical** — none is copied into this file, because
nothing in this change edits one. The capability becomes **16 requirements / 82 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire.

**Why an ADDED requirement rather than a MODIFIED one.** Two shipped requirements already bind each
count-bearing surface individually:

- **Snoozed packages leave the outdated section and its count** (`spec:495-505`) already states that a
  snoozed package "MUST NOT contribute to the outdated count **or badge**". The sidebar badge
  (`SidebarView.swift:217-219`) and the Home attention card (`HomeView.swift:142`) filter the installed
  packages themselves and are therefore **already non-compliant** with it. Bringing them onto
  `InstalledBrowse.outdatedCount(metadata:)` is **compliance with shipped text**, not new behaviour, so
  that requirement needs no edit and gets none.
- **A bulk action's label counts exactly the set it submits** (`spec:647-652`) says the same thing for
  exactly one kind of control: a bulk action's label. It is silent about a badge, a sentence or a status
  item, none of which submits anything.

The genuine gap is the **generalisation**: no shipped requirement says that *every* surface announcing
the number must derive it from the *one* projection. m12 adds a **third** consumer of that number, so
the gap stops being theoretical. The requirement below closes it without restating either shipped rule
and without touching their text.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m12-menu-bar/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable `CellarCore` behaviour | `swift test --package-path Packages/CellarCore` | **1** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` source-scan idiom | `xcodebuild test … -only-testing:cellarTests` | **2** |

## ADDED Requirements

### Requirement: Every surface that announces the outdated count derives it from one snooze-aware projection

Any surface that announces **how many** installed packages are outdated MUST derive that number from
`InstalledBrowse.outdatedCount(metadata:)`, and any set of outdated packages it presents alongside MUST
be `InstalledBrowse.outdatedIDs(metadata:)`, evaluated over the same inventory and the same metadata
lookup. This binds a sidebar badge, a home attention sentence or card, a menu-bar status item, and any
future count-bearing surface alike.

No such surface MUST compute the number for itself. In particular it MUST NOT filter the installed
packages by `InstalledPackage.isOutdated`, MUST NOT read the snapshot's own outdated flag, and MUST NOT
read `InstalledInventory.outdatedIDs` or `InstalledInventory.outdatedCount` without the snooze
exclusion — those are the inputs the projection consumes, not answers a surface may consume directly.

It MUST be **impossible for two surfaces to announce two different outdated numbers** for one inventory
and one metadata lookup. Agreement MUST be structural rather than coincidental: a surface that
reimplemented the derivation and happened to agree today would still violate this requirement, because
the next rule added to the projection would silently pass it by. This is the same failure the
`upgradableIDs` projection was created to prevent, generalised from one bulk control to every surface
that states the number.

Where a surface presents both a count and a set — a badge beside a list, a status title above entries —
the two MUST come from that one projection, so the set a user reads can never be inconsistent with the
number they were shown.

#### Scenario: The sidebar badge, the Home attention card and the menu bar read one projection

- GIVEN the sources of the sidebar, the home attention surface and the menu-bar surface
- WHEN each one's outdated number is traced to its source
- THEN each derives it from `InstalledBrowse.outdatedCount(metadata:)` with the app's metadata lookup
- AND none of the three filters the installed packages itself or reads `InstalledPackage.isOutdated`
- Verification: `unit-app`

#### Scenario: No surface in the app announces a self-computed outdated count

- GIVEN every `.swift` source in the app target, with comments stripped so a rule described is never
  mistaken for one violated
- WHEN they are scanned for a count or set of outdated packages computed by filtering the inventory
- THEN no such derivation exists in any surface
- AND every remaining reference to the un-snoozed inventory count is inside the projection that owns the
  snooze exclusion
- Verification: `unit-app`

#### Scenario: The count and the set a surface presents cannot disagree

- GIVEN an inventory with one snoozed outdated package, one outdated self-updating cask and three other
  outdated packages, and the metadata lookup recording the snooze
- WHEN the projection's count and its set are read together
- THEN the count is 3 and the set is exactly those three packages
- AND the count equals the size of the set, so a surface presenting both states one consistent fact
- Verification: `unit`
