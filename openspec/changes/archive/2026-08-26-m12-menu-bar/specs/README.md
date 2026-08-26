# Spec index — `m12-menu-bar`

**Three** delta files. Hybrid store: these files are canonical; Engram topic `sdd/m12-menu-bar/spec` is
the searchable mirror. Written from `proposal.md` (Engram obs `#7820`, approved by the maintainer
2026-08-25) over `explore.md` (obs `#7819`, as-of `main` @ `f2efbdd`).

| Capability | Op | Block | Scenarios | Net |
|---|---|---|---|---|
| `menu-bar` | **ADDED** — new capability, no `openspec/specs/menu-bar/spec.md` exists | 10 new requirements | +25 (12 `unit`, 13 `unit-app`) | 0 → **10** requirements, 0 → **25** scenarios |
| `installed-inventory` | **ADDED** — one requirement generalising the count's single-projection duty | 1 new requirement; all 15 shipped requirements and all 79 shipped scenarios untouched | +3 (1 `unit`, 2 `unit-app`) | 15 → **16** requirements, 79 → **82** scenarios |
| `service-management` | **MODIFIED** — "The services surface polls only while visible, on an injected clock" | whole block, all 4 existing scenarios byte-identical, one added paragraph | +1 (`unit`) | 12 requirements unchanged, 40 → **41** scenarios |

**Totals: 11 ADDED requirements, 1 MODIFIED block across 3 capabilities, 0 REMOVED, 0 RENAMED — 29 new
scenarios (14 `unit`, 15 `unit-app`, **0** `ui`).** No requirement is removed or renamed, so
`rules.archive`'s destructive-delta warning does not fire.

## Verification classes

Both names are already established in this repository; this change introduces none.

| Class | Meaning | Runner |
|---|---|---|
| `unit` | RED-first assertion over an observable `CellarCore` behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom that reads the repository source off disk — the established class for app-target composition and source-scan assertions | `xcodebuild test … -only-testing:cellarTests` |

**No `ui` scenario exists in this change, deliberately.** A `MenuBarExtra` status item lives in the
system status bar, which `XCUIApplication` does not reach reliably, and this project already has a
recorded UI-test flakiness history. Every claim in these deltas is provable by `unit` or `unit-app`.

`service-management` carries **no** `## Verification classes` table today and its four shipped scenarios
carry no `- Verification:` lines; this change adds none to them, which is exactly what keeps them
byte-identical. Only the scenario it adds carries one. Each delta's own table is delta-local provenance;
the per-scenario inline `- Verification:` lines promote with their requirements, following the precedent
`2026-08-23-m7-tap-trust` recorded at `openspec/specs/installed-inventory/spec.md:1122-1184`.

## The `config.yaml:47` split, applied

`rules.specs` requires specs to "specify observable behavior of CellarCore types without referencing
SwiftUI views", and most of a menu bar is app-target scene composition. The split these deltas use is
the one `system-health`, `package-search` and `release-notes` already use:

- the **projection** — the count, the top-five entries, the remainder, the status title, the per-service
  control sets — is `CellarCore` behaviour, specified as such and proved by `unit`;
- the **scene wiring** — insertion under the preference, the repeated theme environment, the token
  prohibitions, the shell literals, the Settings row and `Open Cellar` — is proved by `unit-app`
  composition and source-scan assertions, and is described as surfaces, entries and copy rather than as
  view types.

No requirement in these files names a SwiftUI view type.

## `package-mutation`: activated, not changed — no delta

m12 adds **no** `package-mutation` delta, exactly as the proposal states. `MutationCommand.upgradeAll`
already lowers to a bare `brew upgrade` (`spec:180-186`) and already requires no confirmation
(`spec:245-251`). The menu bar **activates** both by submitting that shipped command unchanged; a
MODIFIED block would restate a requirement that already says the right thing. Record this at archive as
*activated, not changed*.

## `installed-inventory`: compliance, not a behaviour change, at II12

D1 brings the sidebar badge and the Home attention card onto `InstalledBrowse.outdatedCount(metadata:)`.
That is **compliance with shipped text** — "Snoozed packages leave the outdated section and its count"
(`spec:495-505`) already forbids a snoozed package from contributing to "the outdated count **or
badge**" — so that requirement is **untouched** and gets no MODIFIED block. The new requirement is the
*generalisation* that makes a third consumer safe to add. Health is deliberately **not** migrated onto
the new projection: `HealthComposition.swift:71` already reads the snooze-aware set, so it is compliant
already and its expectations must not move.

## Excluded from these deltas, deliberately

- **Any freshness cue.** Bound decision 6: the surface presents last-known state without annotating its
  age. Proposal risk R5 is accepted rather than specified away.
- **Any `ui` scenario over the status item**, and any new `--ui-testing-*` fixture flag for it.
- **A `settings` capability requirement.** There is no `settings` spec, and this change does not create
  one: the `Show in menu bar` row and the amended doc comment are `unit-app` obligations of `menu-bar`.
- **Any background check, login item, schedule or notification requirement.** PRD `:114-115` non-goals;
  the `SettingsView` rule still forbids a row for a capability that does not exist.
- **Any change to the services poll's gating conjunction.** The `service-management` clause licenses a
  secondary surface by forbidding it from reporting visibility, not by adding a third half.
- **A new `AppSection`.** The menu bar is a scene; the shell's section count and the main content view's
  switch count are pinned unchanged as a `unit-app` scenario.
