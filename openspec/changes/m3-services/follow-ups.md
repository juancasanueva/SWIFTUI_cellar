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
| **M2-2 #8** — carry `standardInput` through `ProcessSpec` | Still deferred, and **no longer load-bearing**. Batch 3 made the guarantee observable without it: `SystemProcessTests` spawns a real `/usr/bin/stat -f "%i %HT" /dev/fd/0` through `BrewRunner` + `SystemProcessLauncher` and compares the **child's own reported stdin inode** against `/dev/null`, on both the `.read` and the `.mutate` path. So SM7 sc3, PM4 sc2 and PM4 sc5 have runtime evidence at the real seam rather than at the fake one, `ProcessSpec` is unwidened, and `SystemProcess.swift` stays byte-unchanged against `main`. What #8 would still buy is observability at the **recording** seam, so a fake launcher could assert it too | A recording seam that carries `standardInput`, if another family ever needs one — the real-process test above covers the guarantee itself |
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

## The open discrepancy, now **closed** (batch 3, task 18.8)

**The service verb vocabulary.** The shipped verbs are `serviceStart`, `serviceRun`, `serviceStop`
and `serviceRestart`, per design D9 and task 13.4, namespaced so an IH5 search cannot collide with a
package verb. The `installation-history` delta's IH1 sc5 text said a service operation records "its
own verb — `start`, `stop`, `restart`, `run`".

`sdd-verify` adjudicated it (ADJUDICATION 1): **the code is right and the spec text was wrong.** The
namespaced form satisfies every IH5 scenario by case-insensitive substring, a bare `run` or `start`
entering a vocabulary that already holds `install`/`upgrade`/`pin` would leave the user unable to tell
which family they matched, and `ServiceCommandTests > eachVerbRecordsUnderItsOwnName` already asserts
`Set(verbs).isDisjoint(with: packageVerbs)` precisely to protect IH5. The delta text was amended to
the namespaced spellings, with the reason stated in IH1's body. **No code changed.**

## Registered by batch 3, from the verify report, and deliberately not fixed in it

The remediation batch was scoped to the CRITICAL, the two HIGHs and the stale text. These are the
findings it deliberately left alone rather than widening a remediation into a second feature slice.

| Item | Why it is open | What would close it |
|---|---|---|
| **MEDIUM 1** — SM12's three scenarios are the thinnest-covered requirement in the slice | The properties hold structurally (`InstalledModels.swift` and `Sources/Catalog/` are byte-unchanged; `ServicesStore` never reads `InstalledStore`), and the catalog-filter half is already pinned by an exhaustive equality. What is missing is a test that *enumerates* the installed projection's fields and one that drives a deliberate name collision | Two tests in the existing `InstalledFilterFavoritesTests` idiom — cheap, and worth doing in the next slice that touches either surface |
| **MEDIUM 2** — `ServiceDetailView` reports a **failed** detail probe as "No service selected" | The same shape as HIGH 1 with a smaller blast radius: `ServicesStore.select` swallows a failed `services info --json <name>` into `detail = nil` while `selected` stays set, and the view branches on `detail != nil` only. `selected` is already `public`, so the view has everything it needs to say the truth | The HIGH 1 treatment applied again: a projection over (`selected`, `detail`, the probe's outcome) in `ServicesPresentation`, plus a `ServiceDetailView` switch. It needs the store to *keep* the failure reason, which HIGH 1 did not require |
| **MEDIUM 3** — the services list is probed once per launch and once per activation even when Services has never been shown | Not a scenario violation: SM3 forbids *polling* while not visible and separately mandates a baseline on becoming visible, and `InstalledRefreshCoordinator` behaves the same way. But it contradicts SM3's own headline and the design's "zero cost while hidden" framing | A deliberate decision, either way: gate the baseline on visibility too, or state in SM3 that a launch/activation baseline is permitted regardless. MV-2(c) is the check that observes it |
| **MEDIUM 4** — closing one of two windows stops the poll while another window still shows Services | `setVisible` is one shared boolean on an app-lifetime coordinator driven by every `ServicesListView.onDisappear`. SM3 sc3 only requires that never *more than one* loop runs, which still holds. A visibility-refcount gap, not a leak | A refcount or a per-scene identity on the coordinator's visibility input |
| **LOW 3** — the row's Copy-command control always copies `brew services start <name>` | Defensible as a default, but the label says "Copy command" without saying which one | Either label it "Copy start command" or derive it from the service's current status |
| **SUGGESTION** — `ServicesListView` passes a redundant `.tag(service.id)` inside `List(_:selection:)` | Harmless; `List` already derives the tag from `Identifiable` | Delete the modifier |
