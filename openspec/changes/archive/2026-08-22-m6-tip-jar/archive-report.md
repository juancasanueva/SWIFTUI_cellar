# Archive Report: `m6-tip-jar`

**Archived**: 2026-08-22 · **Milestone**: PRD **M6** "Ship", **slice 1** — the StoreKit 2 consumable tip jar
**Status at close**: implemented, verified, archived on `feature/m6-tip-jar` — **not pushed, no PR yet**
**Verify verdict**: PASS WITH WARNINGS (round 2) · 0 blockers · 0 CRITICAL
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. Where an intermediate snapshot (`apply-progress`,
`verify-report` round 1) disagreed with the final state, the final state is recorded here and the
snapshot's claim is attributed to its own moment rather than restated as a current fact.

---

## 1. Milestone linkage

- Closes the **FIRST SLICE of PRD milestone M6 "Ship"** (PRD.md :212) — the tip jar. It delivers
  PRD §3.7's Settings tip jar (:124) and the gratitude-based copy rule (:186), and **resolves PRD
  §9 Q2** (:234) as **StoreKit**, superseding :186's earlier external-links ruling.
- **M6 remains OPEN.** This slice closed the tip jar only. Sparkle updates, the CI pipeline, the
  landing page and the remaining Ship work are **other M6 slices**, none of them started here.
- The first four milestones and every M5 slice are already archived; this is the first change
  anchored to M6.

## 2. Delivery references

| Item | Value |
|---|---|
| Branch | `feature/m6-tip-jar` (**not pushed**, **no PR opened**) |
| Merge base | `506e08f` (`main`) |
| Apply commit 1 | `0070264` — `feat(tip-jar): dependency-free TipJar core in CellarCore` |
| Apply commit 2 | `69344a9` — `feat(tip-jar): StoreKit conformer and the one-boolean thank-you` |
| Apply commit 3 | `3463707` — `test(tip-jar): structural sweep over the app target and its tests` |
| Apply commit 4 | `d56fb61` — `feat(tip-jar): wire the tip store into both scenes and amend the PRD` |
| Remediation commit | `20a4576` — `test(tip-jar): close verify's C1 evidence gap and the cheap scanner warnings` |
| Archive commit | this commit — `docs(sdd): archive m6-tip-jar and promote the tip-jar capability spec` |
| Working tree at archive | two **pre-existing** staged files (`cellar/Assets.xcassets/formula.imageset/{Contents.json,formula.png}`) deliberately left **staged and uncommitted**, exactly as they were found |

The two `formula.imageset` files predate this session and belong to the maintainer. `apply-progress`
records that the first apply commit swallowed them because `git commit` writes whatever is already
in the index, and that the four commits were rebuilt from their own trees minus that one path
(`read-tree` → `rm --cached` → `write-tree` → `commit-tree` → `reset --soft`) to restore them. The
archive commit used explicit paths (`git commit -- <paths>`), which is the form that actually scopes
a commit when the index is dirty.

## 3. Review gate

Receipt-driven development is **globally disabled** for this clone (`config.yaml` context line).
Structured status carried **no `reviewGate` key** — the key is structurally absent, there is no
`disabled/unmanaged` value to read, and no review artifact was ever created for this candidate. Per
the archive contract, archive proceeded under **ordinary repository policy**. No review tooling was
invoked, and nothing in this report claims a review approval that does not exist.

## 4. Task completion gate

**40 / 40 tasks complete; zero unchecked (`- [ ]`) entries** in the archived `tasks.md`, verified
mechanically before any spec sync or folder move. No stale-checkbox reconciliation was needed or
performed.

The artifact grew from the planned **29 tasks across 7 phases** to **40 across 8 phases**: phase 8
("Verify remediation (round 1)") added 11 tasks to close verify's blocker and warnings.

> **Hybrid drift, recorded rather than silently reconciled.** The Engram `sdd/m6-tip-jar/tasks`
> topic (`#7644`, revision 1, written 2026-08-21 23:18) was never re-upserted after apply, so it
> still shows the **pre-apply plan**: 29 tasks, 7 phases, every box unchecked. The filesystem
> `tasks.md` — the authoritative persisted tasks artifact for `openspec`/`hybrid` mode, and the one
> the Task Completion Gate reads — shows 40/40 complete. The gate passes on the filesystem artifact;
> the Engram copy is stale history, not a competing claim about completion. A future reader should
> take the archived `tasks.md` as the record.

## 5. Spec sync

**One capability delta, ADDED-only. No existing main spec was modified** — verified by the change
folder containing exactly one delta file, and by the delta carrying no `MODIFIED` / `REMOVED` /
`RENAMED` section.

| Domain | Action | Details |
|---|---|---|
| `tip-jar` | **Created** | 9 requirements / 40 scenarios added; 0 modified, 0 removed, 0 renamed |

- **Source**: `openspec/changes/archive/2026-08-22-m6-tip-jar/specs/tip-jar/spec.md` (460 lines)
- **Promoted to**: `openspec/specs/tip-jar/spec.md` (new file, 517 lines; the capability had no main
  spec)
- **Promotion convention** followed from `2026-08-07-m5-release-notes`: `# Delta for tip-jar` →
  `# tip-jar`; the ADDED-only preamble and the D1–D6 traceability paragraph moved into a
  `## Provenance` section; `## ADDED Requirements` → `## Requirements`; the capability-ownership
  paragraph, the structural-requirements paragraph and the measured-constraints (`probes.md`)
  paragraph carried into the header **by shell slice**.
- **Byte-slicing verification** — every requirement and scenario byte was moved by shell slice
  (`awk` / `tail`), never through the model, and each slice was diffed independently:

| Readback | Comparison | Result |
|---|---|---|
| Requirement/scenario bodies | delta `tail -n +35` vs main lines 23–448 | **empty diff** (exit 0) |
| Capability-ownership + structural paragraphs | delta lines 7–17 vs main lines 3–13 | **empty diff** (exit 0) |
| Measured-constraints paragraph | delta lines 27–31 vs main lines 15–19 | **empty diff** (exit 0) |
| Provenance fragment (authored here) | fragment vs main lines 450–517 | **empty diff** (exit 0) |
| Counts | 9 requirements / 40 scenarios | identical on both sides |

**Destructive-merge check** (`rules.archive`: "Warn before merging destructive deltas"): **no warning
required** — the delta is ADDED-only and performs zero destructive operations. Nothing was removed or
overwritten in any existing main spec, and no other capability's spec was touched.

The `## Provenance` section records D1–D6 plus the D-E amendment with **what each rejected**, so a
later change cannot reintroduce a rejected alternative as a fresh idea — in particular the `.support`
`AppSection`, the `MAS_BUILD` compile flag, the inert/disabled control, and external payment links
beside StoreKit (Guideline 3.1.1 forbids the coexistence).

## 6. Verification: the FAIL → remediation → PASS journey

Both rounds live in one file, `verify-report.md` — round 1 is preserved **verbatim** and round 2 is
appended, so the journey is auditable without reconstructing a superseded document. The Engram topic
`sdd/m6-tip-jar/verify-report` (`#7648`) holds both revisions.

### verify-1 — FAIL (at `d56fb61`)

**1 CRITICAL, 9 WARNING, 4 SUGGESTION — and no functional defect.** The single blocker (C1) was a
**coverage** gap: requirement 3's headline claim — that an *unverified* transaction is still finished
— had no runtime evidence anywhere in either half of the suite. The conformer's verification switch
had two returns and two `finish()` calls, and only the verified branch was ever executed.

### Remediation (`20a4576`)

C1 was closed in **three layers**, not by one assertion:

- **(a) Executed at the decision.** `TipTransactionDisposition.forTransaction(isVerified:)` was
  extracted into `TipJar` with a **stored** `mustFinish`, and three triangulated tests execute it for
  **both** input values. The conformer's switch now only *classifies* (extract transaction +
  `isVerified`); the single `finish()` reached from both branches is already runtime-proven on the
  verified path, so the only branch-dependent input left is `isVerified`, whose mapping to
  `mustFinish == true` is executed for both values.
- **(b) Structural at the call.** `TipCompositionTests.neitherVerificationBranchCanLeaveTheConformerWithoutFinishing`
  guards the extracted `finish(_:)`, with a planted-violation scanner control so the guard cannot
  pass vacuously. The five-assertion bite was verified **by reading** against the old two-return /
  two-`finish` shape.
- **(c) Behavioural.** The pre-existing real-store verified-path test through `SKTestSession`.

**Residual millimetre, disclosed rather than papered over**: StoreKit's own behaviour for a genuinely
unverified transaction remains unminted, because `SKTestSession` cannot produce one. What is proven
is the rule layer plus the call-site structure, not Apple's delivery of that case.

**W1** was closed by **deleting** `ForbiddenSideEffectRecorder` outright (confirmed absent from the
tree) rather than renaming it. Its replacement asserts an exhaustive ordered ledger
(`catalog.callCount == 1`, `events == [.drained, .observed, .purchased]`, read/write `== 1`) — every
clause failable. It does **not** by itself prove no-egress; that rests on the zero-dependency
manifest assertion, and apply says so plainly instead of letting the test name overclaim.

**W3–W6** and the shared `member(named:in:)` extractor were all closed non-vacuously. The extractor
carried a real bug: `range(of: a) ?? range(of: b)` took the **first non-nil** boundary marker rather
than the **nearest**, running two members past the end; `.min()` over all markers replaces it.

### verify-2 — PASS WITH WARNINGS (at `20a4576`)

**0 blockers · 0 CRITICAL · requirements 9/9 · scenarios 40/40**, envelope
`evidence_revision: sha256:1108b4e3…`, admitted by `gentle-ai sdd-verify-validate` (`valid=true`).
Not a clean `pass` because three things are **deferred rather than settled**: requirement 9.5's
end-to-end confirmation needs a healthy UI-automation machine, scenarios 3.2 and 6.3 are worded
against mechanisms the design makes unreachable, and the copy decisions are still the maintainer's.
All three are carried in §10.

> **Superseded snapshot claim, recorded per the Final-State Authority rule.** `apply-progress` line
> 337 (round 2, "Out of scope this round") says requirement 9.5 "must be re-run on a healthy machine
> **before archive**". That was true when written. The later, higher-ranked sources — verify round 2
> and the orchestrator's final-state facts — count 9.5 covered on **structural** evidence with the
> basis stated explicitly, and carry the stronger runtime confirmation as an **open, non-blocking
> follow-up**. Archive proceeded on that ruling; the follow-up is §10 item 1 and is not closed.

## 7. Test and build state at close

| Layer | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1772 executed / 1772 passed**, exit 0 — of which **TipJarTests 40/40** (1 pre-existing known issue: `OperationCenterCancelTests`, unrelated) |
| `xcodebuild test -only-testing:cellarTests` | **194 distinct / 194 passed**, 0 failed, exit 0 — of which `TipCompositionTests` 23, `TipThankYouPreferenceTests` 6, `StoreKitTipSourceTests` 4 |
| `xcodebuild build -scheme cellar` | BUILD SUCCEEDED |
| XCUITest (`cellarUITests`) | **not executed** — the machine's UI-automation environment is invalidated, proven in-session by unmodified `main` failing **29/35** with the identical signature |

Counts reconcile exactly against the round-1 baseline: 188 distinct + 6 new = 194;
CellarCore 1769 + 3 disposition tests = 1772.

## 8. Recorded exceptions and authorizations

- **`project.pbxproj` +7 additive lines — maintainer-accepted** (Engram `#7647`). `project.pbxproj`
  was a *not-touched binding* and it broke. The reason was **measured, not assumed**: with the
  manifest complete and the sources present, the build failed with
  `unable to resolve module dependency: 'TipJar'`. The app target links six package products
  explicitly, and `TipJar` has — by requirement 9 — **no dependents at all**, so nothing else could
  pull it in. What was added is additive only, in the same shape and sequential id scheme as the six
  existing entries: one `PBXBuildFile` line, one `PBXFrameworksBuildPhase` entry, one
  `packageProductDependencies` entry, and one four-line `XCSwiftPackageProductDependency` block.
  **Rejected alternatives**: making an already-linked target depend on `TipJar` (inverts the graph
  and turns a stated architectural fact into a linkage trick) and moving the types into the app
  target (contradicts D-A and requirement 9 outright).
- **The four other not-touched bindings held at exactly 0 lines**, re-checked at `20a4576`:
  `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`, and every `.xcscheme`.
- **Two maintainer-authorized ledger resets** (`m6-tip-jar-reset-1`, `m6-tip-jar-reset-2`; Engram
  `#7647` records the first). Recorded as **authorizations, not defects**: in both cases the overage
  was **SDD bookkeeping lines**, and the code stayed within the change's objectives. At reset 1 the
  4,650 measured lines included 1,799 lines of SDD planning artifacts, leaving code+tests+PRD at
  2,851 — inside the 4,000 budget.
- **Attempt ledger final settle**: `complete` / `passed`.
- **No `size:exception` was required** — the proposal predicted this would be the first M6 slice not
  to need one, and the final measurement agrees. Against the merge base `506e08f..20a4576`: **3,191
  authored changed lines** (code + tests + `PRD.md`, 3,185 additions / 6 deletions) versus a **4,000**
  session budget, with a further 1,925 lines of OpenSpec lifecycle artifacts excluded from the
  authored count.
- **Copy wording is deliberately unsettled** (see §10 item 3) — flagged for maintainer review at PR
  time rather than shipped as though it were decided.

## 9. Accepted deviations from the design

- **`TipCatalogLoader` and `TipPurchaseRunner`** are new types not named in `design.md`. Both were
  extracted from `TipStore` because two of the spec's hardest claims are otherwise unassertable:
  "loading is observable while it is in progress" describes a state that exists only between the call
  and the answer, and "a purchase with no product reaches the seam not at all" is an absence that
  needs a recorder. Every signature `design.md` fixes is unchanged.
- **`TipThankYouPreference`'s observable property is `isTipRecorded`**, not `hasTipped` — the seam
  requires `func hasTipped() async -> Bool`, and Swift will not allow a stored property and a method
  of the same name on one type.
- **Task 1.2's literal instruction was unsatisfiable.** SwiftPM refuses a package containing an empty
  target (`target 'TipJar' referenced in product 'TipJar' is empty`), so "create empty directories and
  confirm it still builds" cannot be run as written. The check it stands for was performed instead:
  `swift package describe` reports `TipJar deps= []`, and the full package suite is green.
- **One test assertion was corrected rather than the code.** `#expect(value as? Int == nil)` was
  written to mean "no tip count was stored", but a `Bool` in a defaults domain returns as an
  `NSNumber`, so `as? Int` succeeds for a flag as readily as for a counter — the assertion was
  factually wrong about Foundation, not about the requirement. It now asserts the value is still `1`
  after **two** recordings, and that the stored type really is `CFBoolean`.
- **`TipProduct.description` is carried but never rendered.** The value maps StoreKit's
  `Product.description` faithfully and `StoreKitTipSourceTests` asserts it came from the store rather
  than from local composition; the card shows the explanation copy instead. Worth a decision when the
  copy is authored — see §10 item 3.

## 10. Carried follow-ups (recorded open, deliberately not closed here)

1. **Requirement 9.5 end-to-end UI run — OPEN, not failed.** The scenario is counted covered on
   structural evidence (`AppTestFixtures.swift` sits inside `AppSecuritySources` scope, so it is
   covered by the importer and token-exclusion sweeps; all six `AppTestTipSource` seam bodies are pure
   values). What is deferred is the stronger runtime confirmation. The machine's UI-automation
   environment was invalidated mid-session — unmodified `main` failed 29/35 with the same signature
   after passing 35/35 earlier. **Re-run condition**: a healthy machine **with a same-session baseline
   control on the merge base**, requiring both a green branch run and a green baseline run. A lone
   green or red run on this machine is worthless in either direction.
2. **Spec wording refinement for scenarios 3.2 and 6.3.** Both are written against mechanisms the
   design deliberately makes unreachable — `SKTestSession` cannot mint an unverified transaction, and
   a zero-dependency `TipJar` has no network or process seam to exercise. Amend the scenario text in
   `openspec/specs/tip-jar/spec.md` to name the evidence mode actually available, so a future verify
   does not re-raise a closed finding.
3. **User-facing copy is a spec-compliant placeholder awaiting maintainer wording.** Every string
   obeys the spec's rules (gratitude, no begging, no countdown, no claim the app is at risk, no
   suggestion any feature depends on tipping, price rendered only by interpolating
   `product.displayPrice`), but the final phrasing is the maintainer's to author. Awaiting review:
   headline `"Say thanks"`; the explanation before and after a tip; button verb `"Tip ·"` / `"Again ·"`
   (price appended from the product); the pending, unverified and failed notes; and the About row
   `"Support"` → `"In Settings"`.
4. **U22 — Mac App Store feasibility spike remains OPEN, and it decides whether this tip jar ever
   transacts in a shipped build.** A StoreKit consumable transacts only in a MAS build, while Cellar
   requires `ENABLE_APP_SANDBOX = NO` to exec `brew`; sandboxed children inherit the container, and
   Guideline 2.5.2 forbids downloading executable code. Recorded openly in `PRD.md` lines 9, 10, 186
   and 234. This slice's success criteria are **build plus local verification**, never "users can tip".
5. **`mustFinish` is a disclosed constant**, so its `if` gate is representational rather than a real
   branch. Revisit only if the finishing rule ever gains a genuine condition.
6. **`cellarUITests/ReleaseNotesUITests` is still unowned** — pre-existing, carried from `m5-health`
   through `m5-release-notes`, not this change's defect and not inherited silently.
7. **No UI test was added by this change.** The `AppTestTipSource` fixture exists to keep existing
   UI-test launches at zero StoreKit and zero egress, which is exactly what the design asked of it —
   not to add coverage.
8. **W7 / W8 accepted deviations** (`TipCatalogLoader` / `TipPurchaseRunner`; pbxproj +7) — recorded
   in §8 and §9, unchanged.

## 11. Learnings worth carrying (three false-green vectors, one project)

This change surfaced a **third** distinct way this project's test tooling can report success over a
failure. All three under-report or mis-report, and `** TEST SUCCEEDED **` plus exit 0 printed
throughout every one of them — that pair remains worthless as evidence here.

1. **A missing `()` in `-only-testing`.** A Swift Testing function identifier without its trailing
   parentheses runs **zero tests** while the build still reports success.
2. **Parallel workers share one StoreKit agent environment.** The shared scheme sets
   `parallelizable = "YES"` and the scheme is a not-touched binding, so `cellarTests` runs across two
   worker processes talking to the **same** StoreKit agent; each worker's `clearTransactions()`
   deleted the leftover the other had just seeded. Mitigated with a `StoreKitAgentLock` flock in the
   test target.
3. **A mangled result line under interleaved output.** Naive `Test case '` anchoring counted 193
   distinct against a 194-name roster; the absentee,
   `BrewfileCompositionTests/confirmingSubmitsAllThreeTapFirst()`, had lost the leading `T` of its
   result line to interleaved parallel-worker output (`est case '…' passed`). It ran and passed. Use a
   truncation-tolerant anchor such as `case '[^']+' (passed|failed)`, and **reconcile against an
   expected roster** — strict counting under-counts here, which fails safe only if something
   independent knows how many tests there should be.

Two further operational learnings: `gentle-ai sdd-verify-validate` rejects a passing verdict when
requirements or scenarios are incomplete ("passing verdict contradicts failing or incomplete
evidence"), so `completed` must equal `total` for `pass`/`pass_with_warnings` — which is why 9.5 was
counted covered on structural evidence **with the basis stated** rather than by silently bumping a
number. And `git commit` writes whatever is already in the index: with a dirty index, explicit-path
`git add` does not scope a commit, but `git commit -- <paths>` does.

## 12. Artifact traceability (Engram observation IDs)

Artifacts read in full for this archive:

| Artifact | Topic key | Observation |
|---|---|---|
| Proposal | `sdd/m6-tip-jar/proposal` | **`#7639`** (rev 1) |
| Spec | `sdd/m6-tip-jar/spec` | **`#7640`** (rev 2 — About row amended to a static informational row) |
| Design | `sdd/m6-tip-jar/design` | **`#7641`** (rev 2 — `TipProduct.description` added; D-E acknowledged) |
| Tasks | `sdd/m6-tip-jar/tasks` | **`#7644`** (rev 1 — pre-apply plan; see the hybrid-drift note in §4) |
| Verify report | `sdd/m6-tip-jar/verify-report` | **`#7648`** (rev 1 = FAIL, rev 2 = PASS WITH WARNINGS) |
| **This archive report** | `sdd/m6-tip-jar/archive-report` | *saved at close* |

Referenced supporting observations: `#7636` (exploration), `#7637` (pre-proposal decision round
D1–D6), `#7638` (probes U16–U21), `#7642` (D-E static About row acknowledged), `#7643` (design
gatekeeper FAIL that produced design revision 2), `#7645` (pre-apply checkpoint), `#7646`
(apply-progress, round 2), `#7647` (ledger reset + pbxproj linkage approval).

## 13. Archive integrity

| Check | Result |
|---|---|
| Main spec created correctly | ✅ `openspec/specs/tip-jar/spec.md`, 9 req / 40 scenarios |
| Requirement bodies byte-identical to the delta | ✅ empty `diff`, exit 0 (§5) |
| Header paragraphs byte-identical to the delta | ✅ two empty `diff`s, exit 0 (§5) |
| Change folder moved to archive | ✅ `git mv` → `openspec/changes/archive/2026-08-22-m6-tip-jar/` |
| Archived tree byte-identical to pre-move snapshot | ✅ empty `diff -r`, exit 0 |
| Source directory gone after the move | ✅ checked explicitly before the readback |
| Archive contains all artifacts | ✅ `proposal.md`, `specs/`, `design.md`, `tasks.md`, `verify-report.md`, plus `explore.md`, `probes.md`, `apply-progress.md` |
| Archived `tasks.md` has no unchecked tasks | ✅ 40 / 40 complete |
| Active changes directory no longer holds this change | ✅ removed |
| Other active changes untouched | ✅ `m3-4`, `m3-services-cleanup-taps`, `m5-pro-parity` not touched |
| Pre-existing staged files preserved | ✅ both `formula.imageset` files still staged and uncommitted |

All file movement was mechanical (`cp -R`, `git mv`, `awk`/`tail` slicing) and verified by
independent `diff` / `diff -r` readbacks. No artifact content passed through a Read → Write path.

---

**SDD cycle complete.** `m6-tip-jar` is planned, implemented, verified and archived on
`feature/m6-tip-jar` (`20a4576` + this archive commit). It closed the **first slice of M6 "Ship"**.
**M6 continues** — Sparkle, CI and the landing page are still ahead, and U22 still decides whether
this tip jar ever transacts.
