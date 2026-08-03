# Proposal: M3-1 — Service Management (`m3-services`)

Slice 2 of 5 in M3. Proposes from `openspec/changes/m3-services-cleanup-taps/explore.md`
(§2, §3, §6-A, §6-B, §6-D, §7 row M3-1, §8, §9) and the closed probe gates U1/U2/U5/U6/U8.

## Intent

Cellar installs packages but cannot see or control the background services brew manages
(PRD §3.3), so users drop to Terminal. Services is also the **first non-package mutation
family**, so this slice generalizes the mutation spine that M3-2 taps and M3-4 cleanup will
both consume — done here, with a real second consumer in the same slice, rather than as a
seam with no caller (the M2-1 `InstalledMutationGate` anti-precedent).

## Scope

### In Scope

- **`BrewMutating` protocol** (explore §6-A option 1). `MutationCommand` conforms unchanged
  — `package-mutation` PM1 "exactly six" stays literally true. `ServiceCommand` conforms beside it.
- **Typed `InvalidationScope`** carried by the command, replacing hardcoded
  `MutationOutcome.forcesReSnapshot == true`; gate fans out per scope. Includes M2-2 #6's
  post-terminal FSEvents grace window (same code, same decision).
- **Reads**: `services list --json` (array; 7-value tolerant status; nullable `user`/`exit_code`)
  and lazy per-selected-service `services info --json` (optional keys emitted as **null**;
  `log_path` and `error_log_path` can be the same file — dedupe). `ServicesStore` joins M3-0's
  single `LocalStores` container.
- **Poll**: 5 s on `LoopOwner` with an injected clock, only while the Services surface is
  visible; stopped entirely on hide/deselect; forced refresh at each service terminal;
  suppressed while a service mutation is in flight.
- **Four verbs** start/stop/restart/run — `start` vs `run` *is* the start-at-login toggle.
  One invocation per service in selection order. Services-scoped duplicate-submit guard (M2-2 #7).
- **Outcome classification from live markers**, not exit code: U8 proved `start` on a running
  service exits 0 with `already started, use …` and no `Successfully` line; `stop` on a stopped
  service exits 0 with a stderr `Warning:`. U5 proved no sudo prompt is reachable — a root-domain
  start emits a non-fatal warning then a user-domain `launchctl bootstrap` that may fail non-zero.
- **History**: each verb writes exactly one entry, null package identity, typed service verb.
- **UI**: sidebar section, list with status, detail with plist + log paths and open-in-Console,
  brew-absent read-only guidance.
- **Absorbed defects**: `HOMEBREW_COLOR=0` → `HOMEBREW_NO_COLOR=1` with a RED test asserting no
  ESC (0x1B) byte survives capture, plus the wrong doc comment and `explore.md:207-208`;
  failed-clear reason erased by the next reload; VS2 `ConfirmationBox` restoring `private(set)`;
  VS4 clock seam **only if** an assertion needs a deterministic timestamp.

### Out of Scope

- `brew services kill` and `stop --keep` — PRD names four verbs; rationale recorded, not silent.
- `--all` for any mutation. One invocation per service (M2 fan-out ruling, PM2 sc2).
- Services multi-select/bulk — would need a new type over a new entity; `BulkSelection.Action`
  is proven exhaustive at two cases by installed-inventory II13 sc4.
- XCUITest harness. Manual checks are **planned into tasks before apply** (ruling c). VS3 stays open.
- Taps, cleanup, disk usage, and gates U3/U4 (they gate M3-4, not this slice).
- Surfacing `skippedRecordCount` — deferred until all four tolerant decoders exist.

## Capabilities

### New Capabilities

- `service-management`: enumerate brew services with status, poll while visible, show plist/log
  paths, and run the four service verbs through the shared mutation spine.

### Modified Capabilities

- `package-mutation`: PM6 "every terminal outcome forces one re-snapshot" → typed invalidation
  scope (invariant preserved: every terminal still owes exactly one refresh of what it *does*
  invalidate, including cancelled and failed). PM4 widened for the root-domain warning path.
  PM1 unchanged by construction.
- `operation-activity`: OA6 gains an explicit non-package clause.
- `installation-history`: IH1 defines the non-package verb vocabulary and null-package form;
  IH5 gains the four verbs. IH3 needs **no** carve-out.
- `installed-inventory`: II10's gate becomes scoped rather than unconditional.
- `brew-execution`: the "Normalized brew environment" requirement names `HOMEBREW_COLOR=0`
  verbatim and must become `HOMEBREW_NO_COLOR=1`, with an ANSI-absence scenario.

## Approach

Protocol generalization over enum extension (§6-A): each family owns its verb vocabulary,
confirmation rule and invalidation scope; a new family costs one conformance, not an enum edit
plus N exhaustive switches. Reads copy `BrewInfoPayloadSource` verbatim — constant argv, a
`…PayloadSourcing` seam producing `Data`, a pure payload function, a closed error enum.
`ServicesStore` copies `InstalledStore` (single-flight, ordinal-guarded adoption, last-good
survives failure). Poll copies `InstalledRefreshCoordinator`'s trust order. `brew` stays the
sole source of truth — `service` remains absent from the installed wire projection.

**Strict TDD is active**: every requirement lands as a RED test first. Fixture-first is
mandatory — the dev machine shows one service and six of seven statuses are unobservable
locally. `.timeLimit` on the new poll suite (the M3-0 habit).

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Sources/BrewClient/MutationCommand.swift`, `OperationCenter*.swift`, `ActivityItem.swift`, `MutationOutcome.swift` | Modified | protocol retype, invalidation scope, `ConfirmationBox`, services markers |
| `Sources/BrewClient/Service*.swift` | New | command, payload source, decoder, store, refresh |
| `Sources/BrewProcess/BrewEnvironment.swift` | Modified | `HOMEBREW_NO_COLOR=1` |
| `Sources/Persistence/HistoryStore.swift` | Modified | failed-clear reason |
| `cellar/Services/`, `cellar/ContentView.swift`, `cellar/cellarApp.swift` | New/Modified | section, list, detail, DI |
| app-target mutation call sites (`MutationMenu`, `InstalledListView`, `ActivityBar`, `BrowseView`) | Modified | mechanical retype |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Slice exceeds the 2,000-line budget by ~2× | **High** | `size:exception` accepted **before** apply, or the split below |
| Protocol retype ripples wider than forecast | Med | M2-3's `PackageTarget` retype cost 56 mechanical edits against a 40–60 estimate — that estimate held |
| Six of seven statuses unobservable locally | High | tolerant decode with a catch-all; fixture-driven tests; unknown status never fails the payload |
| Exact root-domain bootstrap failure text unprobed (U5 residual) | Med | classify the observed `opoo`/non-zero path; treat unmatched failure as generic, never as success |
| Poll burns CPU or flickers status mid-restart | Med | visibility gate stops the loop; suppression while mutating; injected clock, no wall-clock sleeps |
| A double-clicked toggle queues two opposite operations | Med | services-scoped duplicate-submit guard |
| Manual verification thin (VS3) | Med | manual checks written into tasks before apply — M2-3's IH6 CRITICAL is the recorded cost of improvising them |

## Size Forecast and Split Recommendation

The umbrella forecast 2,600–3,400. Re-forecast **3,800–5,200 ledger lines**, because the band
predates the absorbed `HOMEBREW_COLOR` defect, the failed-clear follow-up, and a five-capability
spec delta; because the umbrella under-priced M2-0 by 1.67× and M2-1 by 1.82×; and because the
verify report's own ~300 lines must sit inside the budget from the start. A `size:exception`
is required either way.

**Recommended split** (user decides):

- **M3-1a `m3-services-read`** — both read sources, decoders, `ServicesStore`, poll loop,
  Services list + detail + Console, `HOMEBREW_NO_COLOR` fix, failed-clear fix. No mutation, no
  spine change. New `service-management` capability, read half only. **≈1,800–2,400.**
- **M3-1b `m3-services-control`** — `BrewMutating`, `InvalidationScope`, `ConfirmationBox`,
  four verbs, history verbs, duplicate guard, all five capability deltas. **≈2,000–2,800.**

This boundary keeps the generalization in the same slice as its real second consumer
(`ServiceCommand`), ships user-visible value in both halves, and makes each half independently
rollbackable. The alternative boundary — spine first, feature second — is rejected: it ships a
seam with one conformer.

## Rollback Plan

Revert the PR. The protocol generalization is additive at the type level and `MutationCommand`
conforms unchanged, so reverting restores the M3-0 spine byte-for-byte. `ServicesStore` shares
M3-0's `LocalStores` container and adds no schema, so there is no migration to unwind. The
`HOMEBREW_NO_COLOR` change is a one-key environment edit. No brew state is touched by a revert —
any service started through Cellar stays started, exactly as if started from Terminal.

## Dependencies

- M3-0 archived (`main` @ `3d55ed3`) — supplies `LocalStores`, `BrewExit.unknownOperation`,
  the funnel-only settle path, and the reconciled 2,000-line budget.
- Probe gates U1, U5, U8 closed. U3/U4 are **not** blocking here.
- User acceptance of a `size:exception` (or of the split) before apply starts.

## Success Criteria

- [ ] Services list renders all seven statuses from fixtures; an unrecognised status decodes to
      a catch-all and never fails the payload.
- [ ] Each of start/stop/restart/run writes exactly one history entry with a null package identity.
- [ ] `start` on an already-running service classifies from the marker, not the exit code.
- [ ] A service mutation triggers no `brew info --installed --json=v2` re-snapshot.
- [ ] The poll runs on an injected clock, only while visible, and stops on hide/deselect —
      proven without wall-clock sleeps.
- [ ] No ESC (0x1B) byte survives in captured brew output.
- [ ] All 571 existing tests stay green; `BulkSelection.Action` still has exactly two cases.
- [ ] Manual verification checks for every UI-only scenario exist in `tasks.md` before apply.
