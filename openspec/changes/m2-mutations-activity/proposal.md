# Proposal: M2-2 — Mutations & Activity

## Intent

Cellar can read Homebrew but cannot change it. M2's exit criterion is "full daily package
management without Terminal"; today every install, uninstall, upgrade, and pin still means
leaving the app. `BrewRunner` already serializes mutations, but its queue is a private dict —
PRD §3.10 requires visible pending items, the exact `brew` command per operation, and streamed
logs, none of which are observable. M2-1 also shipped `InstalledMutationGate` with no caller;
mutations are the driver it was built for.

## Scope

### In Scope

- Typed mutation commands: install, uninstall, reinstall, upgrade, pin, unpin — always with explicit `--formula`/`--cask`.
- `BrewRunner` queue observability: enumerable pending/running/terminal state, stable operation identity carrying its argv.
- Activity center store + bottom activity bar + expandable streamed-log drawer; "copy command".
- Cancel UX: honest partial-state messaging, forced re-snapshot at terminal outcome.
- Upgrade single / selected / all (`brew upgrade`, brew defaults: pinned skipped, no `--greedy`).
- Confirmation for uninstall and zap only, showing the exact command.
- Sudo-requiring casks: detect the password signature, fail typed, direct the user to Terminal (stdin stays `/dev/null`).
- Absorptions: drive `InstalledMutationGate.begin()/end()`; quiet-window re-check after mutation; signal-during-inflight stale join; `clear(to:)`-while-in-flight stranding; inert catalog filters under installed/outdated Browse; extract `CellarTestSupport`.

### Out of Scope

- Favorites, notes, snooze, history, persistence (M2-3).
- Release notes, adopt, size on disk (M5).
- Privilege escalation / askpass helper (rejected).
- Real-brew mutation integration tests (fakes only).

## Capabilities

### New Capabilities
- `package-mutation`: typed mutation commands, confirmation policy, upgrade scopes, sudo-cask detection.
- `operation-activity`: queue projection, activity UI, log streaming, copy command, cancel outcome reporting.

### Modified Capabilities
- `brew-execution`: ADD enumerable queue state and stable argv-carrying operation identity.
- `installed-inventory`: mutation-driven suppression, quiet-window re-check, in-flight `clear(to:)`, inert catalog filters.

## Approach

Extend `BrewRunner` with a read-only queue projection over its existing `operations` dict — no
change to the FIFO gate or the SIGINT→SIGTERM policy. Add a `BrewClient` command builder above it,
then a `@MainActor @Observable` activity store mirroring `InstalledStore`. UI is presentational and
driven off that store. Absorptions land beside the code they touch.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `Packages/CellarCore/Sources/BrewProcess/BrewRunner.swift` | Modified | Queue projection, operation identity |
| `Packages/CellarCore/Sources/BrewClient/` | New + Modified | Mutation commands, activity store, gate wiring |
| `Packages/CellarCore/Sources/CellarTestSupport/` | New | Shared `TestClock` |
| `cellar/Activity/`, `cellar/Installed/`, `cellar/Browse/` | New + Modified | Activity bar/drawer, action affordances, filter gating |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Cancel leaves partial brew state (no SIGKILL) | High | Honest copy + forced re-snapshot |
| brew's process-external lock surface UNVERIFIED | Med | Probe in design; map to a typed failure |
| Sudo signature detection false negatives | Med | Fall back to generic failure + Terminal guidance |
| Size exceeds review budget | High | Accepted `size:exception`, ~4.5k–5k forecast |

## Rollback Plan

Revert the feature branch. `BrewRunner` changes are additive; `InstalledMutationGate` returns to
its unused-but-tested M2-1 state. No persistence, no schema, no migration to unwind.

## Dependencies

- M2-1 `m2-installed-inventory` (archived at `2fe1c0d`) — supplies `InstalledStore` and the gate.
- Accepted `size:exception` before apply.

## Success Criteria

- [ ] Install/uninstall/reinstall/upgrade/pin/unpin run from the UI with live logs and the exact command visible.
- [ ] Pending mutations are visible and cancellable before they spawn.
- [ ] Every terminal outcome (success, failure, cancel) forces one inventory re-snapshot.
- [ ] Uninstall and zap require confirmation; nothing else does.
- [ ] All five mandated absorptions have a covering test; suite green with zero concurrency warnings.
