# Apply progress: `m7-tap-trust`

**Mode**: Strict TDD (`strict_tdd: true`) — RED proven by runner output before every GREEN.
**Branch**: `feat/m7-tap-trust` from `main` at `349a47f`.
**Artifact store**: hybrid — this file plus Engram `sdd/m7-tap-trust/apply-progress` (project `swiftui_cellar`).
**Delivery**: `single-pr`, no `size:exception`. Phases 0–8 and Phase 10 done; **Phase 9 is the maintainer's**.

## Baselines (task 0.1, re-measured at `349a47f`)

| Runner | Verbatim summary line |
|---|---|
| `swift test --package-path Packages/CellarCore` | `Test run with 1754 tests in 209 suites passed after 16.112 seconds with 1 known issue.` |
| `xcodebuild test … -only-testing:cellarTests` | **238** `' passed on '` lines, 0 failed |

Both match the expected baseline exactly, so the design's anchors were read against the same tree.

## Anchors (task 0.2)

Every anchor the design pins was found where it said, at `349a47f`:
`ConfirmationDisclosureTests.swift` :161-178 / :203 / :216 / :223-227 · `BrewMutatingTests.swift` :231-240 /
:257-264 / :279 / :292 · `TapShippingProofTests.swift` :90 (`allCases`, found at :92 — same statement,
two lines down from the design's note) / :194 / :197 · `MutationCommandTests.swift:289` ·
`OperationCenterBulk.swift` :113-124 / :169 · `TapProjection.swift` :25-27 / :141-147 ·
`InstalledDecoder.swift` :76 / :108 · `InstalledModels.swift` :39 / :65 / :80 ·
`ContentView.swift` :538-551 / :546 · `HomebrewUpdateNeed.swift` :85-86 · `TapDetailView.swift:183` ·
`MutationConfirmation.swift` :153 / :168 · `BrewfilePlan.swift` :34-43 · `BrewfileEntryTests.swift` :80-87.

## Commits (one per work unit, artifacts first)

| SHA | Commit |
|---|---|
| `66941fa` | `docs(sdd): record the m7-tap-trust exploration, proposal, spec deltas, design and tasks` |
| `a842d5e` | **WU1** `feat(taps): read and show the trust state Homebrew already reports` |
| `ff8e2bb` | **WU2** `fix(taps): stop claiming that adding a tap trusts it` |
| `7bb141e` | **WU3** `fix(installed): a withheld tap is absent, not empty` |
| `7665d9d` | **WU4** `feat(taps): grant and revoke tap trust as explicit answers` |
| `583ba8d` | **WU5** `fix(taps): revoke the grant before removing the tap` |
| `d78d8b1` | **WU6** `feat(activity): explain an untrusted-tap refusal and offer the only safe recovery` |
| `0d13513` | **WU7** `fix(brewfile): install the bare token a qualified entry names` |

No `Co-Authored-By` and no AI attribution on any commit. Nothing pushed; no PR opened (task 8.7 is
deliberately left to the maintainer — see *Tasks left unchecked*).

## TDD cycle evidence

| Unit | Test file · name | Layer | Safety net | RED (verbatim reason) | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 1 | `TapDecodeTests · tapTrustIsThreeValuedAndAbsenceIsNotFalse` | Unit | ✅ 1754 | `error: value of type 'TapRecord' has no member 'trust'` | ✅ | ✅ 4 inputs → 3 states | ➖ |
| 4a | `TapProjectionTests · unreportedTrustShowsNoBadgeAndNoControl` | Unit | ✅ 1754 | `error: type 'TapProjection' has no member 'trust'` | ✅ | ✅ 3 states | ➖ |
| 4e | `TapProjectionTests · everyTrustStringIsScopedToTheTap` | Unit | ✅ 1754 | `error: cannot find type 'TapTrustState' in scope` | ✅ | ✅ 3 states × 4 banned words | ➖ |
| 9c | `TapShippingProofTests · listRowAndDetailHeaderReadOneTrustProjection` | Unit (source scan) | ✅ 1754 | runtime: `Expectation failed: (source.code → "import BrewClient…")` — neither view read the projection | ✅ | ✅ 2 files × 6 patterns | ✅ extracted `tapUISources()` |
| 3 | `ConfirmationDisclosureTests · theAddDisclosureClaimsNoGrantAndTheGrantDisclosureClaimsOne` | Unit | ✅ 17 (WU1) | `error: type 'ConfirmationDisclosure' has no member 'tapAdd'` / `… 'tapTrustGrant'` | ✅ | ✅ 4 disclosures | ➖ |
| 5a | `InstalledDecodeTests · aNullTapIsAbsentNotEmpty` | Unit | ✅ 1759 | runtime: `Expectation failed: (withheld.tap → "") == nil` | ✅ | ✅ null / named / absent / cask | ➖ |
| 5b | `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` | Unit | ✅ 1759 | runtime: `Expectation failed: ((withheld.tap == "") → true) == false` | ✅ | ✅ 3 readers + 2 source scans | ➖ |
| 4b | `TapProjectionTests · aWithheldTapIsInstalledNotMissing` | Unit | ✅ 1759 | `error: value of type 'TapPackage' has no member 'state'` | ✅ | ✅ 3 states in one projection | ✅ `bareToken` extracted |
| 4c | `TapProjectionTests · aWithheldTapIsNotClaimedByATapThatDoesNotPublishIt` | Unit | ✅ 1759 | `error: … has no member 'statusExplanation'` | ✅ | ➖ paired with 4b | ➖ |
| 4d | `TapProjectionTests · aWithheldTapUnderATrustedOrUnreportedTapIsStillNotInstalled` | Unit | ✅ 1759 | `error: cannot infer contextual base in reference to member 'notInstalled'` | ✅ | ✅ parameterized ×2 | ➖ |
| 2a | `TapCommandTests · trustAndUntrustLowerToLiteralArgv` | Unit | ✅ 1764 | `error: type 'TapCommand' has no member 'trust'` | ✅ | ✅ 2 verbs + 4 hostile targets | ➖ |
| 2b | `TapCommandTests · onlyTheGrantIsConfirmedAndBothInvalidateInstalledInventory` | Unit | ✅ 1764 | `error: type 'TapCommand' has no member 'untrust'` | ✅ | ✅ 4 commands compared | ➖ |
| 9 | `TapShippingProofTests · completeActionSurfaceIsBounded` (updated 6→8 actions, 4→6 labels) | Unit | ✅ 1764 | `error: type 'TapCommand' has no member 'trust'`; then `Expectation failed: try staticButtonLabels(in: tapUI) == [...]` | ✅ | ✅ 8 actions | ✅ `exercise` → `[TapCommand]` |
| 9b | `TapShippingProofTests · anUnreportedTapOffersNoControlAndSpawnsNothing` | Unit | ✅ 1764 | `error: type 'TapCommand' has no member 'untrust'` | ✅ | ✅ controls vs removal | ✅ `drain()` extracted |
| 9d | `TapShippingProofTests · trustIsAReportedStateAndAGrantNeverAVerdict` | Unit (source scan) | ✅ 1764 | `error: type 'TapCommand' has no member 'trust'` | ✅ | ✅ 4 files × 11 verdict words | ✅ `coreTrustSources()` |
| 13 | `MutationRefreshReceiptTests · everyTapTerminalRefreshesItsDeclaredDomainsExactlyOnce` | Unit | ✅ 1764 | `error: type 'TapCommand' has no member 'trust'`; then `Expectation failed: (counts.taps → 0) == 1` | ✅ | ✅ **5 commands × 4 terminals = 20** | ✅ bounded `TestPoll` wait |
| 10 | `cellarTests/TapCompositionTests · noPathGrantsTrustWithoutAnExplicitAnswer` (+ `decliningATrustGrantSpawnsNothing`, + `BrewfileCompositionTests · anImportCarryingTrustClaimsSubmitsNoGrant`) | Integration (app) | ✅ 238 | `error: type 'TapCommand' has no member 'untrust'` | ✅ | ✅ 5 actions + decline + import | ➖ |
| 11 | `cellarUITests · theTrustControlAppearsOnlyForAnUntrustedTap` | E2E (XCUITest) | N/A (new) | `Failed to get matching snapshot`, then `("UNTRUSTED") is not equal to ("Untrusted")` | ✅ | ✅ 3 states × badge + 2 controls | ✅ per-surface badge identifiers |
| 2c | `TapCommandTests · everyRemovalRevokesBeforeItRemoves` (+ `removalAndRevocationDeclareNoDisclosure`) | Unit | ✅ 1769 | `error: type 'TapCommand' has no member 'removal'` | ✅ | ✅ parameterized over 3 trust states | ➖ |
| 8 | `ConfirmationDisclosureTests · aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap` | Unit | ✅ 1769 | `error: type 'TapCommand' has no member 'forcedRemoval'` | ✅ | ✅ 4 batch shapes | ➖ |
| 8b | `ConfirmationDisclosureTests · skippingPicksTheFirstDeclaringCommandNotTheStrongest` | Unit | ✅ 1769 | `error: value of type '[AnyBrewMutation]' has no member 'leadDisclosure'` | ✅ | ✅ 3-command batch + 2 edge batches | ➖ |
| 13b | `MutationRefreshReceiptTests · anUntapActionsInventoryRefreshComesFromItsRevocation` | Unit | ✅ 1769 | `error: type 'TapCommand' has no member 'removal'` | ✅ | ➖ one action, two attributions | ✅ bounded `TestPoll` wait |
| 14 | `TapIntegrationTests · aFailedRevocationDoesNotBlockTheRemoval` | Integration | ✅ 1769 | `error: type 'TapCommand' has no member 'removal'` | ✅ | ➖ one sequence, two terminals | ➖ |
| 14b | `TapIntegrationTests · anIdempotentGrantOrRevocationIsAnOrdinarySuccess` | Integration | ✅ 1769 | `error: type 'TapCommand' has no member 'trust'` | ✅ | ✅ re-grant + never-trusted revoke | ➖ |
| 6a | `ClassificationTests · anUntrustedTapRefusalIsItsOwnOutcome` | Unit | ✅ 1776 | `error: type 'MutationOutcome' has no member 'refusedUntrustedTap'` | ✅ | ✅ 6 classification inputs | ➖ |
| 6b | `ClassificationTests · nothingIsExtractedFromTheRefusal` | Unit | ✅ 1776 | same | ✅ | ✅ 2 taps + 5 banned substrings + tail bound | ➖ |
| 6c | `TapProjectionTests · theRecoveryPicksOnlyAUniquePublisherFromCellarsOwnSnapshot` (+ `publicationIsExactInKindAndToken`) | Unit | ✅ 1776 | `error: cannot find 'UntrustedTapRecovery' in scope` | ✅ | ✅ 7 candidate shapes | ➖ |
| 10b | `cellarTests/TapCompositionTests · theRefusalRecoveryOffersTrustOnlyForAUniquePublisher` | Integration (app) | ✅ 241 | `error: cannot find 'UntrustedTapRecovery' in scope` | ✅ | ✅ 0 / 1 / 2 publishers | ➖ |
| 10c | `MutationCommandTests · anUntrustedTapNeverPreBlocksAMutation` | Unit | ✅ 1776 | `error: type 'TapProjection' has no member 'publishes'`; then `Expectation failed: (mutation.contains(gate) → true) == false` | ✅ | ✅ 4 mutations + 9 banned tokens | ✅ narrowed the token list |
| 2d | `TapCommandTests · noRecoveryOrRetryPathSubmitsATrustCommand` | Unit | ✅ 1776 | `error: cannot find 'UntrustedTapRecovery' in scope` | ✅ | ✅ recovery + retry | ➖ |
| 7 | `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken` | Unit | ✅ 1782 | runtime: `Expectation failed: (qualified.installs.first?.arguments → ["install", "--formula", "acme/tap/thing"]) == ["install", "--formula", "thing"]` | ✅ | ✅ 3 families, ≥21 commands, 2 slash rules | ✅ scoped `naming` fixtures |
| 7b | `BrewfilePlanTests · aQualifiedEntryInstallsTheBareToken` | Unit | ✅ 1782 | `error: value of type 'BrewfileEntry' has no member 'installTarget'` | ✅ | ✅ formula / cask / degenerate / bare | ➖ |
| 7c | `BrewfileEntryTests · qualifiedNamesStillConstructAndProjectABareTarget` | Unit | ✅ 1782 | same | ✅ | ✅ 5 entry shapes | ➖ |
| 12 | `MutationCommandTests · everyCommandFamilyBuildsArgvStructurally` (shipped) | Unit | — | **regression guard — never went red**, re-confirmed green after WU7 | ✅ | — | — |

## Work unit evidence

| WU | Focused test command | Exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU1** | `swift test … --filter 'TapDecodeTests\|TapProjectionTests\|TapShippingProofTests'` | `Test run with 17 tests in 3 suites passed after 0.007 seconds.` | `xcodebuild build …` → `** BUILD SUCCEEDED **` | Drop `TapTrustState`, `TapRecord.trust`, `trust(for:)` and `TapTrustBadge`; the badge disappears. Revert WU3 first. |
| **WU2** | `swift test … --filter 'ConfirmationDisclosureTests\|BrewMutatingTests'` | `Test run with 16 tests in 2 suites passed after 0.075 seconds.` (full core `1759 tests in 209 suites … 1 known issue`) | The Add Tap sheet copy **is** the deliverable | Revert the rename commit — a clean single-commit revert. |
| **WU3** | `swift test … --filter 'InstalledDecodeTests\|InstalledDeriveTests\|TapProjectionTests'` | `Test run with 46 tests in 3 suites passed after 0.017 seconds.` (full core `1764 … 1 known issue`) | N/A — pure decode and projection over synthesised values; the end-to-end read is manual evidence 4 | Revert this commit alone. |
| **WU4** | `swift test … --filter 'TapCommandTests\|TapShippingProofTests\|MutationRefreshReceiptTests'` | `Test run with 21 tests in 3 suites passed after 0.023 seconds.` (full core `1769 … 1 known issue`) | `xcodebuild test … -only-testing:cellarTests/TapCompositionTests` → `** TEST SUCCEEDED **`; `… -only-testing:cellarUITests/TapTrustUITests` → `** TEST SUCCEEDED **` | Drop `.trustTap` / `.untrustTap`, their two controls and their pinned entries. |
| **WU5** | `swift test … --filter 'ConfirmationDisclosureTests\|BrewMutatingTests\|TapCommandTests\|MutationRefreshReceiptTests\|TapIntegrationTests'` | `Test run with 42 tests in 5 suites passed after 0.087 seconds.` (full core `1776 … 1 known issue`, twice) | `xcodebuild test … -only-testing:cellarTests` → `** TEST SUCCEEDED **` | Drop the prepend and the second protocol member; `removeTap` returns to one command. |
| **WU6** | `swift test … --filter 'ClassificationTests\|TapProjectionTests\|MutationCommandTests\|TapCommandTests'` | `Test run with 75 tests in 5 suites passed after 0.026 seconds.` (full core `1782 … 1 known issue`) | `xcodebuild test … -only-testing:cellarTests` → `** TEST SUCCEEDED **`; real refusal is manual evidence 2 | Drop `.refusedUntrustedTap`, `UntrustedTapRecovery.swift` and the drawer button; refusals return to `.failed` with the verbatim log. |
| **WU7** | `swift test … --filter 'MutationCommandTests\|BrewfilePlanTests\|BrewfileEntryTests'` | `Test run with 43 tests in 3 suites passed after 0.056 seconds.` | `xcodebuild build …` → `** BUILD SUCCEEDED **`; import row shows the install token | Drop `installTarget`; the plan returns to `entry.*.target`. |

## Phase 8 — verification

| Task | Evidence |
|---|---|
| **8.1** | `swift test --package-path Packages/CellarCore` → `Test run with 1785 tests in 209 suites passed after 16.642 seconds with 1 known issue.` Baseline 1754 → **+31**, 209 suites unchanged, **1 known issue unchanged** (`OperationCenterCancelTests`), 0 failures. |
| **8.2** | `xcodebuild test … -only-testing:cellarTests` → **242** `' passed on '`, **0** `' failed on '`, `** TEST SUCCEEDED **`. Baseline 238 → **+4** (2 `TapCompositionTests`, 1 `BrewfileCompositionTests`, +1 re-run row). |
| **8.3** | `xcodebuild test … -only-testing:cellarUITests/TapTrustUITests` → `Test Case '-[cellarUITests.TapTrustUITests testTheTrustControlAppearsOnlyForAnUntrustedTap]' passed (13.384 seconds).` `** TEST SUCCEEDED **` |
| **8.4** | `git diff --stat main -- scripts/ .github/workflows/ Packages/CellarCore/Sources/Catalog Packages/CellarCore/Sources/BrewProcess Packages/CellarCore/Sources/BrewClient/TapPayloadSource.swift Packages/CellarCore/Sources/BrewClient/MutationCommand.swift cellar.xcodeproj/project.pbxproj` → **empty**. `MutationCommand.swift` is byte-identical: **DD-8 held, D3 not violated.** |
| **8.5** | `git diff --stat main` → **47 files changed, 6239 insertions(+), 115 deletions(-)**. Split: SDD artifacts **3559** (8 files), code + tests **2680 + 115 = 2795** (39 files). Forecast was 2,885–3,567 for the PR total against **6354** actual — the artifact bucket was forecast at 600–900 and landed at 3,559, which is where the whole miss is. The code + test bucket was forecast at 1,815–2,197 and landed at 2,795: a **1.27–1.54×** overshoot on the corrected estimate, i.e. the house 1.9–2.3× correction was applied to a bottom-up that was itself low. Information for the next forecast, not a failure. |
| **8.6** | `?.disclosure ??` ban, `divergent.count == 7`, `Button {` ban and `MutationCommandTests:289` all present and green. `rg '\.tapTrust\('` and `rg 'case tapTrust\b'` over `cellar/` and `Packages/` → **0 hits** each. |
| **8.7** | **Not done, deliberately** — the launch brief instructs "Do NOT push, do NOT open a PR". Left unchecked for the maintainer. |

## Deviations from the design

**D-1 — three more shipped sites pinned the old add sentence verbatim.**
Design §3 tabulated `ConfirmationDisclosureTests.swift:176-177` and `BrewMutatingTests.swift:279`/`:292`
as the copy-bearing sites the D2 rename touches. Four more assert the old sentence and had to move with
it: `ConfirmationDisclosureTests.swift:93`, `cellarTests/BrewfileCompositionTests.swift:265`,
`cellarUITests/BrewfileImportUITests.swift:92`, and `TapCommandTests.swift:111` — the last asserted
`warningText.contains("formulae and casks")` while the new copy says "formulae **or** casks", so it now
anchors on `"clones a third-party repository"`. Evidence: `Expectation failed: (request.warningText →
"Adding acme/tap clones a third-party repository…") == "Adding acme/tap trusts third-party formulae and
casks that can distribute code."` Smallest correct alternative: move the four assertions, change no
production behaviour. No binding decision affected.

**D-2 — the rename sweep is zero over source, not over this change's own instructions.**
Task 2.5 requires `rg '\.tapTrust\('` and `rg 'case tapTrust\b'` to be zero across `cellar/`,
`Packages/` **and** `openspec/changes/m7-tap-trust/`. Source and tests are zero. Three hits remain in
the artifacts — `design.md:345` (the §3 table row "`.tapTrust(tap)` → `.tapAdd(tap)`") and
`tasks.md:203`/`:214` (task 2.1's "RED because" and task 2.5's own literal regex). Those are the written
*instruction* to perform the rename, not code that could compile the old case; deleting them would erase
the record of why the rename happened. Reported rather than absorbed.

**D-3 — `TapProjection.publishes(_:in:)` moved from WU3 to WU6.**
Design §5 groups `bareToken` and `publishes` in WU3. `bareToken` landed there because
`packages(for:installed:)` consumes it and the shipped tests cover it. `publishes` has **no** caller
until `UntrustedTapRecovery` in WU6, so adding it in WU3 would have shipped untested production code
under `strict_tdd: true`. It is now driven RED-first by unit 6c (`error: type 'TapProjection' has no
member 'publishes'`) and additionally pinned by `publicationIsExactInKindAndToken`.

**D-4 — the two tap controls submit through `operations` directly, not through a `ContentView` closure.**
DD-12 prescribes injected `@MainActor` closures for both app-side lookups. That is required for
`ActivityDrawer`, which holds no `TapStore` — implemented exactly as designed (`trustableTap(for:)` in
`ContentView`, forwarded through `ActivityBar`). `TapDetailView` already holds `operations` and submits
`untap` and `forceUntap` directly, so Trust and Untrust do the same. Routing them through `ContentView`
would add a seam the shipped idiom does not have, for no behavioural difference. Behaviour is pinned by
unit 10 (`TapCompositionTests`) and unit 11 (XCUITest).

**D-5 — unit 7's `naming(_:_:)` fixtures cover the identities Cellar types, not synthetic qualified ones.**
The first draft fed `PackageID(kind: .formula, name: "acme/tap/thing")` straight into
`MutationCommand.naming` and demanded no slash in the result. That is a demand for a `/` gate on
`PackageTarget.init?`, which **DD-8 explicitly forbids** (`TapName.init?` is expressed over the same
gate). The fixture set is now the identities Cellar actually types — catalog and installed identities,
which are bare — plus every command a `BrewfilePlan` built from a **qualified** fixture emits, which is
the one path a qualified name can enter by and the one D3 strips. The comment in the test records why.

**D-6 — `SwiftDataHistoryRecorder.classify` needed a new arm.**
Not listed in the design's *File Changes*. Adding `.refusedUntrustedTap` made its switch non-exhaustive
(`error: switch must be exhaustive`), so the recorder gained
`case .refusedUntrustedTap: ("refusedUntrustedTap", nil)` — `nil` status, because the command never ran
and inventing one would be a confident lie in a durable row, exactly as the surrounding comment already
argues for `busy` and `launchFailed`.

**D-7 — the badge needed a per-surface accessibility identifier, and must not be uppercased.**
Both found by unit 11, and both are real: `.textCase(.uppercase)` rendered `UNTRUSTED` while TM12 :422
pins the exact copy `Untrusted` (`XCTAssertEqual failed: ("UNTRUSTED") is not equal to ("Untrusted")`),
and a single identifier resolved to two elements as soon as a badged tap was selected, because the row
and the header render the **same** projection. The identifiers are now `tap-row-trust-badge` and
`tap-detail-trust-badge`; the projection still returns one string.

## Phase 10 — archive obligations, recorded now

- **10.1** Confirmed: **no `## Verification classes` table exists** in any of the four target specs, so —
  unlike the `m6-sparkle-updates` / `m6-cask-tap` precedent — there is **no class table to hand-update at
  archive**. This change is the first to annotate these specs with inline `- Verification:` lines;
  untouched requirements deliberately keep none, and that asymmetry should be recorded rather than
  "fixed" by annotating blocks this change did not review.
- **10.2** `tap-management` provenance arithmetic: the main spec records `m3-taps` as 11 requirements /
  **33** scenarios while the file carries **34** `#### Scenario:` headings. Count the headings, then
  correct the provenance entry in the same archive edit.
- **10.3** Deviations to record at archive: the proposal budgeted **one** ADDED requirement for
  `tap-management` and the delta writes **two** (TM12, TM13); resulting counts assume both. Record **D1**
  (keep Homebrew's tap/trust split; add grants nothing; trust and untrust are separately answered; untap
  revokes first; the fully-qualified-argv bypass is prohibited and asserted by test) rejecting
  add-and-trust as one confirmed batch, the two-outcome confirmation, the pre-launch tap-state gate and
  the fully-qualified argv; **D2** (`ConfirmationDisclosure.tapTrust` → `.tapAdd`, plus `.tapTrustGrant`)
  rejecting a case named for a grant the command never makes; and **D3** (strip the qualifier at the
  Brewfile plan) rejecting a `/` gate on `PackageTarget.init?` and rejecting a carve-out for
  user-authored qualified names. Deferred follow-ups: a per-package trust surface, a trust column in the
  Brewfile diff, trust for official taps (non-mutable under TM4), and **R15** — a qualified Brewfile
  entry keeps its qualified identity for diffing, so it always projects as "missing" even when the bare
  package is installed.

## Tasks left unchecked, and why

- **Phase 9 (9.1–9.6)** — `manual-evidence` on the maintainer's Mac with real Homebrew 6.0.18. Not
  reachable by any `--filter` or `-only-testing:` invocation; the specs themselves declare no harness can
  exist here. `sdd-verify` must not wait for one. The binding stands: **never run `brew upgrade` without
  `--dry-run`** on that Mac, including on any retry.
- **Task 8.7** — opening the PR. The launch brief instructs not to push and not to open a PR. When it is
  opened, the body must state (a) **reverting Cellar does not revoke a grant already written to
  `~/.homebrew/trust.json`** — `brew untrust <tap>` in Terminal remains the exit; and (b) **R5** — on a
  Homebrew with no `untrust` verb every untap shows a visibly failed `untrust` beside a succeeding
  `untap`, which is TM7's deliberate choice, not a defect. Title
  `feat(taps): make tap trust visible, explicit and revocable`, exactly one `type:feature` label.

Everything in Phases 0–8 (except 8.7) and Phase 10 is checked in `tasks.md`.
