```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:05d2c0fc91310aabbe3b762bfa157aabf3f9b2533e398c516c119921d82155d1
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 14/14
scenarios: 89/89
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:9c0f9779cf8c74b325679fdb365a686973c2eef30976ea83a64b4d5d871ac6ff
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
build_exit_code: 0
build_output_hash: sha256:ee58d485be9655e466baaac9f1d759bce3ceb6d581c5e06bf6cf6fc98eb2e733
```

## Verification Report

**Change**: `m7-tap-trust`
**Version**: four capability deltas — `tap-management` (6 MODIFIED / 2 ADDED), `package-mutation`
(2 MODIFIED / 1 ADDED), `brewfile-management` (2 MODIFIED), `installed-inventory` (1 MODIFIED) —
**14 requirement blocks / 89 scenarios** (40 / 30 / 11 / 8)
**Mode**: Strict TDD
**Branch**: `feat/m7-tap-trust` @ `3307241` · base `main` `349a47f` · 10 commits, unpushed, no PR
**Verifier**: independent — no product file, test or doc was edited; only this report and no task
checkbox needed reconciliation. No review started, no receipt created, nothing committed or pushed.
RDD disabled.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr` with
**`size:exception` recorded** (maintainer, 2026-08-23), `review_budget_lines=5000`, `strict_tdd=true`.

### What the envelope counts mean

`requirements: 14/14` and `scenarios: 89/89` mean **every scenario is discharged at the verification
class the spec itself declares for it** — *not* that every scenario has been executed. This is the
house convention set by `2026-08-23-m6-release-pipeline`'s `29/29` and followed by
`2026-08-23-m6-cask-tap`, both of which likewise counted `manual-evidence` scenarios as
documented-but-not-yet-transcribed. The envelope contract requires a passing verdict to carry complete
counts, so the honest split is stated here rather than hidden in the denominators:

| Class | Count | What "discharged" means here | Result |
|---|---|---|---|
| `unit` / `e2e` | **85** | a covering test passed at runtime in one of the three runners | **85/85 runtime-proven; RED independently re-proven for WU1, WU5, WU6, WU7** |
| `manual-evidence` | **4** | the spec declares no harness can exist; the scenario is specified and its acceptance criteria are pinned | **4/4 specified — 0/4 transcribed. Phase 9 is PENDING by maintainer decision** |

**Read plainly: TM13.5, TM13.6, PM10.7 and PM10.8 have no maintainer transcript yet.** They are not
merge blockers and not a test gap — the specs themselves declare no harness can exist for them — but
nothing in this report should be read as evidence that a real `brew` grant, revocation or refusal was
observed. What discharges each is enumerated in *Phase 9* below.

---

### Build / test evidence — all three runners, re-run by this phase at `3307241`

| Runner | Verbatim summary | Exit |
|---|---|---|
| `swift test --package-path Packages/CellarCore` | `Test run with 1785 tests in 209 suites passed after 16.682 seconds with 1 known issue.` | 0 |
| `xcodebuild test … -only-testing:cellarTests` | **242** `' passed on '` lines, **0** `' failed on '`, `** TEST SUCCEEDED **` | 0 |
| `xcodebuild test … -only-testing:cellarUITests/TapTrustUITests` | `Test case 'TapTrustUITests.testTheTrustControlAppearsOnlyForAnUntrustedTap()' passed on 'My Mac - cellarUITests-Runner (20926)' (13.340 seconds)` · `Executed 1 test, with 0 failures (0 unexpected)` · `** TEST SUCCEEDED **` | 0 |

All three match the expected baselines exactly (1785 / 209 / 1 known issue; 242 / 0; 1 / 0). The
`xcresult` device configuration independently reports `passedTests: 242, failedTests: 0,
skippedTests: 0, expectedFailures: 0` over 232 unique test-case nodes — the 10-node difference is
Swift Testing parameterized cases counted individually by the runner, not a discrepancy.

**The one known issue is pre-existing and unchanged**: `OperationCenterCancelTests ·
theHarnessReportsAMissingProcess`, `withKnownIssue("nothing was submitted, so call 0 never launches")`
(`OperationCenterCancelTests.swift:182`). It is the same single known issue the Phase 0 baseline
recorded at `349a47f` (1754 tests / 1 known issue). Net **+31** core tests, **+4** app-target tests,
**209 suites unchanged**, **0 failures**.

UI-test log hash: `sha256:2f71cedd8036f7012b3e2535bbaa6374970818bda8e58be46888e8f1aa70078d`.

---

### TDD Compliance — RED re-proven independently, not read from the report

Every work unit is a **single commit carrying tests and production together**, so RED was
reconstructed rather than checked out: a detached worktree at
`/Users/juancasanueva/programming/swiftUI/cellar-worktrees/verify-red` was set to each WU's **parent**,
and only that WU's **test files** were checked out over it. Four units were re-proven — the four the
launch brief named — and each failed for the reason `apply-progress` recorded, verbatim.

| WU | Parent | RED reconstruction result | Matches recorded reason |
|---|---|---|---|
| **WU1** `a842d5e` | `66941fa` | `TapDecodeTests.swift:86:36: error: value of type 'TapRecord' has no member 'trust'`; with all three test files: `TapProjectionTests.swift:192:35: error: cannot find type 'TapTrustState' in scope`, `:154:39: error: type 'TapProjection' has no member 'trust'` | ✅ units 1, 4a, 4e |
| **WU5** `583ba8d` | `7665d9d` | `TapCommandTests.swift:209:47: error: type 'TapCommand' has no member 'removal'`; `:210:46: … no member 'forcedRemoval'`; `:245:64: error: value of type 'TapCommand' has no member 'declaredDisclosure'` | ✅ units 2c, 8 |
| **WU6** `d78d8b1` | `583ba8d` | `ClassificationTests.swift:386:74: error: type 'MutationOutcome' has no member 'refusedUntrustedTap'`; `TapProjectionTests.swift:321:13: error: cannot find 'UntrustedTapRecovery' in scope`; `:407:31: error: type 'TapProjection' has no member 'publishes'` | ✅ units 6a, 6c, 10c (and **D-3**) |
| **WU7** `0d13513` | `d78d8b1` | **runtime**, not a compile error: `Test "No package position anywhere ever carries a qualified token" recorded an issue at MutationCommandTests.swift:570:9: Expectation failed: (qualified.installs.first?.arguments → ["install", "--formula", "acme/tap/thing"]) == ["install", "--formula", "thing"]`, plus `:576:17 (element.contains("/") → true) == false` ×2 and `:588:17 (element.filter { $0 == "/" }.count → 2) <= 1` ×2 — `Test run with 21 tests in 1 suite failed after 0.004 seconds with 5 issues.` Separately `BrewfileEntryTests.swift:232:25: error: value of type 'BrewfileEntry' has no member 'installTarget'` | ✅ unit 7 byte-for-byte, units 7b/7c |

WU7's reconstruction is the strongest single result in this verification: **unit 7 — the D1 absence
assertion — genuinely caught the real defect at runtime**, reproducing `apply-progress`'s recorded
failure string character for character. It is not a test that could only ever pass.

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | 33-row *TDD cycle evidence* table in `apply-progress.md:46-81` |
| All units have tests | ✅ | 33/33 named test functions exist on disk |
| RED confirmed | ✅ | 4/4 re-proven by reconstruction (WU1, WU5, WU6, WU7); the other 3 accepted on the report |
| GREEN confirmed | ✅ | every named test passed in this phase's three runs |
| Triangulation | ✅ | 29 units triangulated, 4 marked `➖` single-case and correctly so |
| Safety net | ✅ | every unit records the prior full-suite count (1754 → 1782, 238 → 241) |

---

### Spec compliance matrix

#### `tap-management` — 40 scenarios (38 `unit`, 2 `manual-evidence`)

| Scenario | Covering test | Status |
|---|---|---|
| TM5.1 selected prefix only · .2 qualified cask token · .3 equal tokens distinct · .4 exact tap controls handoff · .8 never catalog records · .9 large inventory narrows | `TapProjectionTests`, `TapIntegrationTests` *shipped* | ✅ PASS ×6 |
| TM5.5 withheld + untrusted reads installed | `TapProjectionTests · aWithheldTapIsInstalledNotMissing` | ✅ PASS |
| TM5.6 withheld not claimed by a non-publisher | `TapProjectionTests · aWithheldTapIsNotClaimedByATapThatDoesNotPublishIt` | ✅ PASS |
| TM5.7 withheld under trusted/unreported still "Not installed." | `TapProjectionTests · aWithheldTapUnderATrustedOrUnreportedTapIsStillNotInstalled` | ✅ PASS |
| TM6.1 canonical argv · .2 hostile targets · .5 presentation cannot rewrite execution | `TapCommandTests` *shipped* | ✅ PASS ×3 |
| TM6.3 every add discloses what add does/does not do | `ConfirmationDisclosureTests · theAddDisclosureClaimsNoGrantAndTheGrantDisclosureClaimsOne` | ✅ PASS |
| TM6.4 adding a tap grants no trust | `cellarTests/TapCompositionTests · noPathGrantsTrustWithoutAnExplicitAnswer` | ✅ PASS |
| TM7.1 no hidden force flag · .2 untap revokes before it removes (3 states) | `TapCommandTests · everyRemovalRevokesBeforeItRemoves` | ✅ PASS ×2 |
| TM7.3 failed revocation does not block removal | `TapIntegrationTests · aFailedRevocationDoesNotBlockTheRemoval` | ✅ PASS |
| TM7.4 empty cross-reference hides force · .5 untrustworthy inventory cannot enable force | `TapShippingProofTests` *shipped* + DD-14 | ✅ PASS ×2 |
| TM8.1 disclosure names every kind-qualified package | `ConfirmationDisclosureTests` *shipped* | ✅ PASS |
| TM8.2 revoke-first force batch still shows force disclosure | `ConfirmationDisclosureTests · aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap` | ✅ PASS |
| TM8.3 additions/removals invalidate · .4 kind change invalidates · .5 ordering alone does not | `ForceDenialRecoveryTests` *shipped* | ✅ PASS ×3 |
| TM9.1 tap mutations serialize | `TapIntegrationTests` *shipped* | ✅ PASS |
| TM9.2 five commands × four terminals | `MutationRefreshReceiptTests · everyTapTerminalRefreshesItsDeclaredDomainsExactlyOnce` | ✅ PASS |
| TM9.3 untap's inventory refresh comes from its revocation | `MutationRefreshReceiptTests · anUntapActionsInventoryRefreshComesFromItsRevocation` | ✅ PASS |
| TM11.1 enumerated actions stay within scope (8) | `TapShippingProofTests · completeActionSurfaceIsBounded` | ✅ PASS |
| TM11.2 reported state and grant, never a verdict | `TapShippingProofTests · trustIsAReportedStateAndAGrantNeverAVerdict` | ✅ PASS |
| TM12.1 three states incl. `null` and absent | `TapDecodeTests · tapTrustIsThreeValuedAndAbsenceIsNotFalse` | ✅ PASS |
| TM12.2 unreported shows nothing, controls spawn nothing | `TapShippingProofTests · anUnreportedTapOffersNoControlAndSpawnsNothing` | ✅ PASS |
| TM12.3 badge and controls follow the state | `TapProjectionTests · unreportedTrustShowsNoBadgeAndNoControl` + `cellarUITests/TapTrustUITests` (`e2e` half) | ✅ PASS |
| TM12.4 list row and detail header read one projection | `TapShippingProofTests · listRowAndDetailHeaderReadOneTrustProjection` | ✅ PASS |
| TM12.5 trust copy is about the tap | `TapProjectionTests · everyTrustStringIsScopedToTheTap` | ✅ PASS |
| TM13.1 trust/untrust exact argv | `TapCommandTests · trustAndUntrustLowerToLiteralArgv` | ✅ PASS |
| TM13.2 grant confirmed, revocation not | `TapCommandTests · onlyTheGrantIsConfirmedAndBothInvalidateInstalledInventory` + `TapCompositionTests` | ✅ PASS |
| TM13.3 no path grants trust implicitly | `TapCommandTests · noRecoveryOrRetryPathSubmitsATrustCommand` + `TapCompositionTests` | ✅ PASS |
| TM13.4 idempotent grant/revocation is ordinary success | `TapIntegrationTests · anIdempotentGrantOrRevocationIsAnOrdinarySuccess` | ✅ PASS |
| **TM13.5 real grant round trip flips the badge** | manual evidence 1 | ⏸ **PENDING** |
| **TM13.6 untapping a trusted tap leaves no grant** | manual evidence 3 | ⏸ **PENDING** |

#### `package-mutation` — 30 scenarios (28 `unit`, 2 `manual-evidence`)

| Scenario | Covering test | Status |
|---|---|---|
| PM1.1–.5 kind flags · .6 another family enters the spine | `MutationCommandTests`, `BrewMutatingTests` *shipped* | ✅ PASS ×6 |
| PM1.7 erased mixed batch discloses the tap add · .8 erased install-only discloses package removal · .9 batch led by a non-declaring command | `ConfirmationDisclosureTests · aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap` | ✅ PASS ×3 |
| PM1.10 skipping picks the first declaring, not the strongest | `ConfirmationDisclosureTests · skippingPicksTheFirstDeclaringCommandNotTheStrongest` | ✅ PASS |
| PM1.11 no disclosure recovered by a type test | `ConfirmationDisclosureTests` `?.disclosure ??` / `verb ==` bans (`:355`) | ✅ PASS |
| PM3.1–.6 uninstall/zap/bulk gate | `ConfirmationDisclosureTests` *shipped* ×6 | ✅ PASS ×6 |
| PM3.7 every tap add carries its typed add disclosure · .8 every trust grant confirmed with its disclosure · .9 untrust passes without confirmation | units 3, 2b, 10 | ✅ PASS ×3 |
| PM3.10 force untap carries complete package disclosure · .11 stale disclosure cannot become argv | `ConfirmationDisclosureTests`, `ForceDenialRecoveryTests` *shipped* | ✅ PASS ×2 |
| PM10.1 stderr refusal is the typed outcome · .2 stdout / success / no-tap-phrase does not classify | `ClassificationTests · anUntrustedTapRefusalIsItsOwnOutcome` | ✅ PASS ×2 |
| PM10.3 nothing is extracted | `ClassificationTests · nothingIsExtractedFromTheRefusal` | ✅ PASS |
| PM10.4 offers Trust, worded about the tap | `nothingIsExtractedFromTheRefusal` + `theRecoveryPicksOnlyAUniquePublisherFromCellarsOwnSnapshot` + `TapCompositionTests · theRefusalRecoveryOffersTrustOnlyForAUniquePublisher` | ✅ PASS |
| PM10.5 no argv anywhere carries a qualified token | `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken` + `BrewfilePlanTests · aQualifiedEntryInstallsTheBareToken` | ⚠️ **PASS with W1** — non-vacuity clause partially met |
| PM10.6 an untrusted tap never pre-blocks a mutation | `MutationCommandTests · anUntrustedTapNeverPreBlocksAMutation` | ✅ PASS |
| **PM10.7 formula refusal wording captured first** | manual evidence 5 | ⏸ **PENDING** (gate **HELD**, see below) |
| **PM10.8 a real refusal renders the typed outcome** | manual evidence 2 | ⏸ **PENDING** |

#### `brewfile-management` — 11 scenarios (all `unit`)

| Scenario | Covering test | Status |
|---|---|---|
| BF5.1 a trusted tap still raises the tap-add disclosure · .3 an import submits no trust command | `cellarTests/BrewfileCompositionTests · anImportCarryingTrustClaimsSubmitsNoGrant` | ✅ PASS ×2 |
| BF5.2 `trusted:` never becomes argv | `BrewfileArgvStructureTests` *shipped* | ✅ PASS |
| BF5.4 the claim is surfaced, attributed to the file · .5 `trusted:` on brew/cask parses, confers nothing | `BrewfileParserTests` *shipped* + unit 7b | ✅ PASS ×2 |
| BF5.6 a qualified package entry installs the bare token | `BrewfilePlanTests · aQualifiedEntryInstallsTheBareToken` + `BrewfileEntryTests · qualifiedNamesStillConstructAndProjectABareTarget` | ✅ PASS |
| BF7.1 mixed selection fans out, taps first · .2 only selected entries submitted · .4 empty selection submits nothing | `BrewfilePlanTests` *shipped* | ✅ PASS ×3 |
| BF7.3 one confirmation covers the batch, tap selected last | unit 8 + `BrewfilePlanTests` *shipped* | ✅ PASS |
| BF7.5 a mid-batch failure attributes to one entry | `BrewfileStoreTests` *shipped* | ✅ PASS |

#### `installed-inventory` — 8 scenarios (all `unit`)

| Scenario | Covering test | Status |
|---|---|---|
| II2.1–.5 keg / cask / auto-update / linked shapes | `InstalledDecodeTests` *shipped* ×5 | ✅ PASS ×5 |
| II2.6 withheld tap decodes as absent, not empty · .7 record still enters the inventory | `InstalledDecodeTests · aNullTapIsAbsentNotEmpty` | ✅ PASS ×2 |
| II2.8 an absent tap never matches a selected tap | `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` | ✅ PASS (see S1) |

**Every `shipped` coverage claim was checked**: all twelve named test files exist on disk
(`BrewfileArgvStructureTests`, `BrewfileParserTests`, `ForceDenialRecoveryTests`, `BrewfileStoreTests`,
`TapIntegrationTests`, `TapProjectionTests`, `TapCommandTests`, `ConfirmationDisclosureTests`,
`InstalledDecodeTests`, `BrewMutatingTests`, `BrewfilePlanTests`, `TapShippingProofTests`) and all
passed in this phase's runs.

---

### Binding decisions — verified against source, not against the report

#### D1 — Homebrew's tap/trust split is kept

| Rule | Evidence | Result |
|---|---|---|
| No `/`-qualified package token in any argv Cellar builds | `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken` re-proven RED then GREEN; `TapCommand.arguments` (`TapCommand.swift:112-120`) is five literal-verb + `tap.rawValue` arms; `MutationCommand.swift` **byte-identical to `main`** | ✅ (W1 on breadth) |
| Untap = `[untrust, untap]` | `TapCommand.removal(of:)` `TapCommand.swift:191-194` returns `[.untrustTap(tap), .removeTap(tap)]`; `forcedRemoval` `:197-200` returns `[.untrustTap, forced]` — both unconditional, no trust-state branch | ✅ |
| Trust confirmed, untrust not | `requiresConfirmation` `TapCommand.swift:137-144`: `.addTap, .trustTap, .forceRemoveTap` → `true`; `.removeTap, .untrustTap` → `false` | ✅ |
| Refusal outcome carries no payload | `MutationOutcome.swift:71` `case refusedUntrustedTap` — **no associated value**; classification `:110-119` reads stderr only, `suffix(tailLength)` with `tailLength = 20` (`:79`), after fault/cancel/success | ✅ |
| Recovery from snapshot, exactly-one-candidate | `UntrustedTapRecovery.swift:27-33` filters `trust == .untrusted`, excludes `officialNames`, requires `TapProjection.publishes`, then `guard candidates.count == 1` | ✅ |

#### D2 — `.tapAdd` + `.tapTrustGrant`

`ConfirmationDisclosure` (`TapCommand.swift:48-79`) carries `packageRemoval`, `tapAdd(TapName)`,
`tapTrustGrant(TapName)`, `forceUntap(tap:affected:)`. Sweep `rg '\.tapTrust\(|case tapTrust\b'` over
`cellar/` and `Packages/` → **0 hits**. `TapCommand.verb` still yields the string `"tapTrust"` for
`.trustTap`, which is why task 2.5 correctly forbade grepping the bare substring. ✅ (see W4 for stale
prose)

#### D3 — the Brewfile bare-token strip

`BrewfileEntry.installTarget` (`BrewfileEntry.swift:103-106`) projects
`PackageTarget(PackageID(kind:name: Self.bareToken(id.name)))`; `bareToken` (`:114-118`) splits with
`omittingEmptySubsequences: false`, so `acme/tap/` yields `""` which does not construct. `displayName`
(`:78-84`) keeps the file's token. The parser still accepts qualified names —
`BrewfileParser.entry` calls `FormulaID(name:)`/`CaskID(name:)` with no `/` gate, and
`BrewfileEntryTests.swift:80-87` stays green. `BrewfilePlan.init(selecting:)`
(`BrewfilePlan.swift:41-43`) builds installs from `entry.installTarget` and emits **no command** when
it is `nil`. The import row (`BrewfileImportSheet.swift:131-141`) shows `row.title` with
`"In the file as \(fileToken)"` as secondary detail. ✅

#### The five defaults — exact copy present verbatim in source

| # | Pinned copy | Site |
|---|---|---|
| 1 | “Adding \(tap) clones a third-party repository. Homebrew will not load its formulae or casks until you trust it, and Cellar does not trust it for you.” | `TapCommand.swift:63-68` |
| 2 | “Trusting \(tap) lets Homebrew load and run its formulae and casks. That is third-party code running as you, with your permissions.” | `TapCommand.swift:69-74` |
| 3 | “Installed. Homebrew withholds its tap while this tap is untrusted.” | `TapProjection.swift:55` |
| 4 | “Not installed.” | `TapProjection.swift:56` |
| 5 | “Homebrew refused to load this package because its tap is not trusted. Trust the tap in Taps, then try again.” | `MutationOutcome.swift:236-239` |
| + | badge “Untrusted” (exact, **not** uppercased) | `TapProjection.swift:124`; `TapTrustBadge` (`TapDetailView.swift:305-313`) renders `Text(text)` with no `.textCase` |

All five (and the badge) match their spec text character for character. Strings 2 and 5 use Swift
`\`-continuations, which join without inserting whitespace or newlines. ✅

---

### Guards, bindings and invalidation

| Guard | Expected | Observed | Result |
|---|---|---|---|
| `ConfirmationDisclosureTests` protocol-default proof (`main:161-178`) | unchanged and green | body byte-identical to `main` **except** the two D2 rename lines (`main:176-177` `.tapTrust` → `.tapAdd`), which design §3 tabulated as a rename site | ✅ as designed |
| `ConfirmationDisclosureTests` `?.disclosure ??` ban (`main:203`) | unchanged and green | present at `:355`, plus the sibling `verb ==` ban | ✅ untouched |
| `:216` positive half | `first.disclosure` → `commands.leadDisclosure` | updated as designed | ✅ |
| `:223` / `:225` spine assertions | gain `declaredDisclosure` siblings | present | ✅ |
| `BrewMutatingTests:263` `DisclosingProbe` | `var disclosure` → `var declaredDisclosure` | `:257` struct, `:267` `var declaredDisclosure: ConfirmationDisclosure? = .packageRemoval` | ✅ |
| `BrewMutatingTests` `divergent.count == 7` | unchanged | `:240` unchanged | ✅ |
| `TapShippingProofTests` pinned labels | `["Add Tap","Untap","Force Untap","Show in Installed","Trust","Untrust"]` | `:376-377`, exact set equality | ✅ |
| `TapShippingProofTests` `Button {` ban | intact | `:379` | ✅ |
| `TapManagementAction.allCases` | 8, in TM11 order | `:94-97` `["refresh","filter","Installed handoff","canonical add","plain untap","eligible force untap","trust","untrust"]` | ✅ |
| `MutationCommandTests:289` regression guard | still green | `everyCommandFamilyBuildsArgvStructurally`, with `files.isEmpty == false` anchor | ✅ |

**Conformer table (design §3, eight conformances).** Only `TapCommand` overrides `declaredDisclosure`;
`MutationCommand`, `ServiceCommand`, `CleanupCommand`, `TerminalCleanupProbe` and `ProbeMutation` take
the protocol `nil` default; `AnyBrewMutation` stores it (`BrewMutating.swift:201`, copied at `:212`);
`DisclosingProbe` stores a `var`. `disclosure`'s default is `declaredDisclosure ?? .packageRemoval`
(`:129`) — one source of truth, defaulted **in the protocol**, never by a caller. `leadDisclosure`
(`:230-233`) returns the first *declaring* command in submission order, else `.packageRemoval`. ✅

**Bindings proof.** `git diff --stat main...HEAD --` over
`Packages/CellarCore/Sources/BrewClient/MutationCommand.swift`, `scripts`, `.github`,
`Packages/CellarCore/Sources/Catalog`, `cellar.xcodeproj/project.pbxproj` → **empty**. DD-8 held; no
`/` gate was added to `MutationName.isSafe` or `PackageTarget.init?`. ✅

**Invalidation scopes (TM9).** `TapCommand.invalidates` (`:150-156`): `.addTap, .removeTap` → `.taps`;
`.trustTap, .untrustTap` → `[.taps, .installedInventory]`; `.forceRemoveTap` →
`[.taps, .installedInventory, .diskUsage]` (`.diskUsage` is shipped and unrelated). The TM9 test
(`MutationRefreshReceiptTests.swift:180-216`) is parameterized over four terminals, positively anchored
(`commands.count == 5`, `filter(\.refreshesInventory).count == 3`), asserts `counts.taps == 1` for
every command × terminal, `counts.installed == (refreshesInventory ? 1 : 0)`, and
`invalidates.isDisjoint(with: .services)`. Catalog is never reached. ✅ Exactly TM9.2.

---

### Assertion quality audit

**No tautologies, no orphan-empty assertions, no ghost loops, no smoke-only tests.** Every absence
assertion in this change is positively anchored before its negative loop:

- **unit 7** (`MutationCommandTests.swift:560-566`) anchors `mutations.count >= 11`,
  `tapCommands.count == 5`, `qualified.installs.isEmpty == false`,
  `qualified.taps.map(\.arguments) == [["tap","acme/tap"]]`, `TapCommand.addTap` still produces the one
  legitimate slash, and `qualified.installs.first?.arguments == ["install","--formula","thing"]` — then
  loops. Independently proven able to fail (RED reconstruction above).
- **unit 5b** asserts both the negative (`withheld.tap == nil`, matches neither `"acme/tools"` nor
  `""`) **and** the positive (`namedRow.installedHandoff == PackageID(…"named")`,
  `affected == [named]`, `core.tap == "homebrew/core"`).
- **source-scanning tests** (9c, 9d, 5b's app half, unit 12) use hardcoded file lists with
  `String(contentsOf:)`, which **throws** on a missing file, so none can pass vacuously;
  `staticButtonLabels` asserts exact non-empty set equality.
- **unit 6b** proves "nothing is extracted" by **value equality across two refusals naming different
  taps** (`ClassificationTests.swift:428` uses `stranger/other`) — a structurally stronger check than
  substring absence.

**Assertion quality**: ✅ 0 CRITICAL, 0 WARNING.

**PM10.7's gate is HELD.** No test, source comment or document asserts the classifier covers the
**formula** refusal. Every fixture in `ClassificationTests` is the measured **cask** wording
(`:371`, `:428`), and the negative fixture `"Error: Refusing to load cask acme/tools/widget from a
directory that is not a tap."` (`:399`) pins the "refuses to load but names no untrusted tap →
`.failed`" branch. `MutationOutcome.swift:146-156` describes `"untrusted tap"` as a substring of the
measured cask refusal "and of any plausible formula wording" — a stated prediction, not a coverage
claim. Nothing must be walked back when the transcript arrives.

---

### Deviations D-1 … D-7, each checked against the relevant scenario

| # | Substance | Scenario check | Verdict |
|---|---|---|---|
| **D-1** | four more shipped sites asserted the old add sentence and moved with the rename | TM6.3 demands the exact new text; it is asserted at `ConfirmationDisclosureTests:196-204`. `TapCommandTests:111` re-anchored on `"clones a third-party repository"` because the new copy says "formulae **or** casks" | ✅ violates nothing |
| **D-2** | rename sweep zero over source, three hits left in this change's own artifacts | No scenario governs artifact prose; the artifacts are the instruction to perform the rename | ✅ accepted — but see **W4** |
| **D-3** | `TapProjection.publishes` moved WU3 → WU6 | Avoided shipping untested production code under `strict_tdd`. I re-proved its RED (`error: type 'TapProjection' has no member 'publishes'`) at WU6's parent | ✅ correct call |
| **D-4** | tap controls submit through `operations` directly, not a `ContentView` closure | TM12/TM13 mandate no seam; DD-12's closure is still used where it is required (`ContentView.trustableTap(for:)` `:549-552` for `ActivityDrawer`). Behaviour pinned by units 10 and 11, both green | ✅ violates nothing |
| **D-5** | unit 7 fixtures are the identities Cellar types, plus the Brewfile qualified path | Correctly avoids demanding a `/` gate DD-8 forbids. **But** PM10.5's non-vacuity clause says "covers every command family on the spine" | ⚠️ **W1** |
| **D-6** | `SwiftDataHistoryRecorder.classify` gained `case .refusedUntrustedTap: ("refusedUntrustedTap", nil)` | Compiler-forced exhaustiveness; `nil` status is honest (the command never ran) and matches the shipped `busy`/`launchFailed` reasoning | ✅ violates nothing |
| **D-7** | per-surface badge identifiers; badge must not be uppercased | TM12 pins the exact copy `Untrusted`. `TapTrustBadge` renders `Text(text)` with **no** `.textCase`; the `.textCase(.uppercase)` at `TapDetailView.swift:244` is on `metaRow` labels, a different element | ✅ correct fix |

---

### Task reconciliation

**72 checked, 7 unchecked, 79 total.** The unchecked set is exactly the expected one:
`8.7` (`:450`), `9.1` (`:466`), `9.2` (`:469`), `9.3` (`:473`), `9.4` (`:475`), `9.5` (`:480`),
`9.6` (`:483`). No checkbox required reconciliation: every checked task has evidence in
`apply-progress.md` and every claim I re-tested held. Task 8.7 (open the PR) is deliberately the
maintainer's, per the launch brief.

Diff arithmetic reconciles: `apply-progress` 8.5 recorded 47 files / 6,239 insertions before the two
trailing `docs(sdd)` commits; the branch now measures **48 files, 6,440 insertions, 115 deletions =
6,555 changed lines**, matching `tasks.md:89`'s recorded `size:exception` figure exactly
(3,760 SDD artifacts + 2,680 code/test insertions + 115 deletions).

### Phase 9 — pending, and exactly what discharges each

Not a merge blocker and not a test gap: the specs declare no harness can exist. **Binding, restated:
never run `brew upgrade` without `--dry-run` on the maintainer's Mac, including on any retry.**

| Scenario | Task | What discharges it |
|---|---|---|
| **TM13.5** | 9.1 | `brew tap juancasanueva/cellar`; Cellar shows **Untrusted**; answer **Trust** in-app; the sheet shows `.tapTrustGrant`'s exact text; `brew trust --json v1` captured **before and after** and lists the tap after; the badge clears with **no manual reload** |
| **TM13.6** | 9.3 | a tap already trusted and listed by `brew trust --json v1`, untapped **from inside Cellar**; `brew trust --json v1` afterwards no longer lists it; re-tapping brings it back untrusted |
| **PM10.7** | 9.4 | the **formula** refusal stderr captured **verbatim**. Gates only the *claim* of formula coverage — no such claim exists today (gate HELD above), so nothing must be retracted. If the wording lacks `"untrusted tap"`, that is a `.failed` degradation with the verbatim log and widening needs no design change |
| **PM10.8** | 9.2 | a bare-token upgrade (`--dry-run`, or the self-updating Home-Cellar cask) of a package from an untrusted tap, launched **from inside Cellar**, renders `.refusedUntrustedTap` with brew's own `brew trust …` line visible in the **untruncated** log, and the recovery **Trust** button opens the ordinary confirmation |
| supporting | 9.5 | with the tap untrusted, an installed package from it reads “Installed. Homebrew withholds its tap while this tap is untrusted.” and **Show in Installed** lands on the right record (not a spec scenario) |
| supporting | 9.6 | record that Homebrew < 6 degradation is not reproducible here; covered by unit 1's `.unreported` decode plus unit 9b, documented as limitation R5 |

---

### Issues

**CRITICAL — 0.**

**WARNING — 5.**

- **W1 · PM10.5's non-vacuity clause is only partly met.**
  `Packages/CellarCore/Tests/BrewClientTests/MutationCommandTests.swift:520-592`.
  The scenario requires "the enumeration is non-vacuous: it covers **every command family on the
  spine**". Unit 7 enumerates `MutationCommand` (≥11 builds), `TapCommand` (all 5 cases) and every
  command a `BrewfilePlan` built from a qualified fixture emits — but **not `ServiceCommand` or
  `CleanupCommand`**, which also conform to `BrewMutating` and travel the same spine.
  `ServiceCommand.arguments` is `[services, token, target.name]` and `CleanupCommand.arguments` has a
  `.package(target)` arm, so both carry a package position built from a `PackageTarget` whose
  `MutationName.isSafe` gate permits `/`. Mitigated by unit 12's source scan over **all**
  `*Command.swift` and by neither family having an ingress a qualified token can arrive through
  (their targets come from the installed inventory and cleanup scope, never from a Brewfile) — which
  is why this is a WARNING, not a CRITICAL. **Fix**: append `ServiceCommand` and
  `CleanupCommand(scope: .package(target))` to unit 7's fixture arrays and raise the count anchors.

- **W2 · The `brewfile-management` archive note will raise a false alarm.**
  `openspec/changes/m7-tap-trust/specs/brewfile-management/spec.md:203-205` instructs: "After
  promotion, `rg 'tapTrust'` across `openspec/specs/` MUST return zero hits — a surviving one means a
  block was promoted partially." That is not true of a byte-correct promotion. Of the seven current
  hits in `openspec/specs/brewfile-management/spec.md`, five (`:231`, `:239`, `:322`, `:330`, `:353`)
  are inside the two MODIFIED blocks and are replaced, but **`:7` (file-header prose) and `:510`
  (Provenance, the D4 entry) are outside both blocks** and survive a correct whole-block replacement.
  **Fix**: `sdd-archive` must hand-edit `:7` and `:510` as separate edits, and should not read a
  surviving hit there as evidence of partial promotion.

- **W3 · A changed file is in neither the design's *File Changes* table nor the deviation list.**
  `cellar/AppTestFixtures.swift` (+15 lines) adds the `--ui-testing-m7-tap-trust` launch argument and
  the three-trust-state tap payload that makes unit 11 deterministic. The design's table
  (`design.md:622-645`) lists `cellarUITests` but not this app-target file, and `apply-progress`'s
  D-1…D-7 list does not mention it — although **D-6 set the precedent** of recording exactly this
  class of unlisted-file change. The change itself is correct and follows the shipped
  `--ui-testing-*` convention. **Fix**: record it as D-8 before archive so the durable account is
  complete.

- **W4 · Four stale `tapTrust` doc comments survive in source and tests.**
  `Packages/CellarCore/Sources/BrewClient/BrewfilePlan.swift:21`,
  `cellar/Taps/BrewfileImportSheet.swift:207`,
  `Packages/CellarCore/Tests/BrewClientTests/BrewfilePlanTests.swift:21`,
  `Packages/CellarCore/Tests/BrewClientTests/ConfirmationDisclosureTests.swift:13` — each names "the
  tapTrust disclosure/warning", a `ConfirmationDisclosure` case D2 deleted. Task 2.5's sweep patterns
  (`\.tapTrust\(`, `case tapTrust\b`) cannot match prose by design, and `apply-progress` D-2 reported
  only the three artifact hits, so these went unrecorded. No behavioural effect; a future reader is
  told a case exists that does not. (`TapDecodeTests.swift:67`'s
  `tapTrustIsThreeValuedAndAbsenceIsNotFalse` is legitimate — it names the tap's trust state.)
  **Fix**: reword the four comments to `.tapAdd`.

- **W5 · `size:exception` is recorded self-contradictorily.**
  `openspec/changes/m7-tap-trust/tasks.md:89` records "**`size:exception` — recorded by maintainer
  decision 2026-08-23 after apply**", but `tasks.md:100` still asserts `single-pr` "holds with **no
  `size:exception`**", and `apply-progress.md:6` still says "`single-pr`, no `size:exception`".
  Commit `3307241` updated only the forecast table row, not the two prose statements. PR size itself
  is **not** a finding — the exception is recorded and authoritative. **Fix**: reconcile `tasks.md:100`
  and `apply-progress.md:6` before archive so the archived record does not contradict itself.

**SUGGESTION — 2.**

- **S1 · DD-11's reader-pinning claim is slightly stronger than its test.** DD-11 states the three
  `InstalledPackage.tap` readers "are pinned by `InstalledDeriveTests ·
  everyTapReaderTreatsAbsenceAsNoMatch` rather than by the compiler". Reader 1 is genuinely pinned —
  the test calls `TapProjection.packages(for:installed:)`. Readers 2 and 3
  (`ContentView.forceEvidence`, `HomebrewUpdateNeed.isComparable`) are pinned by an **inline copy of
  their predicate** (`InstalledDeriveTests.swift:367`, `:371-374`) plus a targeted source scan banning
  `tap ?? ""` (`:377-382`). That scan is real and would catch a re-collapse, and II2.8's scenario is
  about inventory matching semantics, which the test asserts directly — so this is not a spec gap.
  Consider calling the production predicates directly if those readers are ever refactored.

- **S2 · `README.md:44` recommends a qualified token to users.** It presents
  `brew install --cask juancasanueva/cellar/home-cellar` as "the unambiguous form". Homebrew 6 reads a
  `/`-qualified package token on the command line as a **per-package trust grant** — the exact
  mechanism D3 exists to keep out of Cellar's own argv. Pre-existing, outside this branch's diff
  (README is correctly unmodified per task 2.4), and safe as a deliberate user action, but it now sits
  beside a product that treats the same token shape as a threat. Worth a follow-up note.

---

### Archive readiness — counts recomputed from the files, not trusted

Post-merge arithmetic recomputed block-by-block by matching delta requirement titles against the main
specs. **Every delta header is exactly right:**

| Capability | Main today | MODIFIED / ADDED | Replaced → new | Post-merge | Delta header claims |
|---|---|---|---|---|---|
| `tap-management` | 11 req / **34** sc | 6 / 2 | 20 → 29, +11 | **13 / 54** | 13 / 54 ✅ |
| `package-mutation` | 9 req / 48 sc | 2 / 1 | 18 → 22, +8 | **10 / 60** | 10 / 60 ✅ |
| `brewfile-management` | 9 req / 38 sc | 2 / 0 | 9 → 11 | **9 / 40** | 9 / 40 ✅ |
| `installed-inventory` | 14 req / 64 sc | 1 / 0 | 5 → 8 | **14 / 67** | 14 / 67 ✅ |

Delta scenario totals also verified: 40 / 30 / 11 / 8 = **89**, of which `unit` 38 + 28 + 11 + 8 = **85**
and `manual-evidence` 2 + 2 = **4**. Every MODIFIED block title matches a title in its main spec, so all
eleven are genuine whole-block replacements; the three ADDED titles (TM12, TM13, PM10) exist in no main
spec.

**Hand-updates `sdd-archive` must make:**

1. **No `## Verification classes` table exists in any of the four target specs** — confirmed by
   direct count (`0` occurrences in each). Unlike the `m6-sparkle-updates` / `m6-cask-tap` precedent
   there is **no class table to hand-update**. The inline `- Verification:` lines travel with the
   promoted blocks; untouched requirements deliberately keep none, and that asymmetry should be
   recorded, not "fixed".
2. **Correct the `tap-management` provenance arithmetic.** `openspec/specs/tap-management/spec.md:355`
   records `m3-taps` as "**11 requirements / 33 scenarios**"; the file carries **34**
   `#### Scenario:` headings. Independently recounted here: **34**. Pre-existing defect; correct the
   provenance entry in the same archive edit.
3. **Two out-of-block `tapTrust` edits in `brewfile-management`** — `:7` and `:510` — per **W2**.
4. Record the **two-ADDED-requirement deviation** (proposal budgeted one for `tap-management`; the
   delta writes TM12 and TM13), **D1/D2/D3** with what each rejected, the batch-disclosure resolution,
   PM1/PM3's replaced rolling `(Previously:)` notes, `installed-inventory`'s **extended** (not
   replaced) note, and the deferred follow-ups (per-package trust surface, a trust column in the
   Brewfile diff, trust for official taps, **R15**).
5. Verify `package-mutation`'s strict-superset claim **by byte-slicing the replaced ranges**, as
   `m5-brewfile` did.

---

### Final verdict

**PASS WITH WARNINGS.**

All **85** automatable scenarios are proven at runtime across three green runners at `3307241`, with
**0 failures** and the single pre-existing known issue unchanged. The three decisions that could have
turned this change into the bypass it exists to forbid — D1's argv prohibition, D2's honest disclosure
split, D3's bare-token strip — are each verified in source **and** independently shown able to fail:
unit 7's RED reconstruction reproduced `apply-progress`'s recorded runtime failure character for
character. Bindings held (`MutationCommand.swift` byte-identical), every guard is intact, and the
archive arithmetic recomputes exactly as claimed.

The five warnings are record-keeping and breadth issues, not defects in shipped behaviour. None blocks
archive; W2 in particular will actively mislead `sdd-archive` if not read first. The four
`manual-evidence` scenarios remain the maintainer's, and PM10.7's gate is held — nothing in the
codebase claims formula coverage, so no claim must be retracted when that transcript arrives.
