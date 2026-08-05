# Design: M3 Cleanup Operations

## Technical Approach

Extend `BrewProcess → BrewClient → Persistence/app`; `DiskUsage` stays read-only and never imports `BrewClient`. The `@MainActor @Observable` cleanup store lives in `BrewClient`, owned/injected by `cellarApp`. Mutations retain `OperationCenter`, `BrewRunner` FIFO, `ActivityItem`, history, and gates. Approved `size:exception`/`exception-ok` mandates one PR; only the maintainer may change that.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| Extend `BrewClient` and the operation spine | Separate cleanup target/store or queue/policy | Preserves direction, one confirmation backlog, FIFO, cancellation, history, and terminal funnel. |
| Typed `CleanupScope`/commands; Homebrew performs mutations | Direct filesystem deletion; cache-only mutation | Prevents option injection and keeps Full cleanup truthful. |
| Queue-front typed evidence revalidation | Execute stale confirmation | Changed/unavailable evidence denies launch and requires a new confirmation. |
| Read-only `DiskUsageSnapshot` join in `BrewClient` | `DiskUsage → BrewClient` dependency | Allocation is “currently on disk,” never reclaimable provenance. |

## Interfaces, Ownership, and Algorithms

- `CleanupScope: Sendable, Hashable` is `.global`, `.package(PackageTarget)`, `.full`, `.autoremove`; `CleanupCommand: BrewMutating` owns exact argv, namespaced verb, optional package identity, environment, and invalidations. `BrewCommand` gains typed command-local overrides; `BrewEnvironment.compose` applies inherited `PATH/HOME`, pinned normalization, then allowed overrides. Cleanup/global/package/full set `HOMEBREW_NO_AUTOREMOVE=1`; autoremove supplies none.
- `CleanupPreviewRequest(id, scope, specification)` and `CleanupPreviewResult(rawStdout, rawStderr, evidence, provenance)` are immutable `Sendable` values. Evidence stores parsed rows, unknown lines, orphan names/count, and `reportedFooter(bytes)|unknown`; provenance stores parser version and recognized footer form. Raw output is byte-preserved.
- Parsing preserves lines, recognizes only fixture-backed item/footer forms, and checked-converts units. Overflow, malformed forms, count mismatch, or unknown nonblank lines are partial. Blank successful autoremove is zero. Only a recognized footer yields reclaimable bytes; row sums never do.
- Evidence equality compares scope, typed rows/orphans, total provenance, and unknown-line bytes, excluding request/time/display text. `CleanupEvidenceFingerprint` is SHA-256 over a versioned, length-prefixed canonical encoding. It supports diagnostics/identity; authorization uses equality, not hash alone.
- `CleanupStore` owns per-scope `loading|content|empty|partial|error|cancelled|stale`, last-good evidence, generation UUID, and task. Starting/cancelling/failing marks last-good stale. Adoption requires matching generation; superseded completions are discarded. Successful current evidence replaces last-good atomically.
- Confirmation extends `OperationCenter.ConfirmationRequest`/`ConfirmationDisclosure` with scope, exact command, evidence/fingerprint, effects, orphan count, provenance, and Full warning. `CleanupLaunchAuthorizer` reruns the identical preview at FIFO front. Equal nonempty evidence allows once; changed, empty-after-nonempty, stale, failed, cancelled, or unavailable publishes refreshed/stale state and returns existing typed denial without spawning.
- `CleanupCommand.invalidates` is installed+disk, with disk areas: global/full `{cellar,caskroom,cache}`, formula `{cellar,cache}`, cask `{caskroom,cache}`, autoremove `{cellar}`. `OperationCenter.finish` remains the sole idempotent history/invalidation site, so every terminal pays once; services/taps/catalog pay zero. A complete, same-root `DiskUsageSnapshot` may sum orphan formula allocation as “currently on disk”; otherwise allocation is unknown.
- History maps verbs `cleanupGlobal`, `cleanupPackage`, `cleanupFull`, `cleanupAutoremove` to “Cleanup,” “Package cleanup,” “Full cleanup,” “Autoremove”; only package cleanup stores identity. Existing verb/name/argv search and nullable Schema V1 remain authoritative.

## Data Flow

```text
CleanupView → CleanupStore → CleanupPreviewSource → BrewRunner(read)
     │ confirm(evidence) → OperationCenter → FIFO authorizer → equal? spawn : deny/refresh
     └ DiskUsageSnapshot(read)                 └ terminal → history + scoped gates once
```

## File Changes

| Files | Action |
|---|---|
| `Packages/CellarCore/Sources/BrewProcess/{BrewCommand,BrewEnvironment,BrewRunner}.swift` | Modify environment plumbing. |
| `Packages/CellarCore/Sources/BrewClient/{CleanupModels,CleanupParser,CleanupPreviewSource,CleanupStore,CleanupCommand,OperationCenterCleanup}.swift` | Create cleanup domain/seams. |
| `Packages/CellarCore/Sources/BrewClient/{BrewMutating,OperationCenterBulk}.swift` | Extend disclosure/invalidation. |
| `Packages/CellarCore/Sources/Persistence/HistoryPresentation.swift` | Add labels/subjects; schema unchanged. |
| `cellar/Cleanup/CleanupView.swift`, `cellar/Activity/MutationConfirmation.swift`, `cellar/{ContentView,cellarApp,AppTestFixtures}.swift` | Compose UI, DI, fixtures, identifiers. |
| `Packages/CellarCore/Tests/{BrewProcessTests,BrewClientTests,PersistenceTests}/`, `cellarUITests/cellarUITests.swift` | Add RED-first coverage/resources. |

Identifiers: `cleanup-preview-{scope}`, `cleanup-state-{state}`, `cleanup-action-{scope}`, `cleanup-confirmation`, `cleanup-command`, `cleanup-provenance`, `cleanup-orphan-{name}`, `cleanup-cancel`.

## Testing Strategy

Strict RED order: environment/argv/hostile names → parser/provenance/fingerprint → store supersession/retention/cancellation → FIFO authorization → exactly-once history/domains → persistence labels/search → XCUITest states/confirmation/cancel. Process seams record `ProcessSpec`; no sleeps. Before apply, probes require a sentinel-marked temporary Homebrew prefix, reject `/opt/homebrew` and `/usr/local`, and cover contention, environment symmetry, autoremove, and `--prune=all`; developer prefixes are preview-only.

## Threat Matrix

| Boundary | Applicability | Response / RED |
|---|---|---|
| Documentation-like paths | N/A — no classification | None. |
| Git repository selection | N/A — no VCS | None. |
| Commit state | N/A — no VCS | None. |
| Push state | N/A — no VCS | None. |
| PR commands | N/A — no PR automation | None. |

Subprocess safety is covered by typed argv, no shell, validated targets, command-local environment, pre-spawn authorization, and recorded-process RED tests.

## Migration / Rollout

No schema/data migration. Failures retain raw diagnostics and last-good stale evidence; cancellation propagates through owned tasks and existing signals. UI/store stay `@MainActor`; parser/evidence/source values are `Sendable`, and `BrewRunner` remains the serialization actor. Activity logs, fingerprints, provenance, outcomes, history, and refresh receipts provide observability. Rollback reverts the PR while preserving DiskUsage and Schema V1. With RDD enabled, normalize before candidate freeze; receipts and independent read-only validation bind to exact bytes, and any edit creates a new candidate. No review starts during design.

## Open Questions

None.
