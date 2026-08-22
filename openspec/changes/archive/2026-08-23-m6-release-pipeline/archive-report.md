# Archive Report: `m6-release-pipeline`

**Archived**: 2026-08-23 · **Milestone**: PRD **M6** "Ship", **slice 2 of 3** — the Developer ID release pipeline
**Status at close**: implemented, verified, **merged to `main`**, archived — PR #58 merged at `32719f4`
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

- Closes the **SECOND SLICE of PRD milestone M6 "Ship"** (PRD.md :212). It delivers PRD :9
  ("Developer ID + notarized"), :187 ("notarization via `notarytool` in CI (GitHub Actions on tags)"),
  :227 (arm64-only), and **discharges the long-unmet :157 obligation** — "Entitlements kept minimal;
  document why in-repo for notarization sanity" — in `RELEASING.md` §6.
- It also **pays down PRD risk :224**, whose mitigation ("set up CI pipeline in M1, not M6") was never
  taken. Before this slice the repository had **no `.github/`, no `scripts/`, and no CI of any kind**.
- **M6 remains OPEN.** Slice 1 was the tip jar (built, then removed — see
  `openspec/changes/archive/2026-08-22-m6-tip-jar/`). Slice 3 is `m6-sparkle-updates`, followed by
  `m6-cask-tap`. The landing page and the actual `v1.0.0` tag are still outside every archived slice.
- **This slice ships no in-app behaviour change.** It is infrastructure, and it is the prerequisite the
  two follow-up slices cannot be verified without.

## 2. Delivery references

| Item | Value |
|---|---|
| Branch | `feature/m6-release-pipeline` (**deleted after merge**) |
| PR | **#58** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/58 |
| PR title | `ci(release): Developer ID signing, notarization and tag-triggered release pipeline (m6-release-pipeline)` |
| Merged | **2026-08-22T22:15:39Z**, merge commit `32719f4` on `main` |
| Merge base | `ec7b1c5` (`main`) |
| Commits | 9 (below) |
| Archive commit | this commit — `docs(sdd): archive m6-release-pipeline and promote the release-distribution capability spec` |

| # | Commit | Subject |
|---|---|---|
| 1 | `e0b4803` | `docs(sdd): open m6-release-pipeline — exploration, proposal, spec, design, tasks` |
| 2 | `1d2117f` | `build(project): pin ARCHS to arm64 in both app-target blocks` (work unit 1) |
| 3 | `8c289bd` | `fix(app): stamp the human-readable copyright from the string catalog` (work unit 2) |
| 4 | `41a7208` | `ci(release): add the local release script and Developer ID export options` (work unit 3) |
| 5 | `e74ba5c` | `ci(release): add the tag-triggered Developer ID release workflow` (work unit 4) |
| 6 | `d7c19c8` | `docs(release): document the release pipeline and amend PRD and README` (work unit 5) |
| 7 | `1ad12d6` | `docs(sdd): record m6-release-pipeline apply progress` |
| 8 | `f993ecf` | `fix(release): capture entitlements before the sandbox gate and complete the rehearsal example` |
| 9 | `77b12db` | `docs(sdd): record m6-release-pipeline verification and reconcile the S10 gate and test counts` |

The five planned work units mapped one-to-one onto commits 2–6, exactly as `tasks.md` forecast.
Commit 8 is the correction that made the S10 sandbox gate actually gate (§10); commit 9 landed the
verification record **and** the three warning fixes discussed in §7.

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not
a defect to investigate:

- Receipt-driven development is **globally disabled** for this repository (`config.yaml` context line;
  session preflight `RDD disabled`). With the kill switch off, zero review code ran for this
  candidate, so no transaction, ledger, receipt or gate context was ever created and none exists to
  read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #58 proceeded under **ordinary repository policy**, and archive proceeds the same
  way.
- Consequently the `sdd/m6-release-pipeline/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES.** `tasks.md` carries **35 checked** items and **14 unchecked** items. Every unchecked
item is verified below to be a non-implementation item, so no stale checkbox reconciliation was
performed and none was needed.

| Group | Items | State | Why unchecked is correct |
|---|---|---|---|
| Phases 0–5 (implementation) | 35 | **all checked** | Every RED/GREEN task and every in-scope `ci-gate` was executed and marked by `sdd-apply`. |
| Maintainer prerequisites P1–P6 | 6 | unchecked | Declared in `tasks.md` under the heading "**not code tasks — a checklist, blocking Phase 6 only**". P6 states in its own text that "the PR may merge without P1–P5". |
| Phase 6 items 6.1–6.8 | 8 | unchecked | Declared in `tasks.md` under the heading "**`ci-gate` / `manual-evidence` — not test tasks, and not merge blockers**", with the preface "the PR of Phases 1–5 may merge before any of this". |

**Phase 6 is DEFERRED-TO-RELEASE by design, not incomplete work.** All four upstream artifacts
(`proposal.md` *Prerequisites*, `specs/release-distribution/spec.md` verification-class table,
`design.md` M1–M10, `tasks.md` Phase 6) declared these items non-merge-blocking **before** apply
started. They are blocked on credentials and repository settings that do not exist yet, not on code
anyone could have written. The complete, ordered checklist is §9.

## 5. Spec sync

| Domain | Action | Details |
|---|---|---|
| `release-distribution` | **Created** | ADDED-only — **8 requirements / 29 scenarios**. 0 modified, 0 removed, 0 renamed. |

- New main spec: **`openspec/specs/release-distribution/spec.md`** — the project's **21st** capability
  (20 existed before this archive).
- **No destructive delta.** `rules.archive`'s "warn before merging destructive deltas" clause **did not
  fire**: nothing was modified, removed or renamed, and no existing capability's requirements were
  touched.
- **Promotion is mechanical, and byte-identity was proven, not asserted.** The requirement and
  scenario bodies (delta lines 50–373) were extracted with `sed` and appended without passing through
  any model read/write path; `diff` against the delta returned **empty**. The class table (delta lines
  31–35), the design-owned paragraph (37–40) and the capability-ownership paragraph (7–11) were
  carried verbatim the same way, each with its own empty `diff`.
- **What the main spec adds over the delta**, following the house convention established by
  `openspec/specs/package-discovery/spec.md` and `openspec/specs/release-notes/spec.md`: the
  `# release-distribution` header replaces `# Delta for release-distribution`; the `## Requirements`
  wrapper replaces `## ADDED Requirements`; a `## Verification classes` heading with one introductory
  sentence replaces the delta's "Admissibility under `rules.specs`" framing; and a `## Provenance`
  section is appended.
- **What the main spec drops**, all of it SDD-process framing with no bearing on the capability: the
  ADDED-only delta-count sentence, the session-preflight block, the `rules.specs` admissibility
  judgment prose, the D-decision traceability line (re-expressed at length in `## Provenance`), and
  the artifact size note.
- The archived delta at
  `openspec/changes/archive/2026-08-23-m6-release-pipeline/specs/release-distribution/spec.md` remains
  the verbatim audit trail.

## 6. What shipped

Ten files changed on the feature branch (17 including the SDD artifacts), **+4,323 / −9** against
`ec7b1c5`.

| Path | Change |
|---|---|
| `.github/workflows/release.yml` | **New** (125 lines) — tag-triggered (`push: tags: ['v*']` only), `runs-on: macos-26`, `permissions: contents: write`, Xcode pinned via `xcode-select`, private-repo fail-fast **before** any signing step, ephemeral keychain + `$RUNNER_TEMP/asc.p8` at mode `600`, one named step per `release.sh` phase, `gh release create … --verify-tag --generate-notes` with a hyphen-derived `--prerelease`, and `if: always()` keychain + key deletion. |
| `scripts/release.sh` | **New** (295 lines, mode `100755`) — `archive export package notarize staple verify all`. Runs the same sequence locally (U26 rehearsal) and on CI. Contains **zero** `gh` and **zero** `git` command tokens: it cannot select a repository and cannot publish. |
| `scripts/ExportOptions.plist` | **New** (16 lines) — `method = developer-id`, `signingStyle = automatic`, `teamID = Z3S5JK8E38`, `manageAppVersionAndBuildNumber = false`. |
| `cellarTests/ReleasePipelineCompositionTests.swift` | **New** — 23 test cases across `ReleaseMetadataTests`, `ReleasePipelinePlacementTests`, `ReleaseWorkflowContractTests` (T1–T19). |
| `cellar.xcodeproj/project.pbxproj` | **Modified — exactly 2 insertions**: `ARCHS = arm64;` in both app-target blocks. Verified independently: the Debug and Release `buildSettings` carry 28 keys each with an **empty symmetric difference**. |
| `cellar/InfoPlist.xcstrings` | **Modified** — `NSHumanReadableCopyright` set to `Copyright © 2026 Juan Casanueva. All rights reserved.`; `INFOPLIST_KEY_NSHumanReadableCopyright` stays `""` at pbxproj :432/:466. |
| `RELEASING.md` | **New** — §1–§8 runbook plus the PRD:157 entitlements rationale. §6's signing evidence is a clearly marked placeholder until task 6.4 lands. |
| `PRD.md` | **Modified** — :9, :157, :168, :187, :212, :224, :227 rewritten in place with reasons (D8, tip-jar precedent). |
| `README.md` | **Modified** — `## Install` and `## Releasing` sections. |
| `.gitignore` | **Modified** — gained `build/` (3 lines; see deviation 3 in §10). |

**Binding 0-line diffs held.** `Packages/CellarCore/**`, every `.swift` under `cellar/`,
`cellar.xcscheme`, `Package.swift`, `Package.resolved` and `THIRD-PARTY.md` are untouched. The only
file changed under `cellar/` is `InfoPlist.xcstrings` — which matters because `cellar/` is a
`PBXFileSystemSynchronizedRootGroup` and anything dropped inside it ships signed in the bundle.
No `.entitlements` file exists anywhere in the repository and no `CODE_SIGN_ENTITLEMENTS` key exists
in the project file.

## 7. Verification

**Verdict: PASS WITH WARNINGS.** Envelope `gentle-ai.verify-result/v1`, verdict
`pass_with_warnings`, **0 blockers, 0 CRITICAL**, requirements 8/8, scenarios 29/29,
`test_exit_code 0`, `build_exit_code 0`. Admitted by `gentle-ai sdd-verify-validate --requirements 8
--scenarios 29` → `valid: true`. Evidence revision
`sha256:fb03271f044c6391dad81f28589d97f55d67a1509066663412d91db1c1e36fd8`; canonical report bytes
`sha256:10adcdb431ffcd845d86f4dbae037b35a4856c5499eee4e4433348a333309179` (38,767 bytes).

**Compliance by declared verification class:**

| Class | Count | State at close |
|---|---|---|
| `unit` | 13/13 | Runtime-COMPLIANT — executed and green. |
| `ci-gate` | 12/12 | Structurally verified; **never executed against a real signed build** (blocked on U26/G3). |
| `manual-evidence` | 4/4 | Documented with exact accepted output; **not yet observed**. |

0 UNTESTED, 0 FAILING. **16 of the 29 scenarios have never run against a delivered artifact.** The
pipeline is implemented and structurally proven; it is **not yet a proven pipeline end to end**.

**Warning disposition at close** — three of the four warnings were fixed in `77b12db`, which landed
*after* `verify-report.md` was written. The report's text still describes them as open; that text is a
snapshot of verification time and is superseded here.

| # | Warning (per `verify-report`, Engram `#7669`) | State at close |
|---|---|---|
| W1 | `design.md:246-247` still prescribed `! codesign … \| grep -q` as the corrected S10 gate | **RESOLVED** in `77b12db` — `design.md:248` now carries the `if … grep -q; then fail; fi` form. |
| W2 | `apply-progress.md` recorded 183 distinct / 160 pre-existing | **RESOLVED** in `77b12db` — a reconciliation blockquote at `apply-progress.md:155-159` states the correct figures and that every "183"/"160" in the file must be read as 184/161. |
| W3 | Phase 6 + P1–P6 unchecked → 16 scenarios never executed against a real build | **DEFERRED-TO-RELEASE by design, not incomplete** — see §4 and §9. Downgraded from CRITICAL by verify itself because all four upstream artifacts declare these items non-merge-blocking. |
| W4 | S14's "offline" claim rests on manual M3; `RELEASING.md` §3 said "Eight gates" with no caveat | **RESOLVED** in `77b12db` — `RELEASING.md:84` now states that the CI `spctl` assessment runs online and that the offline assessment is manual evidence M3 in §6. |

**Failability was mutation-tested**, not assumed. Seven assertions were each broken in a scratch copy
and each produced exactly the expected failure with zero collateral, with the tree restored clean
afterwards. The most valuable of the seven: blanking the catalog copyright fails **T10**, proving the
`InfoPlist.xcstrings` → compiled `InfoPlist.strings` → `Bundle.main.localizedInfoDictionary` path is
real and not a literal compared against itself.

**Four remaining SUGGESTIONS, all carried open and none required** (they are also task 6.8): (G1) a
post-publish `curl -fsSI` reachability assertion to close S1 in CI rather than by observation; (G2)
`release.sh`'s header says `BUILD_NUMBER` is needed for `export` but `phase_export` requires only
`VERSION`; (G3) `RELEASING.md`'s "Eight gates" is stale — `phase_verify` now runs twelve; (G4) an
optional `plutil -lint ExportOptions.plist` CI gate.

## 8. Test, gate and size state at close

| Measure | Value at close | Superseded value (and its source) |
|---|---|---|
| `cellarTests` distinct test functions | **184 passed / 0 failed** | `apply-progress.md` recorded 183 — one short, and it says so in its own reconciliation blockquote. |
| `cellarTests` case executions | **194** (3 parameterized functions expand to 13 cases) | not recorded at apply time. |
| Pre-existing `cellarTests` | **161** — confirmed by `git grep -c '@Test' main -- cellarTests` = 161 with 0 duplicate ids | apply recorded 160; U29 originally recorded 141 (an orchestrator counting error, corrected in Engram `#7668`). |
| New in this slice | **23** (`cellarTests/ReleasePipelineCompositionTests.swift`) | unchanged. |
| CellarCore | **1,732 tests / 204 suites passed** at `ec7b1c5` | Not re-run: the package is a **0-line diff**, which is the stronger proof. |
| `actionlint` 1.7.12 | exit 0 | |
| `shellcheck` 0.11.0 | exit 0 | |
| `bash -n scripts/release.sh` | exit 0 | |
| `xcodebuild build -quiet` | exit 0 | |
| `xcodebuild test` | exit 0 | |
| G3 dry-run prerelease | **NOT RUN** — blocked on U26/P1/P4 | |

**Size and delivery budget:**

| Measure | Value |
|---|---|
| Authored changed lines | **1,502** (1,493+ / 9−) across 10 files — mid-band of the corrected 1,240–2,425 forecast |
| SDD artifacts | 2,422 lines |
| **PR total** | **3,924** vs the governing **5,000** budget — **1,076 lines of headroom** |
| Delivery strategy | `single-pr`, held with **no `size:exception`** |
| Chained PRs | not recommended, not used |

The house's measured **1.9–2.3×** bottom-up correction was reused from `design.md` and not
re-derived, and it landed the estimate correctly.

**Attempt ledger — both attempts settled `complete`:**

| Attempt | Request id | Evidence revision (sha256 content digest) | State |
|---|---|---|---|
| apply | `m6-release-pipeline-settle-1` | `sha256:e5d26a2b…0579` | `complete` |
| verify | — | `sha256:10adcdb4…9179` | `complete` |

## 9. Deferred to release — the exact remaining checklist

**None of these blocked the merge. All of them block the first tagged release.** They are ordered;
each depends on the one before it.

**Maintainer prerequisites (outside this repository):**

| # | Action | Blocks |
|---|---|---|
| P1 | Flip `juancasanueva/SWIFTUI_cellar` to **public** | S1, S4 — release assets on a private repository are not anonymously downloadable, and macOS runner minutes bill at 10× |
| P2 | Create and export the **Developer ID Application** certificate *with its private key* as a `.p12` | U26, and everything after it |
| P3 | Create an **App Store Connect API key** (`.p8`, **Developer** role); note the key id and issuer id | `notarytool` and `-allowProvisioningUpdates` |
| P4 | Set exactly six repository secrets: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | the workflow |
| P5 | Confirm Actions is enabled and `GITHUB_TOKEN` may write releases (`contents: write`) | publication |
| P6 | (statement, not an action) the PR merges without P1–P5; the first release cannot happen without them | — |

**Re-measured at verification time**: `security find-identity -v -p codesigning` →
`1 valid identities found`, listing only `Apple Development: Juan Casanueva (A8EB4839B9)`. There is
**no Developer ID Application certificate and no App Store Connect API key on the build Mac**. That
single fact is why U26 could not run, and U28 and G3 both queue behind it.

**Then, in order:**

1. **6.1 Gate** — confirm P1–P5. No tag may be pushed before 6.2 is green.
2. **6.2 / U26** — local Developer ID export + notarize round trip via `scripts/release.sh all`.
   Record M1 (`notarytool submit --wait` → `status: Accepted`), M2 (`notarytool log` → `"status":
   "Accepted"`, `"issues": null`), M3 (`spctl -a -vvv -t install` **with networking disabled** →
   `accepted`, `source=Notarized Developer ID`), M4 (`stapler validate` → `The validate action
   worked!`), M6 (`codesign -dvvv --entitlements :-` → Developer ID authority for `Z3S5JK8E38`,
   `flags=0x10000(runtime)`, no `com.apple.security.cs.*` key) and M7 (`lipo -archs` → exactly
   `arm64` — load-bearing, it proves the U27 fix took). Discharges S9, S10, S14, S15.
3. **6.3 Manual signing fallback — CONDITIONAL.** Apply **only** if 6.2 measures headless automatic
   Developer ID export failing, and **only** with explicit maintainer approval. It flips the Release
   block to `CODE_SIGN_STYLE = Manual` with `CODE_SIGN_IDENTITY = "Developer ID Application"` and an
   empty `PROVISIONING_PROFILE_SPECIFIER`, sets `ExportOptions.plist` `signingStyle` to `manual` and
   `SIGNING_STYLE=manual` in the workflow — and **relaxes T14 explicitly**, with the reason in the
   test's doc comment. Silently deleting that assertion is not an option.
4. **6.4 / U28 (M8)** — launch the notarized, stapled build from `/Applications`, install then
   uninstall a small formula in-app, confirm with `brew list --formula`. Accepted only if the mutation
   completes **with no entitlement added**. Then fill `RELEASING.md` §6 with the quoted M6 + M8 output
   as `docs(release): record measured signing evidence`. If M8 fails, **no entitlement is added by
   default** — it is reported and reopened as a decision (S13).
5. **6.5 / G3** — dry-run prerelease on the real repository: `git tag v0.0.1-rc.1 && git push origin
   v0.0.1-rc.1`. Delete it **manually** afterwards (`gh release delete v0.0.1-rc.1 --cleanup-tag`);
   the workflow never deletes anything. Discharges S1, S2, S5, S6, S17, S23.
6. **6.6 / M5 + M10** — M5: download the published zip through a browser onto a machine that has never
   seen the bundle and confirm a single "Open" dialog (S16). M10: scan the full run log for key
   headers and blobs → zero matches, every secret masked (S27), then delete the log so the check is
   not itself the leak.
7. **First `v1.0.0` tag.**
8. **6.7 / M9** — from the **second** published release onward, compare `CFBundleVersion` across two
   releases; the newer must be strictly greater, including across a re-cut tag (S7). Deferred by
   definition, not a failure: at the first release there is nothing to compare against.
9. **6.8** — the four optional hardening suggestions from §7. None required.

**Carried risks:**

- **R4 — the rc-tag version hazard.** `MARKETING_VERSION=0.0.1-rc.1` may be rejected by `xcodebuild`
  as non-numeric. The documented fallback is the plain tag `v0.0.1` — but note that **the fallback
  also loses DD-7's hyphen-derived `--prerelease` flag**, so a `v0.0.1` dry run would publish as a
  normal release rather than a prerelease. Whoever runs G3 must know both halves of that trade.
- **R6** — the Xcode 26.6 pin will drift as the `macos-26` runner image updates.
- The **"No App Category" build warning** (`INFOPLIST_KEY_LSApplicationCategoryType`) is deliberately
  **not** fixed here and is owned by `m6-sparkle-updates` (§11).

## 10. Accepted deviations from the design

All five were declared at apply time and judged **justified** by verification.

1. **The S10 sandbox gate is an explicit `if` branch over captured output**, not the design's negated
   pipeline. **Strictly better than the design** — see §12. `design.md` was amended to match in
   `77b12db` (warning W1).
2. **T13 matches a complete `-----BEGIN <TYPE>-----` PEM header**, not the bare `-----BEGIN` prefix
   that `design.md` and `tasks.md` quote in prose. The literal wording was unsatisfiable as written.
3. **`.gitignore` gained `build/`** (3 lines), which sits outside the design's file table. **Required,
   not optional**: the threat matrix's "commit state N/A" row already rested on the release build
   directory being ignored.
4. **T5 asserts a floor of secret lines, not exactly six.** The measured count is 10 because DD-1
   deliberately repeats the ASC bindings per step. Exactness over secret *names* is T6's job, and T6
   uses set equality — so a seventh secret still fails.
5. **A named checkout step** was added so `workflowSteps(in:)`'s `- name:` splitting stays honest.

**Independent confirmations recorded by verification** (each measured, not inferred): the pbxproj diff
is exactly two `ARCHS = arm64;` insertions; the Debug and Release `buildSettings` hold 28 keys each
with an empty symmetric difference; `INFOPLIST_KEY_NSHumanReadableCopyright = "";` is unchanged at
:432/:466; no `.entitlements` file and no `CODE_SIGN_ENTITLEMENTS` key exist anywhere; the built
bundle's `en.lproj/InfoPlist.strings` carries the copyright string while the raw `Info.plist` key is
**absent** (which vindicates T10's `localizedInfoDictionary` choice); `release.sh` is mode `100755`
with zero `gh`/`git` command tokens; the workflow references exactly six secret names, all ten
references as `env:` right-hand sides, with no YAML anchors and no `set -x`.

## 11. Carried follow-ups (recorded open, deliberately not closed here)

**`m6-sparkle-updates`** — M6 slice 3. Sparkle 2.9.6 via SPM, an appcast published to `gh-pages`,
EdDSA key generation, a CellarCore `Updates` target, and the Settings + About surfaces
("Check for Updates…"). **It also owns `INFOPLIST_KEY_LSApplicationCategoryType` and the resulting
"No App Category" build warning** — dropped from this slice at design time because the proposal binds
the pbxproj to exactly one change (`ARCHS = arm64`) and spec S29 forbids a competing build-setting
authority for Info.plist values; `m6-sparkle-updates` touches the pbxproj anyway (Engram `#7661`).
It binds its `<enclosure url>` to this slice's asset URL and its version comparison to this slice's
monotonically increasing `CFBundleVersion`.

**`m6-cask-tap`** — the last M6 shipping slice, in a **separate repository**
`juancasanueva/homebrew-cellar`. Cask token `home-cellar`, `app "cellar.app"` naming the bundle
exactly, `auto_updates true` (because Sparkle will own updates by then), `depends_on arch: :arm64`
and `depends_on macos: ">= :tahoe"`. Its `url` is this slice's asset URL.

Both slices **inherit** the artifact name, asset URL, bundle name, version-stamping rule, architecture
pin and deployment floor from `openspec/specs/release-distribution/spec.md` rather than re-deriving
them. That contract is recorded in the promoted spec's `## Provenance` section.

**Not follow-ups of this slice, but still open**: a PR/test CI workflow (deliberately excluded — this
slice is release-on-tag only), SwiftLint adoption (U21 measured 246 warnings and 20 errors with no
config), a DMG, the landing page, and PRD §9 Q1 (final name and icon).

## 12. Learnings worth carrying

**A. Three shell forms that silently pass a gate that should fail.** The S10 sandbox check had to
become an explicit `if` branch over captured output because all three obvious spellings are broken,
and they are broken for three *different* reasons:

- `codesign … | grep -qv PATTERN` returns 0 the moment **any single line** differs from the pattern,
  and multi-line `codesign` output guarantees one. It can never fail.
- `! cmd | grep -q PATTERN` under `set -e` cannot terminate the script either: bash **explicitly
  exempts** a command whose status is inverted by `!` from errexit.
- Even as a bare pipeline, `grep -q` closes the pipe on its first match, so under `pipefail` a **real
  match** becomes SIGPIPE/141 — and a genuine detection reads as a pass.

`f993ecf` removed the third by capturing output first; the `if` branch removed the first two. **Only
the capture-then-`if … grep -q; then fail; fi` form actually gates.** A design-phase validator caught
the first form and flagged it, and the corrective rewrite introduced the second — the same class of
bug twice, from two different agents.

**B. `xcodebuild` tears log lines, so count test ids byte-oriented.** The `cellarTests` baseline drifted
141 → 160 → 161 across three sessions. The final ±1 was not a renamed or parameterized test: the log
literally contains `Test case 'BrewfileExportCompositionTests/aF`, then a block of
`IDETestOperationsObserverDebug` lines and `** TEST SUCCEEDED **`, then
`ailedDumpNeverOpensAPanelAndNeverWrites()' passed`. A line-oriented `sort -u` drops that id; a
byte-oriented regex finds it. Separately, `Executed N tests` reads **"Executed 0 tests"** for Swift
Testing bundles and is a false-zero vector, and 3 parameterized functions expand to 13 cases, so
*functions* (184) and *executions* (194) are different numbers that must be reported separately.

**C. A design gate can fail on an artifact contradicting its own binding constraints.** Round 1 of the
design gate returned FAIL on 1 CRITICAL: the design placed `NSHumanReadableCopyright` into the pbxproj
as an `INFOPLIST_KEY` in both blocks, contradicting the proposal's binding "pbxproj = exactly one
change" and spec S29's "the build setting MUST NOT carry the copyright". The orchestrator's own probe
amendment compounded it by adding `INFOPLIST_KEY_LSApplicationCategoryType`. One corrective rerun with
10 itemized fixes resolved everything and returned PASS-WITH-WARNINGS. Two lessons: a validator may
read a file **mid-edit**, so re-check its "unfixed" claims against disk before acting; and dropping a
scope addition (the app category) is cheaper than defending it.

**D. `cellarTests/` is also a `PBXFileSystemSynchronizedRootGroup`.** The new test file needed **no**
pbxproj edit at all, which is what kept the project-file diff at exactly two lines. The same property
is a hazard on the `cellar/` side, where any `.plist`, `.yml` or `.sh` dropped in ships signed inside
the bundle — which is precisely why T12 exists as a test rather than a comment.

**E. `gentle-ai sdd-attempt settle` takes a content digest, not a git SHA.** Its `--evidence-revision`
wants `sha256:<64hex>` produced by e.g. `shasum -a 256 apply-progress.md`. The full required flag set
is `--outcome passed|failed|interrupted`, `--evidence-revision`, `--diagnosis`,
`--harness-disposition reused|invalidated`, `--cleanup-evidence` and `--process-evidence`, each ≤500
bytes on a single line.

## 13. Artifact traceability (Engram observation IDs)

Every artifact was retrieved in full via `mem_get_observation`, not from a search preview.

| Artifact | Engram obs | Topic | Archived file |
|---|---|---|---|
| explore | `#7659` (under `sdd/m6-ship-pipeline/explore`, written for the umbrella change then sliced) | `sdd/m6-ship-pipeline/explore` | `explore.md` |
| decisions | **`#7661`** | `sdd/m6-release-pipeline/decisions` | — (Engram only) |
| proposal | **`#7662`** | `sdd/m6-release-pipeline/proposal` | `proposal.md` |
| probes | **`#7663`** | `sdd/m6-release-pipeline/probes` | — (Engram only) |
| spec (delta) | **`#7664`** | `sdd/m6-release-pipeline/spec` | `specs/release-distribution/spec.md` |
| design | **`#7665`** | `sdd/m6-release-pipeline/design` | `design.md` |
| state | **`#7666`** | `sdd/m6-release-pipeline/state` | — (Engram only) |
| tasks | **`#7667`** | `sdd/m6-release-pipeline/tasks` | `tasks.md` |
| apply-progress | **`#7668`** | `sdd/m6-release-pipeline/apply-progress` | `apply-progress.md` |
| verify-report | **`#7669`** | `sdd/m6-release-pipeline/verify-report` | `verify-report.md` |
| **archive-report** | *this file* | `sdd/m6-release-pipeline/archive-report` | `archive-report.md` |

**Two mirrors are known-lossy and the archived file is authoritative in both cases:**

- **`#7665` (design)** is truncated at 50,000 characters. `design.md` is ≈570 lines and is the
  authority.
- **`#7667` (tasks)** is the **authoring-time** snapshot written by `sdd-tasks`, so every checkbox in
  it reads unchecked. The archived `tasks.md` carries the apply-time completion state (35 checked)
  and is the authority for §4's gate.

`review/*` topics do not exist — see §3.

## 14. Archive integrity

**Mechanical copy contract satisfied.** No artifact byte passed through a model read/write path.

| Operation | Mechanism | Readback | Result |
|---|---|---|---|
| Spec promotion — requirement bodies | `sed -n '50,373p'` append | `diff` vs delta lines 50–373 | **empty** |
| Spec promotion — ownership paragraph | `sed -n '7,11p'` append | `diff` vs delta lines 7–11 | **empty** |
| Spec promotion — class table + design-owned paragraph | `sed -n '31,35p;37,40p'` append | `diff` vs delta lines 31–35, 37–40 | **empty** |
| Change folder → archive | `git mv` | `diff -r` vs a pre-move recursive `cp -R` snapshot | **empty** |
| Rename fidelity | — | `git diff --cached -M --name-status` | **7 files, all `R100`** |

- Main spec created: `openspec/specs/release-distribution/spec.md` (427 lines) — the 21st capability.
- Change folder archived: `openspec/changes/archive/2026-08-23-m6-release-pipeline/` — 7 artifacts
  plus this additive report.
- `openspec/changes/m6-release-pipeline/` no longer exists.
- `tasks.md` was archived **unmodified**; no checkbox was reconciled, because none needed to be (§4).
- No archived change was deleted or modified. The archive is an audit trail.
