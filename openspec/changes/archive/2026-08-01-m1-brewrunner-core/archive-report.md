# Archive report: m1-brewrunner-core

**Change**: `m1-brewrunner-core` — M1 (PRD milestone "Core & Catalog", first slice: CellarCore
foundation, `BrewRunner` actor, brew detection; catalog/Browse deferred).
**Closed**: 2026-08-01 · **Artifact store**: hybrid (OpenSpec files + Engram, project `cellar`)
**Status at close**: shipped and merged to `main`. SDD cycle complete.

This report is the terminal record of the cycle. Where it disagrees with `apply-progress` or
`verify-report`, those are intermediate snapshots and this report states the final state.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#1** (`feature/m1-brewrunner-core` → `main`), **merged by the user** |
| Merge commit | `ef88ce1` on `main`, containing all 7 change commits `2cb317c..a4537af` |
| Local `main` | synced with `origin/main` |
| Branch state | `feature/m1-brewrunner-core` still exists locally and on `origin` (not deleted) |
| Tasks | 53/53 complete, all `[x]` in the archived `tasks.md` |
| Tests | **86/86** package (15 suites, `swift test --package-path Packages/CellarCore`) + **4/4** app scheme — all green |
| Coverage | 98.27% lines / 93.07% regions (whole package) |
| Verify verdict | **PASS WITH WARNINGS** — 0 critical, 0 blockers, 6 warnings (W1–W6), 4 suggestions (S1–S4) |
| Authored diff | ~3.6k lines (apply-progress measured 3473 authored lines at its snapshot) |
| Delivery strategy | `single-pr` with user-accepted `size:exception` (cached budget 800 lines) |

Snapshot deltas explicitly superseded by this report:

- `verify-report` describes the branch at `9e79e85` with 6 commits and no PR; `apply-progress`
  states "NOT pushed, no PR opened". Both were true when written. Final state: 7 commits
  `2cb317c..a4537af`, PR #1 opened and merged as `ef88ce1`.
- `verify-report` W1/W2 recommend amending the spec text at archive. Both amendments were applied
  during this archive (see "Specs merged"); they are closed, not open.

## Native review authority

| Lineage | Subject | Risk / lenses | Outcome |
|---|---|---|---|
| `review-ba0dbfa2ece4907e` | verify report candidate | medium · `review-reliability` | receipt `terminal_state: approved`, `evidence_outcome: passed` |
| `review-c6ea6ae11054df48` | full branch candidate | medium · `review-reliability` | receipt `terminal_state: approved`, `evidence_outcome: passed` |

- Both receipts live under `.git/gentle-ai/review-transactions/v2/<lineage>/review-receipt.json`,
  schema `gentle-ai.review-receipt/v2`, generation 1, final candidate tree
  `7bc9a6238f3585a726ae44c4028e2eb15efc80ac`, empty fix delta (no correction transaction consumed).
- Review findings: 0 blockers, 0 criticals, 6 warnings, 4 suggestions.
- Delivery gates `post-apply` / `pre-commit` / `pre-push` / `pre-pr` all returned **allow**.
- SDD attempt ledger complete; the maintainer reset accepted the 3611-line size overage.
- Archive gate: satisfied by `reviewGate.result: allow` with both approved terminal receipts read
  and matched to the final candidate tree.

## Specs merged (source of truth updated)

`openspec/specs/` was empty before this change; both deltas were ADDED-only, so each became the
first main spec for its capability.

| Domain | Action | Details |
|---|---|---|
| `brew-execution` | **Created** `openspec/specs/brew-execution/spec.md` | 6 requirements / 12 scenarios added, 0 modified, 0 removed — plus amendment W2 |
| `brew-detection` | **Created** `openspec/specs/brew-detection/spec.md` | 5 requirements / 12 scenarios added, 0 modified, 0 removed — plus amendment W1 |

Archive-time amendments (both requested by the verify report; text corrected so spec and shipped
code agree — no code changed):

- **W1 — `brew-detection`, scenario "Disappearing configured path transitions away"**: the THEN now
  enumerates `configuredPathMissing` alongside `invalid(notExecutable)` and `absent`, and states
  that a vanished path is reported as `configuredPathMissing` (distinct from a path that exists but
  is not executable). Matches design D6 and task 3.9.
- **W2 — `brew-execution`, requirement "Terminal result and exit handling"**: a non-zero exit is now
  specified as a `BrewExit` **value** carrying the exit status with `reason: .exited`, explicitly
  not a thrown error. The old wording ("fails with an error carrying exit code 1") contradicted
  approved design decision D3, which the implementation follows.

The archived delta specs are left verbatim as the audit trail; the amendments exist only in the
main specs, with provenance notes recorded there.

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| proposal | `#7036` `sdd/m1-brewrunner-core/proposal` | `proposal.md` |
| spec (both deltas) | `#7039` `sdd/m1-brewrunner-core/spec` | `specs/brew-execution/spec.md`, `specs/brew-detection/spec.md` |
| design | `#7040` `sdd/m1-brewrunner-core/design` | `design.md` |
| tasks | `#7041` `sdd/m1-brewrunner-core/tasks` | `tasks.md` |
| apply-progress | `#7042` `sdd/m1-brewrunner-core/apply-progress` | (Engram only) |
| verify-report | `#7043` `sdd/m1-brewrunner-core/verify-report` | `verify-report.md` |
| archive-report | `sdd/m1-brewrunner-core/archive-report` | this file |
| supporting decision | `#7037` "M1 sequencing: Swift 6 migration before any CellarCore code" | — |

No `sdd/m1-brewrunner-core/review/{transaction,ledger,receipt,gate-context}` Engram topics exist for
this change; review authority was read directly from the repository CAS receipts listed above.

## What shipped

- Swift 6 language mode (`SWIFT_VERSION 5.0 → 6.0`, 6 blocks), `MACOSX_DEPLOYMENT_TARGET 26.5 → 26.0`
  (4 blocks), `ENABLE_APP_SANDBOX YES → NO` on app Debug+Release (hardened runtime untouched).
- `Packages/CellarCore` local SPM package, single target `BrewProcess`, tools 6.0,
  `platforms: [.macOS("26.0")]`, `.swiftLanguageMode(.v6)`, plus the shared `CellarCore` scheme.
- `actor BrewRunner` over an injectable process seam (`ProcessLaunching` / `LaunchedProcess` /
  `SystemProcess` confined by `Mutex<State>`): pinned brew environment, verbatim `AsyncStream<LogLine>`
  streaming with stdout/stderr tagging, `BrewExit` value results, SIGINT → SIGTERM cancellation
  escalation (never SIGKILL), FIFO mutation gate with unblocked concurrent reads.
- Detection: `BrewVersion.parse`, `DefaultBrewLocator` (native → Rosetta prefix precedence), strict
  custom-path validation with one typed reason, soft `absent` with install guidance, and
  `@MainActor @Observable BrewDetectionStore` with single-flight `refresh()`.
- App seam: `CellarCore` linked into target `cellar`; detection state refreshed at launch and on
  `NSApplication.didBecomeActiveNotification`, rendered as text only.

Zero `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` in `Packages/CellarCore/`
and `cellar/`; zero compiler warnings on a clean package rebuild and on the app scheme build.

## M2 follow-up register (carried forward, none blocking)

| # | Follow-up | Source | Notes |
|---|---|---|---|
| 1 | `BrewRunner.operations` is never evicted | verify S2 / apply-progress | One record per command for the runner's lifetime; harmless in M1, needs eviction on terminal resolution before M2's continuous usage |
| 2 | `cancelledUnresponsive` path leaves a live process feeding an unread unbounded stream | archive review of the escalation path | After SIGINT+SIGTERM both fail, the operation resolves as unresponsive while the real process may still run and buffer output |
| 3 | Detection `--version` probe has no timeout | archive review of `DefaultBrewLocator` | A hung or non-terminating configured binary can stall detection indefinitely |
| 4 | `BrewDetectionStore` single-flight can join a stale probe | archive review of `refresh()` | A `configuredPath` change mid-probe joins the in-flight evaluation for the *previous* path instead of restarting |
| 5 | `detectStandard` publishes the unresolved symlink path | archive review vs. deviation 3 | Validation resolves symlinks before probing, but the published installation URL is the unresolved path |
| 6 | Declared test command does not run the 86 core tests | verify + config | `openspec/config.yaml` `test_command` is the app scheme (4 tests); the package suite runs only via `swift test --package-path Packages/CellarCore`. Unify the schemes so one command covers both |
| 7 | Document `BrewRunner.start`'s `fault()` channel | verify W3 | A gated `.mutate` surfaces spawn failure via `await operation.fault()` and resolves `BrewExit(status: 127, reason: .exited)`; a caller inspecting only `exit()` misreads it as an ordinary exit 127. Currently explained only in the apply artifact |
| 8 | AppKit focus-notification wiring is untested | verify W5 | `cellarApp.swift`'s `didBecomeActiveNotification` plumbing was verified once by a temporary, uncommitted accessibility harness; a regression would be silent |

Also open, lower priority: verify S1 (spec `native`/`rosettaCarryOver` vs. code
`BrewPrefix.appleSilicon`/`.intelCarryOver` vocabulary), S3 (`BrewEnvironment` inherits only `PATH`
and `HOME`), S4 (`BrewVersion.parse` region coverage 73%), W4 (tasks 2.9–2.10 had no observable RED,
self-disclosed), W6 (reviewer load — accepted `size:exception`).

## Archive integrity note

The archived change folder is an audit trail: `proposal.md`, `design.md`, `tasks.md`,
`verify-report.md`, and `specs/` are preserved byte-for-byte as written by their phases. Only this
report was added.

The archived `tasks.md` contains no unchecked implementation tasks; no stale-checkbox reconciliation
was needed or performed.
