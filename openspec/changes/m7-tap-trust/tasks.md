# Tasks: Tap Trust as a First-Class, Honest Capability (`m7-tap-trust`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`chain_strategy=n/a (single-pr)`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

Inputs: `design.md` (DD-1…DD-14, the conformer table, the six exact guard updates, RED units 1–14b,
Scenario Coverage, Work Units WU1–WU7, Bindings, Risk Register R1–R16, *Evidence to Capture*),
`proposal.md` (**D1, D2 binding**), Engram obs `#7730` (**D3** binding, plus the five resolved
defaults), and the four spec deltas
`specs/{tap-management,package-mutation,brewfile-management,installed-inventory}/spec.md`
(**89 scenarios**: 40 / 30 / 11 / 8 — **85 `unit`/`e2e`, 4 `manual-evidence`**). The design passed a
fresh-context validator against these amended deltas; nothing below re-litigates it.

Size note: this artifact exceeds the generic 530-word phase budget, matching the house precedent at
`openspec/changes/archive/2026-08-23-m6-cask-tap/tasks.md:47`. Nothing is padded.

## Scenario map (IDs used by every task below)

**`tap-management` — 40.** **TM5**.1 selected prefix only · .2 qualified cask token matches ·
.3 equal formula/cask tokens distinct · .4 exact installed tap controls handoff · **.5 withheld under
untrusted reads installed** · **.6 withheld not claimed by a non-publisher** · **.7 withheld under
trusted/unreported is still "Not installed."** · .8 tap names never become catalog records ·
.9 large inventory narrows lazily. **TM6**.1 canonical argv · .2 hostile targets rejected ·
**.3 every add discloses what add does and does not do** · **.4 adding a tap grants no trust** ·
.5 presentation cannot rewrite execution. **TM7**.1 plain untap grows no hidden force flag ·
**.2 untap revokes before it removes** · **.3 a failed revocation does not block the removal** ·
.4 empty cross-reference hides force · .5 untrustworthy inventory cannot enable force.
**TM8**.1 disclosure names every kind-qualified package · **.2 a revoke-first force batch still
presents the force-untap disclosure** · .3 additions/removals invalidate stale confirmation · .4 kind
change invalidates · .5 ordering alone does not. **TM9**.1 tap mutations serialize · **.2 tap
terminals refresh only declared domains** · **.3 an untap action's inventory refresh comes from its
revocation**. **TM11**.1 **enumerated tap actions stay within scope (8)** · **.2 trust is a reported
state and a grant, never a verdict**. **TM12**.1 **three distinct states** · **.2 an unreported tap's
controls show nothing and spawn nothing** · **.3 badge and controls follow the state exactly** ·
**.4 list row and detail header read one projection** · **.5 trust copy is about the tap**.
**TM13**.1 **trust/untrust exact argv** · **.2 a grant is confirmed and a revocation is not** ·
**.3 no path grants trust implicitly** · **.4 an idempotent grant or revocation is an ordinary
success** · **.5 a real grant round trip flips the badge** *(`manual-evidence`)* · **.6 untapping a
trusted tap leaves no grant behind** *(`manual-evidence`)*.

**`package-mutation` — 30.** **PM1**.1–.5 kind flags · .6 another family enters the spine ·
**.7 erased mixed batch discloses the tap add** · **.8 erased install-only batch discloses package
removal** · **.9 a batch led by a non-declaring command still presents the real disclosure** ·
**.10 skipping picks the first declaring command, not the strongest** · .11 no disclosure recovered by
a type test. **PM3**.1–.6 uninstall/zap/bulk gate · **.7 every tap add carries its typed add
disclosure** · **.8 every trust grant is confirmed and carries the grant disclosure** · **.9 untrust
passes the gate without a confirmation** · .10 force untap carries complete package disclosure ·
.11 stale disclosure/display text cannot become argv. **PM10**.1 **a stderr refusal on a failed
mutation is the typed outcome** · **.2 the same prose on stdout, on a success, or without the tap
phrase does not classify** · **.3 nothing is extracted from the refusal** · **.4 the outcome offers
Trust and is worded about the tap** · **.5 no mutation argv anywhere carries a qualified package
token** · **.6 an untrusted tap never pre-blocks a mutation** · **.7 the formula refusal wording is
captured before the classifier claims it** *(`manual-evidence`)* · **.8 a real refusal renders the
typed outcome with brew's own trust line** *(`manual-evidence`)*.

**`brewfile-management` — 11.** **BF5**.1 a trusted tap still raises the tap-add disclosure ·
.2 `trusted:` never becomes argv · .3 an import submits no trust command · .4 the claim is surfaced,
attributed to the file · .5 `trusted:` on a brew/cask line parses and confers nothing · **.6 a
qualified package entry installs the bare token**. **BF7**.1 mixed selection fans out, taps first ·
.2 only selected entries are submitted · .3 one confirmation covers the batch · .4 an empty selection
submits nothing · .5 a mid-batch failure attributes to one entry.

**`installed-inventory` — 8.** **II2**.1–.5 keg/cask/auto-update/linked shapes · **.6 a withheld tap
decodes as absent, not as empty** · **.7 a record with a withheld tap still enters the inventory** ·
**.8 an absent tap never matches a selected tap**.

**Verification-class honesty.** Exactly four scenarios — **TM13.5, TM13.6, PM10.7, PM10.8** — are
`manual-evidence` on the maintainer's Mac (Homebrew 6.0.18). They are **not** RED/GREEN tasks, no
`--filter` or `-only-testing:` invocation can reach them, and `sdd-verify` MUST NOT wait for a harness
the specs themselves declare cannot exist here. Phase 9 carries the exact commands and the exact
accepted evidence. Every other scenario is `unit` except TM12.3's control visibility, whose `e2e` half
is `cellarUITests`.

## Review Workload Forecast

Reused from `design.md` *Review Workload Forecast* — **not re-derived**.

| Field | Value |
|---|---|
| Bottom-up lines | **~1,425** (core ~285 · app ~150 · tests ~520 · specs ~470) |
| House correction | **1.9–2.3×**, applied to the **code + test** buckets only (955 → **1,815–2,197**); the spec buckets are enumerated requirement-by-requirement and are not subject to discovery drift |
| SDD artifacts (proposal, design, tasks) | **~600–900** |
| Estimated changed lines (PR total) | **~2,885–3,567** authored |
| Governing budget | **5,000** (`config.yaml` and session preflight agree) |
| Risk vs governing budget | **Low** — ≤71 % at the ceiling |
| Chained PRs recommended | No — one PR, seven work-unit commits plus one artifact commit |
| Suggested split | Single PR on `feat/m7-tap-trust`. If the maintainer later prefers slices, the natural cut is **WU1–WU3** (read, honest copy, withheld state) then **WU4–WU7** (grant, revoke, refusal, Brewfile) |
| Sizing label | **`size:exception` — recorded by maintainer decision 2026-08-23 after apply.** Measured PR total 6,555 changed lines: 2,680 code+tests (inside the corrected forecast band) + 3,760 SDD artifacts under `openspec/` (forecast 600–900; the two validator rounds and the 89-scenario deltas are the overrun). One PR kept; ledger objective reset to 7,000 with that reason. PR label: none (this repository defines no `type:*` labels) |
| Delivery strategy | single-pr |
| Chain strategy | pending (n/a — no chain) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**; that default does not
govern this repository. Against the governing 5,000-line budget the risk is **Low**, so `single-pr`
held at forecast time with no `size:exception`; **after apply the measured total (6,555) exceeded the budget and the maintainer recorded `size:exception` (row above)** — unlike the `m6-release-pipeline` /
`m6-cask-tap` precedent.

**Branch**: `feat/m7-tap-trust` (`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**PR title**: `feat(taps): make tap trust visible, explicit and revocable`.

### Suggested Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

RED and GREEN may be separate commits inside a unit (house precedent); tests never leave the unit
whose behaviour they verify.

| Unit | Goal | Commit | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| **WU1** | `trusted` decode → `TapTrustState`; `TapTrustPresentation`; list/detail badge | `feat(taps): read and show the trust state Homebrew already reports` | `swift test --package-path Packages/CellarCore --filter 'TapDecodeTests|TapProjectionTests|TapShippingProofTests'` | `xcodebuild build …` then launch and open Taps: an untrusted tap shows **Untrusted**; full round trip deferred to manual evidence 1 | Drop the decode and the projection; the badge disappears and nothing else changes. **Revert WU3 first if WU1 is dropped** (WU3 compiles against `TapTrustState`) |
| **WU2** | `.tapAdd` / `.tapTrustGrant`; `MutationConfirmation` copy; `PRD.md` §3.7 :108 | `fix(taps): stop claiming that adding a tap trusts it` | `swift test --package-path Packages/CellarCore --filter 'ConfirmationDisclosureTests|BrewMutatingTests'` | Open the Add Tap sheet and read the sentence — the copy **is** the deliverable | Revert the rename commit; a clean single-commit revert |
| **WU3** | `InstalledPackage.tap: String?`; `bareToken` / `publishes`; the withheld state; `statusExplanation` | `fix(installed): a withheld tap is absent, not empty` | `swift test --package-path Packages/CellarCore --filter 'InstalledDecodeTests|InstalledDeriveTests|TapProjectionTests'` | N/A — pure decode and projection over synthesised values; the end-to-end read is manual evidence 4 | Revert this commit alone; independent of every trust **surface**, but see the WU1 note |
| **WU4** | `.trustTap` / `.untrustTap`; detail controls; shipping proof; composition tests; refresh receipts | `feat(taps): grant and revoke tap trust as explicit answers` | `swift test --package-path Packages/CellarCore --filter 'TapCommandTests|TapShippingProofTests|MutationRefreshReceiptTests'` + `xcodebuild test … -only-testing:cellarTests/TapCompositionTests` | `xcodebuild test … -only-testing:cellarUITests/TapTrustUITests`; real grant is manual evidence 1 | Drop the two cases, their controls and their pinned entries |
| **WU5** | `removal(of:)` / `forcedRemoval`; `submitSequence`; `declaredDisclosure` + `leadDisclosure` | `fix(taps): revoke the grant before removing the tap` | `swift test --package-path Packages/CellarCore --filter 'ConfirmationDisclosureTests|BrewMutatingTests|TapCommandTests|MutationRefreshReceiptTests|TapIntegrationTests'` | Untap a tap from the running app and read Activity: two visible operations in order; real revocation is manual evidence 3 | Drop the prepend and the second protocol member; `removeTap` returns to one command |
| **WU6** | `.refusedUntrustedTap`; `UntrustedTapRecovery`; the Activity recovery button | `feat(activity): explain an untrusted-tap refusal and offer the only safe recovery` | `swift test --package-path Packages/CellarCore --filter 'ClassificationTests|TapProjectionTests|MutationCommandTests'` + `xcodebuild test … -only-testing:cellarTests/TapCompositionTests` | Manual evidence 2 (a real refusal, `--dry-run` only) | Drop the case and the new file; refusals return to `.failed` with the verbatim log |
| **WU7** | **D3**: `BrewfileEntry.installTarget`; the plan strip; import-row detail; the absence assertion | `fix(brewfile): install the bare token a qualified entry names` | `swift test --package-path Packages/CellarCore --filter 'MutationCommandTests|BrewfilePlanTests|BrewfileEntryTests'` | Import a Brewfile containing `brew "acme/tap/thing"` and read the preview row before applying | Drop the projection; the plan returns to `entry.*.target` |

Plus one artifact commit, **first on the branch** so the reviewed diff opens with the reasoning:
`docs(sdd): record the m7-tap-trust proposal, spec deltas, design and tasks`.

**Parallel vs sequential.**

- **Sequential, hard dependencies**: WU1 → WU3 (`installState` reads `tap.trust`); WU1 → WU4 (controls
  switch on the three states); WU2 → WU4 (`.tapTrustGrant` must exist before `.trustTap` declares it);
  WU4 → WU5 (`.untrustTap` must exist before a sequence can prepend it); WU1 + WU3 + WU4 → WU6
  (`UntrustedTapRecovery` reads `record.trust` **and** `TapProjection.publishes`, and the button
  submits `.trustTap`).
- **Parallelisable in principle**: WU1 ∥ WU2 (disjoint files), and WU7 ∥ everything (only
  `BrewfileEntry.swift`, `BrewfilePlan.swift` and the import row). **One writer, executed
  sequentially** — no parallel worktrees. WU7 is scheduled last so unit 7's absence assertion walks
  the argv surface *after* WU4/WU5 added to it.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Never negotiable.
- **Rollback order** is the reverse — WU7 → WU6 → WU5 → WU4 → WU3 → WU1 — with WU2 standing alone.
  This corrects `design.md` *Work Units*, which lists WU3 as unconditionally independent: its
  `tap: String?` half is, its withheld-state half is not.

## Phase 0: Preflight (sequential; no behaviour changes)

- [x] 0.1 Measure and record the green baseline; do not re-derive it later. Expected
      `swift test --package-path Packages/CellarCore` → **1754 tests / 209 suites, 1 known issue,
      0 failures**, and `xcodebuild test … -only-testing:cellarTests` → **238 passed / 0 failed**.
      Count **distinct** passing test ids; `Executed 0 tests` is meaningless for Swift Testing bundles.
      A different number is the new baseline, not a defect — record it and move on.
- [x] 0.2 Confirm every anchor the design pins is still where it says (all were at `349a47f`):
      `ConfirmationDisclosureTests.swift` :161-178 / :203 / :216 / :223-227 ·
      `BrewMutatingTests.swift` :231-240 / :257-264 / :279 / :292 ·
      `TapShippingProofTests.swift` :90 / :194-197 / :219-226 · `MutationCommandTests.swift:289` ·
      `OperationCenterBulk.swift` :113-124 / :169 · `TapProjection.swift` :25-27 / :141-147 ·
      `InstalledDecoder.swift` :76 / :108 · `InstalledModels.swift` :39 / :65 / :80 ·
      `ContentView.swift` :538-551 / :546 · `HomebrewUpdateNeed.swift` :85-86 ·
      `TapDetailView.swift:183` · `MutationConfirmation.swift` :153 / :168 ·
      `BrewfilePlan.swift` :34-43 · `BrewfileEntryTests.swift` :80-87. A moved anchor is a deviation
      to report, not to absorb.
- [x] 0.3 `git checkout -b feat/m7-tap-trust main`, then commit the SDD artifacts
      (`docs(sdd): record the m7-tap-trust proposal, spec deltas, design and tasks`).

## Phase 1: WU1 — read and show the trust state (TM12.1, .3, .4, .5)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapDecodeTests|TapProjectionTests|TapShippingProofTests'`

- [x] 1.1 **RED — unit 1.** `TapDecodeTests · tapTrustIsThreeValuedAndAbsenceIsNotFalse`:
      `trusted` `true` / `false` / **`null`** / **absent** → `.trusted` / `.untrusted` /
      `.unreported` / `.unreported`. The fixture MUST mirror the real `tap-info --installed --json`
      object shape (PR #67 lesson). **RED because** `TapWire` names no `trusted` key. *(TM12.1)*
- [x] 1.2 **RED — unit 4a.** `TapProjectionTests · unreportedTrustShowsNoBadgeAndNoControl`:
      `TapProjection.trust(for:)` over all three states; badge text exactly `"Untrusted"` for
      `.untrusted`, `nil` otherwise; `canGrant` / `canRevoke` per DD-13. **RED because** no trust
      projection exists. *(TM12.3)*
- [x] 1.3 **RED — unit 4e.** `TapProjectionTests · everyTrustStringIsScopedToTheTap`: every string the
      trust surface presents names the tap and none states or implies that a *package* is untrusted
      (R7 — a per-package grant would make that false). **RED because** no trust strings exist.
      *(TM12.5)*
- [x] 1.4 **RED — unit 9c.** `TapShippingProofTests · listRowAndDetailHeaderReadOneTrustProjection`:
      both `TapsListView.swift` and `TapDetailView.swift` call `TapProjection.trust(for:)` and neither
      computes a badge string or a control condition locally. **RED because** nothing prevents the two
      drifting. *(TM12.4)*
- [x] 1.5 **Prove RED.** Run the focused command; 1.1–1.4 MUST fail, each for its stated reason. A
      green test here is a defect in the test.
- [x] 1.6 **GREEN.** `TapWire.swift`: add `TapTrustState { trusted, untrusted, unreported }`,
      `case trusted` in `CodingKeys`, `decodeIfPresent(Bool.self, forKey: .trusted)`, and
      `TapRecord.trust` **after `lastCommit` with an initialiser default of `.unreported`** so every
      shipped fixture keeps compiling. `TapDecoder.inventory(from:)` maps
      `wire.trusted.map { $0 ? .trusted : .untrusted } ?? .unreported` — design §1, verbatim.
- [x] 1.7 **GREEN.** `TapProjection.swift`: add `TapTrustPresentation { badge, canGrant, canRevoke }`
      and `static func trust(for:)` exactly as design §6 states.
- [x] 1.8 **GREEN.** `cellar/Taps/TapsListView.swift` (badge beside the tap name, **no button**) and
      `cellar/Taps/TapDetailView.swift` (badge in the header), both reading `trust(for:)` and nothing
      else.
- [x] 1.9 Re-run the focused command → green; commit WU1.

## Phase 2: WU2 — the copy stops lying (TM6.3, PM3.7)

Runner: `swift test --package-path Packages/CellarCore --filter 'ConfirmationDisclosureTests|BrewMutatingTests'`

- [x] 2.1 **RED — unit 3.** `ConfirmationDisclosureTests ·
      theAddDisclosureClaimsNoGrantAndTheGrantDisclosureClaimsOne`: the exact `warningText` for
      `.tapAdd(TapName)` and `.tapTrustGrant(TapName)` from design §2, plus `.packageRemoval` and
      `.forceUntap` unchanged. In the **same** RED commit, rename the shipped assertions at
      `ConfirmationDisclosureTests.swift:176-177` and `BrewMutatingTests.swift:279`/`:292` from
      `.tapTrust(tap)` to `.tapAdd(tap)`. **RED because** `.tapTrust` still asserts a grant.
      *(TM6.3, PM3.7)*
- [x] 2.2 **Prove RED**, then **GREEN**: `TapCommand.swift` — `ConfirmationDisclosure.tapTrust`
      becomes `.tapAdd(TapName)` and `.tapTrustGrant(TapName)` is added (**D2**). `.tapTrustGrant`
      has no producer yet; that is WU4 and is correct here.
- [x] 2.3 **GREEN.** `cellar/Activity/MutationConfirmation.swift` :153 / :168 — `.tapAdd` → title
      "Add this tap?" / confirm label "Add Tap"; `.tapTrustGrant` → "Trust this tap?" / "Trust".
- [x] 2.4 **GREEN.** `PRD.md` §3.7 :108 — the taps-manager line describes tap **versus** trust
      honestly (adding clones a repository; loading its formulae and casks needs a separate trust that
      Cellar never grants for the user), and the action list grows to include trust and untrust.
      `README.md` :37-45 **already** states this correctly — confirm, do not edit.
- [x] 2.5 **Rename sweep, precisely (R10).** `rg '\.tapTrust\('` and `rg 'case tapTrust\b'` MUST return
      **zero** hits across `cellar/`, `Packages/` and `openspec/changes/m7-tap-trust/`. Do **not** grep
      the bare substring `tapTrust`: `.tapTrustGrant` and `TapCommand.verb == "tapTrust"` (the verb of
      `.trustTap`, added in WU4) legitimately contain it.
- [x] 2.6 Focused command green; commit WU2.

## Phase 3: WU3 — a withheld tap is absent, not empty (II2.6, .7, .8; TM5.5, .6, .7)

Runner: `swift test --package-path Packages/CellarCore --filter 'InstalledDecodeTests|InstalledDeriveTests|TapProjectionTests'`

- [x] 3.1 **RED — unit 5a.** `InstalledDecodeTests · aNullTapIsAbsentNotEmpty`: `tap: null` → `nil`;
      `"acme/tools"` → that value; the key absent → `nil`; the record still decodes with version and
      kind intact and still enters the inventory. **RED because** `?? ""` collapses null.
      *(II2.6, II2.7)*
- [x] 3.2 **RED — unit 5b.** `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch`: the three
      readers — `TapProjection.swift:146` no-match, `ContentView.forceEvidence` excludes the record,
      `HomebrewUpdateNeed` treats it as incomparable — and absence matches neither a tap name nor `""`.
      **RED because** (DD-11) the migration is **not** compiler-enforced; nothing else pins these
      sites. *(II2.8)*
- [x] 3.3 **RED — unit 4b.** `TapProjectionTests · aWithheldTapIsInstalledNotMissing`: withheld +
      untrusted + published here → `.installedTapWithheld(id)`, copy exactly
      `"Installed. Homebrew withholds its tap while this tap is untrusted."`, `installedHandoff`
      non-`nil`; exact-match and not-installed paths unchanged. **RED because** `exactInstalled` has
      two states. *(TM5.5)*
- [x] 3.4 **RED — unit 4c.** `TapProjectionTests · aWithheldTapIsNotClaimedByATapThatDoesNotPublishIt`:
      a `tap: nil` record the selected tap does not publish makes no middle-state claim. **RED
      because** nothing enforces the publication clause for the withheld path. *(TM5.6)*
- [x] 3.5 **RED — unit 4d.** `TapProjectionTests ·
      aWithheldTapUnderATrustedOrUnreportedTapIsStillNotInstalled`, parameterized over `.trusted` and
      `.unreported`: exact copy `"Not installed."`, no withheld copy. *(TM5.7)*
- [x] 3.6 **Prove RED** (all five), then **GREEN**: `InstalledModels.swift` :39 / :65 / :80 →
      `tap: String?` with the design's doc comment; `InstalledDecoder.swift` :76 / :108 → drop both
      `?? ""`.
- [x] 3.7 **GREEN.** `TapProjection.swift`: add `bareToken(_:publishedBy:)`, `publishes(_:in:)`,
      `TapPackageInstallState`, the private `installState(_:tap:inventory:)`, `TapPackage.state`,
      `isInstalled`, `installedHandoff`, and rename `uninstalledExplanation` → `statusExplanation`
      (DD-10). Follow the rename into its view readers in the same commit.
- [x] 3.8 Focused command green; commit WU3.

## Phase 4: WU4 — grant and revoke as explicit answers (TM13.1, .2; TM11.1, .2; TM12.2; TM9.2; TM6.4; PM3.8, .9; BF5.1, .3)

Runners: `swift test --package-path Packages/CellarCore --filter 'TapCommandTests|TapShippingProofTests|MutationRefreshReceiptTests'`
and `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests/TapCompositionTests`.
`TapShippingProofTests` lives in `Packages/CellarCore/Tests/BrewClientTests/`, so it runs under
`swift test`, **not** `xcodebuild`.

- [x] 4.1 **RED — unit 2a.** `TapCommandTests · trustAndUntrustLowerToLiteralArgv`:
      `["trust","acme/tools"]` / `["untrust","acme/tools"]`; verbs `tapTrust` / `tapUntrust`;
      `packageID == nil`; no kind flag and no extra token. **RED because** the cases do not exist.
      *(TM13.1)*
- [x] 4.2 **RED — unit 2b.** `TapCommandTests ·
      onlyTheGrantIsConfirmedAndBothInvalidateInstalledInventory`: `requiresConfirmation` true for
      `.trustTap` and false for `.untrustTap`; `invalidates == [.taps, .installedInventory]` for both.
      *(TM13.2, PM3.8, PM3.9)*
- [x] 4.3 **RED — unit 9.** `TapShippingProofTests`, two shipped cases updated deliberately (R9):
      `:90` `TapManagementAction.allCases` grows **6 → 8** (`…, "trust", "untrust"`, in TM11's order)
      and the flattened argv/invalidation expectations at `:101-110` grow with it; `:194` the pinned
      `staticButtonLabels` set grows **4 → 6** to
      `["Add Tap","Untap","Force Untap","Show in Installed","Trust","Untrust"]`; `:197`'s `Button {`
      ban and the excluded-capability scan stay green untouched. The `exercise(_:store:installed:)`
      helper's return type becomes `[TapCommand]`. *(TM11.1)*
- [x] 4.4 **RED — unit 9b.** `TapShippingProofTests · anUnreportedTapOffersNoControlAndSpawnsNothing`:
      invoking both controls for an `unreported` tap builds and spawns nothing
      (`launcher.specs.isEmpty`), **while an untap of the same tap still submits its revocation**
      (the amended TM12 clause — spec amendment #2). *(TM12.2)*
- [x] 4.5 **RED — unit 9d.** `TapShippingProofTests · trustIsAReportedStateAndAGrantNeverAVerdict`:
      everything the surface presents is either the reported state or a control submitting brew's own
      grant/revocation; no scoring, ranking or recommendation vocabulary appears. *(TM11.2)*
- [x] 4.6 **RED — unit 13.** `MutationRefreshReceiptTests ·
      everyTapTerminalRefreshesItsDeclaredDomainsExactlyOnce`: **5 commands × 4 terminals** (success,
      failure, launch failure, cancellation before spawn) — taps ×1 each; installed inventory ×1 for
      trust, untrust and force untap and ×0 for add and plain untap; catalog ×0 everywhere. **RED
      because** TM9's enumeration is three commands today. *(TM9.2)*
- [x] 4.7 **RED — unit 10.** New file `cellarTests/TapCompositionTests.swift` ·
      `noPathGrantsTrustWithoutAnExplicitAnswer`: Add Tap raises exactly one `.tapAdd`; Trust exactly
      one `.tapTrustGrant`; **Untrust none**; Untap none; Force Untap exactly one `.forceUntap`. Extend
      `cellarTests/BrewfileCompositionTests.swift`: an import with `trusted:` on tap, brew and cask
      lines raises exactly one `.tapAdd` and submits **no** `trust` argv. `cellarTests/` is a
      `PBXFileSystemSynchronizedRootGroup`, so the new file needs **no** `project.pbxproj` edit.
      *(TM6.4, TM13.2, BF5.1, BF5.3, PM3.7, PM3.8, PM3.9)*
- [x] 4.8 **RED — unit 11.** New file `cellarUITests/TapTrustUITests.swift` (XCUITest, not Swift
      Testing) · `theTrustControlAppearsOnlyForAnUntrustedTap`: Trust present only for `.untrusted`,
      Untrust only for `.trusted`, neither for `.unreported`, badge text exactly `Untrusted`. *(TM12.3
      `e2e` half)*
- [x] 4.9 **Prove RED** across all three runners, then **GREEN**: `TapCommand.swift` gains
      `.trustTap` / `.untrustTap`, the `trust(_:)` / `untrust(_:)` factories, and their `arguments`,
      `verb`, `packageID`, `requiresConfirmation` and `invalidates` arms — design §2 verbatim, every
      argv a literal verb plus `tap.rawValue`.
- [x] 4.10 **GREEN.** `TapDetailView.swift`: `Button("Trust")` inline in the header and
      `Button("Untrust")`, both string-literal form (DD-13 — `Button {` is banned at `:197`), gated on
      `TapTrustPresentation.canGrant` / `.canRevoke`. `ContentView.swift`: the two submission closures
      in the shipped `forceEvidence(for:)` `@MainActor` idiom (:538-551).
- [x] 4.11 All three runners green; **`MutationCommandTests:289` (unit 12) must still be green** —
      it is a regression guard that never goes red. Commit WU4.

## Phase 5: WU5 — revoke before removing, without downgrading a disclosure (TM7.2, .3; TM8.2; TM9.3; TM13.4; PM1.7–.10)

Runner: `swift test --package-path Packages/CellarCore --filter 'ConfirmationDisclosureTests|BrewMutatingTests|TapCommandTests|MutationRefreshReceiptTests|TapIntegrationTests'`

- [x] 5.1 **RED — unit 2c.** `TapCommandTests · everyRemovalRevokesBeforeItRemoves`:
      `removal(of:) == [.untrustTap, .removeTap]` and
      `forcedRemoval(evidence:) == [.untrustTap, .forceRemoveTap]` for **all three** trust states
      (DD-5 — unconditional); argvs character-for-character as TM7/TM8 pin them; no third command;
      plain untap grows no hidden `--force`. **RED because** the factories do not exist.
      *(TM7.1, TM7.2)*
- [x] 5.2 **RED — unit 8, with the four guard updates in the same commit.**
      `ConfirmationDisclosureTests · aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap`:
      `[.untrustTap, .forceRemoveTap]` → `.forceUntap`; `[.untrustTap, .removeTap]` raises **no**
      request; an erased install-only batch → `.packageRemoval`; an erased mixed tap+install batch →
      `.tapAdd`. Guards, exactly as design §3 tabulates — (a) `:216`
      `"disclosure: first.disclosure"` → `"disclosure: commands.leadDisclosure"`; (b) `:223` keeps its
      assertion and gains the sibling
      `#expect(spine.code.contains("var declaredDisclosure: ConfirmationDisclosure? { get }"))`;
      (c) `:225` keeps its assertion and gains
      `#expect(spine.code.contains("public let declaredDisclosure: ConfirmationDisclosure?"))`;
      (d) `BrewMutatingTests.swift:263` `var disclosure` → `var declaredDisclosure` on
      `DisclosingProbe`, with `:279` and `:292` following. **`:161-178` and `:203` are NOT touched and
      MUST stay green** — `declaredDisclosure ?? .packageRemoval` does not contain the banned
      substring `?.disclosure ??` (capital `D`), and `:231-240`'s `divergent.count == 7` is unchanged.
      *(TM8.2, PM1.7, PM1.8, PM1.9)*
- [x] 5.3 **RED — unit 8b.** `ConfirmationDisclosureTests ·
      skippingPicksTheFirstDeclaringCommandNotTheStrongest`: `[untrust, addTap, forceRemoveTap]` →
      `.tapAdd`, **not** `.forceUntap` — submission order, never severity. *(PM1.10, BF7.3)*
- [x] 5.4 **RED — unit 13b.** `MutationRefreshReceiptTests ·
      anUntapActionsInventoryRefreshComesFromItsRevocation`: an untap action refreshes installed
      inventory exactly once, attributable to the revocation, while `removeTap.invalidates` still
      excludes it. *(TM9.3)*
- [x] 5.5 **RED — unit 14.** `TapIntegrationTests · aFailedRevocationDoesNotBlockTheRemoval`: the
      revocation reaches a failed terminal outcome, the removal is **still** submitted and reaches its
      own, and the failure is its own visible `ActivityItem` rather than being swallowed (DD-5).
      *(TM7.3)*
- [x] 5.6 **RED — unit 14b.** `TapIntegrationTests · anIdempotentGrantOrRevocationIsAnOrdinarySuccess`:
      exit 0 for a re-grant and for a never-trusted revocation → `.succeeded`, not a failure and not a
      defect (obs `#7722`). *(TM13.4)*
- [x] 5.7 **Prove RED** (six), then **GREEN**: `BrewMutating.swift` — add the
      `declaredDisclosure: ConfirmationDisclosure?` protocol requirement with a `nil` default,
      redefine `disclosure`'s default as `declaredDisclosure ?? .packageRemoval` (one source of
      truth), add `Collection.leadDisclosure`, and store **both** members on `AnyBrewMutation`,
      copied from the same command in its single initialiser.
- [x] 5.8 **GREEN.** `TapCommand.swift`: replace the `disclosure` override with `declaredDisclosure`
      (`nil` for `.removeTap` and `.untrustTap`), and add `removal(of:)` / `forcedRemoval(evidence:)`.
- [x] 5.9 **GREEN.** `OperationCenterBulk.swift`: `disclosure: commands.leadDisclosure` (the one
      behavioural line at `:169`), the `submitSequence(_:)` mirror of `submitBulk`, and the two new
      `ConfirmationRequest.tapIdentity` arms. `TapDetailView.swift`: Untap and Force Untap submit
      through `submitSequence`.
- [x] 5.10 Focused command green, **and `:161-178` / `:203` / `:231-240` still green**; commit WU5.

## Phase 6: WU6 — classify the refusal, offer the only safe recovery (PM10.1–.4, .6; TM13.3)

Runners: `swift test --package-path Packages/CellarCore --filter 'ClassificationTests|TapProjectionTests|MutationCommandTests'`
and `xcodebuild test … -only-testing:cellarTests/TapCompositionTests`.

- [x] 6.1 **RED — unit 6a.** `ClassificationTests · anUntrustedTapRefusalIsItsOwnOutcome`: the refusal
      prose on **stderr** with a non-zero exit → `.refusedUntrustedTap`; the same prose on **stdout** →
      `.failed`; exit 0 → `.succeeded`; **`"Refusing to load"` without `"untrusted tap"` → `.failed`**
      (DD-6 — one structural phrase, case-sensitive, so a broad match never offers a Trust button for
      a refusal trust cannot fix). *(PM10.1, PM10.2)*
- [x] 6.2 **RED — unit 6b.** `ClassificationTests · nothingIsExtractedFromTheRefusal`: the outcome
      carries no tap, package, token or command — asserted by **value equality across two refusals
      naming different taps** — the message is the spec's exact sentence, and classification read no
      more than `MutationOutcome.tailLength` lines. *(PM10.3, PM10.4)*
- [x] 6.3 **RED — unit 6c.** `TapProjectionTests ·
      theRecoveryPicksOnlyAUniquePublisherFromCellarsOwnSnapshot`: `UntrustedTapRecovery.trustableTap`
      returns the tap for exactly one untrusted publisher; `nil` for two publishers, for a trusted or
      unreported publisher, for an official tap, and for `packageID == nil`. *(PM10.4)*
- [x] 6.4 **RED — unit 10b.** `cellarTests/TapCompositionTests ·
      theRefusalRecoveryOffersTrustOnlyForAUniquePublisher`: the button appears for one publisher and
      not for zero or two; pressing it opens the ordinary **confirmed** Trust sheet and **retries
      nothing**. *(PM10.4, TM13.3)*
- [x] 6.5 **RED — unit 10c.** `MutationCommandTests · anUntrustedTapNeverPreBlocksAMutation`: a
      mutation for a package whose tap is withheld and untrusted is built and submitted normally, and
      no build path consults a trust state (obs `#7724` — a per-package grant makes a pre-launch gate
      block what brew would allow). *(PM10.6)*
- [x] 6.6 **RED — unit 2d.** `TapCommandTests · noRecoveryOrRetryPathSubmitsATrustCommand`: the refusal
      recovery and a retry of a failed mutation each submit **no** `trust` argv of their own.
      *(TM13.3)*
- [x] 6.7 **Prove RED** (six), then **GREEN**: `MutationOutcome.swift` — `case refusedUntrustedTap`
      **with no associated value**, `Signature.untrustedTap = "untrusted tap"` +
      `isUntrustedTap(_:)` in the shipped `isLock` / `isPrivilege` idiom, the `classify` arm after the
      lock and privilege checks, and the `message` / `summaryLabel` / `isFailure` arms — design §7
      verbatim, including the comment recording **why** nothing is parsed (R2).
- [x] 6.8 **GREEN.** New file
      `Packages/CellarCore/Sources/BrewClient/UntrustedTapRecovery.swift` — the one-candidate
      projection from design §7, filtering on `record.trust == .untrusted`, excluding
      `TapProjection.officialNames`, and requiring `TapProjection.publishes(package, in: record)`.
- [x] 6.9 **GREEN.** `cellar/Activity/ActivityDrawer.swift`: `Button("Trust")` shown only when the
      injected `@MainActor` closure returns a `TapName`, submitting `operations.request(.trustTap(tap))`.
      `cellar/ContentView.swift`: the `trustableTap(for:)` closure in the `currentForceEvidence` idiom.
- [x] 6.10 Both runners green; commit WU6.

## Phase 7: WU7 — D3, the bare token and the argv prohibition (PM10.5; BF5.6; BF7.3)

Runner: `swift test --package-path Packages/CellarCore --filter 'MutationCommandTests|BrewfilePlanTests|BrewfileEntryTests'`

- [x] 7.1 **RED — unit 7.** `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken`: over
      every `MutationCommand` factory and `naming(_:)` build, every `TapCommand` case, and every
      command a `BrewfilePlan` built from a qualified-name fixture emits — **no `MutationCommand` argv
      element contains `/`**, and no argv element of any family contains two or more `/`. Positively
      anchored: the fixture set is asserted non-empty, `TapCommand.addTap` really does produce exactly
      one `/`, and the qualified Brewfile entry really does produce `install --formula thing`. A
      vacuous version of this test is worse than none. *(PM10.5)*
- [x] 7.2 **RED — unit 7b.** `BrewfilePlanTests · aQualifiedEntryInstallsTheBareToken`:
      `brew "acme/tap/thing"` → `["install","--formula","thing"]`; `cask "acme/tap/app"` →
      `["install","--cask","app"]`; the entry still parses with **no skip counted**; a degenerate
      `acme/tap/` produces **no** command and is not presented as applied. *(BF5.6, BF5.5)*
- [x] 7.3 **RED — unit 7c.** `BrewfileEntryTests · qualifiedNamesStillConstructAndProjectABareTarget`:
      `FormulaID(name: "acme/tap/thing")` **still** succeeds — `BrewfileEntryTests.swift:80-87` stays
      green — while `installTarget?.name == "thing"`. **DD-8: no `/` gate is added to
      `PackageTarget.init?` or `MutationName.isSafe`; both stay byte-identical.** *(BF5.6)*
- [x] 7.4 **Prove RED** (three), then **GREEN**: `BrewfileEntry.swift` — `installTarget`,
      `installName` and `bareToken(_:)` (splitting with `omittingEmptySubsequences: false` so
      `acme/tap/` yields `""`, which does not construct, instead of installing the wrong package), and
      correct `displayName`'s now-false doc comment in the same commit.
- [x] 7.5 **GREEN.** `BrewfilePlan.swift` :34-43 — the install arm builds from `entry.installTarget`;
      an entry with no constructible bare token produces no command. The Brewfile import row shows
      `installName` as its title and the file's qualified token as secondary detail when they differ.
- [x] 7.6 Focused command green; **`MutationCommandTests:289` still green**; commit WU7.

## Phase 8: Verification and bindings

- [x] 8.1 Full core suite: `swift test --package-path Packages/CellarCore` → the Phase 0 baseline
      (**1754 / 209 suites / 1 known issue**) **plus** every new case, **0 failures**. Assert counts,
      never a bare success line.
- [x] 8.2 App target: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`
      → the Phase 0 baseline (**238 / 0**) plus the new composition cases, 0 failures.
- [x] 8.3 `xcodebuild test … -only-testing:cellarUITests/TapTrustUITests` → green (unit 11).
- [x] 8.4 **Bindings proof.**
      `git diff --stat main -- scripts/ .github/workflows/ Packages/CellarCore/Sources/Catalog Packages/CellarCore/Sources/BrewProcess Packages/CellarCore/Sources/BrewClient/TapPayloadSource.swift Packages/CellarCore/Sources/BrewClient/MutationCommand.swift cellar.xcodeproj/project.pbxproj`
      → **empty output**. `MutationCommand.swift` is a **new** binding under DD-8; any line there means
      a `/` gate was added and D3 was violated. `BrewfilePlan.swift` is **no longer** bound to zero.
      A deviation is reported before merge, never absorbed.
- [x] 8.5 `git diff --stat main` for the whole branch — record the authored total and compare it with
      the forecast (**2,885–3,567**). A large miss is information for the next forecast, not a failure.
- [x] 8.6 Confirm the regression guards that must never have moved: `ConfirmationDisclosureTests`
      `:161-178` and `:203`, `BrewMutatingTests:231-240`, `MutationCommandTests:289`,
      `TapShippingProofTests:197`. Confirm `rg '\.tapTrust\('` is still zero (task 2.5's rule).
- [x] 8.7 Open the PR from `feat/m7-tap-trust`: title
      `feat(taps): make tap trust visible, explicit and revocable`, exactly one `type:feature` label,
      and a body that states up front (a) **reverting Cellar does not revoke a grant already written
      to `~/.homebrew/trust.json`** — `brew untrust <tap>` in Terminal remains the exit; and (b) **R5**
      — on a Homebrew with no `untrust` verb every untap shows a visibly failed `untrust` beside a
      succeeding `untap`, which is TM7's deliberate choice, not a defect.

## Phase 9: `manual-evidence` (maintainer's Mac, Homebrew 6.0.18 — not merge blockers, not test tasks)

> **BINDING — never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (obs `#7724`).
> Use `brew upgrade --cask --dry-run <token>`, or the installed Home-Cellar, which declares
> `auto_updates`. This applies to **every** step below, including any retry.

Each transcript is captured **verbatim into the verify report** — the artifact that carries evidence
in this repository (spec amendment #7; a design written before execution cannot contain it).

- [ ] 9.1 **ME1 — TM13.5.** `brew tap juancasanueva/cellar` → Cellar shows **Untrusted** → in-app
      **Trust** → the sheet shows `.tapTrustGrant`'s exact text → `brew trust --json v1` lists the tap
      → the badge flips with **no manual reload**. Capture `brew trust --json v1` before and after.
- [ ] 9.2 **ME2 — PM10.8.** A bare-token upgrade (`--dry-run`) of a package from an untrusted tap,
      launched **from inside Cellar**, renders `.refusedUntrustedTap` with brew's own `brew trust …`
      line visible in the untruncated log, and the recovery **Trust** button opens the ordinary
      confirmation.
- [ ] 9.3 **ME3 — TM13.6.** **Untap** a trusted tap from Cellar → `brew trust --json v1` no longer
      lists it → re-tap it → it comes back untrusted. This is the whole stale-grant fix (R3).
- [ ] 9.4 **ME5 — PM10.7, blocking a claim rather than the merge.** Capture the **formula** refusal
      stderr verbatim (R6 — only the cask wording was ever measured). **The classifier MUST NOT be
      described as covering formulae until this transcript exists.** If the wording lacks
      `"untrusted tap"`, that is a `.failed` degradation with the verbatim log, and widening the
      phrase needs no design change.
- [ ] 9.5 **Supporting evidence (not a spec scenario).** With the tap untrusted, an installed package
      from it reads *"Installed. Homebrew withholds its tap while this tap is untrusted."* and **Show
      in Installed** still lands on the right record.
- [ ] 9.6 Record that **Homebrew < 6 degradation is not reproducible here**; it is covered by unit 1's
      `.unreported` decode plus unit 9b, and documented as a limitation (R5).

## Phase 10: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [x] 10.1 **No `## Verification classes` table exists** in any of the four target specs, so — unlike
      the `m6-sparkle-updates` / `m6-cask-tap` precedent — **there is no class table to hand-update**.
      This change is the first to annotate these specs with inline `- Verification:` lines; untouched
      requirements deliberately keep none.
- [x] 10.2 `tap-management` provenance arithmetic: the main spec records `m3-taps` as 11 requirements /
      **33** scenarios while the file carries **34** `#### Scenario:` headings. Count the headings,
      then correct provenance in the same archive edit.
- [x] 10.3 Record the deviation the tap-management delta declares: the proposal budgeted **one** ADDED
      requirement and the delta writes **two** (TM12, TM13); resulting counts assume both. Record D1,
      D2 and D3 with what each rejected, and the deferred follow-ups (per-package trust surface, a
      trust column in the Brewfile diff, trust for official taps, and **R15** — a qualified Brewfile
      entry keeps its qualified identity for diffing).
