# Archive Report: `m5-release-notes`

**Archived**: 2026-08-07 · **Milestone**: PRD **M5** "Pro-parity flows", **slice 3 of 5**
**Status at close**: shipped and merged · **Verify verdict**: PASS WITH WARNINGS (re-verify)
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. Where an intermediate snapshot (`verify-report`) disagreed with
the final state, the final state is recorded here and the snapshot's claim is attributed to its own
moment.

---

## 1. Milestone linkage

- Closes **M5 slice 3 of 5** — pre-upgrade release notes, anchored to PRD.md **M5** (§7), feature
  §3.2 (release notes preview), §4.1 (`ReleaseNotes` target), §4.3 (`api.github.com`, 60 req/h
  unauthenticated, optional PAT).
- **M5 remains OPEN.** Remaining slices: `m5-brewfile`, `m5-health`.
- Slices 1 and 2 (`m5-catalog-inspection`, `m5-discover`) archived 2026-08-06. Slice 1 landed the
  formula URL projection (`urls.stable` / `urls.head`) that this slice consumes; slice 3 spent none
  of slice 1's encoded-snapshot footprint headroom because it added no catalog field.

## 2. Delivery references

| Item | Value |
|---|---|
| Pull request | **#18** (`feature/m5-release-notes` → `main`) |
| Merge commit | **`b71fba4`** |
| Implementation commit | `4be6091` — `feat(release-notes): pre-upgrade release notes from GitHub with consent gate` |
| Lifecycle commit | `61b4d0e` — `docs(sdd): record the m5-release-notes lifecycle` |
| Working tree at archive | clean, branch `main` at `b71fba4` |

## 3. Review gate

Receipt-driven development is **disabled for this clone**. Structured status carried **no
`reviewGate` key** — the key is structurally absent, there is no `disabled/unmanaged` value, and no
review artifact was ever created for this candidate. Per the archive contract, archive proceeded
under **ordinary repository policy**. No review tooling was invoked, and nothing here claims a
review approval that does not exist.

## 4. Task completion gate

**69 / 69 tasks complete; zero unchecked (`- [ ]`) entries** in the archived `tasks.md`, verified
mechanically before any spec sync or folder move. No stale-checkbox reconciliation was needed or
performed.

The tasks artifact grew from the planned 62 tasks (12 phases) to 69 during apply; the additional
tasks were absorbed into the same phase structure.

## 5. Spec sync

**One capability delta, ADDED-only. No existing main spec was modified** — verified by the change
folder containing exactly one delta file, and by the delta carrying no `MODIFIED` / `REMOVED` /
`RENAMED` section.

| Domain | Action | Details |
|---|---|---|
| `release-notes` | **Created** | 9 requirements / 39 scenarios added; 0 modified, 0 removed, 0 renamed |

- **Source**: `openspec/changes/archive/2026-08-07-m5-release-notes/specs/release-notes/spec.md`
- **Promoted to**: `openspec/specs/release-notes/spec.md` (new file; the capability had no main spec)
- **Promotion convention** followed from `2026-08-06-m5-discover`: `# Delta for release-notes` →
  `# release-notes`; the ADDED-only preamble and the traceability paragraph moved into a
  `## Provenance` section; `## ADDED Requirements` → `## Requirements`; the capability-ownership
  paragraph and the design-alignment paragraph carried into the header by shell slice.
- **Byte-slicing verification** — every requirement and scenario byte was moved by shell slice, never
  through the model, and each slice was diffed:

| Readback | Comparison | Result |
|---|---|---|
| Requirement/scenario body | delta `tail -n +30` vs main lines 19–449 | **empty diff** |
| Capability-ownership paragraph | delta lines 6–12 vs main lines 3–9 | **empty diff** |
| Design-alignment paragraph | delta lines 22–27 vs main lines 11–16 | **empty diff** |
| Counts | 9 requirements / 39 scenarios | identical on both sides |

**Destructive-merge check** (config rule "Warn before merging destructive deltas"): **no warning
required** — the delta is ADDED-only and performs zero destructive operations. Nothing was removed
or overwritten in any existing main spec.

The `## Provenance` section records D1–D6 with what each rejected, so a later change cannot
reintroduce a rejected alternative as a fresh idea, and points at the archived `design.md` as
authoritative wherever it is more specific than the spec.

## 6. Configuration correction (user-approved)

`openspec/config.yaml` still recorded `review_budget_lines: 2000` from M3 while every M5 session
governed at 5,000. This drift was flagged at propose and at design (Engram `#7505`) for correction at
archive time, and the user approved fixing it here.

- **Changed**: `review_budget_lines: 2000` → `review_budget_lines: 5000`, with a one-line comment
  recording the M5 session decision.

> **Residual inconsistency, flagged not silently changed.** `openspec/config.yaml` line 55 (under
> `rules.tasks`) still reads *"Forecast the 2,000-line review budget explicitly."* — the same stale
> figure in prose. It was **left untouched** because the approved correction named only
> `review_budget_lines`, and changing a `rules.tasks` guideline exceeds that scope. Until it is
> updated, a future `sdd-tasks` run reads a 2,000-line instruction beside a 5,000-line setting. This
> is carried as a follow-up in §9.

## 7. Verification: the FAIL → remediation → PASS journey

The Engram topic `sdd/m5-release-notes/verify-report` (`#7512`) holds both revisions; revision 1 is
the FAIL and revision 2 is the final PASS, so the journey is auditable in one place.

### verify-1 — FAIL (revision 1, evidence_revision `sha256:1547e3af…`)

One **CRITICAL** blocker: `Fakes/GlobalRequestSpy.swift` counted requests in **process-global mutable
state** with an `install()`/`uninstall()` reset. Under the parallel Swift Testing runner this raced,
and its realistic failure mode was a **false zero** — a test asserting "zero requests were issued"
could pass because another test's `install()` had reset the counter, not because no request was
issued. That is precisely the shape of assertion this capability's central guarantee depends on
("a bulk upgrade issues zero release-notes requests"), so the guard could have vouched for the very
property it was meant to prove. Test evidence at that point: **6 of 6 runs failing**. Spec compliance
was 36 ✅ / 2 ⚠️ / 1 ❌.

### Remediation

The fake was **deleted**, not serialised. `.serialized` would have made the suite green while leaving
the false-zero hazard intact for every future test. It was replaced by a per-instance tagged
`RecordingURLProtocol` / `RecordingNetwork`:

- `canInit` claims a request only when the recorder's **per-instance UUID tag header** is present.
- `static let ledgers = Mutex<[String: Ledger]>([:])` is keyed by that tag, so each recorder reads
  only its own ledger — **no shared counter exists**.
- No `install()` / `uninstall()`, so the false-zero reset hazard has **no analogue**.
- `protocolClasses` is set per-session (replacing the list, not registering globally).
- Uses Swift 6 `Synchronization.Mutex`, not `NSLock` + `nonisolated(unsafe)`.
- Built from the **shipped** `ReleaseNotesSession.configuration()`, so a regression in the real
  session config now fails these tests instead of being bypassed by a hand-rolled config.

Two triangulations were strengthened rather than weakened in the process: `aRevokedGrantIssuesNoRequest`
now drives the shipped `GitHubReleaseNotesSource` through a real `authorise()` grant on the same
transport (v1 used an unrelated `URLSession.shared` call to a dead port), and the runtime
`observedCount == 0` assertion migrated into an exhaustive source-level guard
(`urlSessionAppearsInExactlyOneFile`) that proves no second session exists at all.

**Coverage did not shrink to buy the green** — this was checked explicitly, because a green suite
bought with deleted coverage looks identical to a real fix at the summary line:

| Metric | Before | After |
|---|---|---|
| Package `@Test` / suites | 1396 / 176 | **1396 / 176** |
| ReleaseNotes subset | 187 / 17 | **187 / 17** |
| `#expect` + `#require` across the 5 touched files | 220 | **220** (−1 migrated, +1 strengthened) |
| `@Test` across those files | 77 | **77** |

No test was deleted, disabled, or wrapped in `.serialized`. The diff was confined to five test files,
the deleted fake, and `design.md` / `tasks.md` — **no production source was touched**.

### verify-2 — PASS WITH WARNINGS (revision 2, evidence_revision `sha256:6bd6cf43…`)

**0 CRITICAL · 2 WARNING · 4 SUGGESTION · spec compliance 39 / 39 scenarios ✅.**
Verify-1 was 6/6 failing; verify-2 was **3/3 passing**. The three previously degraded rows — RN-R1
"costs nothing", RN-R3 "no second egress", RN-R9 "spawns no brew process" — all pass on the
per-instance recorder. Verify-1's W1 and W2 were both cleared by documentation corrections
(`design.md` amendments 16, 17 and 18; `tasks.md` 6.7 `data(for:)` → `bytes(for:)` with its reason).

## 8. Test and build state at close

| Layer | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1396 tests / 176 suites green**, exit 0 (1 pre-existing known issue: `OperationCenterCancelTests`) |
| `xcodebuild test -only-testing:cellarTests` | **TEST SUCCEEDED — 66 cases, 0 failures**, exit 0 |
| `xcodebuild build -scheme cellar` | **BUILD SUCCEEDED**, exit 0, **zero warnings** |
| XCUITest (`cellarUITests`) | **not executed** — machine-wide environment breakage, pre-existing and proven on clean `main`. 4 E2E cases were written and statically verified as behavioural (presence + absence assertions). |

The single remaining CellarCore known issue is pre-existing and unrelated to this change.

## 9. Recorded exceptions and authorizations

- **`size:exception` — user-accepted** (Engram `#7509`). Delivered at **~9,800 authored lines**
  (verify-report measured **9,736** authored source+tests after the 64-line fake was deleted, plus
  1,789 lines of OpenSpec lifecycle artifacts) against a **5,000**-line session budget. `sdd-tasks`
  forecast 3,700–4,700 authored with a High 400-line risk and Medium–High 5,000-line risk, and named
  this a real fork; the user chose **Option A** (single PR with `size:exception`), honouring the
  cached `delivery_strategy: single-pr`.
- **Two maintainer-authorized ledger resets** (Engram `#7513`). Recorded as authorizations, **not as
  defects**. The remediation itself ran **279 lines against a 200-line bound** and was authorized by
  ledger reset.
- **Consent disclosure copy — user-approved** (Engram `#7511`), closing design Open Question 2. The
  disclosure names `api.github.com` and states that a repository name reveals this Mac has the
  package installed and is about to upgrade it; it claims no anonymity.
- **E2E environment block — user-accepted** (Engram `#7511`), the basis for WARNING-B below.

## 10. Carried follow-ups (recorded open, deliberately not closed here)

1. **WARNING-A — `CompositionRequestSpy` holds the same false-zero shape, and this change added a
   call site.** `cellarTests/SecurityCompositionSupport.swift:181` (spy body ~179–215) still uses
   `static var count` + `install()` reset + `uninstall()` unregistering a process-wide `SpyProtocol`.
   The **file** is pre-existing M4 and is not this change's defect, but the **call site** at
   `cellarTests/ReleaseNotesCompositionTests.swift:219–236` is new here. Non-blocking: the suite is
   green, the site is untriangulated so its realistic failure is a *vacuous pass* rather than a red
   suite, and the guarded claim is independently proven (`isOffered` is pure; resolver purity is
   proven in CellarCore). **Fix**: fold the M4 spy into the same per-instance tagged shape adopted in
   §7 — this also clears verify SUGGESTION-B. *Line numbers are as of `b71fba4`; re-locate before
   citing them.*
2. **XCUITest environment breakage** — machine-wide, pre-existing, proven on clean `main`. Until it
   is fixed, the 4 E2E cases in this slice (and the E2E layer generally) remain unexecuted.
3. **Slice-1 W2 — decorative assertion**, carried forward from `m5-catalog-inspection`. *Check current
   line numbers before citing.*
4. **S4 — encoded snapshot bound headroom is 2.4%.** This slice consumed **none** of it: no catalog
   change, no `CatalogPackage` field, no schema version move, and `CatalogFootprintTests` passes
   unchanged. Future catalog work still faces the same narrow margin.
5. **`RecordingURLProtocol.ledgers` grows without teardown** (verify SUGGESTION-A). Harmless at
   current scale — entries are small and per-test — but worth a cleanup hook.
6. **`openspec/config.yaml` line 55** still says "Forecast the 2,000-line review budget explicitly."
   See §6.

Remaining verify suggestions, recorded for completeness: **(C)** RN-R1 prose versus `design.md`
amendment 14's non-catalog homepage fallback; **(D)** record the 403 fixture's `content-length: 305`
/ 305-byte invariant.

## 11. Artifact traceability (Engram observation IDs)

Artifacts read in full for this archive:

| Artifact | Topic key | Observation |
|---|---|---|
| Proposal | `sdd/m5-release-notes/proposal` | **`#7504`** (rev 2) |
| Spec | `sdd/m5-release-notes/spec` | **`#7506`** (rev 2; supersedes a 35-scenario version) |
| Design | `sdd/m5-release-notes/design` | **`#7507`** (rev 1) |
| Tasks | `sdd/m5-release-notes/tasks` | **`#7508`** (rev 1) |
| Verify report | `sdd/m5-release-notes/verify-report` | **`#7512`** (rev 1 = FAIL, rev 2 = PASS) |
| **This archive report** | `sdd/m5-release-notes/archive-report` | *saved at close* |

Referenced supporting observations: `#7503` (probe U5 — repository resolution coverage), `#7505`
(design decisions, including the config-drift flag), `#7509` (`size:exception` acceptance), `#7511`
(disclosure copy approval + E2E environment acceptance), `#7513` (two ledger resets), `#7476` (M5
exploration), `#7477` (M5 slice decision round).

## 12. Archive integrity

| Check | Result |
|---|---|
| Main spec created correctly | ✅ `openspec/specs/release-notes/spec.md`, 9 req / 39 scenarios |
| Requirement bodies byte-identical to the delta | ✅ empty `diff` (§5) |
| Change folder moved to archive | ✅ `git mv` → `openspec/changes/archive/2026-08-07-m5-release-notes/` |
| Archived tree byte-identical to pre-move snapshot | ✅ empty `diff -r` |
| Archive contains all artifacts | ✅ `proposal.md`, `specs/`, `design.md`, `tasks.md`, `verify-report.md` |
| Archived `tasks.md` has no unchecked tasks | ✅ 69 / 69 complete |
| Active changes directory no longer holds this change | ✅ removed |
| Other active changes untouched | ✅ `m5-pro-parity`, `m3-4`, `m3-services-cleanup-taps` not touched |

All file movement was mechanical (`cp -R`, `git mv`, shell slicing) and verified by independent
`diff` / `diff -r` readbacks. No artifact content passed through a Read → Write path.

---

**SDD cycle complete.** `m5-release-notes` is planned, implemented, verified, merged (PR #18,
`b71fba4`) and archived. M5 continues with `m5-brewfile` and `m5-health`.
