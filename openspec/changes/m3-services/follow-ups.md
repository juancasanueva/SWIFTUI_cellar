# Follow-up register at the close of M3-1 (`m3-services`)

Written during apply (Phase 15), not at archive time, so the reasons are recorded while the code that
produced them is still in front of the person recording them. It supersedes the M3-0 register
(`openspec/changes/archive/2026-08-03-m3-hardening-prelude/archive-report.md` §"Follow-up register")
for every item this slice touched, and carries the rest forward unchanged.

## Closed by this slice

| Item | Where it was | How it is closed |
|---|---|---|
| **VS2** (M2-3) — `OperationCenter.pendingConfirmation` widened to `public internal(set)` | M2-3 verify SUGGESTION, routed "absorb into M3-1" | **CLOSED, and more strongly than asked.** A nested `@Observable ConfirmationBox` holds the value and `pendingConfirmation` is a computed getter with **no setter at all** — there is no setter left to widen a second time. The one writer is a module-internal method. `ConfirmationBoxTests` |
| **M2-2 #7** — duplicate submission of the same command | M2-2 register, routed "absorb narrowly" | **CLOSED narrowly, exactly as routed.** `ServiceSubmissionGuard`, keyed on the validated service name, on the services submit path only. The general dedup rule stays deferred and `brew-execution` still permits duplicate submissions in general — see "Still open" below |
| **M2-2 #9** — the sudo signature set is unprobed | M2-2 register, routed "gate U5 makes it reachable" | **CLOSED as far as U5 reaches.** U5 established from source that a root-domain start never invokes sudo and cannot reach a password prompt, so the shipped signature set is not on that path at all. What remains is the *bootstrap* signature, recorded separately as the U5 residual below — a message-quality gap, not a privilege gap |
| **Register top item** — a failed clear's reason erased by the next search-driven reload | M3-0 register | **CLOSED in batch 1** (Phase 7): `HistoryStore` keeps a sticky failure reason that survives a keystroke-driven reload |

## Closed already, and confirmed here rather than assumed (task 15.5)

Both were listed as open on an inherited register that is **stale**. Verified in shipped code at
`main` before this slice planned any work for them, and no code task exists for either.

| Item | Evidence |
|---|---|
| **S1** — `BrewRunner.exit(of:)` fabricating `BrewExit(status: 0)` for an unknown id | `Sources/BrewProcess/BrewRunner.swift:288/293` returns `.unknownOperation`; `MutationOutcome.classify` maps it to `.launchFailed` before any prose is read. Carried in `openspec/specs/brew-execution/spec.md:272-283` |
| **W1** — a no-runner submit writing no history entry | `Sources/BrewClient/OperationCenter.swift:168-177` — the gate is opened above the runner guard and the no-runner path routes through `finish()`, the single terminal funnel, so the entry is written by construction |

## Still open, with the reason each stayed open

### M2-2 #6 — a mutation's own post-terminal FSEvents echo (re-registered, task 15.3)

**Status: OPEN. Deliberately not closed by this slice, and this is the reason.**

An earlier draft of this design folded #6 in as an `isSettling` grace window on
`InstalledRefreshCoordinator`. That was wrong as designed, and the correction is worth keeping:

`openspec/specs/installed-inventory/spec.md:334-337` requires that a change signal arriving *after*
an acquisition started MUST "cause a further re-snapshot once the quiet window elapses, so the
inventory converges on state observed at or after the newest signal". A grace window sits exactly
where that re-snapshot would fire and **drops** it. For the mutation's own echo that is harmless —
but the rule cannot tell the echo apart from a genuine external change landing in the same window,
and that one would be silently lost. The draft cited II10 sc5 as cover; that paragraph (`:329-332`)
governs *in-flight* suppression, which is a different moment and a different guarantee.

**Closing #6 therefore requires an explicit `installed-inventory` II10 amendment** narrowing the
`:334-337` convergence guarantee so a post-terminal echo can be dropped without also dropping a
genuine external signal in the same window. That is a spec decision, not a design one, and this slice
does not take it. The register already classifies the redundant re-snapshot as **conforming, not a
defect**.

Guarded rather than trusted: task 17.2 asserts `rg 'isSettling|settleGrace'` returns zero, and task
9.7 asserts `InstalledChangeObserving.swift` is byte-unchanged against `main`.

### The remaining open items (task 15.4)

| Item | Why it is still open | What would close it |
|---|---|---|
| **VS3** (M2-3) — app-target UI has no automated coverage | The ruling stands: accept planned manual evidence again rather than stand a harness up inside a feature slice, which is how feature slices overrun. This slice added four more untested surfaces (`ServicesListView`, `ServiceRow`, `ServiceDetailView`, `ServiceControls`) and twelve pre-written manual checks to compensate | A dedicated XCUITest harness slice, funded separately |
| **VS4** (M2-3) — `HistoryDraft.date` is `Date()`, not an injected clock | **Considered and deliberately not adopted** (design D6). No assertion in this slice needs a deterministic timestamp: the history claims are "exactly N entries", "null package identity", "typed verb" and "exact argv", and every one is provable without one. Adding the seam speculatively would have been unused surface | The first assertion that genuinely needs a deterministic timestamp — then add it additively |
| **`InstalledMutationGate` naming debt** — **new, from this slice** | The type now serves two domains under an installed-specific name. It was always a depth counter plus a `terminals` stream with nothing installed-specific in its body, so the services gate is a second *instance*, not a second type. Renaming it is public-API churn across test call sites and the app's composition root, and buys no behaviour | A rename in a slice that is already touching those call sites |
| **U5 residual** — the exact stderr/exit signature of a rejected root-domain `launchctl bootstrap` | Unprobed, and not safely probeable on the dev machine. The classifier degrades correctly without it: a rejected bootstrap is a generic failure with its log verbatim, never a success and never a state change that did not happen. This is a **message-quality** gap, not a correctness gap | A live probe on a machine where a root-domain service can be rejected |
| **`brew services info --json <name>` cost** — **new, from this slice** | Schema-verified from Homebrew source and cost-probed only via `--all` at n = 1 service. A per-service call could prove slower than measured | If it does: a cache. The fetch is already lazy and selection-keyed, so the mitigation is not a redesign |
| **M2-2 #8** — carry `standardInput` through `ProcessSpec` | Still deferred. U5 answered the question that could have changed this verdict: a root-domain start does **not** hang, because brew never invokes sudo on that path, so stdin observability stays cosmetic | A recording seam that carries `standardInput`, if another family ever needs one |
| **M2-2 #10** — `skippedRecordCount` is never surfaced | Still deferred, and deliberately **not** solved for one decoder. This slice added a fourth tolerant decoder (`ServicesDecoder`), which strengthens the original reasoning rather than weakening it: the answer is one mechanism across all of them | One shared "what did we skip" surface, across every tolerant decoder at once |
| **M3-0 VS2** — the equal-ordinal/equal-revision invariant is unstated | Untouched by this slice; it lives in `Catalog` | Assert it, or state it in the type |
| **M3-0 (c)** — the app-target `reconcileOrder` expression is unproved | Untouched; folds into the VS3 ruling | The VS3 harness |

## Spec reconciliation carried out during apply

| Task | What was reconciled |
|---|---|
| 15.1 | The `package-mutation` delta header now carries an explicit **rename-in-place** instruction for PM6, so the archive step cannot leave the main spec carrying both the old and the new title |
| 15.2 | `openspec/specs/package-mutation/spec.md`'s capability header prose described the **unconditional** re-snapshot at every terminal outcome. That prose sits outside delta scope and would have survived promotion untouched, so it was corrected during apply |
| 15.2 | `openspec/specs/installation-history/spec.md`'s header was **checked and needed no edit** — it names no forced inventory re-snapshot. The only such phrase in that file is inside IH7's requirement text, which this slice's delta replaces in full, and inside IH3, which is untouched and still accurate. Recorded rather than silently skipped |
| 1.5 (batch 1) | `openspec/changes/m3-services-cleanup-taps/explore.md:207-208` repeated the false claim that `HOMEBREW_COLOR=0` stops ANSI. Corrected |

## One open discrepancy this slice did **not** resolve

**The service verb vocabulary.** The shipped verbs are `serviceStart`, `serviceRun`, `serviceStop`
and `serviceRestart`, per design D9 and task 13.4, namespaced so an IH5 search cannot collide with a
package verb. The `installation-history` delta's IH1 sc5 text says a service operation records "its
own verb — `start`, `stop`, `restart`, `run`".

Both readings satisfy every IH5 scenario, because the namespaced form still matches a case-insensitive
`stop` substring search and the service's name is found through the argv either way. The
implementation follows the design because the design states a reason and the delta text does not
contradict it deliberately — but **the delta text needs reconciling to the shipped form**, and that
is a spec edit this apply phase did not take on its own authority.
