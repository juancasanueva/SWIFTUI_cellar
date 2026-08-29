# Proposal: npm as a second package source (`npm-package-source`)

PRD anchor: **M13 — npm package source** (`PRD.md` §7). Exploration: `explore.md` / Engram `sdd/npm-package-source/explore`. Decisions: Engram `sdd/npm-package-source/decisions`.

## Intent

Users who manage tooling with both Homebrew and global npm packages must leave Cellar for `npm outdated -g` / `npm update -g`. M13 makes Cellar show and apply both sets of updates from one Updates list, without weakening the brew-only guarantees existing users rely on.

## Scope

### In Scope (one PR, three ordered work units)

1. **Read-only inventory**: `NpmLocator` (priority: configured path > Homebrew > Node.pkg `/usr/local` > Volta > fnm default > nvm default > mise), `NpmDetectionStore`, `NpmEnvironment`, `NpmPayloadSource` + decoder (`npm ls -g --json --depth=0`, `npm outdated -g --json` accepting exit 0/1), `PackageKind.npm`, Settings "Enable npm source" toggle (default off) with path/version/prefix, Source chip in `InstalledFilterBar`, NPM tag in `PackageRow`.
2. **Mutations**: `BrewRunner` generalised to executable + environment; `OperationCenter` holds source-keyed runners; `source` projection on `BrewMutating` (default `.homebrew`, copied by `AnyBrewMutation`); `NpmCommand` (upgrade, uninstall with `.packageRemoval` confirmation) with its own `classify` (`EACCES/EPERM` → `needsPrivileges`); `.npmInventory` invalidation bit + refresh gate; source-aware history/activity wording.
3. **Copy and offline states**: Home card, menu bar, Health and empty-state copy distinguish "brew up to date, npm not checked (offline)". Independent `npm outdated` cadence; offline never renders as up to date.

### Out of Scope

- Per-project `node_modules`, `npx`, install-from-search of npm packages.
- Multiple npm binaries at once (one selected npm, user-overridable).
- npm in Cleanup, disk usage, Security/CVE, Brewfile, catalog Discover.
- Persisted schema changes: `"npm"` round-trips through existing `kindRaw` strings.

## Capabilities

### New Capabilities
- `npm-source`: npm detection, environment composition, global inventory/outdated reading, npm mutation commands and outcome classification, enable toggle.

### Modified Capabilities
- `installed-inventory`: merged inventory contains npm entries; Source filter; offline "not checked" state.
- `package-mutation`: `source` projection; `PackageTarget` rejects npm ids (brew argv can never name an npm package).
- `brew-execution`: runner generalised over executable + environment; per-source runners.
- `operation-activity`: activity rows carry source; display command prefix derives from source.
- `installation-history`: rows carry a source badge and source-aware outcome labels.
- `brew-detection`: detection state model gains an npm sibling (no widening of brew types).
- `menu-bar`, `system-health`: source-aware counts and copy (work unit 3).

## Approach

Hybrid approach C. Identity is cheap: `PackageKind.npm` keys favourites, snooze, history and counts through `PackageID` with no migration. Execution is clean: source-keyed runners, per-source env/locator/payload source, `NpmStore` feeding the one read-model. ~13 exhaustive `PackageKind` switches are extended; catalog paths treat `.npm` as never present. `NpmCommand.swift` sits at top level in `BrewClient` so the structural argv tests cover it automatically.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Sources/Catalog` | Modified | `PackageKind.npm`; roster/analytics/sync switches |
| `Packages/CellarCore/Sources/BrewProcess` | New/Modified | `NpmEnvironment`, `NpmLocation`, `DefaultNpmLocator`, `NpmDetectionStore`; `BrewRunner` init |
| `Packages/CellarCore/Sources/BrewClient` | New/Modified | `NpmCommand`, `NpmPayloadSource`, `NpmDecoder`, `NpmStore`; `BrewMutating`, `OperationCenter`, `MutationOutcome`, `BulkSelection` |
| `Packages/CellarCore/Sources/Persistence` | Modified | `HistoryPresentation` wording |
| `cellar/` app target | Modified | `cellarApp` wiring, Installed, Settings, Home, Sidebar, Health, menu bar views |
| `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Npm/` | New | npm stdout/stderr fixtures |
| `cellar.xcodeproj` | Unchanged expected | All new files live in SwiftPM targets; no target-membership edits planned |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `npm outdated` slow/offline reads as "up to date" | High | Separate cadence; tri-state result (`fresh`, `notChecked`, `failed`); offline copy in unit 3 |
| GUI PATH lacks `node`; npm cannot launch | High | `NpmEnvironment` prepends resolved bin dir; structural env test |
| Exit-code semantics (exit 1 = outdated present) | Med | Dedicated adapter; never reuse `InstalledPayload` non-zero rule |
| `PackageKind` in brew-free `Catalog` becomes source-bearing | Med | Record as ownership debt; catalog code treats `.npm` as never present |
| Brew argv accidentally names an npm package | Low | `PackageTarget.init?` rejects `.npm`; argv tests |
| Existing users see changed surfaces | Low | Toggle defaults off; all npm surfaces gated on `isEnabled && detected` |
| Review load (~4.5–6k lines, budget 8,000) | Med | Three ordered work units, each with its own tests and rollback |

## Rollback Plan

- No `cellar.xcodeproj` or target-membership change is planned. If one becomes necessary (e.g. a new app-target file), it must be an isolated commit; rollback is `git revert` of that commit plus removal of the file.
- Work units are independently revertible in reverse order (3 → 2 → 1); unit 1 alone leaves a hidden-by-default feature.
- Persistence: no schema migration; `"npm"` history rows remain decodable and are hidden if the kind case is reverted (decoder returns nil).
- Setting default off means disabling the toggle restores pre-M13 behaviour at runtime.

## Dependencies

- Test fixtures captured from npm/cli `latest` (`npm --version`, `ls -g`, `outdated -g`, `prefix -g`, `install -g`, `uninstall -g`).

## Success Criteria

- [ ] With the toggle off, every existing screen, count and test is byte-identical in behaviour.
- [ ] With the toggle on and npm detected, Installed/Updates show npm globals with Source filter and NPM tag; Settings shows path, version and prefix.
- [ ] Upgrade/uninstall of an npm package runs through the queue, activity log and history with `npm` wording; no brew argv ever contains an npm name (structural test).
- [ ] Offline, the Updates lens says "npm not checked", never "up to date"; brew status is unaffected.
- [ ] PRD M13 exit met: a user with both sources applies both sets of updates from one Updates list.

## Open Questions

1. May brew and npm mutations run concurrently (two FIFO runners) or must `OperationCenter` serialise across sources?
2. Upgrade verb: `npm update -g <name>` (respects semver range, may skip majors) vs `npm install -g <name>@latest` (needs a validated spec token under the structural argv rule).
3. Should Health include an npm signal in v1, or only copy adjustments?
