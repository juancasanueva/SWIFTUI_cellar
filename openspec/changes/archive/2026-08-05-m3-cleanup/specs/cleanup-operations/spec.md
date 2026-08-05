# Cleanup Operations Specification

## Purpose

Preview-gated cleanup.

## Requirements

### Requirement: Typed scopes are exact

Only these argv vectors (excluding `brew`) MUST exist:

| Scope | Preview | Mutation | `HOMEBREW_NO_AUTOREMOVE` |
|---|---|---|---|
| Global | `cleanup --dry-run` | `cleanup` | `1` |
| Package | `cleanup --dry-run <name>` | `cleanup <name>` | `1` |
| Full | `cleanup --dry-run --prune=all` | `cleanup --prune=all` | `1` |
| Autoremove | `autoremove --dry-run` | `autoremove` | absent |

Package scope MUST retain validated kind/name; overrides MUST remain command-local and authoritative.

#### Scenario: Scope matrix is exact

- GIVEN every scope with conflicting inherited environment
- WHEN specifications are inspected
- THEN argv and environment match the table exactly

### Requirement: Preview evidence is tolerant and honest

Stdout MUST remain verbatim; unknown lines raw. Only Homebrew's footer MAY supply reclaimable bytes; otherwise the total is unknown and row sums MUST NOT substitute. Autoremove MUST preserve exact names/count; blank means zero, mismatch/unknown is partial, never fabricated.

Complete current disk data MAY total orphans only as **currently on disk**. Incomplete allocation MUST NOT become zero or reclaimable.

#### Scenario: Source and uncertainty survive parsing

- GIVEN cleanup/autoremove fixtures and complete/partial disk data
- WHEN parsing completes
- THEN raw text, states, names/count, and total provenance remain distinct

### Requirement: Preview states remain distinct

The projection MUST distinguish loading, content, empty, partial, error, cancelled, and stale. Failure MUST retain raw diagnostics; cancellation MUST remain distinct. Superseded results MUST NOT replace newer/last-good evidence, which remains stale.

#### Scenario: Late and unsuccessful results stay truthful

- GIVEN last-good, late, failed, and cancelled previews
- WHEN they settle
- THEN late evidence is rejected and states remain distinct

### Requirement: Confirmation requires fresh matching evidence

Confirmation MUST follow its typed preview and disclose scope, command, effects, orphans/count, and total provenance. Full MUST warn that `--prune=all` removes cache regardless of age, may include installed-package downloads, and is not cache-only.

FIFO-front preview MUST rerun; typed evidence MUST match. Unchanged evidence MAY spawn once; changed, empty-after-nonempty, stale, failed, cancelled, or unavailable evidence MUST spawn nothing, publish refreshed evidence, and require reconfirmation. Prose MUST NOT become argv/evidence.

#### Scenario: Authorization fails closed

- GIVEN unchanged, changed, and unavailable confirmed evidence
- WHEN authorization runs at FIFO front
- THEN only unchanged evidence launches; others require reconfirmation

### Requirement: Invalid preconditions spawn nothing

Empty, whitespace-containing, or leading-`-` names MUST be rejected. Absent brew, missing path, or invalid detection MUST provide read-only guidance, spawn nothing, and recover without restart.

#### Scenario: Hostile targets and invalid brew are inert

- GIVEN `""`, `"bad name"`, `"--force"`, or invalid brew
- WHEN cleanup is requested
- THEN nothing queues/spawns and guidance is available

### Requirement: Shared execution refreshes exact scopes

Cleanup MUST inherit FIFO, activity, exact copy argv, logs, cancellation, outcomes, and exactly-once history; no second policy MAY exist. Every terminal outcome MUST refresh exactly once:

| Scope | Domains |
|---|---|
| Global/Full | installed, Cellar, Caskroom, cache |
| Formula | installed, Cellar, cache |
| Cask | installed, Caskroom, cache |
| Autoremove | installed, Cellar |

Services, taps, and catalog MUST refresh zero times.

#### Scenario: FIFO and refresh scopes hold

- GIVEN mixed mutations and terminal outcomes
- WHEN execution and refreshes are observed
- THEN shared contracts hold and only table domains refresh once

### Requirement: Presentation and verification are bounded

Presentation MUST preserve storage rows and expose all states, preview-first actions, provenance, orphans, Full warning, and cancel. Stable identifiers/fixtures MUST cover content, empty, unknown, partial, error, cancelled, stale/changed, brew absence, confirmation, and refresh.

Only Homebrew MAY mutate; direct deletion is forbidden. Mutation probes MUST use disposable prefixes; developer prefixes MAY only preview. Rollback MUST preserve `disk-usage`, spine, and schemas.

#### Scenario: Safety boundaries are testable

- GIVEN fixtures, process records, accessibility, and safe probes
- WHEN cleanup flows run
- THEN states are identifiable and mutation/rollback boundaries hold
