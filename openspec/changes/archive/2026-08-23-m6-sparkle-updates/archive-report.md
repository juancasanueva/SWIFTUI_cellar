# Archive Report: `m6-sparkle-updates`

**Archived**: 2026-08-23 · **Milestone**: PRD **M6** "Ship", **slice 3 of 3** — Sparkle 2 in-app updates
**Status at close**: implemented, verified, **merged to `main`**, archived — PR #60 merged at `3655dbc`
**Verify verdict**: PASS WITH WARNINGS · 0 blockers · 0 CRITICAL · validator-admitted
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started, delivery under ordinary repository policy

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate
snapshots archived alongside it; where either disagrees with the final state, the final state is
recorded here and the snapshot's claim is attributed to its own moment rather than restated as a
current fact.

---

## 1. Milestone linkage

- Closes the **THIRD AND FINAL in-repository slice of PRD milestone M6 "Ship"** (PRD.md :212). It
  delivers PRD :188 — "Sparkle 2: EdDSA-signed appcast hosted on GitHub Pages… In-app 'Check for
  updates'" — completes the :9 Distribution line (which read "Sparkle updates pending
  `m6-sparkle-updates`"), and **settles the :168 external-service row**, whose appcast-host decision
  had been explicitly deferred to this slice. GitHub Pages is the host; no off-GitHub deploy
  credential was introduced.
- It also **amends PRD :124 away**: the PRD promised an update-**channel picker** this slice
  deliberately does not build (decision **D4**), and `SettingsView.swift:9-15` forbids an inert row.
  The promise was rewritten in place with its reason rather than left as an undelivered commitment.
- **M6 is not yet closed.** Slice 1 was the tip jar (built, then removed —
  `openspec/changes/archive/2026-08-22-m6-tip-jar/`). Slice 2 was the release pipeline
  (`.../2026-08-23-m6-release-pipeline/`). This is slice 3. Still outside every archived slice:
  **`m6-cask-tap`** (a different repository), the landing page, and **the actual `v1.0.0` tag**.
- **This slice is the first M6 slice that ships user-visible behaviour.** The release pipeline was
  infrastructure; this one adds a Settings group, an app-menu command, and an update mechanism that
  runs on every installed copy.

## 2. Delivery references

| Item | Value |
|---|---|
| Branch | `feature/m6-sparkle-updates` — **still present on `origin` at close** (not deleted, unlike the previous slice) |
| PR | **#60** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/60 |
| PR title | `feat(updates): Sparkle 2 auto-updates with appcast publication on GitHub Pages (m6-sparkle-updates)` |
| Merged | **2026-08-23T08:29:28Z** (10:29:27+02:00), merge commit `3655dbc` on `main` |
| Merge base | `215540b` (`main`) |
| Branch head | `119573d` |
| Commits | 16 (below) |
| Delivery strategy | `exception-ok` — **ONE PR under an accepted `size:exception`** (maintainer chose one PR over the recommended split; see §8) |
| Archive commit | this commit — `docs(sdd): archive m6-sparkle-updates and promote the app-updates capability spec` |

| # | Commit | Subject |
|---|---|---|
| 1 | `b5bb0fc` | `docs(sdd): plan m6-sparkle-updates` |
| 2 | `9332ffe` | `build(app): declare the developer-tools application category` |
| 3 | `53720aa` | `build(app): link Sparkle 2.9.6 as a pinned package dependency` |
| 4 | `ae9aa14` | `build(app): merge a partial property list carrying the update feed` |
| 5 | `85807be` | `test(updates): pin the repository to one Ed25519-shaped literal` |
| 6 | `7481b4e` | `build(app): commit the real Sparkle public verification key` |
| 7 | `b355ef4` | `feat(updates): add a dependency-free Updates target to CellarCore` |
| 8 | `8d0b7d1` | `build(app): link the CellarCore Updates product` |
| 9 | `2725b7a` | `feat(updates): add the Updates settings card, menu command and wiring` |
| 10 | `3ef89c9` | `docs(third-party): attribute the embedded Sparkle framework` |
| 11 | `b7ea75a` | `feat(release): add the appcast build script` |
| 12 | `0c96f4c` | `ci(release): publish the appcast to GitHub Pages on a stable tag` |
| 13 | `b893c54` | `docs(release): document the update feed, its key and its prerequisites` |
| 14 | `a5f8511` | `docs(sdd): record m6-sparkle-updates apply progress` |
| 15 | `ab46446` | `docs(sdd): correct apply-progress test counts and PR size after validation` |
| 16 | `119573d` | `docs(sdd): record m6-sparkle-updates verification report` |

Commits 2–13 are the twelve implementation work units. Commit 15 is the fresh-context apply
validation correction (§10); commit 16 landed the verification record.

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not
a defect to investigate:

- Receipt-driven development is **disabled clone-local** for this repository (session preflight
  `RDD disabled`). With the kill switch off, zero review code ran for this candidate, so no
  transaction, ledger, receipt or gate context was ever created and none exists to read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #60 proceeded under **ordinary repository policy**, and archive proceeds the same
  way — identical to every prior slice.
- Consequently the `sdd/m6-sparkle-updates/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES.** `tasks.md` carries **66 checked** items and **3 unchecked** items (69 total). Every
unchecked item is verified below to be a `manual-evidence` observation that cannot exist yet, so **no
stale-checkbox reconciliation was performed and none was needed**. `tasks.md` was archived unmodified.

| Group | Items | State | Why unchecked is correct |
|---|---|---|---|
| Phase 3a app-side (`A0`–`A7`) + Phase 3b publication (`B1`–`B3`) | 62 | **all checked** | Every RED/GREEN task executed and marked by `sdd-apply`, re-executed and confirmed by `sdd-verify`. |
| `B4.1`–`B4.4` maintainer checkpoints and local rehearsal | 4 | **all checked** | Discharged during apply: the seventh secret, Pages enablement, `scripts/release.sh all` with Sparkle embedded (notarization **Accepted**), and the exported-bundle re-checks. |
| `B4.5`, `B4.6`, `B4.7` | 3 | unchecked | Declared in `tasks.md` under the section heading "**not test tasks, not merge blockers**". Each requires a **pushed tag that does not exist**: a live appcast URL (`B4.5`), an observed rc→stable self-update plus an offline Gatekeeper relaunch and a job-log key sweep (`B4.6`), and a prerelease run publishing no feed entry (`B4.7`). |

**The publication half is DEFERRED-TO-TAG by design, not incomplete work.** All four upstream
artifacts (`proposal.md` *Prerequisites*, `specs/app-updates/spec.md` verification-class table,
`design.md` Tier 4, `tasks.md` §B4) declared these items non-merge-blocking **before** apply started.
They are blocked on a release event, not on code anyone could have written. The ordered checklist is §9.

## 5. Spec sync

| Domain | Action | Details |
|---|---|---|
| `app-updates` | **Created** | ADDED-only — **7 requirements / 31 scenarios**. 0 modified, 0 removed, 0 renamed. |
| `release-distribution` | **Updated** | MODIFIED-only — **3 requirements replaced in full**, 0 added, 0 removed, 0 renamed. **8 req / 29 sc → 8 req / 32 sc**. |

**`app-updates` — the project's 22nd capability** (21 existed before this archive):
`openspec/specs/app-updates/spec.md`, 419 lines.

- **No destructive delta.** `rules.archive`'s "warn before merging destructive deltas" clause **did
  not fire** for this domain: nothing was modified, removed or renamed.
- **What the main spec adds over the delta**, following the convention established by
  `openspec/specs/release-distribution/spec.md`: the `# app-updates` header replaces
  `# Delta for app-updates`; the `## Requirements` wrapper replaces `## ADDED Requirements`; a
  `## Verification classes` heading replaces the delta's "Admissibility under `rules.specs`" framing;
  and a `## Provenance` section is appended.
- **What the main spec drops**, all of it SDD-process framing with no bearing on the capability: the
  ADDED-only delta-count sentence, the session-preflight block, the `rules.specs` admissibility
  judgment prose, the D-decision traceability line (re-expressed at length in `## Provenance`), and
  the "Notes for archive" section.

**`release-distribution` — non-destructive amendment**:

- `rules.archive`'s destructive-delta clause **applies in its weaker sense** — three requirement
  blocks were replaced wholesale — and was judged, not waived. **No scenario was removed**: the
  scenario count was measured **29 before / 32 after** (`rg -c '^#### Scenario:'`), all **8**
  requirements survive with unchanged names and order, and the five requirements the delta did not
  reproduce are byte-identical to their `m6-release-pipeline` text. The staged diff is
  **+62 / −5**, and every one of the five deleted lines belongs to a reworded requirement paragraph
  or the architecture scenario it governs.
- **The `## Verification classes` table was hand-updated**, from `unit` 13 / `ci-gate` 12 /
  `manual-evidence` 4 (total 29) to `unit` **14** / `ci-gate` **14** / `manual-evidence` **4**
  (total **32**). That table lives outside every requirement block, so a MODIFIED delta structurally
  cannot carry it; the delta's *Notes for archive* stated the obligation, and this step **did not
  trust the note** — the arithmetic was confirmed against the merged file by counting
  `- Verification:` lines, which returned exactly 14 / 14 / 4.
- The three edits: **(a)** a stable tag now also publishes the update feed and a prerelease tag
  publishes none (**+2 `ci-gate` scenarios**); **(b)** the arm64 claim now binds the **application
  executable**, allowing a vendored prebuilt framework to carry extra slices (**D2**; 0 scenarios
  added, the architecture scenario reworded to follow); **(c)** the referenced secret set is now
  **closed and enumerated at seven** (**+1 `unit` scenario**).
- **The fourth MODIFIED block never fired.** Scoping the stowaway scenario to exclude
  `Contents/Frameworks/` was pre-authorised **only** if probe `U32` fired. It did not — the sweep
  returned empty on the built bundle *and* on the exported, notarized bundle — so
  `release.sh:252-254` is unchanged and the scenario stands as written. The pre-authorisation was
  spent correctly: nothing was quietly amended.
- The archived delta specs under
  `openspec/changes/archive/2026-08-23-m6-sparkle-updates/specs/` remain the verbatim audit trail.

## 6. What shipped

**59 files changed, +7,085 / −24** against `215540b` — of which **8 files / 3,621 lines** are the SDD
artifacts themselves. Authored product and infrastructure change: **51 files, +3,464 / −24**.

| Path | Change |
|---|---|
| `Packages/CellarCore/Sources/Updates/{AppVersion,AppcastDocument,UpdateCheckPresentation,AppUpdating,UpdatePolicy}.swift` | **New** — the dependency-free `Updates` target (DD-1). `AppVersion` is `Sendable, Hashable, Comparable` with a typed `AppVersionParseFailure`; `AppcastDocument` is an **offline validator over XML text** using Foundation `XMLParser` only (DD-8); `UpdatePolicy.swift` holds the two pure decisions DD-15 moved out of the app target. |
| `Packages/CellarCore/Tests/UpdatesTests/**` + 14 XML fixtures | **New** — `AppVersionTests`, `AppcastDocumentTests`, `UpdateCheckPresentationTests`, `AppUpdatingTests`, `UpdatePolicyTests`, `FakeAppUpdater`. |
| `Packages/CellarCore/Package.swift` | **Modified** — `.library(Updates)`, a target with **no `dependencies:` key at all**, and a test target carrying `Fixtures`. |
| `cellar/Updates/{SparkleUpdateChecker,AutomaticUpdateChecks,UpdatesSettingsGroup,CheckForUpdatesCommands}.swift` | **New** — 0 pbxproj lines (`cellar/` is a synchronized root group). `SparkleUpdateChecker` is **the only file in the repository that imports Sparkle**. |
| `cellar/{cellarApp,Settings/SettingsView,AppTestFixtures}.swift` | **Modified** — DI wiring, the Updates group after "Interface", and the UI-test route to an in-memory `AppTestUpdater`. |
| `Resources/Cellar-Info.plist` | **New** — exactly two keys, merged into the bundle at build time: `SUFeedURL` and the **real** `SUPublicEDKey` `jqReS/…/ZDVs= (redacted here: the repository's key-literal guard requires exactly one occurrence, in `Resources/Cellar-Info.plist`)`. Held **outside** `cellar/` because a `.plist` inside a synchronized root group ships as a bundle resource. |
| `cellar.xcodeproj/project.pbxproj` | **Modified — exactly 29 insertions, 0 deletions**, the ten binding items and no eleventh key. Both app-target blocks stay byte-identical modulo `name`. |
| `cellar.xcodeproj/.../swiftpm/Package.resolved` | **New** — pins Sparkle 2.9.6, revision `ac2def28…`. |
| `scripts/appcast.sh` | **New** — fetch the live feed, verify a pinned tool by sha256, sign the asset with the key on **stdin**, merge one `<item>` newest-first, emit. Zero `git`, zero `gh`, no `set -x`. |
| `.github/workflows/release.yml` | **Modified** — job `permissions` (`contents: write`, `pages: write`, `id-token: write`) plus `environment: github-pages`, and four publication steps at the existing extension point, each guarded by `if: !contains(github.ref_name, '-')`. |
| `cellarTests/{UpdateCompositionTests,BundleUpdateKeysTests,UpdateProjectFileTests,AutomaticUpdateChecksTests,AppcastWorkflowTests,AppcastScriptContractTests,UpdateKeyMaterialTests,UpdatePackageManifestTests}.swift` | **New** — 8 structural suites. |
| `cellarTests/ReleasePipelineCompositionTests.swift` | **Modified** — T14/T15 only (the six-secret set becomes seven). |
| `THIRD-PARTY.md`, `RELEASING.md`, `PRD.md`, `README.md` | **Modified** — Sparkle attribution (D7: the sole attribution surface); `RELEASING.md` §2 prerequisites 6–8 and "Six" → "Seven repository secrets", §7 gains the appcast/feed row and **deletes** the now-discharged `LSApplicationCategoryType` follow-up; PRD :9/:124/:168/:188/:212 rewritten in place with reasons. |

**Binding 0-line diffs held.** `scripts/release.sh`, `scripts/ExportOptions.plist`,
`cellar/Shell/AboutView.swift` and `cellar/InfoPlist.xcstrings` are untouched — confirmed by
`git diff main --stat` returning nothing for all four. `theWorkflowCanOnlyEverCreateARelease` passes
**unamended** (`gh` = 1, `git` = 0). No `.entitlements` file exists anywhere in the repository.
Nothing new was added under `cellar/` except `.swift`.

## 7. Verification

**Verdict: PASS WITH WARNINGS.** Envelope `gentle-ai.verify-result/v1`, verdict
`pass_with_warnings`, **0 blockers, 0 CRITICAL**, requirements 10/10, scenarios 35/35,
`test_exit_code 0`, `build_exit_code 0`. Admitted by
`gentle-ai sdd-verify-validate --requirements 10 --scenarios 35` → `valid: true`. Evidence revision
`sha256:166d32d305264176d6dc6dc9a79a5a918e1dce64ce3486fb6d770e24152bd4f7`; canonical report bytes
`sha256:8b0d8659f881d2646ddf98963fd3d1fb93e38c35cd8edc28d4e9e91cd9da7e32` (32,889 bytes).

**Scenario-count derivation** (why 35 and not 47): `app-updates` contributes all **31** of its
scenarios. The `release-distribution` delta *reproduces* 16 scenarios because the MODIFIED convention
requires whole-block reproduction, but only **4** are change-owned (RD-a1, RD-a2, RD-b, RD-c); the
other 12 are verbatim carry-overs already discharged by the archived `m6-release-pipeline`.
31 + 4 = **35**.

**Compliance by declared verification class:**

| Class | Count | State at close |
|---|---|---|
| `unit-core` (app-updates) | 19/19 | Runtime-PROVEN — executed and green. |
| `unit-app` (app-updates) | 11/11 | Runtime-PROVEN — executed and green. |
| `manual-evidence` (app-updates) | 0/1 observed | AU-S16, the self-replacement itself. **Deferred to the first stable tag.** |
| `unit` (release-distribution, change-owned) | 1/1 | Runtime-PROVEN (RD-c, the seven-secret set). |
| `ci-gate` (release-distribution, change-owned) | 3/3 | Structurally verified. RD-b additionally **re-measured** locally and on the exported bundle; RD-a1 / RD-a2 execution pending the first tag. |

**31 of 35 scenarios are runtime-proven by a test that passed during verification.** The other four
require a pushed tag that does not exist. 0 UNTESTED, 0 FAILING.

**Nineteen independent runtime and structural checks** were executed by verification beyond the test
suites, each read-only at `ab46446`. The load-bearing ones: the partial plist carries exactly two
keys and the key base64-decodes to **32 bytes** (not a placeholder); the built bundle's `Info.plist`
carries `SUFeedURL`, `SUPublicEDKey` and `LSApplicationCategoryType` while
`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` / `SUScheduledCheckInterval` are all **absent**;
`Sparkle.framework` is embedded; `lipo` reports the app executable `arm64` and the framework
`x86_64 arm64`; the stowaway sweep is empty; exactly **one** file imports Sparkle; the `Updates`
target has no `dependencies:` key; the workflow references exactly the **seven** named secrets;
`shellcheck` and `actionlint` both exit 0.

**Two apparent violations were run down and cleared** rather than reported as findings: a naive
`rg '\bgh '` over `release.yml` returns 2 and `rg 'set -x'` over `appcast.sh` returns 1 — both
matches are inside **comments that explain the very prohibition they name**. The owning tests match
command tokens over comment-stripped text and carry non-vacuity floors, so the prohibitions hold.

**Warning disposition at close** — all seven warnings are recorded open; **none blocks archive**, and
none was silently downgraded.

| # | Warning (per `verify-report`, Engram `#7690`) | State at close |
|---|---|---|
| W1 | Three tasks incomplete (`B4.5`–`B4.7`), all structurally undischargeable before a tag | **DEFERRED-TO-TAG by design, not incomplete** — see §4 and §9. |
| W2 | Four scenarios not runtime-proven; the **real `sign_update` invocation has never run** | **OPEN and carried.** The highest residual risk in this slice — a malformed signature would be discovered on the first stable tag, not before. |
| W3 | The `size:exception` overrun is larger than the one the maintainer accepted | **OPEN, recorded not smoothed** — see §8. |
| W4 | `cellarUITests/ReleaseNotesUITests` remains unowned since `m5-health` | **OPEN, inherited** — not this slice's defect; carried forward in §11. |
| W5 | DD-12 residual gap: a private key committed in a format that is **not** 44-char base64 evades both sweeps | **OPEN by design** — disclosed at design, re-confirmed at verify, not closed. |
| W6 | Pages deploy is a **full-site replacement** | **OPEN and now load-bearing** — the empty Pages root is a maintainer decision (Engram `#7681`), so any future landing page must be built by the **same** job or it strands every installed copy. |
| W7 | The private key is a one-way door | **OPEN and permanent.** Apply records the offline backup as done; verify could not check an offline backup and did not claim to. |

**Four SUGGESTIONS, all non-required.** Two were acted on at archive: **S1** (the forwarded preflight
header in the delta specs and `tasks.md` still reads `delivery_strategy=single-pr` while the resolved
value is `exception-ok`) is **recorded here rather than edited into the archived artifacts** — the
archive is an audit trail and the artifacts are frozen as written; the resolved strategy is stated in
§2 and in `tasks.md`'s own Q4 block. **S2** (the exact torn log line behind the 215-vs-216 gap) is
carried into §8 so the discrepancy is never re-litigated. **S3** (T25 was a tasks-phase addition
covering AU-S28, which the design's requirement→check map left unbound) and **S4** (the design's
≈28-vs-29 pbxproj arithmetic slip) are recorded in §10 rather than back-edited into the archived
`design.md`, for the same reason.

**Assertion quality audited across all 13 new test files (194 assertions):** zero tautologies, zero
assertions that never call production code, zero ghost loops — the sweeping tests carry explicit
non-vacuity floors (`#expect(scanned > 100)`, `#expect(sources.count > 10)`, and a test that asserts
a real `set` **is** visible so "no `set -x`" cannot pass by seeing nothing). The suites assert **exact
counts** rather than presence — *exactly one* importer, *exactly two* rows, *exactly seven* secrets,
*exactly one* key literal — which is what makes a silent future addition fail rather than pass.

## 8. Test, gate and size state at close

| Measure | Value at close | Superseded value (and its source) |
|---|---|---|
| `cellarTests` `@Test` functions | **216 passed / 0 failed** | `apply-progress.md` originally recorded 183 → 215 from the raw log; corrected to **184 → 216** by the fresh-context apply validator in `ab46446` (see the artifact's trailer). |
| `cellarTests` baseline at `215540b` | **184** | Confirmed independently: `rg -c '@Test' cellarTests/*.swift` = 184 at `main`, 216 at HEAD, Δ **+32**. |
| CellarCore | **1,753 tests / 209 suites passed**, 0 failed, **1 known issue** (pre-existing) | was **1,732 / 204** at `215540b` — Δ **+21 tests / +5 suites**. |
| `xcodebuild build` (Release, `CODE_SIGNING_ALLOWED=NO`) | `** BUILD SUCCEEDED **`, exit 0 | |
| `swift build --package-path Packages/CellarCore` | clean | |
| `shellcheck scripts/appcast.sh` | exit 0, no findings | |
| `actionlint .github/workflows/release.yml` | exit 0, no output | |
| swiftlint | clean, one accepted `optional_data_string_conversion` warning matching the identical accepted warning at `ReleasePipelineCompositionTests:448` | |
| `U30` local release rehearsal | **PASS** — notarization `Accepted`, id `593818bf-c3db-460d-b674-3db6078732b6` | |
| `deploy-pages` / live feed | **NOT RUN** — feed returns `404`, correct pre-tag state | |

**The 215-vs-216 gap is resolved, not assumed.** `xcodebuild` tore one log line in two:
`Test case 'AutomaticUpdateChecksTests/thePreference` … *(an interleaved
`IDETestOperationsObserverDebug` block)* … `WritesExactlyOneKey()' passed`. The test **passed**; a
line-oriented count drops the id, a byte-oriented one finds it. Same failure mode as the previous
slice's 183/184 drift, from the same tool.

**Size and delivery budget — the honest numbers:**

| Measure | Value |
|---|---|
| Authored product + infrastructure change | **3,488 changed lines** (3,464+ / 24−) across 51 files |
| SDD artifacts | **3,621 lines** across 8 files |
| **PR total at merge (`215540b`…`119573d`)** | **7,109 changed lines** (7,085+ / 24−) across **59 files** vs the governing **5,000** budget — overrun **≈2,109 lines (≈42%)** |
| Delivery strategy | `exception-ok` — **ONE PR under an accepted `size:exception`** |
| Chained PRs | **recommended by `sdd-tasks`** (option A: 3a app-side now, 3b publication as a follow-up change) and **declined by the maintainer** in favour of option B, one PR |

**Label correction, recorded rather than resolved silently.** The archive launch prompt described
"code-only ≈6,671 changed lines". Direct measurement contradicts that label: **6,671** is the
**whole-PR** figure at `ab46446` (58 files, 6,647+ / 24−) — the number `verify-report.md` measured
before its own commit added the 438-line report — not a code-only figure. Measured at the merged head
`119573d`: whole PR **7,109**, code-only **3,488**. Both figures are reproducible with
`git diff --shortstat 215540b 119573d` and the same command excluding
`openspec/changes/m6-sparkle-updates/*`. The overrun is therefore **larger** than every intermediate
account of it: the accepted exception anticipated ≈1,411 lines over budget, `verify-report.md`
measured ≈1,671, and the final figure is **≈2,109**. Still within the granted exception *in kind* —
the maintainer chose one PR knowingly — but the number moved twice and the archive says so.

**Attempt ledger:**

| Attempt | Request id | State |
|---|---|---|
| apply | `apply-3a-3b` (acquire → `state: proceed`, zero ledger mutation) | not settled by the apply executor; validated in a fresh context as **PASS-WITH-WARNINGS** |
| verify | `m6-sparkle-verify-settle-001` | `complete` |

## 9. Deferred to the first stable tag — the exact remaining checklist

**None of these blocked the merge. All of them block calling this capability proven.** Unlike the
previous slice, **every maintainer prerequisite is already MET** — what remains is a release event.

**Prerequisites, all discharged before merge and re-measured at verification:**

| # | Prerequisite | State |
|---|---|---|
| P1 | Repository public | ✅ `visibility: public` |
| P2 | Developer ID Application certificate | ✅ installed; exercised by the `U30` rehearsal |
| P3 | App Store Connect API key | ✅ `GF2PP6LZ22` |
| P4 | **Seven** repository secrets incl. `SPARKLE_PRIVATE_KEY` | ✅ `gh secret list` → 7 (the seventh added 2026-08-23T07:33:58Z) |
| P5 | EdDSA keypair generated, public key committed, **private key backed up offline** | ✅ public key `jqReS/…/ZDVs= (redacted here: the repository's key-literal guard requires exactly one occurrence, in `Resources/Cellar-Info.plist`)` in `Resources/Cellar-Info.plist`; private key in the login Keychain with an offline backup (Engram `#7686`) |
| P6 | GitHub Pages enabled, source = GitHub Actions | ✅ `has_pages: true`, `build_type: workflow`. The site root is **intentionally empty for v1** — the artifact carries only `appcast.xml`, and the root `404` is an accepted maintainer decision (Engram `#7681`) |
| P7 | `github-pages` environment admits **tag** refs | ✅ **resolved during this cycle** — see §10 deviation 1 |

**Then, in order, at the first stable tag:**

1. **Push `v1.0.0`.** This is the single event that discharges everything below.
2. **`B4.5` / M4 / `U33`** — `curl -fsSI https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`
   → `200` with an XML content type, after the first `deploy-pages` run. **Watch the `deploy-pages`
   step specifically**: it is the only step in the whole pipeline that has never executed.
3. **`B4.6` / M5 / M6 / M7** — install the `v0.0.1-rc.1` build into `/Applications`, let the
   already-published stable tag be found, and watch the update install and relaunch. **rc → rc is
   impossible under D4**, so the rehearsal must be rc-installed → stable-published. Then confirm
   Gatekeeper accepts the **replaced** bundle with **networking disabled**, and sweep the job log for
   the key's value — **zero** occurrences, `SPARKLE_PRIVATE_KEY` appearing only as `***`.
   This discharges **AU-S16**, the one scenario that proves the capability actually works.
4. **`B4.7` / RD-a2** — push a prerelease tag and confirm the four guarded steps are skipped and the
   live feed is byte-unchanged.
5. **`m6-cask-tap`** — the last M6 shipping slice, in the separate repository
   `juancasanueva/homebrew-cellar`.

**The single highest residual risk**: the real `sign_update` invocation has **never run**. Apply's
script harness exercised the guard, the 404-fetch, the digest verification, the extraction, the merge
and the emit for real, and stubbed exactly one line — the signing call — because the private key is a
repository secret. If the signature is malformed, every installed copy rejects the update and the
symptom appears at the first stable tag, not before.

## 10. Accepted deviations from the design

Fourteen were declared at apply time; verification re-read each against the code and judged them
**design-refining and spec-preserving**. The ones that matter:

1. **The `github-pages` environment excluded tag refs** — apply's deviation 1, reported as a **red
   blocker for the first publishing tag**. The environment carried `custom_branch_policies: true`
   with exactly one policy, `{"name":"main","type":"branch"}`, while the release job runs on `v*`
   **tag** refs. **DD-13's pre-costed second-job fallback does not fix it**: a second job runs on the
   same tag ref and hits the same policy — DD-13 addresses protection *rules* on the release job, not
   a *ref* policy. **RESOLVED before merge**, by a repository settings change rather than code: the
   `github-pages` environment now carries `{"name":"v*","type":"tag"}` alongside `main`, verified by
   `gh api …/environments/github-pages/deployment-branch-policies` → `total_count: 2`. Apply's text
   still calls it a blocker; that text is a snapshot of apply time and is superseded here.
2. **pbxproj is 29 insertions, not the design's ≈28.** The design's own itemisation of the Sparkle
   dependency sums to 19 while its prose says 18; the measured diff is 19. Ten items, no eleventh
   key, both app-target blocks byte-identical modulo `name`. **An arithmetic slip in the design, not
   a scope change** (verify SUGGESTION S4).
3. **`AppcastValidationFailure` gained three cases the design's enumeration omitted** —
   `.missingVersion(item:)`, `.missingShortVersionString(item:)` and `.malformedDocument`. Required
   by AU-S12's "naming the missing field"; the design's case list had no case for it. An improvement
   over the design, not drift.
4. **The design's placeholder property list does not parse.** `<string><!-- … --></string>` fails
   `PropertyListSerialization` with *"Encountered improper CDATA opening"*. Moot once the real key
   landed, but it would have blocked the build exactly as written.
5. **BSD `awk -v` rejects a newline inside a value** — found by *running* `appcast.sh`, not by
   reading it. The design's merge shape would have failed on the first real tag, on the macOS runner.
   The item now goes through a file and is read with `getline`.
6. **`appcast.sh` asserts the signing tool's output shape.** T19 requires the literals
   `sparkle:edSignature` and `length=` in the script, but with the fragment approach neither appears
   — both come from `sign_update`. Rather than satisfy the test with a comment, the script aborts if
   either attribute is missing from the fragment. **A tool whose output shape changed would otherwise
   publish an item every installed copy rejects.**
7. **`Xcode` rewrote `project.pbxproj` on first build**, quoting `INFOPLIST_FILE` (the value contains
   a hyphen) and re-sorting package product dependencies. The canonical serialisation was adopted and
   the test pins the **quoted** form — pinning the unquoted one would have passed exactly once.
8. **`T15` was green on arrival** and is the only non-RED row in the 22-row TDD table. Apply recorded
   it as a deviation rather than presenting it as a TDD cycle, which is the correct behaviour.
9. **D-1 amendment (approved by the maintainer, 2026-08-23):** the proposal's "LITERAL and BINDING"
   pbxproj list grew from **7 to 10 items** to cover linking the CellarCore `Updates` product. Amended
   in the proposal in place, with the evidence cited (6 of 7 products are linked explicitly).
10. **`UpdatesSettingsGroup` reproduces `SettingsView`'s card shape** (~25 lines) instead of making
    the private helpers internal — keeping the rollback boundary at one file plus one line.
11. **`A7.2` moved into `B3.1`**, as `tasks.md` specifies under option (B).
12. **`T25` is a tasks-phase addition** discharging AU-S28, which the design's requirement→check map
    left unbound. A genuine gap the tasks phase caught (verify SUGGESTION S3).

**Probes, all measured, none assumed:** **U24** (`INFOPLIST_KEY_SU*` are dropped by Xcode's generator
— the partial `INFOPLIST_FILE` merge is the *measured* fallback, not a guess); **U25** (SPM
auto-embeds and re-signs `Sparkle.framework` with **no** Embed Frameworks phase — the pre-costed
~10-line deviation was **withdrawn** — and Sparkle's API compiled under `-swift-version 6
-default-isolation=MainActor` with **zero** Sparkle-related diagnostics); **U30** (notarization
`593818bf-c3db-460d-b674-3db6078732b6` **Accepted**, and `codesign --verify --strict --verbose=2`
green over **all five** nested objects: `Sparkle`, `Autoupdate`, `Updater.app`, `Downloader.xpc`,
`Installer.xpc` — the gate was **not** relaxed); **U31** (the framework is universal — D2's allowance
is exercised, not theoretical); **U32** (**does not fire** — no stowaways). **U33 remains open by
design** and is discharged only by the first stable tag.

## 11. Carried follow-ups (recorded open, deliberately not closed here)

**`m6-cask-tap`** — the last M6 shipping slice, in the separate repository
`juancasanueva/homebrew-cellar`. Cask token `home-cellar`, `app "cellar.app"`, `depends_on arch:
:arm64`, `depends_on macos: ">= :tahoe"`, and **`auto_updates true`** — which is now load-bearing
rather than notional, because Sparkle owns updates as of this slice and a Sparkle-replaced cask
install would otherwise diverge from what `brew` recorded (PRD :189).

**The first stable tag** is a follow-up in its own right — see §9. It is not another SDD change; it
is a release event that discharges four scenarios and three tasks.

**Open, recorded, not owned by this slice:**

- **`cellarUITests/ReleaseNotesUITests` is still unowned** since `m5-health`. Confirmed present on
  disk and outside the `-only-testing:cellarTests` scope. Stated rather than inherited silently.
- **DD-12's residual gap**: a private key committed in a format that is **not** 44-character base64
  evades both `UpdateKeyMaterialTests` and `repositoryCarriesNoCredentialMaterial`. The exact-count
  guard that replaced the broad sweep is false-positive-free and strictly stronger for the shape it
  covers; this shape it does not cover.
- **The Sparkle update window is plain AppKit in the system appearance**, mismatching the dark-only
  `.hiddenTitleBar` shell. Accepted for v1; a custom driver is a v1.1 item.
- **Release-notes presentation in the update window** (`<description>` / `sparkle:releaseNotesLink`)
  is deferred out of v1 — populating it crosses the existing release-notes consent gate and belongs
  to its own change. Sparkle's window simply shows no notes.
- **The landing page (PRD :190) must be built by the same `deploy-pages` job.** Pages publishes a
  whole-site artifact, so a second job deploying a landing page would silently overwrite
  `appcast.xml` and strand every installed copy. The empty Pages root is a decision (Engram `#7681`),
  and it is now a decision with consequences.
- A PR/test CI workflow, SwiftLint adoption, a DMG, and PRD §9 Q1 (final name and icon) remain open
  from earlier slices.

## 12. Learnings worth carrying

**A. Three failures the design could not have caught by reading, and one it introduced.** Apply found
all four by *running* the artifacts: BSD `awk -v` rejects a newline inside a value (the design's
merge shape would have failed on the first real tag, on the runner, with no local symptom); the
design's placeholder plist does not parse because a comment inside a `<string>` element is
*"improper CDATA opening"*; the signing tool's output shape needed an explicit assertion because the
literals the test demands come from the tool, not the script; and Xcode rewrites `project.pbxproj` on
first build, so a test pinning the *unquoted* `INFOPLIST_FILE` would have passed exactly once. The
pattern from the previous slice repeats: **shell and build-tool behaviour is measured, never
reasoned about.**

**B. A pre-costed fallback can be pre-costed against the wrong failure.** DD-13 pre-authorised a
second `appcast:` job in case the `github-pages` environment carried protection rules incompatible
with the release job. The environment did block the release — but by a **deployment-branch-ref
policy**, not a protection rule, and a second job runs on the same tag ref and hits the same policy.
The fallback was well-reasoned and simply did not address the failure that arrived. The real fix was
one repository setting: add a **tag** rule matching `v*`. Worth carrying: **name the mechanism a
fallback defeats, not just the outcome it avoids**, or a future reader will reach for it reflexively.

**C. A well-formed placeholder is worse than no feature.** A fake 44-character base64
`SUPublicEDKey` satisfies the 32-byte-decode test, is indistinguishable from a real key at review,
and ships builds that can **never** update themselves — every signature fails and the only recovery
is telling every user to re-download by hand. The proposal made key generation a maintainer
checkpoint **inside apply**, before the plist task, precisely so the real key landed in the PR. That
sequencing is the reusable part.

**D. Two sweeps for the same byte shape cancel each other out.** A raw Ed25519 *private* key is 44
base64 characters with no header — byte-shape-identical to the *public* key this change commits on
purpose. Any pattern broad enough to catch one catches the other, and a filename allow-list is a
guard that passes because it was told to. DD-12 replaced the broad sweep with an **exact-count**
guard: the repository contains exactly one Ed25519-shaped literal, and it is the committed public
key. Strictly stronger for what it covers — a second key anywhere fails it — and the residual gap
(a key in some other format) is stated rather than smoothed. The same exact-count discipline shows up
across this slice's suites: *exactly one* importer, *exactly two* Settings rows, *exactly seven*
secrets. **Presence assertions let additions pass; count assertions make them fail.**

**E. `xcodebuild` tore a log line again, and the reconstruction is worth keeping.** The 215-vs-216
gap was not a renamed or parameterized test: line 365 ends mid-identifier at
`AutomaticUpdateChecksTests/thePreference` and line 377 resumes with
`WritesExactlyOneKey()' passed`. Verification located and quoted the exact split rather than
attributing it generically, which is what makes the count re-derivable instead of re-litigable. Count
`@Test` occurrences in the source as the cross-check; the log alone is not trustworthy.

**F. A moving overrun should be reported every time it moves.** The accepted `size:exception`
anticipated ≈1,411 lines over budget; apply measured ≈1,460 then ≈1,668; verify measured ≈1,671; the
final merged figure is **≈2,109**. Each phase reported its own number honestly, and the drift is
visible only because none of them rounded to the previously accepted one. The maintainer's decision
stands, but the decision was made against the smallest of five numbers.

## 13. Artifact traceability (Engram observation IDs)

Every artifact was retrieved in full via `mem_get_observation`, not from a search preview.

| Artifact | Engram obs | Topic | Archived file |
|---|---|---|---|
| explore (incl. the measured **U24 addendum**) | **`#7680`** | `sdd/m6-sparkle-updates/explore` | `explore.md` |
| decisions (D1–D5, maintainer-accepted) | **`#7681`** | *(also carries the empty-Pages-root decision)* | — (Engram only) |
| proposal (incl. the **D-1 amendment**, 7 → 10 pbxproj items) | **`#7682`** | `sdd/m6-sparkle-updates/proposal` | `proposal.md` |
| spec (both deltas) | **`#7683`** | `sdd/m6-sparkle-updates/spec` | `specs/app-updates/spec.md`, `specs/release-distribution/spec.md` |
| design (**revision 2**, corrective rerun) | **`#7684`** | `sdd/m6-sparkle-updates/design` | `design.md` |
| tasks (+ orchestrator gate and prerequisite correction) | **`#7685`** | `sdd/m6-sparkle-updates/tasks` | `tasks.md` |
| EdDSA public key record | **`#7686`** | `cellar/sparkle-eddsa-key` | — (Engram only) |
| apply-progress | **`#7687`** | `sdd/m6-sparkle-updates/apply-progress` | `apply-progress.md` |
| Pages tag-ref discovery | **`#7688`** | *(deviation 1 evidence)* | — (Engram only) |
| state | **`#7689`** | `sdd/m6-sparkle-updates/state` | — (Engram only) |
| verify-report | **`#7690`** | `sdd/m6-sparkle-updates/verify-report` | `verify-report.md` |
| **archive-report** | *this file* | `sdd/m6-sparkle-updates/archive-report` | `archive-report.md` |

**Known-lossy mirrors — the archived file is authoritative:**

- **`#7684` (design)** is condensed against Engram's 50,000-character truncation; `design.md` is 658
  lines and is the authority.
- **`#7682` (proposal)** records the D-1 amendment as a decision note and states in its own text that
  the file is authoritative for the amended section.
- **`#7685` (tasks)** is the authoring-time snapshot, so its checkboxes read unchecked. The archived
  `tasks.md` carries the apply-time completion state (66 checked) and is the authority for §4.

`review/*` topics do not exist — see §3.

## 14. Archive integrity

**Mechanical copy contract satisfied.** No artifact byte passed through a model read/write path.

| Operation | Mechanism | Readback | Result |
|---|---|---|---|
| `app-updates` — capability-ownership paragraph | `sed -n '7,11p'` | `diff` vs delta 7–11 | **empty** |
| `app-updates` — class table + design-owned paragraph | `sed -n '33,46p'` | `diff` vs delta 33–46 | **empty** |
| `app-updates` — requirement and scenario bodies | `sed -n '56,373p'` | `diff` vs delta 56–373, re-run **after** the provenance append | **empty** |
| `release-distribution` — 3 MODIFIED blocks | `sed -n '47,121p'`, `'123,182p'`, `'184,242p'` | `diff` vs each delta range | **empty** (×3) |
| `release-distribution` — 4 preserved regions | `sed -n` from the pre-merge main spec | `diff` vs each original range | **empty** (×4) |
| Change folder → archive | `git mv` | `diff -r` vs a pre-move recursive `cp -R` snapshot | **empty**, exit status 0 |
| Rename fidelity | — | `git diff --cached -M --name-status` | **8 files, all `R100`** |

All seven `release-distribution` segments and all three `app-updates` segments were diffed
individually against their sources; every diff was empty. Scenario counts were measured before and
after the merge (`rg -c '^#### Scenario:'`: **29 → 32**) and the verification-class counts were
re-derived from the merged file (`unit` 14, `ci-gate` 14, `manual-evidence` 4) rather than copied from
the delta's note.

- Main spec **created**: `openspec/specs/app-updates/spec.md` (419 lines) — the **22nd** capability.
- Main spec **updated**: `openspec/specs/release-distribution/spec.md` (+62 / −5 requirement content,
  plus the class-table counts and an extended provenance section).
- Change folder archived: `openspec/changes/archive/2026-08-23-m6-sparkle-updates/` — 8 artifacts plus
  this additive report.
- `openspec/changes/m6-sparkle-updates/` no longer exists.
- `tasks.md` was archived **unmodified**; no checkbox was reconciled, because none needed to be (§4).
- No archived change was deleted or modified. The archive is an audit trail.

---

## 15. Post-archive addendum — the publication path, proven (2026-08-23, same day)

Written after the archive commit, on the fresh commit `v1.0.0` is cut from. It closes the items §"Still
open, by design" deferred to the first stable tag, and records two defects the proving releases found.

| Evidence | Tag / run | Result |
|---|---|---|
| M4 / U33 — real `sign_update` with the repository secret; `deploy-pages` from a tag ref | `v0.0.2` · run 32629158393 | Feed live at `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`; signature verified offline with `sign_update --verify` against the published zip |
| M5–M7 — an installed copy updates itself | 0.0.2 → 0.0.4 | Sparkle offered 0.0.4, downloaded, replaced the bundle in `/Applications`, relaunched; post-swap `spctl` accepted (Notarized Developer ID), ticket stapled, About shows `0.0.4 (4)`; no administrator prompt |
| Feed history preserved across releases | `v0.0.5` · run 32633420385 | Feed shows `5, 4, 2` |
| Same-commit guard | `v0.0.6` on the same commit as `v0.0.5` | Refused in 5 s before notarization; no release, feed unchanged; tag deleted afterwards |

**Defect 1 — a second stable tag on an already-deployed commit left the feed stale (`v0.0.3`).**
GitHub Pages keys a deployment by its commit SHA: a repeat deployment of the same commit is accepted,
reports success, and changes nothing. Measured by diffing the run's artifact (correct, two items)
against the served feed (unchanged) with both deployments at `succeed`.

**Defect 2 — PR #61 fixed it wrongly (`v0.0.4`).** Replacing `actions/deploy-pages` with a `curl`
deployment using `pages_build_version = <sha>-<run>` failed every deployment with HTTP 404, after the
release had already been published. A throwaway diagnostic workflow then measured the API contract:
`pages_build_version` must be a commit SHA present in the repository (a synthetic 40-hex string is
also refused), and the status endpoint answers HTTP 200 for every SHA — only the body's `status`
field distinguishes a deployed commit from one that never was.

**Fix — PR #62 (`d30dfe7`).** `actions/deploy-pages@v5` is back, and a guard placed before any
signing or notarization refuses a stable tag whose commit has already deployed the feed. The rule it
enforces is now documented in `RELEASING.md`: **every stable release is cut from a distinct commit.**
`0.0.3` exists as a release with no feed item, which strands nobody.

**Carry-forward:** whether a commit whose earlier deployment ended in a failure state can be
redeployed is unmeasured; the guard fails closed on any status other than empty or `succeed`.
