# Proposal: M3 Cleanup Operations

## Intent

Close PRD milestone **M3** with honest, preview-gated Homebrew cleanup. Today `disk-usage` forbids cleanup, and cleanup preview, command, orphan, confirmation, and history vocabulary are absent.

## Scope

### In Scope
- Typed previews for global, per-package, **Full cleanup**, and autoremove scopes; tolerant parsing preserves raw output and distinct empty, unknown-total, partial, failure, cancellation, and stale states.
- Exact orphan names/count; complete allocation may appear only as **currently on disk**. Only Homebrew-reported totals support reclaimable-byte copy.
- Typed FIFO mutations preserve exact argv, copy, logs, cancellation, history, and exactly-once installed/disk invalidation.
- Preview-before-confirmation and queue-front revalidation; changed or unavailable evidence fails closed to a refreshed preview.
- Extend `CleanupView`, confirmations, fixtures, identifiers, and tests.

### Out of Scope
- Health scoring, heuristics, treemap, broad localization/accessibility, automation, Brewfile/doctor/security, direct deletion, cache-only claims, or a new target.

## Capabilities

### New Capabilities
- `cleanup-operations`: Previews, scopes, confirmation freshness, mutations, invalidation, and presentation.

### Modified Capabilities
- `installation-history`: Add namespaced verbs, null/per-package subjects, labels, and search terms.

`disk-usage` remains read-only. `package-mutation` and `operation-activity` supply existing generic spine contracts without absorbing cleanup requirements.

## Approach and Boundaries

| Area | Decision |
|---|---|
| `BrewProcess` | Add command-scoped environment composition. |
| `BrewClient` | Own previews/commands/store; reuse `BrewMutating`, `OperationCenter`, `PackageTarget`, and invalidation gates. |
| `DiskUsage` | Provide read-only snapshots; never depend on `BrewClient`. |
| `cellar/Cleanup` | Compose state and controls; keep rules in CellarCore. |

Normal and Full cleanup previews/mutations set `HOMEBREW_NO_AUTOREMOVE=1`; autoremove stays separate. Full cleanup runs `brew cleanup --prune=all`, never described as cache-only. Typed argv is authoritative; prose never becomes execution input.

## Risk Controls and Verification

- Homebrew prose drift: tolerant parsing, provenance fixtures, and explicit unknown totals.
- Preview races: rerun the exact preview at queue front and compare typed evidence.
- Strict TDD: RED-first parser, environment, store, spine, freshness, persistence, and XCUITest coverage.
- Before design/apply, probe contention, environment symmetry, autoremove provenance, and prune-all in a disposable prefix; never destructively probe the developer prefix.

## Delivery, RDD, and Rollback

One PR is the rollback boundary. Approved `size:exception` covers the forecast above 2,000 lines and RDD’s 400-line default; session `exception-ok` and enabled RDD override stale config metadata. Later work binds authority, receipts, lineage, recovery, and independent read-only validation to one frozen candidate; changed bytes require a new candidate. No review starts here.

Rollback reverts that PR, removing cleanup and command-local environment behavior while preserving read-only DiskUsage; no migration is required.

## Success Criteria

- [ ] Every destructive scope executes only after matching fresh evidence.
- [ ] Cleanup never implicitly autoremoves; byte and Full cleanup claims remain truthful.
- [ ] Existing queue, history, cancellation, and scoped refresh invariants remain proven.
