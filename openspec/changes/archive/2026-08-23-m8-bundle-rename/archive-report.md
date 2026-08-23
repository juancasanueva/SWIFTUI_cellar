# Archive Report — `m8-bundle-rename`

**One name on disk: `cellar.app` → `Home-Cellar.app`.**

| Field | Value |
|---|---|
| Change | `m8-bundle-rename` |
| Archived | **2026-08-23** → `openspec/changes/archive/2026-08-23-m8-bundle-rename/` |
| Capability touched | `release-distribution` — **3 MODIFIED / 0 added / 0 removed / 0 renamed** |
| Capability after merge | **10 requirements / 42 scenarios** (was 10 / 41) |
| PRD milestone closed | **M6 "Ship"** (`PRD.md:216-217`), specifically its cask-channel line `:194` |
| Shipped as | **`v1.2.0`**, tagged on `c7f9f0f` |
| Verify verdict at close | **PASS WITH WARNINGS** — 0 CRITICAL, 0 blockers (round 2, obs `#7752`) |
| Artifact store | `hybrid` — OpenSpec files + Engram project `swiftui_cellar` |
| Delivery strategy | `single-pr`, across **two repositories** |
| Review gate | **structurally absent** — RDD disabled clone-local; archived under ordinary repository policy |
| Task completion | **59 / 60**, one deliberately open with a live reason (§4) |

> **Final-state notice.** This report describes the change **at close**. `apply-progress.md` and
> `verify-report.md` are intermediate snapshots and are cited as such, with their time and source.
> Where a snapshot says *pending*, *held* or *unreachable* and the work has since completed, this
> report records the **completed** state and names where the completion landed. Two such
> supersessions matter and are called out explicitly: **verify-report W4** (§7) and **the entire
> Phase 7 block** (§4).

---

## 1. Milestone linkage

M6 "Ship" set a 1.0 public release as its exit. The product reached that exit answering to **four
different names for one app**: Finder and the cask said `Home-Cellar`, the release asset was
`Home-Cellar-<version>.zip`, but the bundle on disk was `cellar.app`, the process in Activity Monitor
was `cellar`, and the tap's cask stanza said `app "cellar.app"`. `PRD.md:194` still promised that
`brew install --cask home-cellar` installs `/Applications/cellar.app`.

This slice collapsed those to one. `PRD.md:194` now names `/Applications/Home-Cellar.app`, and M6's
cask-channel line is true as written for the first time.

The moment mattered as much as the change. **D1** — the maintainer's binding decision that the app had
no installed base beyond their own Mac — is what made a rename a rename rather than a migration. That
window closes permanently the first time a stranger installs the app; this slice used it.

---

## 2. Delivery references

### App repository

| Item | Value |
|---|---|
| Branch | `feat/m8-bundle-rename` |
| PR | **#71** — `feat(release): name the delivered bundle Home-Cellar.app` |
| Merge commit | **`c7f9f0f`** (2026-08-23T21:39:39Z) |
| Diff at merge | 16 files, **2,786 insertions / 35 deletions** (2,401 of the insertions are SDD artifacts) |
| Code + docs + tests only | **324 lines** — `release.yml` 2 · `PRD.md` 2 · `README.md` 11 · `RELEASING.md` 16 · `project.pbxproj` 16 · `cellar.xcscheme` 6 · `BundleNamingTests.swift` 240 · `CaskZapInventoryTests.swift` 18 · `release.sh` 13 |

Eight commits, conventional, no `Co-Authored-By`, no AI attribution:

```
c1f5898  docs(sdd): record the m8-bundle-rename proposal, spec delta, design and tasks
f95b9d6  feat(build): rename the product to Home-Cellar and pin the module name      (WU1)
7ae6c89  fix(release): separate the product name from the scheme name                (WU2)
63b48a9  fix(ci): inspect the renamed export path                                    (WU3)
8e01341  docs(release): document Home-Cellar.app as the one installed bundle         (WU4)
8ed3924  docs(sdd): record the m8-bundle-rename apply progress and task evidence
f50becf  docs(sdd): correct the m8-bundle-rename tap ordering to an atomic post-release commit
463b226  docs(sdd): record the m8-bundle-rename round-2 verification (pass with warnings)
```

### Release

| Item | Value |
|---|---|
| Tag | **`v1.2.0`** on `c7f9f0f` (corroborated: `git rev-list -n1 v1.2.0` → `c7f9f0f78b88…`) |
| Release run | **32668275745** — success |
| Asset | **`Home-Cellar-1.2.0.zip`**, 6,469,774 bytes |
| `sha256` | `3e2b5c89dd02449756d38f9f2c7001414063ab0adf2c0f85cbfe88184dcfe259` |
| Content proof | `unzip -Z1` (orchestrator): contains `Home-Cellar.app/`, **zero** lowercase `cellar.app` entries |

### Tap repository — `juancasanueva/homebrew-cellar`

| Item | Value |
|---|---|
| Branch | `feat/m8-bundle-rename` |
| PR | **#1** — `fix(cask): install Home-Cellar.app, the bundle the asset now carries` |
| Held commit | `7c50ee6` — **amended into `35fd080`** (the atomic commit) |
| Merge commit | **`5b4b83c`** (2026-08-23T21:48:53Z) |
| `brew style` | clean |

**Nine minutes separate the app merge from the tap merge.** That interval is the whole R4 window, and
it was held closed deliberately (§6).

---

## 3. Review gate

`reviewGate` is **structurally absent**. Receipt-driven development is disabled clone-local for this
repository, so no review was started for this candidate, zero review code ran, and there is no
receipt, transaction, ledger or gate-context artifact to read or validate.

Per the archive contract this is not a defect to investigate and not grounds to demand a receipt:
archive proceeds under **ordinary repository policy** — the repository's own tests, gates and CI,
all of which are recorded in §8. **No approval is claimed, fabricated or implied.**

---

## 4. Task completion gate

**59 of 60 tasks complete.** One is deliberately open, with a reason that has not expired.

### The Phase 7 block — closed at archive, superseding the snapshots

`verify-report` (obs `#7752`, written 2026-08-23 22:59) recorded **14 tasks incomplete** and asked
archive to *"keep Phase 7 (7.1–7.7) open"*. Every one of those tasks except 7.7 has since been
executed. Recording them as pending would send a future reader to redo finished work, so they are
recorded here as done, each against the evidence that closed it:

| Task | State at snapshot | State at close | Closing evidence |
|---|---|---|---|
| 1.6 | `[ ]` moved to Phase 7 | **done** | discharged by 7.3–7.5; no residual work |
| 6.8 | `[ ]` maintainer action | **done** | PR **#71** merged as `c7f9f0f` |
| 7.1 | `[ ]` pause the bump | **done** | `bump.yml` disabled **before** the tag; re-enabled after the tap merge |
| 7.2 | `[ ]` asset proof | **done** | `unzip -Z1` → `Home-Cellar.app/`, 0 `cellar.app`; `sha256 3e2b5c89…` |
| 7.3 | `[ ]` the atomic commit | **done** | `7c50ee6` amended → **`35fd080`**; `version`+`sha256`+`app` in one commit |
| 7.4 | `[ ]` tap PR merged | **done** | tap PR **#1** merged as `5b4b83c` |
| 7.5 | `[ ]` restore the schedule | **done** | both tap workflows (Bump, CI) active again |
| 7.6 | `[ ]` ME1 | **done** | observed on the maintainer's Mac (§7) |
| 7.8 | `[ ]` honesty statement | **done** | discharged verbatim by the round-2 verify report itself |
| 8.1–8.4 | `[ ]` archive obligations | **done** | executed by this phase (§5, §11) |

This is a **reconciliation against higher-ranked final-state evidence**, not a stale-checkbox repair:
each task named above describes work that genuinely happened after the snapshots were written, and
each is cited to the artefact that proves it.

### The one task left open — 7.7 (ME2)

> *"A self-updated app does not fight `brew upgrade`."*

ME2 requires a **Sparkle self-update of a cask-installed copy of the renamed build**. `v1.2.0` is that
build and it is now installed — but **no newer stable release exists for it to update to**, so the
precondition is still unreachable. This is the same structural reason it was unreachable before the
tag, not a step that was skipped or forgotten.

It is left `[ ]` on purpose. Marking it done would be an inference, not an observation, and the
`manual-evidence` class exists precisely to refuse inferences. The `m6-cask-tap` slice observed ME2
and archived it passing — but that observation binds `cellar.app`, the **old** bundle name, so it is
not evidence for this one. Carried forward in §12.

---

## 5. Spec sync

`openspec/specs/release-distribution/spec.md` — merged, then hand-edited.

### Promoted blocks (3 MODIFIED, whole-block replacement)

| Requirement | Scenarios | What moved |
|---|---|---|
| A pushed tag is the only thing that produces a downloadable release | 6 | the bundle inside the asset becomes **`Home-Cellar.app`**, with executable `Contents/MacOS/Home-Cellar`; the bundle identifier `com.juancasanueva.cellar` becomes **requirement text** |
| The delivered build is installable through the project's Homebrew tap | **7** (+1) | installed path becomes `/Applications/Home-Cellar.app`; the old "MUST NOT rename it" clause is replaced by the new invariant; the **atomic-post-release ordering** and the **no-migration-mechanism** rule become binding text |
| Uninstalling states exactly what it removes, and what it cannot | 4 | the documented installed bundle becomes `Home-Cellar.app`, with a one-name exclusivity clause; the inventory itself is explicitly unmoved |

The merge was performed **mechanically** — the delta's block byte-ranges were spliced into the main
spec with `sed`, never re-typed. Five `diff` readbacks were run and all five were empty: the preamble,
the 7 untouched requirements, and the whole `## Provenance` section are **byte-identical** to before;
the two spliced regions are **byte-identical** to the delta.

### Counts — measured against the merged file, not trusted from the note

```
### Requirement:   10
#### Scenario:     42
- Verification:    42     unit 18 · ci-gate 18 · manual-evidence 6
```

The `## Verification classes` table needed exactly one cell changed: **`ci-gate` 17 → 18**. `unit` (18)
and `manual-evidence` (6) were already correct. The note's prediction and the measurement agree.

`rules.archive`'s destructive-delta warning **did not fire**: nothing was removed or renamed.

### Hand-edits outside every requirement block (R7 — six passages)

A MODIFIED delta structurally cannot carry prose that lives outside a requirement block. All six were
re-located **by content** (line numbers had drifted by the merge) and edited by hand:

| Original ref | Passage | Treatment |
|---|---|---|
| `:567` | `m6-release-pipeline` **D4/D7** — "containing `cellar.app` with display name `Home-Cellar`" | **historical** — decision kept verbatim, annotated that the bundle inside the zip is `Home-Cellar.app` since `v1.2.0` |
| `:601` | inherited-contract stanza — "the cask's `app` stanza **must name** `cellar.app` exactly" | **updated in place** — see below |
| `:619` | `m6-sparkle-updates` probe **U31** — `Contents/MacOS/cellar` stayed `arm64` | **historical** — measurement preserved exactly as taken, annotated that the executable is now `Contents/MacOS/Home-Cellar` and that the architecture finding is unaffected |
| `:686-688` | `m6-cask-tap` **D3** — "this change MUST NOT rename it", `app "cellar.app"`, rejection of `target:` | **historical + closure** — records that `m8-bundle-rename` performed the rename D3 deferred, **and that D3's rejection of `target:` still stands**, because the cask names the new bundle *directly*, which is not the rejected alternative |
| `:706` | the "now CONSUMED" paragraph — "its `app` stanza to `cellar.app`" | **historical** — binding kept, annotated as since moved |
| `:718-720` | the deferred-slice list — "the `Home-Cellar.app` rename (its own slice …)" | **deferred → LANDED**, with its "update continuity for every installed 1.0.0 copy" clause marked **closed by D1**; the other two deferred items stay deferred |

**`:601` was the only one rewritten rather than annotated, and that asymmetry is the point.** The other
five record what was *measured* or *decided* at a past moment — rewriting them would falsify the audit
trail. `:601` states a **live requirement in the present tense** ("must name `cellar.app` exactly"), so
leaving it annotated-but-intact would have left the file contradicting its own merged requirement. It
was updated to `Home-Cellar.app` and carries a note that `m8-bundle-rename` superseded it.

A `## Provenance` amendment entry for `m8-bundle-rename` was added following the house convention,
recording the delta shape, D1, D2, the +1 scenario, and the R4 ordering rationale.

---

## 6. What shipped — and the ordering that made it possible

### The two settings that carry the whole change

```
PRODUCT_NAME = "Home-Cellar"  ──┬──→ EXECUTABLE_NAME  ──→ Contents/MacOS/Home-Cellar
                                └──→ FULL_PRODUCT_NAME ──→ Home-Cellar.app

PRODUCT_MODULE_NAME = cellar  ──X──  severs $(PRODUCT_NAME:c99extidentifier); module stays `cellar`
```

Without the second pin, the Swift module would silently have become `Home_Cellar` and **22
`@testable import cellar` files** would have failed to compile. That default was **measured**, not
inherited from documentation — the R5 probe was run before the edit, after the edit, and independently
again by `sdd-verify`, and the three permitted lines are the only ones that moved.

### Binding 0-line diffs, held end to end

| Invariant | Proof at close |
|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar` | unchanged in pbxproj ×2; **and confirmed on the installed 1.2.0 app** — `CFBundleIdentifier` reads `com.juancasanueva.cellar` |
| Swift module name | `PRODUCT_MODULE_NAME = cellar` ×2; 22 imports, **zero** Swift source edits |
| `Packages/CellarCore/` and `cellar/` | `git diff --stat` → **empty**. No app or core source file was touched |
| `bump.yml` **content** | `git diff --stat` → **empty**. Only its schedule *state* was toggled |
| zap inventory / Keychain items | unmoved — every write root derives from the bundle identifier, not the product name |

**The rename moved names. It moved no data, and it moved no identity.** The maintainer launched the
reinstalled app and confirmed all data was present — bundle-id-keyed persistence carried over exactly
as D1 predicted.

### R4 — the ordering constraint, and why both obvious answers were wrong

This is the substantive lesson of the cycle.

A cask's `app` artifact must name the bundle its declared version actually contains. The automated bump
path gates only on `brew style` and `brew audit`, and **neither extracts the archive nor resolves the
`app` artifact** — so a mismatched cask **audits clean and installs broken**. Both naive orderings
produce exactly that:

- **Tap first** — the tap would declare `app "Home-Cellar.app"` against the published **`v1.1.0`**
  asset, which contains `cellar.app`. Misnamed immediately.
- **Tag first, tap later** — `bump.yml` runs `17 */6 * * *` and rewrites only `version` and `sha256`.
  It would land the new version against the **old** `app` stanza. Same defect, other direction.

Only one shape works: **publish the renamed asset → pause the bump → land ONE commit moving `version`,
`sha256` and `app` together → restore the bump.** That is now binding requirement text, not a note.

**And that is exactly what executed:**

```
c7f9f0f  app PR #71 merged                         21:39:39Z
         bump.yml disabled  ← BEFORE the tag (race-safe)
v1.2.0   tagged on c7f9f0f → run 32668275745 → Home-Cellar-1.2.0.zip
         unzip -Z1 → Home-Cellar.app/ , zero cellar.app     (7.2 gate passed)
35fd080  version 1.2.0 + sha256 3e2b5c89… + app "Home-Cellar.app"  ← ONE commit
5b4b83c  tap PR #1 merged                          21:48:53Z
         bump.yml re-enabled  ← immediately after
```

The pause preceded the tag, which is the part that makes it race-safe: had it been disabled after
tagging, a scheduled bump could have fired in between and reproduced the defect.

---

## 7. Verification — a two-round story

### Round 1 — **FAIL** (`sha256:31506165…0b23b33d`)

**C1 (CRITICAL): R4's "tap before the tag" ordering was unsatisfiable.** The spec delta, the design and
the task ledger all encoded "tap merges first" — and the verifier re-downloaded the published `v1.1.0`
asset, measured it, and found `cellar.app` inside. A tap merged ahead of the renamed release would
declare a version whose asset it misnames. The instruction could not be followed by anyone.

Three warnings accompanied it: **W1** the tap branch was based on stale `main` and would have regressed
the cask 1.1.0 → 1.0.0; **W2** the R7 archive list named 3 passages when 6 were out-of-block; **W3** a
scenario was counted compliant on build evidence when it asserts a property of the extracted zip.

This is a blocker that only an independent re-derivation finds. Every artifact in the chain agreed with
every other artifact; they were consistently wrong. What broke the agreement was measuring the actual
published bytes.

### Round 2 — **PASS WITH WARNINGS** (obs `#7752`, `sha256:9e05ac70…0c0533e3`)

**C1 closed on the merits**, verified against four independent things rather than against the
remediation's own claims: the re-downloaded `v1.1.0` asset, `bump.yml`'s schedule and gates, the held
tap commit's content and message, and the Phase 7 task ledger. **W1, W2, W3 all closed.** **S1** accepted
and independently confirmed; **S2** declined with a genuine reason and carried forward.

| Metric | Value at round 2 |
|---|---|
| Verdict | `pass_with_warnings` — **0 blockers, 0 CRITICAL** |
| Requirements | 3/3 |
| Scenarios | 16/16 to their declared classes — **5 runtime-proven**, 9 `ci-gate` execution-pending, 2 `manual-evidence` pending |
| Build | `** BUILD SUCCEEDED **` (exit 0) |
| `cellarTests` | `** TEST SUCCEEDED **` (exit 0) — 247 executed cases, 0 failures |
| `CellarCore` | 1793 tests / 210 suites passed, 1 known issue — identical to baseline, zero-line causal surface |
| TDD compliance | 7/7 checks |
| Assertion quality | 0 tautologies, 0 orphan absence assertions, 3 anti-overreach guards |

### W4 — **discharged**, and this is the supersession that matters most

> *"The held tap commit is **prepared**, not yet **atomic**. `sdd-archive` must not treat `7c50ee6` as
> already satisfying R4."* — `verify-report`, obs `#7752`, 2026-08-23 22:59

At the time it was written this was exactly right and well-reasoned. `7c50ee6` carried
`version "1.1.0"` + `sha256 a6d5c68d…` + `app "Home-Cellar.app"` — three values that did **not**
describe the same release. It was the "audits clean, installs broken" cask its own requirement forbids,
held safe only by being unpushed and by a `HOLD — DO NOT MERGE` line in its commit message. The verifier
was warning archive not to be fooled by the word "atomic" appearing in the remediation's prose.

**That state no longer exists.** `7c50ee6` was amended into **`35fd080`**, which moves
`version "1.2.0"`, `sha256 3e2b5c89dd02449756d38f9f2c7001414063ab0adf2c0f85cbfe88184dcfe259` and
`app "Home-Cellar.app"` **together in one commit**, after `v1.2.0` published and after `unzip -Z1`
proved the asset carries the renamed bundle. `brew style` clean; merged as `5b4b83c`.

**W4 is therefore discharged, not waived and not overridden.** The mechanism the amended R4 prescribes
executed exactly as written. The warning did its job: it survived the hand-off, archive checked the
tap's state rather than the prose, and found the work done.

### ME1 — observed on the maintainer's Mac, 2026-08-23

> *"A tap and an install put the released build in `/Applications`."*

| Check | Observed |
|---|---|
| `brew uninstall --cask home-cellar` | removed `/Applications/cellar.app` |
| `brew install --cask home-cellar` | installed **`/Applications/Home-Cellar.app`** |
| `CFBundleShortVersionString` | **1.2.0** |
| `CFBundleIdentifier` | **`com.juancasanueva.cellar`** — unchanged across the rename |
| `brew list --cask --versions` | `home-cellar 1.2.0` |
| `spctl -a -vv` | **accepted**, source = **Notarized Developer ID** — no Gatekeeper refusal |
| App launch | launched; **all data present** |

**One deviation, recorded rather than smoothed away:** the uninstall receipt showed stale **1.0.0**
metadata — the `Homebrew/brew#22993` shape, which explore had already recorded as a known brew defect.
Artifact removal worked correctly regardless. This is brew's receipt bookkeeping, not a defect in this
change, and it is not evidence of anything about the rename.

---

## 8. Gate state at close

| Gate | State |
|---|---|
| `xcodebuild build` | ✅ `** BUILD SUCCEEDED **` |
| `cellarTests` | ✅ 247 executed cases (237 distinct functions), 0 failures |
| `CellarCore` | ✅ 1793 / 210 suites, 1 known issue, matching baseline |
| Release run 32668275745 | ✅ success — asset published, notarized, stapled |
| Tap `brew style` | ✅ clean |
| Tap PR #1 CI | ✅ merged green |
| `cellarUITests` | ⚠️ **2 pre-existing failures remain open on `main`** — see §12 |
| Lint | ✅ no new warnings (2 pre-existing, outside edited ranges) |
| Size vs governing 5,000-line budget | ✅ **Low** — no `size:exception` needed |

---

## 9. Decisions recorded, with what each rejected

**D1 — the app has no users yet** (binding, maintainer, 2026-08-23). *Rejected in consequence:* every
migration mechanism (`target:`, a `/Applications/cellar.app` zap entry, `uninstall delete:`,
`SUBundleName`), all old-name user guidance, and any in-app notice. A zap must not delete a bundle the
cask never placed. Explore risks **R1/R2/R3** (Sparkle orphaning a copy at the old path; duplicate
bundles for direct-download users; brew#22993 orphaning on `--greedy`) describe an installed base that
did not exist — recorded as facts, deliberately **not** mitigated.

**D2 — all three proposal defaults accepted.** `cellar.xcarchive` stays (**DD-4**; a build intermediate
no user sees — this closed **R8** by decision rather than by omission). The Xcode target and the
`cellar/` folder are **never** renamed (*rejected:* explore Approach 1 — the largest blast radius for
the smallest visible gain). The product/module divergence is accepted and documented (*rejected:* 22
mechanical import edits to align them).

**DD-2 — `EXECUTABLE_NAME` follows to `Home-Cellar`.** *Rejected:* Approach 3b, pinning it to `cellar`
to save four changed lines. `Contents/MacOS/cellar` is what Activity Monitor and `codesign -dvvv`
print; pinning it would have re-created the exact inconsistency the slice exists to delete.

**R6 — the case-sensitive assertion was updated, never widened.** `CaskZapInventoryTests:335` went RED
because `"Home-Cellar.app"` does not contain `"cellar.app"` — the capital `C` **is** the assertion. It
was updated to assert the new name; it was not "fixed" by lowercasing, by `caseInsensitiveCompare`, or
by relaxing the substring.

---

## 10. Deferred items dispositioned at archive

| # | Item | Disposition |
|---|---|---|
| **S2** | `design.md:216` calls `ReleasePipelineCompositionTests:94` / `UpdateProjectFileTests:68` "guards"; they are helper `.filter`s | **APPLIED.** Verified first: both lines are the *only* sites naming the identifier in those files, and both are block-selection `.filter`s inside `appTargetBuildConfigurationBlocks()`, not assertions. The row now says so — and records *why they are still load-bearing*: if the identifier moved, the filter would select 0 blocks and every dependent `blocks.count == 2` assertion would fail. Load-bearing as a filter, not as a guard |
| **S3** | Three sites said "247 distinct ids", which is measurably wrong | **APPLIED.** `apply-progress.md:119`, `:144` and `tasks.md:424` now read "executed cases". The correct reconciliation is **237 distinct functions − 3 parameterized + 13 runs = 247 executed cases** |
| **S4** | S2's decline was recorded in `apply-progress.md` but not in the Phase 8 list archive reads | **Moot** — S2 is applied above, so nothing evaporated between phases |

Both corrections were applied **before** the folder was archived, and both were made with surgical
single-line shell edits, never by re-typing artifact content. Correcting a wrong `file:line` reference
was worth doing while the trail was still writable: the next slice's baseline comparison is exactly
where a false discrepancy would surface.

---

## 11. Archive integrity

### Mechanical operations, with mandatory readbacks

| Operation | Mechanism | Readback |
|---|---|---|
| Spec merge | `sed` byte-range splice into `openspec/specs/release-distribution/spec.md` | **5 × `diff` — all empty.** Preamble, 7 untouched requirements, and the whole `## Provenance` section byte-identical to before; both spliced regions byte-identical to the delta |
| Archive move | `git mv openspec/changes/m8-bundle-rename → openspec/changes/archive/2026-08-23-m8-bundle-rename` | **`diff -r` against a pre-move recursive snapshot — empty.** Source directory confirmed gone |

No artifact content passed through a Read → Write path. Empty diffs are the only passing evidence and
they are what was produced.

### Archive contents

```
2026-08-23-m8-bundle-rename/
├── explore.md
├── proposal.md
├── design.md
├── tasks.md              (59/60 complete; 7.7 open with reason)
├── apply-progress.md
├── verify-report.md      (round 2 — PASS WITH WARNINGS)
├── archive-report.md     (this file — additive, excluded from the readback)
└── specs/release-distribution/spec.md
```

### Hybrid-store parity — stated honestly

The round-2 verify report confirmed the OpenSpec files and their Engram twins were byte-identical for
`spec.md`, `tasks.md` and `apply-progress.md` **at that time**. This phase then edited three of those
files by design — ticking Phase 7/8 in `tasks.md`, and applying S2/S3 to `design.md` and
`apply-progress.md`.

**Those three Engram twins (`#7749`, `#7750`, `#7751`) are therefore point-in-time snapshots from their
authoring phase and no longer byte-match the archived files.** They were deliberately **not** re-saved:
doing so would require routing artifact content back through model generation, which is precisely the
truncation hazard the mechanical-copy contract forbids.

**After archive, the archived OpenSpec files under
`openspec/changes/archive/2026-08-23-m8-bundle-rename/` are the authoritative audit trail.** The Engram
twins remain useful for recovery and search, not for byte-comparison. This drift is recorded rather
than silently tolerated.

---

## 12. Carried follow-ups — recorded open, deliberately not closed here

1. **ME2 / task 7.7 — "A self-updated app does not fight `brew upgrade`" for the renamed bundle.**
   Unreachable until a release newer than `v1.2.0` exists for an installed copy to update to. The
   `m6-cask-tap` observation binds `cellar.app` and does not transfer. **Binding, and it still stands:
   never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (Engram `#7724`) — use
   `brew upgrade --cask --dry-run home-cellar`.
2. **Two `cellarUITests` failures remain open on `main`** —
   `testTapDetailFilteringInstalledHandoffAndForceDisclosure` and
   `testTapsNavigationOfficialSourcesAndAddConfirmation`. **Not part of this change**: both were proven
   to fail identically at `main f0a5817` with none of this change applied, and they trace to
   `m7-tap-trust` untap-sheet element matching. The app launched normally in every run
   (`title: 'Home-Cellar'`), so the rename is not implicated.
3. **The bump's next scheduled run has not yet been observed as a no-op.** Restoring the schedule was
   task 7.5's obligation and it is done; observing idempotence is the `ci-gate`'s job on the next cycle.
4. **Still deferred from `m6-cask-tap`, unchanged by this slice**: moving `~/Library/Caches/Cellar`
   under the bundle identifier (a genuine migration — deliberately not folded in here, which would have
   turned a zero-data-movement change into a data-migration change); and submission to `homebrew/cask`
   (notability requirements unmet — the self-hosted tap is the channel).

---

## 13. Learnings worth carrying

1. **Measure the artifact, not the plan.** Round 1's blocker was invisible to every artifact in the
   chain because they all agreed with each other. Re-downloading the published `v1.1.0` asset and
   running `unzip -Z1` is what proved the ordering unsatisfiable. Consistency across documents is not
   evidence; bytes are.

2. **A gate that does not read the thing it protects will pass a broken artifact.** `brew style` and
   `brew audit` never extract the archive or resolve the `app` stanza, so a cask naming a bundle its
   asset lacks audits perfectly clean and installs broken. That single fact generated the whole R4
   ordering constraint — and it is why the constraint became **requirement text** rather than a note.

3. **Pause before you tag, not after.** Disabling `bump.yml` *before* pushing `v1.2.0` is what made the
   window race-safe. Reversed, a scheduled run could have fired between the tag and the atomic commit
   and landed the exact mismatch the whole design existed to prevent.

4. **Pin the derived setting you are about to invalidate.** `PRODUCT_MODULE_NAME` defaults to
   `$(PRODUCT_NAME:c99extidentifier)` and was declared in no file. Changing `PRODUCT_NAME` alone would
   silently have renamed the Swift module to `Home_Cellar` and broken 22 imports. The default was
   *measured* with `-showBuildSettings` before and after, not inherited from documentation.

5. **Historical prose gets annotated; live requirements get rewritten.** Five of the six provenance
   passages record what was measured or decided at a past moment, and rewriting them would falsify the
   audit trail. The sixth stated a binding contract in the present tense and had to be corrected, or the
   spec would have contradicted itself. Telling those two cases apart is the whole skill.

---

## 14. Artifact traceability (Engram observation IDs)

| Artifact | Topic key | Obs ID |
|---|---|---|
| Exploration | `sdd/m8-bundle-rename/explore` | **#7745** |
| Decisions (D1, D2) | `sdd/m8-bundle-rename/decisions` | **#7746** |
| Proposal | `sdd/m8-bundle-rename/proposal` | **#7747** |
| Spec delta | `sdd/m8-bundle-rename/spec` | **#7748** |
| Design | `sdd/m8-bundle-rename/design` | **#7749** |
| Tasks | `sdd/m8-bundle-rename/tasks` | **#7750** |
| Apply progress | `sdd/m8-bundle-rename/apply-progress` | **#7751** |
| Verify report (round 2) | `sdd/m8-bundle-rename/verify-report` | **#7752** |
| Archive report | `sdd/m8-bundle-rename/archive-report` | *this document* |

Round 1's verify report (`sha256:31506165…0b23b33d`, FAIL) was superseded in place by round 2 under the
same topic key — Engram upserts overwrite. Its findings survive in round 2's *Round-1 Findings Closure*
table and in §7 above, which is why that table exists.

---

## Final state

The app answers to **one name**. `/Applications/Home-Cellar.app`, `Contents/MacOS/Home-Cellar`,
`Home-Cellar-1.2.0.zip`, display name `Home-Cellar`, cask token `home-cellar` — and, underneath all of
them and deliberately unmoved, `com.juancasanueva.cellar`.

The documentation describes exactly one install path with no "but it is actually called…" caveat. The
tap's `app` stanza resolves against the asset the release job publishes. No migration mechanism exists
anywhere, because none was ever owed.

**Cycle complete.** Planned, specified, designed, implemented under strict TDD, verified across two
rounds, shipped as `v1.2.0`, installed and observed on real hardware, and archived.
