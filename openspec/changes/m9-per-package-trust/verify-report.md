```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:0cde71f7a4d1c99fe24f3607d176f97224b837a867ca2d7f4cd8409bafa57139
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 11/11
scenarios: 55/55
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:d52b638b20ca83a63ece24d896e170ee432c11bf7f1d37329b71a69334da2821
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
build_exit_code: 0
build_output_hash: sha256:85f1a45a6675ebc208b2e11d3d54f62b97fa787c2f43ba567a0ad6d289cf7968
```

## Verification Report — round 2 (supersedes the round-1 report)

**Change**: `m9-per-package-trust`
**Version**: spec deltas rev 3 (post-ME2 amendment)
**Mode**: Strict TDD
**Branch**: `feat/m9-per-package-trust` @ `5922e37` (round 1 verified `72c9f9b`), working tree clean but
for this untracked report
**Round-1 verdict**: `fail` on evidence completeness only — 0 blockers, 0 CRITICAL, both commands exit 0.
**Round-2 verdict**: **PASS WITH WARNINGS.** Both completeness gaps are discharged; 55/55.

### Scope of this round

Round 1 established the production code, all binding invariants, the exact-copy audit, assertion
quality, and 49/50 unit scenarios. **`git diff --stat 72c9f9b..HEAD -- 'Packages/CellarCore/Sources/**'
'cellar/**'` is empty — not one line of production source moved**, so those findings carry forward
unchanged rather than being re-derived. What follows verifies the deltas, plus a re-confirmation of the
four bindings the brief named.

Two commits since round 1:

| Commit | What |
|---|---|
| `cb3527d` | PT1.2 covering test (+65 lines, tests only); `package-mutation` delta header arithmetic corrected; `tasks.md` Phase 11 |
| `5922e37` | ME2 executed live → PT8.3 rewritten, **PT8.4 added**; transcript filed at `evidence/me2-transcript.txt`; `tasks.md` Phase 12 |

### Build & Tests Execution — re-run by this round

| Suite | Result | Exit | vs round 1 |
|---|---|---|---|
| `swift test --package-path Packages/CellarCore` | **1,825 tests / 215 suites**, 0 failures, 1 known issue | 0 | **+1 test** (the PT1.2 case) |
| `xcodebuild test … -only-testing:cellarTests` | **248 passing results**, `** TEST SUCCEEDED **` | 0 | unchanged |

Both match the brief's expectation (1,825/215 and 248) exactly. The PT1.2 case was observed executing
and passing by name:
`Test "A package's per-package state reads as three distinct answers" passed after 0.477 seconds.`

The one known issue remains the pre-existing, unrelated `OperationCenterCancelTests.swift:183`
`withKnownIssue`. The UI suite was not re-run: nothing executable in the app target moved since round 1,
where it passed.

**Round-1 WARNING-4 is settled by measurement**: the app suite is **248**, not 249. `apply-progress.md`
now records 248 and states the round-1 number was a miscount. My two independent runs agree at 248.

### Authoritative counts — recounted mechanically from the delta files at `5922e37`

| Delta | Req | Scenarios | unit | manual-evidence | Header self-declares | Class table |
|---|---|---|---|---|---|---|
| `package-trust` | 8 | **33** | 30 | 3 | 33 ✅ | 30 / 3 ✅ |
| `package-mutation` | 1 | **11** | 9 | 2 | 11 replacing 8 ✅ | 9 / 2 ✅ |
| `tap-management` | 1 | 7 | 7 | 0 | 7 replacing 5 ✅ | 7 ✅ |
| `package-detail` | 1 | 4 | 4 | 0 | 4 ✅ | 4 ✅ |
| **Total** | **11** | **55** | **50** | **5** | | |

Counted by scanning `^### Requirement: ` and `^#### Scenario: `, and cross-checked against
`^- Verification:` class markers — every file's `unit + manual` equals its scenario count. The claimed
**55 / 11** is correct.

**Round-1 WARNING-2 discharged.** The `package-mutation` header now reads "**11** scenarios replace the
**8**", and its class table reads 9 `unit` / 2 `manual-evidence`. I independently re-counted the shipped
block on `main`: PM10 carries **8** scenarios and the capability is 10 req / 60 sc, so the end state
60 − 8 + 11 = **63 sc / 10 req** is unchanged and still correct.

**Round-1 WARNING-3 discharged.** `tasks.md:9` now reads "**55 scenarios**: 33 / 7 / 11 / 4" and carries
its own audit trail (53 → 54 in task 11.2, 54 → 55 in task 12.1). The scenario map's `package-trust`
line reads "33 (30 `unit`, 3 `manual-evidence`)". No stale 53 or 32 remains anywhere in the file.

### PT1.2 — the round-1 PARTIAL, now COMPLIANT

`TapProjectionTests · aPackagesPerPackageStateReadsAsThreeDistinctAnswers` stages the scenario's exact
triple and satisfies every clause:

- **GIVEN** a decoded report listing cask `acme/tools/widget`; the same report for formula
  `acme/tools/helper`, which it does not list; and a machine with no decoded report.
- **WHEN** each package's state is read, as the pair `(grantsIndividually, TrustGrantState)`.
- **THEN** the three answers are `granted` / `noGrantRecorded` / `unreported`, asserted individually.
- **AND** all three pairwise inequalities are asserted explicitly.

Two things raise this above a box-ticking test. It is **positively anchored** — the fixture is asserted
to carry the one entry and not the other before the answers are read, so the three results are not three
refusals from an empty ledger. And it **pins both halves as necessary**:
`#expect(noGrantRecorded.marked == unreportedState.marked)` and
`#expect(granted.report == noGrantRecorded.report)` prove the `Bool` alone cannot separate the last two
and the report alone cannot separate the first two — so dropping either half collapses the triple into
the pair PT1 forbids. That is precisely the concern round 1 raised, answered directly.

**RED substitute — honestly recorded.** There is no honest RED here: the behaviour was already correct,
and the only way to manufacture one would be to invent a package-level three-valued API the spec does
not require and this focused unit was not authorized to add. `apply-progress.md` says so plainly and
substitutes **two reverted production mutations**, each observed red:

| Mutation | Observed |
|---|---|
| `grantsIndividually` forced to always answer `false` | **2 failures** |
| `TrustGrantState.entryCount` for `.unreported` forced from `nil` to `0` | **1 failure** |

Production was then restored byte-identical, which I verified independently:
`git diff 72c9f9b..HEAD -- 'Packages/CellarCore/Sources/**' 'cellar/**'` is **empty**. The mutation
counts are consistent with the test's own structure (two assertions read `marked` on a granted package;
one reads `unreported.entryCount == nil`). This follows the disclosed task-6.1 house precedent rather
than dressing a green test as a RED→GREEN cycle. **Correctly reported.**

### ME2 — executed live, and it falsified the premise it was meant to confirm

Transcript filed at `openspec/changes/m9-per-package-trust/evidence/me2-transcript.txt` (4,954 bytes,
committed at `5922e37`). It is **primary over any brief or observation**, and I read it as such.

**Environment**: macOS 26.5.2 arm64; **Homebrew 6.0.18-182-ga963211**. The brief and obs `#7775` rev 1
carried 6.0.15; obs `#7775` rev 2 and the amended spec both correct to 6.0.18 on the transcript's
authority. ✅ Correctly resolved in favour of the transcript.

**BEFORE** — `trust.json` sha256 `63ed7c9db32e4912806350e82ff10feed843c0485e67ec465425e5738a233eee`,
the same digest ME1 recorded and the same content as the `#7764` apply fixture. 14 entries: `taps` 1,
`formulae` 9, `casks` 4, `commands` 0 — including `guria/tap/nehir`, `guria/tap/nehir@rc` and
`nkzw-tech/tap/codiff`.

**Attempt 1 — refused, and the refusal is itself evidence.** Untapping `jnsahaj/lumen` from inside
Cellar was refused by Homebrew (`Refusing to untap … because it contains the following installed
formulae`). Cellar surfaced it as a single failed activity item — the m7 D4 narrowing holding on a real
refusal. The pre-untap UI state is attested in the transcript: `jnsahaj/lumen — 1 formula · 1 trusted
individually` on **both** row and header (PT5.1's one-projection rule, live), the `lumen` package row
carrying `Trusted individually` (PT5.4, live), and the "Other trusted packages" section already
surfacing the orphan `nkzw-tech/tap/codiff` and the URL-shaped unattributed formula
`https://github.com/cloudmanic/spice-edit/spice-edit` (PT8.1 and PT3.2, live).

**The measurement.** `guria/tap` was untapped from inside Cellar, which runs TM7's `brew untrust <tap>`
after the untap. **AFTER**: both `guria/tap/nehir` and `guria/tap/nehir@rc` are gone from `casks`;
digest `1150051fa010f48edf62814ba59e8cf750290b82ca3334567d1bdc54ec505070`. So
**`brew untrust <tap>` cascades to that tap's per-package grants** — the opposite of the m7-era belief
PT8.3 asserted.

**RESTORATION** — Homebrew auto-updated 6.0.18 → 6.0.19, `guria/tap` was re-tapped and both casks
re-granted, and the RESTORED payload is content-identical to the BEFORE payload and to the `#7764`
fixture. State fully restored. The binding "never run `brew upgrade` without `--dry-run`" was honoured:
the update was Homebrew's own auto-update, not an invoked upgrade.

**Adjudication of the amendment.** Amending the spec to the measurement is right, and the direction
matters: the change is a **strengthening**. If TM7's flow removes per-package grants, the in-Cellar path
closes the dormant-grant hole at package granularity too — better than `m7-tap-trust` recorded. The
implementation is not at fault and did not change: Cellar rendered exactly what the report said and
refreshed through the `.taps` ride, as DD-3/DD-4 designed. **No code, no test, and no other delta was
touched by `5922e37`** — verified. The amended PT8.3 (outside-Cellar orphan) and new PT8.4 (the cascade)
are internally consistent with each other, with the requirement prose, and with the transcript.

The archive note correctly records that the m7 R7 claim must not be carried forward unqualified, and
correctly preserves the deferral: `brew untrust --cask <qualified>` remains **unmeasured**, and the
cascade says nothing about whether naming a qualified package to `untrust` registers a grant before
removing it. `proposal.md` and `explore.md` deliberately retain the superseded belief as historical
record — the right call; rewriting history would hide that the belief was ever held.

### Manual-evidence ledger — all five accounted

| Scenario | Evidence | Status |
|---|---|---|
| PT4.5 — a real report accounts for every entry | ME1 (obs `#7764`); re-corroborated by the ME2 BEFORE payload — 14 entries, digest `63ed7c9d…` unchanged across two reads, equal to `ledger.entryCount` | ✅ COMPLIANT |
| PT8.3 — an outside-Cellar orphan is still listed and surfaced | `nkzw-tech/tap/codiff` present in `casks` while `nkzw-tech/tap` is absent from `brew tap`; transcript attests Cellar surfaced it in "Other trusted packages" | ✅ COMPLIANT (see WARNING-2) |
| PT8.4 — an in-Cellar untap removes that tap's grants | BEFORE/AFTER payloads and both digests `63ed7c9d…` → `1150051f…`; restoration recorded | ✅ COMPLIANT |
| PM10.10 — formula refusal wording | captured in `m7-tap-trust` Phase 9, byte-identical here, correctly not re-run | ✅ COMPLIANT |
| PM10.11 — a real refusal renders the typed outcome | captured in `m7-tap-trust` Phase 9; **additionally** re-observed live in this transcript (the `jnsahaj/lumen` untap refusal) | ✅ COMPLIANT |

### Spec Compliance Matrix — 55/55

Unit scenarios **50/50 COMPLIANT**. Round 1 traced 49 of them to named tests that executed and passed;
none of those tests moved, and all re-ran green at `5922e37`. The fiftieth, PT1.2, is now covered as set
out above. Manual-evidence **5/5**, per the ledger. **0 UNTESTED, 0 FAILING, 0 PARTIAL.**

### Binding invariants — re-confirmed at `5922e37`

| Invariant | Evidence | Result |
|---|---|---|
| `MutationCommand.swift` 0-line diff (plus `BrewMutating`, `TapCommand`, `scripts/`, workflows, `pbxproj`) | `git diff --stat main -- …` → empty | ✅ |
| C2 byte-identical | sha256 `1561832f552a643a03f290789d49dbcb9f4c8d443a86b88fec912da554644d5d` for `main:[500-613]` and `HEAD:[638-751]` | ✅ unchanged from round 1 |
| `MutationCommandTests.swift` diff is one hunk | `rg -c '^@@'` → **1** | ✅ |
| No 5th `InvalidationScope` member | 4 `public static let … InvalidationScope(rawValue:` in `BrewMutating.swift` | ✅ |
| README canonical three-line install block | sha256 `858f3437596bfdbd198beda5b79bfed0bda037b06743879bd7eaf392a522cf37` on both `main` and `HEAD` | ✅ |
| No production source moved since round 1 | `git diff --stat 72c9f9b..HEAD -- 'Packages/CellarCore/Sources/**' 'cellar/**'` → empty | ✅ |

The exact-copy audit (7/7 pinned strings byte-identical) and the assertion-quality audit from round 1
carry forward untouched, since `TapProjection.swift` did not move.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | **85** |
| Tasks complete | **78** |
| Tasks incomplete | **7** |

The seven open are **8.7** (open the PR) and **10.1–10.6** (archive-phase promotion). **9.2 and 11.4 are
now closed against the filed evidence**, which was round 1's WARNING-5. No implementation task is open.
`apply-progress.md` states 79/86 — see WARNING-1.

### Round-1 findings — disposition

| Round-1 finding | Disposition |
|---|---|
| WARNING-1 PT1.2 PARTIAL, assigned to no task | ✅ **Discharged** — covering test added, task 11.1, executes and passes |
| WARNING-2 `package-mutation` delta arithmetic | ✅ **Discharged** — 8 / 11 / 9-unit, re-counted independently |
| WARNING-3 downstream totals | ✅ **Discharged** — `tasks.md` at 55 = 33/7/11/4 with an audit trail |
| WARNING-4 app count 249 vs 248 | ✅ **Discharged** — 248 confirmed by two more runs |
| WARNING-5 ME2 unproven | ✅ **Discharged** — executed live; premise falsified; spec amended to the measurement |
| SUGGESTION 1–4 | 1–3 carried into the archive record; 4 (singular form in the XCUITest) not taken — still optional |

### Issues Found

**CRITICAL**: None.

**WARNING**:

1. **`apply-progress.md` reports "79 / 86 tasks complete"; `tasks.md` mechanically counts 78 / 85.**
   Counted every `- [x]`/`- [ ]` line at any indent, and confirmed 85 distinct numbered ids (0.1 … 12.3)
   with no duplicates. The open count (7) agrees; total and completed are each one high. Cosmetic, but
   it is the same class of miscount as round-1 WARNING-4, recurring in the very artifact that corrected
   it — worth fixing before archive so the number is not inherited a third time.
2. **PT8.3's evidence clause names a screenshot that is not filed.** The amended scenario requires "the
   transcript **and the screenshot** of that section appear in the verify report". The transcript is
   committed and referenced here; the screenshots are attested inside it ("screenshot captured by
   maintainer, 16.37.46") but no image is archived, so the clause cannot be fully satisfied from the
   repository. The scenario's *substantive* claims are evidenced in the transcript's text, which is why
   I record it COMPLIANT rather than PARTIAL — but a clause the archived record can never satisfy is a
   durable problem. Either file the screenshots under `evidence/`, or reword the clause to "the
   transcript, which attests the rendered section".
3. **The transcript's restoration block does not isolate the re-grant command.** It shows
   `==> Tapping guria/tap` … `Tapped 2 casks` … `Trusted cask: guria/tap/nehir` as one run of output, so
   on its face it reads as though `brew tap` auto-trusted the casks. Obs `#7775` supplies the missing
   step ("re-tap guria/tap **+ re-grant both casks**"). This matters because PT8.4's closing clause says
   the in-Cellar path "re-arms nothing on a later re-tap": that is sound *as an inference* from the
   evidenced fact that no grant record survives the untap, but the transcript alone reads against it.
   Recommend annotating the restoration block with the exact commands, so the archived evidence is
   self-contained and a future reader does not conclude that tapping auto-grants.
4. **The RESTORED payload was read on Homebrew 6.0.19, not the 6.0.18 the measurement ran on.** Homebrew
   auto-updated mid-transcript. This does not touch the cascade finding, which happened before the
   update, and the restored report is content-identical to the fixture — but the restoration is verified
   on a different build than the measurement, which is worth one sentence in the archive note.

**SUGGESTION**:

1. Record in the archive provenance that ME2 also produced two *bonus* live confirmations neither
   scenario claims: the `jnsahaj/lumen` untap-refusal path (m7 D4 narrowing, surfaced as one failed
   activity item) and the live one-projection count line appearing identically on row and header. Both
   are free corroboration of PM10 and PT5.1 on a real machine, and they are cheap to lose.
2. `brew untrust --cask <qualified>` remains unmeasured and the grant/revoke deferral correctly stands.
   Keep that explicit in the promoted `package-trust` provenance — the cascade finding makes it *more*
   tempting to assume the revocation is safe, and it is exactly what was not measured.
3. Carried forward: add the singular `1 trusted individually` form to the XCUITest, and enumerate
   `apply-progress.md` + the verify report in the next change's artifact-bucket forecast.

### Verdict

**PASS WITH WARNINGS** — 0 blockers, 0 CRITICAL, 4 WARNING, 3 SUGGESTION. **55/55 scenarios, 11/11
requirements.**

Both round-1 completeness gaps are genuinely closed rather than argued away. PT1.2 has a real covering
test that pins the exact triple *and* proves neither half of the pair carries it alone — the strongest
form the answer could take without inventing production surface the spec does not ask for. ME2 was run
for real, and when it contradicted the spec the spec was amended to the measurement instead of the
measurement being explained away; the transcript was filed in the repository rather than paraphrased.
That is the right instinct, and the resulting change is safer than the one that was specified: the
cascade closes at package granularity a hole `m7-tap-trust` believed was open.

All four WARNINGs are archive-hygiene items about the *record*, not the software. No production source
has moved since round 1, every binding invariant still holds, both suites are green at 1,825 and 248,
and no scenario is untested, failing or partial.

**Recommended next**: `sdd-archive`. Fold WARNING-1 through WARNING-4 into the Phase 10 promotion —
correct the task tally, resolve the screenshot clause one way or the other, annotate the restoration
commands, and note the 6.0.19 restoration build.
