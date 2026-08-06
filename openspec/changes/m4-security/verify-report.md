```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:e767dd9404827c08463a7da58f30ddb3cd287fce7f45fc12aa744ec6cd4e67f4
verdict: pass
blockers: 0
critical_findings: 0
requirements: 15/15
scenarios: 28/28
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:201a6ed9c6a98f4ae1677db5d7e77cf3ff2ebe66f67a24b55674b6d3721d405f
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:9645823ddeac894cedd24128e909214e6f1e311803d22eee9892be9195a6dfb6
```

## Verification Report

**Change**: `m4-security`
**Version**: 3 spec deltas — `vulnerability-scanning` (ADDED), `artifact-integrity` (ADDED),
`local-package-metadata` (MODIFIED)
**Mode**: **Strict TDD**
**Candidate**: `feature/m4-security` @ `b0b9467`, 30 commits over `main`, worktree clean, not pushed
**Verified**: 2026-08-06, all gates re-run independently by this phase — no number below is copied
from `apply-progress.md` without being re-measured.

---

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | **113** |
| Tasks complete | **113** |
| Tasks incomplete | **0** |
| Phases | 19 (0–18) |
| Probe gates closed | 3 — U1 re-capture + U2 + U5 at Phase 2, U3 at task 14.0 |
| Manual checks executed | 10 / 10 (MV-1 … MV-10), plus MV-0 |

Counted directly from `openspec/changes/m4-security/tasks.md`: 113 `- [x]` lines, zero `- [ ]`
lines. The plan's own "108" was five short and was corrected in place at task 18.1 (Deviation 72);
the corrected denominator is what this phase counted, and it matches the file.

---

### Build & Tests Execution

**Build**: ✅ Passed

```text
xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
** BUILD SUCCEEDED **   exit 0
concurrency / Sendable warnings: 0
```

**Tests**: ✅ all green across three harnesses, zero failures anywhere

| Gate | Command | Measured | Exit |
|---|---|---|---|
| CellarCore | `swift test --package-path Packages/CellarCore` | **1090 tests in 152 suites passed**, 1 known issue (pre-existing), 0 failures | 0 |
| App target | `xcodebuild test … cellarTests` | **32 cases in 5 suites**, 0 failures | 0 |
| UI target | `xcodebuild test … cellarUITests` | **20 executed, 0 failures**, incl. both `SecurityIdentityUITests` | 0 |
| Build | `xcodebuild build …` | BUILD SUCCEEDED, 0 concurrency warnings | 0 |
| Lint | `swiftlint --quiet` | **117 findings** | — |
| File length | `wc -l` over every added `.swift` | **zero new files over 400 lines** | — |

`cellarTests` breakdown read off the runner, not estimated: `SecurityCompositionTests` 13 runs
(10 functions, one parameterized ×4), `SecurityCaskScopeTests` 8, `SecurityArtifactScopeTests` 6,
`ConsentDisclosureTests` 3, `cellarTests` 2 = **32**. This reproduces the apply record exactly.

**On the lint count — 117 is one *below* the 118 baseline and is not drift.** Confirmed against the
recorded series 116 (pre-change) → 118 → 118 → 118 → 118 → 118 → **117**. Moving the shell preview
out of `ContentView.swift` during the batch-5 corrective carried a pre-existing 126-character line
with it and re-wrapped it. Authored findings introduced by this change: **zero**, at every batch
boundary. Not flagged as drift, per the apply record and re-measured here.

**Coverage**: ➖ Not available — no coverage tool is configured for this project. Not a failure.

---

### Live manual-verification observations — carried verbatim

These are the feature's own description of what it can and cannot do. They are reproduced without
paraphrase because rounding them would misstate the release.

#### MV-3 — the four coverage counts (obs 7458)

> **Vulnerable 0** (an explicit rendered "0"), **Not covered 163**, **Clean 7**, **Unavailable 0**.

Clean 7 is exactly the seven curated mapping entries — `bat`, `eza`, `ripgrep`, `sd`, `uv`,
`protobuf`, `llhttp` — all answering clean at their real installed versions. 163 not-covered over a
**~170-package inventory** (159 formulae + casks), each with its typed reason. Measured coverage is
therefore **7 of ~170 ≈ 4.1%**, inside the 3–5% band probe U1 sized the feature against. This is
the honest self-description of the release, not a defect: the four states are exactly what
`vulnerability-scanning` requires never to collapse, and `Not covered` is the state the
presentation is designed around.

#### MV-6 — request volume against inventory size (obs 7461)

> `nettop` capture during a full consented re-scan shows exactly **ONE** TCP connection from the
> cellar process: `192.168.1.125:55556 ←→ wa-in-f121.1e100.net:443` (Google-hosted = `api.osv.dev`
> via `ghs.googlehosted.com`; IP `64.233.184.121` differs from the user's `dig` `66.102.1.121` due
> to Google DNS rotation — the reverse hostname confirms). **ZERO** connections to NVD (the
> Cloudflare `172.65.90.24-27` range is absent). ~6.7 KB in / 4.8 KB out, consistent with a single
> `querybatch` POST plus its response, zero hydrations (zero findings to hydrate), zero NVD
> enrichment. **One request against a ~170-package inventory: volume follows findings, not
> inventory — claim verified live.**

#### MV-7 — identity parity (obs 7465)

Ghostty's disclosure: `com.mitchellh.ghostty` / `24VZTF6M5V` /
`Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)` → `Developer ID Certification
Authority` → `Apple Root CA`. All three fields are **literal matches** against
`codesign -dv --verbose=4`, obtained without Cellar spawning anything.

#### The remaining seven, in one line each

| Check | Result | Observation |
|---|---|---|
| MV-0 | PASS | U2/U5 at Phase 2, U3 at 14.0; `probe-manifest.txt` digests match on re-run (38 files) |
| MV-1 | PASS | Security section honest on first launch with no consent recorded; Not-covered present with its count; nothing claims the inventory is clean (obs 7458) |
| MV-2 | PASS | Zero pre-consent connections; the sheet names both hosts and the transmitted data (obs 7458) |
| MV-4 | PASS | First real `SchemaV1 → V2` migration on the user's live store; every pre-migration history row survived (obs 7459) |
| MV-5 | PASS | Offline relaunch shows cached results labelled with their age, nothing presented as fresh, no error alert (obs 7460) |
| MV-8 | PASS | `xattr -l` and `stat` identical before/after a full sweep on three artifacts; no admin prompt; no `codesign`/`spctl`/`xattr` process in Activity Monitor (obs 7463) |
| MV-9 | PASS | A distinctive non-brew `.app` in `/Applications` never appeared, while all **9** brew casks did — the positive anchor (obs 7464) |
| MV-10 | PASS | Fixture patch rendered all four sections (Vulnerable 1 / Not covered 163 / Clean 5 / Unavailable 1), HIGH above UNRATED in distinct buckets, and the finding read *"A fix published at 1.2.4, comparison not possible for this version scheme (a Homebrew packaging revision)"* with no ordering verdict; patch reverted, `git status` clean (obs 7466) |

**Four defects were found by these live checks and fixed**, none catchable by the suite — the suite
reached 1,090 green tests without any of them being visible to it. Each sat at a boundary *between*
tested layers: a missing **supplier** (`caskArtifacts: [:]` — 468 artifacts, zero casks, `b92f071`),
a missing **consumer** (identifier + authority chain reached the report, the view never read them,
`3410e45`), a missing **interaction** (the identity disclosure drew no indicator and took no click,
`e4de71d`), and a missing **addressability** (a container's `accessibilityIdentifier` overrode every
descendant's, `e4de71d`). This is the most instructive result of the milestone and it is recorded
as Deviation 71.

---

### Spec Compliance Matrix

15 requirements / 28 scenarios, counted from the retrieved delta specs
(`vulnerability-scanning` 8/14, `artifact-integrity` 6/8, `local-package-metadata` 1/6).

#### `vulnerability-scanning` — 8 requirements / 14 scenarios

| Requirement | Scenario | Covering evidence | Result |
|---|---|---|---|
| Coverage is typed and never collapses into "clean" | Unanswered packages never read as clean | `CoverageAggregationTests.anAllUnmappedInventoryIsNotClean`; `CVEMatcherTests.anUnansweredPackageNeverBecomesClean`; `SecurityPresentationTests.anUnscannedInventoryReportsThatRatherThanCleanliness`; **MV-1, MV-3** | ✅ COMPLIANT |
| ↑ | The four states survive aggregation | `CoverageAggregationTests.fourDistinctCountsSurviveAggregation`, `.theCleanCountIncludesOnlyCoveredClean`; `CVEMatcherTests.everyOutcomeIsExactlyOneOfTheFourStates`; **MV-3, MV-10** | ✅ COMPLIANT |
| Discovery is curated data, never inference | An identity collision is never a finding | `EcosystemMappingTests.theU1CollisionNamesAreDeliberatelyAbsent` (7 U1-measured names); `CVEMatcherTests.theMatcherPerformsNoNameSimilarityOrKeywordMatching`; `.anAdvisoryInAnotherEcosystemIsNotAFinding` | ✅ COMPLIANT |
| ↑ | Only the primary keg is in scope | `CVEMatcherTests.onlyThePrimaryKegIsEverMatched`; `cellarTests/SecurityCompositionTests.thePrimaryKegIsReadFromInstalledPackageAndNotRederived` | ✅ COMPLIANT |
| Enrichment is by CVE identifier only, severity never defaulted | Volume follows findings, not inventory | `NVDSourceTests.enrichmentIsByCveIdsOnlyAndNeverNamesAnInstalledPackage` (159 names, disjointness + positive anchor); `.identifiersAreBatchedAtOneHundred`; **MV-6 (one OSV request, zero NVD, vs ~170 packages)** | ✅ COMPLIANT |
| ↑ | An unscored advisory stays unrated | `NVDWireTests.aRecordWithNoCvssMetricStaysUnrated`, `.aNonCvssMetricEntryIsIgnoredRatherThanTiered`; `SeverityTierTests.anUnscoredAdvisoryStaysUnratedAndSortsInItsOwnBucket`; `SecurityPresentationTests.findingsSortBySeverityWithUnratedLast`; **MV-10** | ✅ COMPLIANT |
| Fix version compared only when both sides are strict SemVer | A non-SemVer version is not compared | `VersionBoundaryTests.aRevisionSuffixedInstallIsCoveredAndReportsAnUncomparableFix` (real `bat 0.18.1_1` vs real `GHSA-p24j-h477-76q3`); `.theSameAdvisoryAgainstAStrictInstallDoesOrder` (control); `SecurityFindingPresentationTests.aNonComparablePairStatesTheGapAndAssertsNoOrdering`; **MV-10** | ✅ COMPLIANT |
| ↑ | The upgrade offer names Homebrew's version | `SecurityFindingPresentationTests.theUpgradeOfferNamesHomebrewsVersion`, `.homebrewBehindTheAdvisoryFixIsStated`, `.aMatchingHomebrewVersionNeedsNoDifferenceNote`; **MV-10** (Homebrew `0.26.1` vs advisory `1.2.4`) | ✅ COMPLIANT |
| Dismissal is scoped to the exact finding and installed version | An upgrade re-surfaces a dismissed finding | `DismissalStoreTests.aVersionChangeReSurfacesTheFindingWithNoUserAction`, `.aDismissalSuppressesNoOtherFindingForTheSamePackage`, `.dismissalsAreEnumerableAndReversible`, `.twoAdvisoriesWithoutCveAliasesAreDismissedIndependently`; `CoverageAggregationTests.aDismissalSuppressesExactlyOneFindingAndChangesNoCoverageState` | ✅ COMPLIANT |
| Every result carries provenance, age and cache discipline | Provenance is inspectable per package | `SecurityStoreLifecycleTests.provenanceSurvivesTheCacheRoundTrip` (asserts `scannedAt`, `matcherVersion`, enrichment flags), `.aCachedLoadCarriesTheScansOwnProvenanceAndPartiality`; `AdvisoryCacheTests.cachedOutcomesArePublishedAsCachedWithTheirAge`; `CleanCoverage.answeredBy` asserted in `CVEMatcherTests` | ✅ COMPLIANT |
| Degradation is explicit and never fabricates a clean result | A rate-limited enrichment does not fabricate severity or health | `NVDSourceTests.aRateLimitedEnrichmentKeepsFindingsUnratedAndNeverMakesAPackageClean`, `.anAdvisorysOwnPublishedSeveritySurvivesARateLimit`; `SecurityStoreLifecycleTests.aRefusedEnrichmentReachesTheStoreAsPartial`, `.aPartialScanIsAdoptedAsPartialAndNeverAsComplete` | ✅ COMPLIANT |
| ↑ | Findings are readable offline | `AdvisoryCacheTests.cachedOutcomesArePublishedAsCachedWithTheirAge`, `.aCorruptOrUnreadableFileYieldsNoEntriesAndNoErrorPath`; `SecurityStoreLifecycleTests.lastGoodSurvivesAFailedScan`; **MV-5 (live, Wi-Fi off, relaunch)** | ✅ COMPLIANT |
| Scanning is opt-in, disclosed, reversible and Keychain-backed | Nothing is transmitted before consent | `ScanConsentTests.nothingIsTransmittedBeforeConsent`, `.aBlockedEgressEmitsBlockedPendingConsentRatherThanParkingSilently`; `cellarTests/ConsentDisclosureTests.theDisclosureNamesExactlyTheHostsTheAppCanReach`, `.theDisclosureStatesWhatIsSentAndWhatIsNot`, `.everyDisclosedHostCarriesItsPurpose`; **MV-1, MV-2** | ✅ COMPLIANT |
| ↑ | Off means fully off | `ScanConsentTests.turningScanningOffStopsEveryRequestAndEveryScheduledRun`, `.theCacheStaysReadableWithItsAgeAfterRevocation`; `cellarTests/SecurityArtifactScopeTests.neitherFiresWhileConsentIsOff`, `.revokingConsentStopsTheNextTrigger`; `CredentialStoreTests.theKeyRoundTripsThroughTheSeamAndNeverThroughUserDefaults`, `.theSecurityTargetNamesNoDefaultsOrLoggingApi` | ✅ COMPLIANT |

#### `artifact-integrity` — 6 requirements / 8 scenarios

| Requirement | Scenario | Covering evidence | Result |
|---|---|---|---|
| Assessment is read-only, unprivileged and subprocess-free | Inspection spawns nothing and writes nothing | `IntegrityProhibitionTests.noByteOfAnInspectedArtifactChanges`, `.noProcessIsLaunchedDuringAFullSweep`, `.noElevationIsRequested`, `.theFingerprintComparisonDetectsEveryKindOfChange` (control); `EgressStructureTests.securityKitSpawnsNothing`, `.securityKitWritesNothing`; **MV-8** | ✅ COMPLIANT |
| Signing and notarization verdicts are typed, including "could not assess" | An inconclusive assessment is not a verdict | `SignatureInspectorTests.anInconclusiveAssessmentIsCouldNotAssessWithAReasonAndIsCountedAsNeither`, `.totalsKeepCouldNotAssessApartFromBothVerdicts`, `.everyUnavailableReasonHasItsOwnSentence`, `.nonStapledNotarizationIsCouldNotAssessRatherThanNotNotarized` | ✅ COMPLIANT |
| ↑ | A signed artifact reports its identity | `SignatureInspectorTests.aSignedArtifactReportsItsIdentifierTeamIdentifierAndAuthorityChain`; `ArtifactIdentityPresentationTests.aSignedArtifactProjectsIdentifierTeamAndAuthorityChain`, `.theAuthorityChainKeepsThePlatformsOrder`, `.everyFieldCarriesADistinctKey`; `cellarUITests/SecurityIdentityUITests.testSigningIdentityDisclosureRevealsTheAuthorityChain`; **MV-7 (three literal matches)** | ✅ COMPLIANT |
| Quarantine and provenance are enumerated, decoded and cross-referenced | A quarantined artifact explains itself | `QuarantineInspectorTests.theAttributeDecodesIntoFlagsTimestampAgentAndUuid`, `.theRawValueIsPreservedVerbatimAlongsideTheTypedComponents`, `.provenancePresenceIsReportedWhenPresent`, `.theRealInspectorReadsARealAttributeOffDisk`; `IntegrityEngineTests.everyReportCarriesBothHalvesAndItsOwnArtifact` | ✅ COMPLIANT |
| ↑ | An unrecognised attribute component stays unknown | `QuarantineInspectorTests.anUnrecognisedComponentReportsUnknownAndIsNeverGuessed`, `.aComponentCountOtherThanFourIsNotWellFormed`, `.anEmptyAgentFieldIsAbsentRatherThanUnknown`, `.flagsAreDecodedAsANumberAndNeverInterpreted` | ✅ COMPLIANT |
| Scope is brew-managed artifacts only | Non-brew applications are out of scope | `cellarTests/SecurityArtifactScopeTests.onlyBrewManagedLocationsAreEnumerated`, `.formulaScopeIsThePrimaryKegsBinAndSbinOnly`, `.everyCandidateIsFilteredThroughArtifactAssessability`; `cellarTests/SecurityCaskScopeTests.aNonBrewAppBesideTheBrewInstalledOnesNeverAppears`, `.onlyTheInstalledVersionsCaskroomDirectoryIsEnumerated`, `.caskArtifactsResolveThroughTheRecordedSymlinkToTheRealBundle`; `ArtifactAssessabilityTests` (12); **MV-9 (decoy + 9-cask positive anchor)** | ✅ COMPLIANT |
| Assessment is per-item, off-main, streamed and cancellable | A slow lookup does not freeze or poison the run | `IntegrityEngineTests.resultsArriveIncrementallyPerArtifactRatherThanAsOneTerminalBatch`, `.aPerArtifactFailureBecomesACouldNotAssessEventAndNeverTerminatesTheStream`, `.cancellationStopsTheRunWithoutPresentingItAsComplete`, `.aCancelledProducerNeverEmitsFinished`, `.aFailingQuarantineReadLeavesTheSignatureVerdictStanding` | ✅ COMPLIANT |
| Visibility does not become remediation | No clearing affordance exists | `IntegrityProhibitionTests.noPublicSurfaceOfTheCapabilityAcceptsAWrite`, `.noWriteToAnExtendedAttributeExistsAnywhereInTheTarget`, `.thePublicSurfaceScannerFiresOnAMutatingDeclaration` (control); independently re-verified this phase: **zero `removexattr`/`setxattr` call sites** in `Sources/SecurityKit/` (the only two textual hits are prose in a doc comment) | ✅ COMPLIANT |

#### `local-package-metadata` — 1 modified requirement / 6 scenarios

| Requirement | Scenario | Covering evidence | Result |
|---|---|---|---|
| A snooze suppresses the outdated badge until the offered version changes | The badge is suppressed while the offered version is unchanged | `SnoozeProjectionTests.theBadgeIsSuppressedWhileUnchanged` | ✅ COMPLIANT |
| ↑ | A newer offered version revives the badge | `SnoozeProjectionTests.aNewerOfferedVersionRevivesTheBadge` | ✅ COMPLIANT |
| ↑ | A revision-suffixed or older offered version also revives the badge | `SnoozeProjectionTests.anyDifferentOfferedVersionRevivesTheBadge`, `.aChangedOfferedVersionReturnsItToTheSet` | ✅ COMPLIANT |
| ↑ | Unsnoozing restores the badge immediately | `SnoozeProjectionTests.unsnoozingRestoresTheBadgeImmediately` | ✅ COMPLIANT |
| ↑ | A snoozed package is still listed as installed | `SnoozeProjectionTests.aSnoozedPackageIsStillListed`, `.theOutdatedFilterAgreesWithTheList` | ✅ COMPLIANT |
| ↑ | The security comparator is structurally unreachable from snooze | `SnoozeGuardTests.noVersionComparatorExists` (tokens absent + equality anchor), `.noSecurityComparatorIsReachableFromSnooze` (all six enumerated files), `.dismissalStoreIsTheOnlyPersistenceFileImportingSecurityKit` (whole-directory, not an allow-list), `.snoozeBehaviourIsByteIdenticalToItsPreComparatorForm`, `.theImportScannerDetectsASecondImport` / `.theComparatorScannerDetectsAnOrdering` / `.theSecurityScannerDetectsAReference` (controls); `PackageGraphTests.brewClientCannotReachSecurityKit` (declared **and** transitive) | ✅ COMPLIANT |

**Compliance summary**: **28 / 28 scenarios COMPLIANT.** Every scenario has at least one named
covering test that passed at runtime in this phase's own execution; 13 of the 28 additionally carry
a live MV observation. Zero `UNTESTED`, zero `FAILING`, zero `PARTIAL`.

---

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Four-state coverage with no boolean collapse | ✅ Implemented | `CVEScanOutcome` is `.covered(Coverage)` / `.notCovered(NotCoveredReason)` / `.unavailable(AdvisoryError)` with `Coverage { findings, clean }`; **no `isClean` accessor exists** (the only textual hit is the doc comment saying so). `NotCoveredReason` has exactly the spec's three cases and nothing else. |
| Curated mapping only, no inference | ✅ Implemented | `EcosystemMapping` is a compiled Swift literal table with **7 entries**, per-entry provenance, and a `revisionFingerprint` that fails the suite if an entry is edited without bumping the revision. |
| NVD enrichment-only | ✅ Implemented | `NVDSource.enrich([String])` builds `cves/2.0?cveIds=` from identifiers filtered through `isWellFormedCVEIdentifier`; no request path takes a package name. Batch size 100. API key travels in a header, never the query string. |
| Consent gates every egress | ✅ Implemented | `ScanConsent` has one consenting constructor (`granted(at:)`, date-required) and `authorise()` **throws** rather than returning a `Bool`, so a silent `if consented { }` with no `else` is unrepresentable. |
| Keychain credential seam | ✅ Implemented | `AdvisoryCredentialStoring` protocol; `KeychainAdvisoryCredentialStore` uses `kSecClassGenericPassword`, service `com.juancasanueva.cellar.nvd-api-key`, `kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable: false`. No test touches the real Keychain — the query dictionary is asserted instead. |
| Read-only quarantine | ✅ Implemented | **Zero `removexattr` / `setxattr` call sites** in `Sources/SecurityKit/` (re-verified this phase). |
| Subprocess-free | ✅ Implemented | Re-verified this phase: no `Process`, `posix_spawn`, `NSTask`, `/usr/bin/`, `spctl`, `codesign` or `xattr` **identifier** in `Sources/SecurityKit/` — every textual hit is prose in a doc comment, and the shipped scanner is identifier-boundary aware so the mandated `getxattr`/`listxattr` C functions are not banned along with the forbidden tool. |
| No `SecAssessmentTicketLookup` call site | ✅ Implemented | Re-verified: zero call sites anywhere in `Packages/CellarCore/Sources/` or `cellar/`; the only two hits are doc comments recording the U3 answer. |
| Strict-SemVer-only fix comparison | ✅ Implemented | `FixVersionComparison.swift` contains the word `String` **exactly once, inside a comment**; every entry point is typed on `StrictSemVer` / `InstalledVersion` / `VersionScheme`, none of which carries a raw string value. A caller cannot hand it two Homebrew version strings. |
| Concurrency discipline | ✅ Implemented | Re-verified: **zero** `@unchecked Sendable` and zero `nonisolated(unsafe)` in `Sources/SecurityKit/` and `cellar/Security/`; both new targets build at `.swiftLanguageMode(.v6)` with zero concurrency warnings. |

---

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| `SecurityKit → Catalog` only | ✅ Yes | `Package.swift:80-81` — `dependencies: ["Catalog"]`, verified literally. |
| `Persistence → {BrewClient, SecurityKit}` | ✅ Yes | `Package.swift:98-99` — exactly those two, in that order. |
| No `BrewClient → SecurityKit` edge | ✅ Yes | `Package.swift:60-61` — `["BrewProcess", "Catalog", "DiskUsage"]`. Asserted declared **and** transitively by `PackageGraphTests.brewClientCannotReachSecurityKit`. |
| `DismissalStore.swift` the sole `Persistence` importer of `SecurityKit` | ✅ Yes | Whole-directory scan returns exactly one file. |
| Typed coverage, no clean-collapse | ✅ Yes | With the recorded nesting deviation (below). |
| Curated-mapping-only discovery | ✅ Yes | 7 entries, fingerprinted, collisions asserted absent. |
| NVD enrichment-only, volume follows findings | ✅ Yes | Proven at the transport seam **and** live at MV-6. |
| Consent gate on every egress path, including notarization | ✅ Yes — **with recorded amendment** | The design routed online ticket lookup through the same consent gate. U3 measured that `SecAssessmentTicketLookup` is **absent from the public macOS 26.5 SDK**, so the inspector has no network path to gate. Tasks 14.4/14.5 were amended in the open (Deviation 48) and the claim is now proven the honest way: `SignatureInspectorTests.theVerdictIsIdenticalWithAndWithoutConsentBecauseNoOnlineLookupExists` — identical verdicts under granted and revoked consent, with the recording network seeing zero requests either way. A weaker feature, not a different architecture, exactly as the design predicted. |
| Keychain credential seam | ✅ Yes | |
| Read-only quarantine, zero `removexattr` call sites | ✅ Yes | |
| Strict-SemVer-only fix comparison + evolved no-comparator guard | ✅ Yes | The guard grew from repository-wide to reachability-scoped, over six enumerated files plus an exhaustive whole-directory `Persistence` scan, with three controls; snooze behaviour is unchanged and asserted so by path. |
| `CVEScanOutcome` flat two-case `.covered` spelling | ⚠️ **Deviated — recorded (Deviation 9)** | Swift declares two same-named cases and then refuses to pattern-match them. Verified against the toolchain with a standalone reproduction before anything changed. Nested one level as `covered(Coverage)`; the four states, their names, and the absence of any boolean shortcut are all preserved, and `switch` remains exhaustive over four possibilities. **Does not break a spec requirement.** |
| `AdvisoryQuery` file placement | ⚠️ **Deviated — recorded (Deviation 10)** | One extra `Sources/SecurityKit/` file so the version boundary is reachable from `swift test`; the app-side `SecurityQueryBuilder` becomes a projection with no rules of its own. Narrows the composition point rather than widening it. |
| `AdvisorySource` as one protocol | ⚠️ **Deviated — recorded (Deviation 17)** | Split into `AdvisoryDiscovering` / `AdvisoryEnriching` because neither conformer is a fallback for the other. |
| Dismissal key `(cveID, kind, name, version)` | ⚠️ **Deviated — recorded (Deviation 39), spec amended in the open** | Keyed on `advisoryID` instead, because `GHSA-`/`RUSTSEC-`/`PYSEC-` records routinely publish no CVE alias and every unaliased finding for one package at one version would otherwise share the empty string. The `vulnerability-scanning` spec carries the amendment strikethrough-style with its rationale. Still four-part, still primitives only, still `#Unique`. Proven by mutation: keying on the CVE fails 9 of 11 tests. |
| Engine builds entries only for queried packages | ⚠️ **Deviated — recorded (Deviation 52)** | Widened to `AdvisoryScanRequest { queries, predecided }` because the original shape made the feature's central claim unsatisfiable: ~150 of 159 formulae produce no query and would have been absent from every settled result, leaving Not-covered permanently empty. Caught while wiring the composition root, fixed RED-first. |

**Approximately 73 deviations are recorded across six batches and four correctives, each with its
rationale.** This phase spot-checked the reconciliation in both directions and found **no unrecorded
divergence**: every `Sources/SecurityKit/` and `cellar/Security/` file absent from the design's file
table is accounted for by a numbered deviation or by a task (`AdvisoryQuery` 10, `SecurityScanEvents`
33, `SecurityScanPipeline` 57, `SecurityFindingPresentation` 45, `ArtifactSignatureModels` batch-5
lint split, `SecurityPreviews` 60, `ArtifactIntegrityStore` 56, `SecurityKit.swift` task 1.7,
`SecurityPresentation` task 16.3, `ArtifactIdentityPresentation` batch-5 third corrective).

---

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | TDD Cycle Evidence tables present in all five implementing batches |
| All tasks have tests | ✅ | 63 RED tasks; every behavioural task has a named test file that exists on disk |
| RED confirmed (tests exist) | ✅ | Every test file named in the evidence tables was located and executed this phase |
| GREEN confirmed (tests pass) | ✅ | 1090 / 1090 CellarCore, 32 / 32 `cellarTests`, 20 / 20 `cellarUITests` — zero failures |
| Triangulation adequate | ✅ | Parameterized corpora throughout: 159 real installed versions, 298 suffix-free corpus rows, 25 accept/reject SemVer rows, 8-case violation corpora on the structural scanners, four-state exhaustive matrices |
| Safety Net for modified files | ✅ | Each batch records the pre-edit green count (811 → 823 → 912 → 969 → 1004 → 1080 → 1090); task 13.1 ran the eleven existing snooze tests green **before** any new assertion was written |
| Absence guards carry positive anchors / controls | ✅ | Every prohibition scan has a planted-violation control (`theScannerDetectsAViolation`, `theComparisonScannerDetectsAnOrdering`, `theStringScannerDetectsAStringComparator`, `theImportScannerDetectsASecondImport`, `theScannerDetectsAPlantedDirectConstruction`, `thePublicSurfaceScannerFiresOnAMutatingDeclaration`, `theFingerprintDetectsEveryKindOfEdit`, `theDigestCheckDetectsAnEditedFixture`) |
| Mutation proof for absence claims | ✅ | Recorded per batch, e.g. generation check dropped → 3 fail; ordinal check dropped → 9 fail; partial adopted as content → 4 fail; dismissal keyed on CVE → 9 of 11 fail; `.lightweight` stage removed → 1 fail (the plan test, not the data test); second `import SecurityKit` → 2 fail |

**TDD Compliance**: 8 / 8 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|------:|------:|---|
| Unit (pure, fixture, corpus, structural) | ~1,090 total suite; the security half spans 33 `SecurityKitTests` files | 33 | Swift Testing |
| Integration (real SQLite, real filesystem, real xattr, transport seam, real Security.framework) | included above — `MigrationTests`, `DismissalStoreTests`, `AdvisoryCacheTests`, `QuarantineInspectorTests`, `ArtifactAssessabilityTests`, `SignatureInspectorTests` (2 real-framework tests), `OSVSourceTests`/`NVDSourceTests` via `RecordingURLProtocol` | — | Swift Testing + `URLProtocol` |
| App composition | **32 cases in 5 suites** | 6 | `xcodebuild test` |
| E2E / UI | **20 executed**, incl. 2 new `SecurityIdentityUITests` | 1 new | XCUITest |
| Live manual | 10 MV checks + MV-0 | — | real machine, real endpoints |

The layering is unusually complete for this project: the UI layer exists precisely because
`ArtifactIdentityPresentationTests` was green while a human could not reach the value it projected.

### Changed File Coverage

Coverage analysis skipped — no coverage tool is configured for this project. Not a failure.

### Assertion Quality

Scanned every test file added or modified by this change.

- **Tautologies**: zero. No `#expect(true)`, `#expect(true == true)`, `#expect(1 == 1)` or
  `#expect(Bool(true))` anywhere in `SecurityKitTests`, `cellarTests`, the new `PersistenceTests`
  or `SnoozeGuardTests`.
- **Assertion volume**: **899** `#expect`/`#require` sites in `SecurityKitTests`, **83** in
  `cellarTests`.
- **Orphan empty checks**: 6 sites assert an empty collection; every one has a companion non-empty
  test with the same arrangement (`anEmptyQueryListIssuesNoRequest` beside
  `discoveryPostsExactlyOneQuerybatchWithTheMappedSubset`, `anEmptyIdentifierListIssuesNoRequest`
  beside `identifiersAreBatchedAtOneHundred`, `anEmptyArtifactListFinishesImmediately` beside the
  streaming tests). Not orphans.
- **Type-only assertions used alone**: zero.
- **Ghost loops**: none found — every parameterized suite draws its arguments from a captured
  fixture whose non-emptiness is itself asserted by `FixtureManifestTests`.
- **Smoke-test-only**: none. The two XCUITests assert the *absent* state before the control is used,
  which is what stops an already-open control from passing by accident.

**Assertion quality**: ✅ All assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

### Quality Metrics

**Linter**: ✅ 117 findings, **zero authored by this change**; one below the 118 baseline for the
reason recorded above. Thirteen findings were introduced during batch 5 and all thirteen were
removed by splitting or correcting rather than silencing; the two `swiftlint:disable` directives in
the change are scoped and carry written justifications (`identifier_name` on `case v2`,
`static_over_final_class` on a `URLProtocol` override that cannot be `static`).
**Type Checker**: ✅ No errors — `xcodebuild build` succeeded with zero concurrency warnings at
Swift 6 language mode.

---

### Delivery

Recorded factually, because the absence of a review receipt here is a decision, not an omission.

| Fact | State |
|---|---|
| Receipt-driven development | **off**, decided by `clone_local` (`gentle-ai review mode status`, read this phase) |
| Review receipt for this candidate | **None exists** |
| Why | RDD was enabled during apply and a review was started for this exact candidate — lineage `review-81b740ee85f5bca7`, state `reviewing`, 4 lenses, 147 files / 23,156 lines. Negotiated `review status --next-transition` then could not route that base-diff lineage: `start` created what `status` cannot resolve (obs 7469). An apparent upstream provider defect, not a candidate problem. |
| Defect report | The user was offered the report path and **chose Stop here**; no GitHub issue was created, per the handoff contract. |
| Resolution | The user then disabled RDD **clone-locally** and chose ordinary repository policy. |
| Consequence | Delivery proceeds under ordinary repository policy — hooks, tests, CI. Nothing is silently approved; this report and the gates above are the evidence in place of a receipt. |
| Size | `single-pr` with `size:exception`, granted at the 11.6–14.6k forecast (obs 7456) and **reconfirmed by the user against the measured candidate at 22,887** (obs 7468). HEAD now measures **147 files, 22,972 insertions, 184 deletions = 23,156 changed lines** — 269 lines above the reconfirmed figure, entirely the final `apply-progress.md` documentation commit. |
| Push / PR | Neither. Nothing is pushed and no PR is open. |

---

### Open questions — registered by design, not findings

Three questions are carried forward in `design.md` with reasons rather than deleted (task 18.4,
Deviation 73). None is a defect in what shipped and none blocks archive.

1. **Coverage is ~4% and that is the feature's real limit.** The curated table maps seven formulae;
   MV-3 measured Clean 7 / Not covered 163 over a ~170-package inventory. The declared fix is the
   **v1.1 local advisory index**. Registered rather than deleted because "not covered" is the honest
   state this release ships, and the next release is where it shrinks.
2. **The mapping table's growth path.** Seven entries were curated by hand with per-entry
   provenance; there is no safe procedure yet for adding an eighth, because U1 proved name matching
   is dominated by identity collisions. Open until the v1.1 index replaces the table or gives it a
   verification procedure.
3. **`the-unarchiver`-shaped casks yield no artifact.** One of ten installed casks leaves a stale
   Caskroom directory that `SecStaticCodeCreateWithPath` rejects with `-67028`; the panel shows
   nothing for it rather than an unassessable row saying why. Pinned by
   `aStaleCaskroomDirectoryShellYieldsNothing` (which passed in this phase's run), and a visible
   "not assessable" row is the fix.

---

### Issues Found

**CRITICAL**: None.

**WARNING**:

1. **Two strict-TDD cycles ran test-after-code and are recorded as such** (Deviations 11 and 37).
   Fix selection among several declared advisory fixes was written after the implementation, and the
   duplicate-join assertion did not bite on its first writing. Both were closed the only way that
   restores the guarantee — **by mutation**: the naive last-declared-fix rule fails six of seven
   cases, and "return instead of joining" now fails two tests where it previously passed. Recorded
   rather than dressed up as clean cycles. Non-blocking: the guarantee is proven, the honesty is
   intact, and both are already visible in the apply record.
2. **MV-4's snooze half is vacuously satisfied.** The user had zero snoozes and zero notes before
   migrating, so live real-store evidence covers history survival only. Recorded honestly in the apply
   record rather than overclaimed. The snooze half is covered by
   `MigrationTests.aStoreWrittenUnderV1OpensUnderV2WithEveryRowIntact`, which writes and reads real
   `Snooze` rows through a real on-disk SQLite store, so the requirement is not untested — only the
   live half is partial. Non-blocking.

**SUGGESTION**:

1. The reconfirmed `size:exception` figure (22,887) is 269 lines behind HEAD's 23,156. The delta is
   documentation only and does not change the decision, but the archive record should carry the HEAD
   number so the next forecast calibrates against the real total.
2. The apply record's own forecast lesson is worth promoting out of this change: price `openspec/`
   documentation at ~4× the intuitive figure once a change exceeds three work-unit batches, and carry
   an explicit contingency for defects found at manual verification. Both are now measured
   (`openspec/` ran 4.4× over; ~600 lines existed only because two MV checks failed).
3. The milestone's most transferable result is Deviation 71 — three live defects at three layers,
   each with the layer itself tested and the boundary past it not. A standing rule for the next
   change: for every seam, assert that something real is plugged into it, not only that it resolves
   what it is handed.

---

### Verdict

**PASS**

All 113 tasks are complete and match the code state; all 28 spec scenarios across 15 requirements
have a named covering test that passed at runtime in this phase's own execution; the full gate is
green on every harness (CellarCore 1090/152, `cellarTests` 32/5, `cellarUITests` 20, build
SUCCEEDED with zero concurrency warnings, swiftlint 117 with zero authored findings); every design
decision under scrutiny — the dependency graph, the four typed coverage states, curated-mapping-only
discovery, NVD enrichment-only, the consent gate, the Keychain seam, read-only quarantine, and
strict-SemVer-only fix comparison behind an evolved reachability guard — was independently
re-verified rather than accepted from the record; and every divergence from the plan is recorded
with its rationale, with no unrecorded divergence found. Two warnings and three suggestions are
non-blocking. Nothing blocks archive.
