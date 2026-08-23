# Apply progress: `m8-bundle-rename` — batch 1 (only batch)

**Mode**: Strict TDD (`strict_tdd: true`, enforced — no fallback taken).
**Artifact store**: hybrid (this file + Engram `sdd/m8-bundle-rename/apply-progress`, project
`swiftui_cellar`).
**Delivery**: `single-pr`, no `size:exception`. Chain strategy n/a.
**Attempt**: `gentle-ai sdd-attempt acquire` → `state: proceed` on the parent token
`sha256:3157aa48…92bd6f`. Not settled here; the orchestrator settles.

**Status: 45 of 56 tasks executed. 11 explicitly deferred** — every deferral is a maintainer action
(push / PR / merge) or a post-tag / post-merge obligation that is unreachable from this phase, never
a skipped one.

## Branches and commits

Nothing was pushed and no PR was opened. Both branches are local and ready.

### App repo — `/Users/juancasanueva/programming/swiftUI/cellar`, branch `feat/m8-bundle-rename` (from `main f0a5817`)

| Order | Commit | Unit | Message |
|---|---|---|---|
| 1 | `c1f5898` | Phase 0.5 | `docs(sdd): record the m8-bundle-rename proposal, spec delta, design and tasks` |
| 2 | `f95b9d6` | **WU1** | `feat(build): rename the product to Home-Cellar and pin the module name` |
| 3 | `7ae6c89` | **WU2** | `fix(release): separate the product name from the scheme name` |
| 4 | `63b48a9` | **WU3** | `fix(ci): inspect the renamed export path` |
| 5 | `8e01341` | **WU4** | `docs(release): document Home-Cellar.app as the one installed bundle` |
| 6 | branch `HEAD` (self-referential — see the return contract for the SHA) | artifacts | `docs(sdd): record the m8-bundle-rename apply progress and task evidence` |

### Tap repo — `/Users/juancasanueva/programming/swiftUI/homebrew-cellar`, branch `feat/m8-bundle-rename` (from `main f9e7428`)

| Commit | Unit | Message |
|---|---|---|
| `e16589f` | **WU5** | `fix(cask): install Home-Cellar.app, the bundle the asset now carries` |

No `Co-Authored-By` and no AI attribution on any commit, in either repository.

## The blocking gate: R5 post-probe (task 2.11)

Run immediately after the pbxproj + scheme edit, before WU2. Verbatim:

```
EXECUTABLE_NAME = Home-Cellar
FULL_PRODUCT_NAME = Home-Cellar.app
PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar
PRODUCT_MODULE_NAME = cellar
PRODUCT_NAME = Home-Cellar
```

Diffed line-by-line against the Phase 0.1 pre-change block recorded in `design.md`:

| Setting | Before | After | Verdict |
|---|---|---|---|
| `EXECUTABLE_NAME` | `cellar` | `Home-Cellar` | moved — **permitted** |
| `FULL_PRODUCT_NAME` | `cellar.app` | `Home-Cellar.app` | moved — **permitted** |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.juancasanueva.cellar` | `com.juancasanueva.cellar` | **byte-identical** |
| `PRODUCT_MODULE_NAME` | `cellar` | `cellar` | **byte-identical** |
| `PRODUCT_NAME` | `cellar` | `Home-Cellar` | moved — **permitted** |

Exactly the three permitted lines moved. **R5 is closed on both sides.** The phase proceeded.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2.2 unit 1 | `cellarTests/BundleNamingTests.swift` | Unit (source-scanning) | ✅ 242/242 (Phase 0.2) | ✅ 2 expectations failed | ✅ Passed | ✅ 3 counts, two settings + block count | ➖ new file, already minimal |
| 2.3 unit 2 | same | Unit | ✅ 242/242 | ✅ `→ 0 == 2`, `→ 6 == 0` | ✅ Passed | ✅ presence **and** absence | ➖ |
| 2.4 unit 4 | same | Unit | ✅ 242/242 | ✅ `→ 0 == 3`, `→ 3 == 0` | ✅ Passed | ✅ 3 counts incl. anti-overreach | ➖ |
| 3.1 unit 3 | same | Unit | ✅ WU1 green | ✅ 5 of 6 expectations failed | ✅ Passed | ✅ 6 counts in 3 pairs | ➖ |
| 4.1 unit 5 | same | Unit | ✅ WU2 green | ✅ both halves failed | ✅ Passed | ➖ single spec scenario, presence + absence is the pair | ➖ |
| 5.1 R6 update | `cellarTests/CaskZapInventoryTests.swift` | Unit (approval-style) | ✅ suite green pre-edit | ✅ 1 case failed, `Home-Cellar.app` count in README was **0** | ✅ Passed | ➖ deliberate single-assertion update of a shipped test | ✅ doc comment rewritten to match |

**Every RED was proven by runner output before its GREEN.** Verbatim expectation messages were
pulled from the `.xcresult` (`xcrun xcresulttool get test-results test-details`) rather than from the
console summary, because `xcodebuild`'s streamed output does not carry them.

RED reasons, verbatim:

```
Expectation failed: try BundleNamingSources.appTargetBlocksDeclaring(Self.productName) == 2
Expectation failed: try BundleNamingSources.appTargetBlocksDeclaring(Self.moduleName) == 2
Expectation failed: (occurrences(of: Self.testHost, in: project) → 0) == 2
Expectation failed: (occurrences(of: "cellar.app", in: project) → 6) == 0
Expectation failed: (occurrences(of: "BuildableName = \"Home-Cellar.app\"", in: scheme) → 0) == 3
Expectation failed: (occurrences(of: "BuildableName = \"cellar.app\"", in: scheme) → 3) == 0
Expectation failed: (occurrences(of: "$SCHEME.app", in: script) → 2) == 0
Expectation failed: (occurrences(of: "MacOS/$SCHEME", in: script) → 2) == 0
Expectation failed: (occurrences(of: "$PRODUCT.app", in: script) → 0) == 2
Expectation failed: (occurrences(of: "MacOS/$PRODUCT", in: script) → 0) == 2
Expectation failed: script.contains("readonly PRODUCT=\"Home-Cellar\"")
Expectation failed: workflow.contains("build/export/Home-Cellar.app")
Expectation failed: !(workflow.contains("build/export/cellar.app"))
```

Three assertions passed from the very first RED run and were **meant** to:
`blocks.count == 2` (the block-splitting helper works, so the failures are about the settings and not
about the parser), `BlueprintName = "cellar"` == 3 and `-scheme "$SCHEME"` present (the two
anti-overreach guards — a rename that leaked into the target or the scheme invocation would have
turned these red instead).

### Test summary

- **Tests written**: 5 new (`BundleNamingTests`), 1 shipped assertion deliberately updated.
- **Tests passing**: 247/247 in `cellarTests` (242 baseline + 5).
- **Layers used**: Unit 5. No integration or E2E layer exists for build-system composition; the
  runtime harness below is the higher layer that does exist.
- **Approval tests**: 1 — task 5.1 is an approval-style update of shipped behaviour (the README's
  documented bundle name), rewritten to the new expected behaviour and then made green.
- **Pure functions created**: 1 — `BundleNamingSources.occurrences(of:in:)`, plus four pure
  block/text accessors.

## Work Unit Evidence

| Unit | Focused test command and exact result | Runtime harness command/scenario and exact result | Rollback boundary |
|---|---|---|---|
| **WU5** (tap) | **None in this repository (DD-8)** — no app-repo test reads the tap clone, by design. `ReleasePipelineCompositionTests:808` (the app repo names no other repository) stayed green | `brew style Casks/home-cellar.rb` → `1 file inspected, no offenses detected`. The online strict audit and the install/uninstall round trip belong to the tap's own `ci.yml` and are **unexercised** — they need the PR the maintainer opens | `git revert e16589f` in the tap clone: `app "cellar.app"` returns, `bump.yml` untouched, `livecheck` / `auto_updates` / `zap trash:` never in the diff |
| **WU1** | `-only-testing:cellarTests/BundleNamingTests` → `** TEST SUCCEEDED **`, 3/3. Guards `ReleasePipelineCompositionTests` + `UpdateProjectFileTests` + `CaskZapInventoryTests` → `** TEST SUCCEEDED **` | `xcodebuild build …` → `** BUILD SUCCEEDED **`; `Build/Products/Debug/Home-Cellar.app/Contents/MacOS/Home-Cellar` exists and is executable, `Build/Products/Debug/cellar.app` does **not** exist. The test runner's own device line read `My Mac - Home-Cellar` — the renamed `TEST_HOST` launched | Revert `f95b9d6`: `PRODUCT_NAME` → `$(TARGET_NAME)`, `PRODUCT_MODULE_NAME` disappears, **module stays `cellar` either way**. WU2–WU4 keep compiling (no Swift source in `cellar/` is touched) |
| **WU2** | `-only-testing:…/theReleaseScriptSeparatesTheProductFromTheScheme()` + `ReleasePipelineCompositionTests` + `ReleasePipelinePlacementTests` → `** TEST SUCCEEDED **` | **N/A — `release.sh` runs end-to-end only at the next tag** (design verification plan). Static proof supplemented by `bash -n scripts/release.sh` → OK and `shellcheck scripts/release.sh` → clean | Revert `7ae6c89`; `SCHEME` reabsorbs all four roles. No other file references `$PRODUCT` |
| **WU3** | `-only-testing:…/theWorkflowInspectsTheRenamedExportPath()` + `ReleasePipelineCompositionTests` → `** TEST SUCCEEDED **` | **N/A — tag-triggered workflow, unreachable before the tag.** `rg 'homebrew-cellar\|juancasanueva/cellar\|repository_dispatch' .github/workflows/release.yml` → zero hits, so DD-8 held | Revert `63b48a9` — one line |
| **WU4** | `-only-testing:cellarTests/CaskZapInventoryTests` → `** TEST SUCCEEDED **` | **N/A — passive documentation plus one source-scanning assertion.** Sweep harness: `rg -n --case-sensitive 'cellar\.app' README.md RELEASING.md PRD.md` → **zero hits** | Revert `8e01341`; the docs and the assertion move back together, so the test never disagrees with the prose |

## Verification gates (design gates 0–6)

| Gate | Result |
|---|---|
| 0 — R5 pre-probe | Already measured in `design.md` at `main f0a5817`; not re-run |
| 1 — core package | **PASS.** `1793 tests in 210 suites passed … with 1 known issue`, identical to baseline. See the flake note below |
| 2 — build | **PASS.** `** BUILD SUCCEEDED **`; product is `Home-Cellar.app` with `Contents/MacOS/Home-Cellar` |
| 3 — full suite | **PASS for `cellarTests`**: 247 distinct ids, 247 Passed, 0 failures. Two `cellarUITests` cases fail — **pre-existing, proven at `main`** (below) |
| 4 — R5 post-probe | **PASS**, recorded verbatim above and in `tasks.md` task 2.11 |
| 5 — import proof | **PASS.** 22 `@testable import cellar` files at `main`, 22 on the branch, **zero** Swift source edits |
| 6 — display-name gate | **Unmodified.** `git diff main -- scripts/release.sh \| rg 'CFBundleDisplayName'` returns nothing |
| 7 — tap CI | **Unexercised** — needs the tap PR (maintainer) |
| 8 — manual, post-tag | **Unexercised** — needs `v1.2.0` |

### Baselines measured at Phase 0.2 (`main f0a5817`)

- `swift test --package-path Packages/CellarCore` → `Test run with 1793 tests in 210 suites passed
  after 16.7 seconds with 1 known issue`.
- `xcodebuild test … -only-testing:cellarTests` → `** TEST SUCCEEDED **`, **242 distinct test ids,
  242 Passed, 0 failures**, counted from the `.xcresult` rather than from a summary line.

## Issues found

1. **Two `cellarUITests` cases fail — pre-existing, not caused by this change.**
   `testTapDetailFilteringInstalledHandoffAndForceDisclosure()` and
   `testTapsNavigationOfficialSourcesAndAddConfirmation()`. Phase 0.2's baseline only covered
   `cellarTests`, so this phase checked out `main f0a5817` and ran those two tests there: **both fail
   identically with none of this change applied.** The failure is an element-matching one — two
   `confirmation-command` elements in one sheet (`brew untap --force…` and `brew untrust acme/…`),
   which is the shape `m7-tap-trust`'s untap-then-revoke work introduced — and the app launched
   normally in both runs (`Application, pid: …, title: 'Home-Cellar'`). Recorded, not chased.
2. **One intermittent `CellarCore` flake.** One of six gate-1 runs reported a second issue beside the
   known one and did not reproduce across five retries. `git diff --stat main -- Packages/CellarCore/`
   is **empty**, so this change has a zero-line causal surface there.
3. **Task 6.6's second command matches diff context lines.** As literally written,
   `git diff main -- …project.pbxproj \| rg 'PRODUCT_BUNDLE_IDENTIFIER\|…'` returns three hits, but all
   three carry a leading space — they are unchanged **context**, which is precisely the invariant the
   task wants. Run in its precise form (`… \| rg '^[-+]' \| rg …`) it returns empty. The task text, not
   the tree, is what needed the correction.

## Deviations from design

1. **The scheme's three `BuildableName` lines were rewritten by Xcode, not by hand.** Xcode was
   running and re-serialized the shared scheme the moment `PRODUCT_NAME` changed in the pbxproj. The
   resulting bytes are exactly what design §2 specifies — `:19`, `:73`, `:104` renamed; `:39`/`:50`
   (`cellarTests.xctest`, `cellarUITests.xctest`), `BlueprintIdentifier`, `BlueprintName` and the
   filename all untouched — and the RED test for unit 4 was written and proven red **before** the
   pbxproj edit that triggered it, so the cycle held. Worth knowing because it independently confirms
   DD-5's premise: Xcode does rewrite these files on its own, which is why the hyphenated values are
   quoted and `PRODUCT_MODULE_NAME` is bare.
2. **`release.sh` gained 5 lines rather than 1.** Design says "ADD `readonly PRODUCT="Home-Cellar"`".
   A four-line comment was added above it explaining why one constant could not keep serving both
   roles, matching the file's existing density of rationale comments. The assertion
   (`contains("readonly PRODUCT=\"Home-Cellar\"")`) is unaffected.
3. **The `README.md:63` sentence was re-wrapped onto two lines.** `Home-Cellar.app` is 10 characters
   longer than `cellar.app` and the line would have exceeded the file's wrap width.
4. Nothing else. The pbxproj edit is byte-for-byte the design's table, in the alphabetical slot
   (DD-6), quoted per DD-5, in both blocks identically (DD-7).

## Deferred tasks and why (11)

| Task | Reason |
|---|---|
| 1.5 | Open the tap PR — **maintainer action**; this phase never pushes and never opens PRs. Branch ready at `e16589f` |
| 1.6 | Tap PR **merged** — maintainer gate; the binding R4 pre-condition on the `v1.2.0` tag push |
| 6.8 | Open the app-repo PR — **maintainer action**. Branch ready at `8e01341`; PR body content drafted below |
| 7.1 | R4 re-check on the tap's **default** branch — unreachable until the tap PR merges |
| 7.2 | ME1 — post-tag, needs a published `Home-Cellar.app` asset |
| 7.3 | ME2 — post-tag, needs a Sparkle self-update of a cask-installed renamed build. **`brew upgrade` only ever with `--dry-run`** (Engram `#7724`) |
| 7.4 | Composition-only honesty statement — an obligation on the **verify report**, which this phase does not author |
| 8.1–8.4 | Archive obligations — `openspec/specs/release-distribution/spec.md` is edited only at `sdd-archive` |

## PR body content required by task 6.8 (drafted, not posted)

Title: `feat(release): name the delivered bundle Home-Cellar.app`. Body must state, up front:

- **(a) R4.** The tap PR (`juancasanueva/homebrew-cellar`, branch `feat/m8-bundle-rename`, commit
  `e16589f`) must be **merged before any `v*` tag is pushed**, or `bump.yml`'s `17 */6 * * *`
  schedule must be paused across the window. `bump.yml` rewrites only `version`/`sha256` and gates on
  `brew style` + `brew audit` — neither extracts the archive nor resolves the `app` stanza — so a tag
  pushed against `app "cellar.app"` yields a cask that audits clean and installs broken.
- **(b) DD-1.** `PRODUCT_MODULE_NAME` is pinned to `cellar` **on purpose**. The Swift module and all
  22 `@testable import cellar` lines are untouched; without the pin, `PRODUCT_NAME = "Home-Cellar"`
  would resolve the module to `Home_Cellar` through `$(PRODUCT_NAME:c99extidentifier)` and break all
  22 files.
- **(c) D1.** Update-safe with **no migration**: the installed base is empty, so there is no `target:`
  stanza, no zap entry for the old path, and no user-facing old-name guidance anywhere.

This repository defines no `type:*` labels, so apply none.
