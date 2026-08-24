# Tasks: A read-only per-package trust surface (`m9-per-package-trust`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m9-per-package-trust/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `chain_strategy=pending`, `review_budget_lines=5000`,
`strict_tdd=true`. RDD disabled.

Inputs: the four spec deltas **rev 2, post-correction** (`specs/{package-trust,tap-management,package-mutation,package-detail}/spec.md`
— **53 scenarios**: 32 / 7 / 10 / 4), `design.md` (**DD-1…DD-12**), `proposal.md` (obs `#7760`),
maintainer scope decisions (obs `#7759`), gate decisions (obs `#7766`), and the **MEASURED** probe
results (obs `#7764`).

Size note: this artifact exceeds the generic 530-word phase budget, on the house precedent at
`openspec/changes/archive/2026-08-23-m7-tap-trust/tasks.md:16`. Nothing is padded.

## Binding reconciliations — the spec supersedes the design where they disagree

The deltas were corrected after the design was written. **Where they differ, the spec is normative.**
Apply these five; do not implement the design's superseded shape.

| # | Design said | Spec rev 2 requires | Where |
|---|---|---|---|
| **B1** | `.noGrants` renders **nothing** (DD-8) | a decoded report with no entries renders exactly **“Homebrew records no packages trusted individually.”** | PT6 sc3 |
| **B2** | `.unreported` copy *“Homebrew did not report per-package trust grants.”* | exactly **“This Homebrew does not report per-package trust.”** | PT6 sc3 |
| **B3** | orphan/section copy as drafted in design §4 | exactly **“Homebrew still records these grants. Cellar shows them; it does not remove them.”** | PT8 sc2 |
| **B4** | `UnattributedGrants { formulae, casks, other }` | a **five-category partition** that sums to the decoded entry count: attributed · excluded (`taps` for an installed tap) · **orphan tap grants** (`taps` for an uninstalled tap) · unmatched package grants · other | PT4 sc1, PT8 sc1 |
| **B5** | unknown top-level keys are **ignored** for forward compatibility | an unmodelled key whose value is a list of qualified strings **decodes and its entries are counted as “other”**; nothing is discarded uncounted | PT4 sc4 |

Two further measured facts the design predates (obs `#7764`): the namespaces are **not disjoint** —
`gentleman-programming/tap/engram` appears in **both** `formulae` and `casks`, so nothing may
deduplicate, displace or mask the other (PT4 sc2) — and a package name can carry `@`
(`guria/tap/nehir@rc`).

## Scenario map (IDs used by every task below)

**`package-trust` — 32 (30 `unit`, 2 `manual-evidence`), all new.**
**PT1** .1 constant argv names nothing · .2 three distinct values · .3 no trust verb → unreported,
never zero · .4 no trust file read from disk. **PT2** .1 concurrent refreshes coalesce · .2 failed
refresh keeps last good · .3 stale answer not adopted · .4 no per-package invalidation domain ·
.5 rides the taps domain once per refresh · .6 a failing grant read never fails a tap refresh.
**PT3** .1 qualified entry attributes to its publisher · .2 URL-shaped entry never split ·
.3 same-named package under another tap not claimed. **PT4** .1 the accounting partitions the decoded
set · .2 the same identifier in two namespaces is two entries · .3 `commands` counted, never dropped ·
.4 an unmodelled namespace does not fail the decode · .5 a real report accounts for every entry
*(`manual-evidence`)*. **PT5** .1 row and header read one value · .2 zero and unreported render no
count line · .3 the count is scoped to its own tap · .4 the marker is additive on the package row.
**PT6** .1 every per-package string is positive · .2 no grant renders nothing · .3 unreported vs
reported-empty distinguishable in copy · .4 nothing derives a verdict. **PT7** .1 no path submits a
package trust command · .2 no argv element gains a second `/` · .3 the surface exposes display only.
**PT8** .1 an uninstalled tap's grant is an orphan · .2 the orphan copy is exact and offers nothing ·
.3 a per-package grant survives an untap *(`manual-evidence`)*.

**`tap-management` — 7 (TM12 MODIFIED).** .1–.5 **survive byte-identical from `m7-tap-trust`**
(decode three-valued · unreported controls · badge follows state · one projection · copy about the
tap) — they are **regression guards, never RED**. **.6 the tap's own state still comes from one
source** and **.7 the count line is additive and never touches the badge** are **new**.

**`package-mutation` — 10 (PM10 MODIFIED).** .1–.6 **survive byte-identical from `m7-tap-trust`** —
regression guards, never RED; **.7 a per-package grant state never pre-blocks a mutation**,
**.8 the source-scanning absence names the per-package trust types** and **.9 the per-package read is
not a command on the mutation spine** are **new**. .10/.11 are the two `manual-evidence` scenarios
(formula refusal wording; a real refusal) **already captured in `m7-tap-trust` Phase 9** — carried
forward unchanged, **not re-run here**.

**`package-detail` — 4 (PD8 ADDED), all new and mostly negative.** .1 a grant marks only the exact
package it names · .2 no grant and no report both render nothing · .3 the marker is not a projection
field · .4 the marker states a grant and offers nothing. **PD8 is expected to render nothing on
today's shipped surface** (PD6 keeps third-party packages out of catalog detail); it exists so the
bare-name hazard is impossible to ship, per obs `#7766` gate decision 2.

**New RED work: 39 `unit` scenarios** (30 PT + 2 TM + 3 PM + 4 PD). **13 shipped scenarios are
regression guards that must never go red.** **2 new `manual-evidence`** (PT4.5, PT8.3) are not
RED/GREEN tasks — no `--filter` or `-only-testing:` invocation can reach them, and `sdd-verify` MUST
NOT wait for a harness the spec itself declares cannot exist.

## Review Workload Forecast

| Field | Value |
|---|---|
| Bottom-up **code + tests** | **~1,440** (core code ~540 · app code ~115 · tests ~785) |
| House correction | **1.9–2.3×**, applied to the code+test bucket **only** (1,440 → **2,736–3,312**) |
| **SDD artifacts, forecast separately with NO code-derived correction** (learning E / R8) | **~1,900–2,300** — and mostly **counted, not estimated**: the four deltas are already on disk at **955** lines (478 + 171 + 196 + 110), `design.md` **353**, this file **~350**, `proposal.md` **~200**; the verify report adds **~250–450** at verify time |
| Estimated changed lines (PR total) | **~4,636–5,612** authored |
| Governing budget | **5,000** (`config.yaml:8` and session preflight agree) |
| Risk vs governing budget | **Medium** — the band **straddles the ceiling**: 93 % at the low end, **112 % at the high end**. Unlike `m7-tap-trust`, this is a real decision, not a formality |
| Chained PRs recommended | **Yes** — prepared, two slices, cut exactly where the design flagged it |
| Suggested split | **PR 1 = WU1–WU3** (artifacts + read + store + coordinator, ~3,460) → **PR 2 = WU4–WU7** (attribution/accounting + guards + views + doc sweep, ~2,100). Both slices land under 5,000 |
| Delivery strategy | single-pr |
| Chain strategy | **pending** — the maintainer chooses `stacked-to-main`, `feature-branch-chain`, or one PR with `size:exception` (the `m7-tap-trust` precedent, recorded after apply at 6,555 measured lines) |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**, which does not govern
this repository. The governing 5,000-line judgement is the **Medium** row above. Because
`delivery_strategy=single-pr`, the orchestrator MUST resolve one of: accept the WU3/WU4 split, or
record `size:exception`, **before** `sdd-apply` starts.

**Branch**: `feat/m9-per-package-trust`
(`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**PR title**: `feat(taps): show the per-package trust grants Homebrew already records`.

### Suggested Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

RED and GREEN may be separate commits inside a unit (house precedent); tests never leave the unit
whose behaviour they verify.

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| **WU1** | TM12 MODIFIED lands **first** — the four deltas, design, tasks (**DD-12 / R1**) | PR 1 | N/A — artifacts only, no code | N/A — no behaviour changes | Revert the single artifact commit; the tree returns to `main` |
| **WU2** | `TrustGrantWire.swift` + `TrustGrantPayloadSource.swift` — the constant-argv read and the four-plus-unmodelled-namespace decode | PR 1 | `swift test --package-path Packages/CellarCore --filter 'TrustGrantDecodeTests|TrustGrantSourceTests'` | N/A — pure decode over the **verbatim** obs `#7764` payload; the live read is manual evidence PT4.5 | Delete both new files; nothing else references them yet |
| **WU3** | `TrustGrantStore.swift` + `TapRefreshCoordinator` concurrent `async let` (**DD-4**) | PR 1 | `swift test --package-path Packages/CellarCore --filter 'TrustGrantStoreTests|TrustGrantRefreshTests|MutationRefreshReceiptTests'` | `xcodebuild build …` — the app must still compile with the default-`nil` `grants:` parameter | Delete `TrustGrantStore.swift` and revert the coordinator's one parameter; every shipped construction site already compiles without it |
| **WU4** | `TapProjection` attribution, the **five-category** accounting (B4) and all exact copy (B1–B3) | PR 2 | `swift test --package-path Packages/CellarCore --filter 'TapProjectionTests|TrustGrantAccountingTests'` | N/A — pure, total functions over synthesised values | Revert the `TapProjection.swift` additions; `trust(for:)` and `packageSummary(for:)` are untouched by construction (**D-d**) |
| **WU5** | Guards: C1 ban list, PM10's three new absences, C2 byte-identical proof | PR 2 | `swift test --package-path Packages/CellarCore --filter 'MutationCommandTests|TapShippingProofTests'` | N/A — source-scanning and enumeration absences | Revert the two ban-list tokens and the three new cases; C2 never moved |
| **WU6** | Four view surfaces + DI + `cellarTests` + `cellarUITests` | PR 2 | `swift test --package-path Packages/CellarCore --filter 'TapShippingProofTests'` + `xcodebuild test … -only-testing:cellarTests/PerPackageTrustCompositionTests` | `xcodebuild test … -only-testing:cellarUITests/PerPackageTrustUITests`, then launch and open Taps | Revert the view commit; the stores stay, render nothing, and every shipped surface is byte-unchanged |
| **WU7** | `README.md` :44-47 qualified-token sweep — **doc-only** | PR 2 | N/A — prose; `rg` check only | N/A | Revert one prose commit; `release-distribution` D-2's canonical three-line install is untouched |

Plus one artifact commit, **first on the branch**, which **is** WU1:
`docs(sdd): record the m9-per-package-trust proposal, spec deltas, design and tasks`.

**Parallel vs sequential.**

- **Sequential, hard dependencies**: **WU1 → everything** (DD-12/R1 — TM12's unqualified single-source
  clause forbids this change until it is scoped; no line of code may land first).
  **WU2 → WU3** (the store decodes through `TrustGrantDecoder`). **WU2 → WU4** (attribution consumes
  `TrustGrantLedger`). **WU4 → WU6** (every surface reads a projection). **WU2 + WU4 → WU5** (the ban
  list names `TrustGrant` and `grantsIndividually`, which must exist to be banned meaningfully).
- **Parallelisable in principle**: **WU3 ∥ WU4** (disjoint files — `TrustGrantStore.swift` +
  `TapRefreshCoordinator.swift` vs `TapProjection.swift`), and **WU7 ∥ everything** (`README.md`
  alone). **One writer, executed sequentially** — no parallel worktrees, no parallel branches.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Never negotiable.
- **Rollback order** is the reverse — WU7 → WU6 → WU5 → WU4 → WU3 → WU2 — with WU1 last, since
  reverting the TM12 scoping while code remains would re-break R1.
- **Bottleneck**: WU4 is on the critical path for WU5 **and** WU6 and carries the largest single-file
  diff. It is the named split candidate and the unit most likely to need a second session.

## Phase 0: Preflight (sequential; no behaviour changes)

- [x] 0.1 Measure and record the green baseline; do not re-derive it later, and do not assume the
      `m7-tap-trust` numbers still hold — `m8-bundle-rename` shipped after them. Run
      `swift test --package-path Packages/CellarCore` and
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
      Count **distinct** passing test ids; `Executed 0 tests` is meaningless for Swift Testing bundles.
      A different number from any earlier change is the new baseline, not a defect.
- [x] 0.2 Confirm every anchor the design pins is still where it says:
      `TapProjection.swift` :121-132 (`trust(for:)`) / :166-174 (`packageSummary`) / :208-222
      (`bareToken`, `publishes`) · `TapStore.swift` :26-36 / :55-93 (the spine WU3 clones) ·
      `TapRefreshCoordinator.swift` :11-19 / :46-59 · `MutationCommandTests.swift` :471-479 (the C1
      ban list) / :500-613 (**C2 — must not move and must not be edited**) · `TapsListView.swift:52` ·
      `TapDetailView.swift` :57-65 / :149-180 · `PackageDetailView.swift:557` · `README.md` :44-47.
      A moved anchor is a deviation to report, not to absorb.
- [x] 0.3 `git checkout -b feat/m9-per-package-trust main`.

## Phase 1: WU1 — TM12 lands first (DD-12, R1; tap-management delta)

- [x] 1.1 Commit the SDD artifacts, **TM12's MODIFIED block included**, before any Swift file changes:
      `docs(sdd): record the m9-per-package-trust proposal, spec deltas, design and tasks`.
      **Acceptance**: `specs/tap-management/spec.md` scopes the single-source clause to the tap's own
      trust state and states that **only two** of the clause's four prohibitions are taken.
- [x] 1.2 Confirm the delta's arithmetic before moving on: package-trust **8 ADDED / 32 scenarios**;
      tap-management **1 MODIFIED, 7 scenarios replacing 5** → 13 req / 57 sc; package-mutation
      **1 MODIFIED, 10 scenarios replacing 7** → 10 req / 63 sc; package-detail **1 ADDED / 4
      scenarios** → 8 req / 30 sc. A mismatch is a spec defect to report, not to patch here.
- [x] 1.3 Record the **five binding reconciliations B1–B5** above in the apply context, so no task
      below implements the design's superseded copy or its three-category `UnattributedGrants`.

## Phase 2: WU2 — the read (PT1.1, .3, .4; PT4.2, .3, .4)

Runner: `swift test --package-path Packages/CellarCore --filter 'TrustGrantDecodeTests|TrustGrantSourceTests'`

- [x] 2.1 **RED.** New file `Packages/CellarCore/Tests/BrewClientTests/TrustGrantDecodeTests.swift` ·
      `theVerbatimHomebrewPayloadDecodesEveryNamespace`: the fixture is the **verbatim obs `#7764`
      capture**, byte-for-byte — 1 tap, 9 formulae, 4 casks, `"commands": []`. Assert all four keys
      decode, entries are byte-identical to the payload, the URL-shaped
      `https://github.com/cloudmanic/spice-edit/spice-edit` survives, `nehir@rc` keeps its `@`, and an
      absent key is `[]`. **PR #67's lesson is binding: the fixture MUST NOT be invented.**
      **RED because** `TrustGrantLedger` does not exist. *(PT4.2, PT4.3)*
- [x] 2.2 **RED.** `TrustGrantDecodeTests · anUnansweredBrewIsUnreportedNotZeroGrants`: a non-zero exit
      with an unknown-command message, a launch failure, blank output, malformed JSON and a non-object
      envelope each → `.unreported`; a decoded payload of empty arrays → `.noGrants`; the two compare
      **not equal**, and no case reports a count of `0` or an empty grant set. **RED because** the
      three-valued type does not exist. *(PT1.3, D-b, R4)*
- [x] 2.3 **RED.** `TrustGrantDecodeTests · anEmptyLedgerCannotBeGranted`: `TrustGrantState.reported`
      over an empty ledger is `.noGrants`, and **no** construction path yields `.granted` carrying an
      empty ledger. **RED because** the canonical constructor does not exist. *(DD-1)*
- [x] 2.4 **RED — B5.** `TrustGrantDecodeTests · anUnmodelledNamespaceIsCountedNotDiscarded`: a payload
      carrying the four known keys **plus** an additional top-level key whose value is a list of
      qualified strings decodes successfully, the four known namespaces account as usual, and the
      extra key's entries are retained for the **other** category. A present-and-**empty** `commands`
      array is distinguishable from an **absent** `commands` key. **RED because** the design's
      four-`decodeIfPresent` shape discards unknown keys. *(PT4.4, PT4.3)*
- [x] 2.5 **RED.** New file `TrustGrantSourceTests.swift` ·
      `theGrantReadIsAConstantArgvWithNoQualifiedToken`: argv is exactly `["trust","--json","v1"]`,
      kind `.read`, **no element contains `/`**, none carries a package name, tap name or kind flag,
      and the source file's argv literal is a `static let` with no interpolation. **RED because** the
      source does not exist. *(PT1.1, D-f, DD-11)*
- [x] 2.6 **RED.** `TrustGrantSourceTests · noPathReadsATrustFileFromDisk`: scanning
      `TrustGrantPayloadSource.swift`, `TrustGrantWire.swift` and `TrustGrantStore.swift`, none
      contains `FileManager`, `trust.json`, `.homebrew`, `XDG_CONFIG_HOME` or a `URL(fileURLWithPath:`
      literal, on **every** path including each failure path; the only acquisition is the spawned
      `brew` read. **RED because** the files do not exist. *(PT1.4, `rules.apply`)*
- [x] 2.7 **Prove RED.** Run the focused command; 2.1–2.6 MUST fail, each for its stated reason. A
      green test here is a defect in the test.
- [x] 2.8 **GREEN.** New file
      `Packages/CellarCore/Sources/BrewClient/TrustGrantWire.swift` — `TrustGrantState` (with the
      canonical `reported(_:)`), `TrustGrantLedger` (`formulae`, `casks`, `taps`, `commands`, **plus
      `unmodelled: [String: [String]]` for B5**, and package-scoped `isEmpty` that ignores `taps`),
      `TrustGrantError`, and `@concurrent TrustGrantDecoder.decode` using a dynamic-key container so
      unknown list-of-string keys are retained rather than dropped.
- [x] 2.9 **GREEN.** New file `.../BrewClient/TrustGrantPayloadSource.swift` — `TrustGrantSourcing`
      and `BrewTrustGrantPayloadSource` with
      `static let command = BrewCommand.read(["trust", "--json", "v1"])`, cloning
      `BrewTapPayloadSource`'s `BrewRunner.start` → drain → exit body and its 12-line stderr tail.
- [x] 2.10 Focused command green; commit WU2
      (`feat(taps): read the per-package trust report Homebrew already publishes`).

## Phase 3: WU3 — the store and the concurrent refresh (PT2.1–.6)

Runner: `swift test --package-path Packages/CellarCore --filter 'TrustGrantStoreTests|TrustGrantRefreshTests|MutationRefreshReceiptTests'`

- [x] 3.1 **RED.** New file `TrustGrantStoreTests.swift` ·
      `concurrentRefreshesCoalesceIntoOneSpawn`: three refreshes requested while one is in flight →
      exactly one process spawned, all four requests observe the same report; `invalidate()` defeats
      coalescing. **RED because** the store does not exist. *(PT2.1, R5)*
- [x] 3.2 **RED.** `TrustGrantStoreTests · aFailedRefreshKeepsTheLastGoodReport`: success → `.granted`;
      a following failure keeps `.granted` and moves `state` to `.failed`; it is **not** replaced by an
      empty report, by `.unreported`, or by a zero count; a **first-ever** failure leaves `.unreported`.
      *(PT2.2)*
- [x] 3.3 **RED.** `TrustGrantStoreTests · aStaleAnswerIsNotAdoptedOverANewerOne`: two refreshes whose
      answers arrive out of order → the newer is retained, the older discarded. *(PT2.3)*
- [x] 3.4 **RED.** New file `TrustGrantRefreshTests.swift` ·
      `bothReadsAreIssuedOnceForOneRefreshAndOverlap`: one coordinator refresh issues exactly one
      `tap-info` spawn and exactly one `trust` spawn, **overlapping rather than sequential**, and
      neither refreshes installed inventory or the catalog. **RED because** the coordinator holds one
      store. *(PT2.5, DD-4)*
- [x] 3.5 **RED.** `TrustGrantRefreshTests · aDegradedGrantReadNeverFailsTheTapReceipt`: the grant
      source throws, and separately never answers; in both cases `RefreshResult` is the successful one
      the **tap** read produced, the taps domain still refreshes exactly once, the tap snapshot is
      adopted undelayed, and the grant state degrades to `.unreported` or the last good report.
      *(PT2.6, DD-4)*
- [x] 3.6 **RED.** `TrustGrantRefreshTests · noPerPackageInvalidationDomainExists`: enumerating every
      `InvalidationScope` value every command family on the shared spine can declare yields **exactly
      the shipped set**, with no member for per-package trust, and no command declares one. **RED
      because** nothing today pins the enumeration against growth. *(PT2.4, DD-3, obs `#7766` gate 1)*
- [x] 3.7 **RED — extend the shipped `MutationRefreshReceiptTests`.** Tap trust, tap untrust and the
      revocation behind an accepted removal, each across success, failure, launch failure and
      cancellation: each terminal refreshes the taps domain exactly once, and **that one refresh now
      issues one tap read and one grant read**. *(PT2.5)*
- [x] 3.8 **Prove RED** (all seven), then **GREEN**: new file `.../BrewClient/TrustGrantStore.swift` —
      `TrustGrantLoadState` and `@MainActor @Observable TrustGrantStore`, cloning `TapStore`
      member-for-member (`InFlightRefresh` keyed on `(request, invalidationCount)`, `nextToken` /
      `installedSequence` monotonic adoption, `invalidate()`, both `refresh` overloads, `clear(to:)`,
      `vacate(_:)`), with `public private(set) var grants: TrustGrantState = .unreported` and
      `init(source: any TrustGrantSourcing = BrewTrustGrantPayloadSource())`.
- [x] 3.9 **GREEN.** `TapRefreshCoordinator.swift` — add `grants: TrustGrantStore?` with a **default of
      `nil`** (the shipped `mutations:` / `refreshRegistry:` idiom, so every existing construction site
      still compiles), and refresh both stores with `async let` in `performRefresh`, `refresh(using:)`
      and `refresh(for:)`. **`RefreshResult` continues to read `store.state` alone.**
- [x] 3.10 Focused command green **and** `xcodebuild build …` still compiles; commit WU3
      (`feat(taps): refresh the grant report alongside the tap snapshot`).

## Phase 4: WU4 — attribution, the five-category accounting, and the exact copy (PT3, PT4.1, PT5, PT6, PT8.1–.2; PD8.1–.3)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapProjectionTests|TrustGrantAccountingTests'`

- [ ] 4.1 **RED.** `TapProjectionTests · attributionRequiresBothThePrefixAndThePublication`:
      prefix-only → unattributed; publication-only (a bare `wget`) → unattributed; **both** →
      attributed; the URL-shaped entry → unattributed, **never crashed and never split on `/`**; no tap
      is derived from its first two slash-separated components. **RED because** the rule does not
      exist. *(PT3.1, PT3.2, DD-5, R6)*
- [ ] 4.2 **RED.** `TapProjectionTests · aSameNamedPackageUnderAnotherTapIsNotClaimed`: a report listing
      formula `acme/tools/widget`, with installed `widget` from `other/tools` and catalog `widget` from
      `homebrew/core`, leaves **both** `noGrantRecorded`; neither is marked from the bare name.
      *(PT3.3, PD8.1)*
- [ ] 4.3 **RED — B4.** New file `TrustGrantAccountingTests.swift` ·
      `theAccountingPartitionsTheDecodedSet`: over the spec's exact fixture — 2 `taps` (one installed,
      one not), 3 `casks` (two published by installed taps), 1 URL-shaped `formulae`, 1 `commands` —
      the totals are **attributed 2 · excluded tap grants 1 · orphan tap grants 1 · unmatched package
      grants 2 · other 1**, they **sum to the 7 entries decoded**, every entry lands in exactly one
      category, and no `taps` entry contributes to any package count. **RED because** the design's
      three-category value cannot express the partition. *(PT4.1, PT8.1, DD-9)*
- [ ] 4.4 **RED.** `TrustGrantAccountingTests · theSameIdentifierInTwoNamespacesIsTwoEntries`: both
      `gentleman-programming/tap/engram` occurrences are decoded and accounted **separately**, one as a
      formula and one as a cask; neither deduplicates, displaces, overwrites or masks the other; a grant
      for one kind does **not** mark the other kind; `nehir@rc` neither truncates nor fails.
      **RED because** nothing pins non-disjointness. *(PT4.2, obs `#7764`)*
- [ ] 4.5 **RED.** `TrustGrantAccountingTests · theCommandsNamespaceIsCountedNeverDropped`: a report
      whose only entries are in `commands` counts them as **other** and renders a non-empty section; a
      present-and-empty `commands` beside populated namespaces is a report of nothing, distinguishable
      from an absent key, and neither report is presented as empty. *(PT4.3, DD-9)*
- [ ] 4.6 **RED.** `TapProjectionTests · oneProjectionCarriesTheCountAndTheMarkedSet`: a tap with two
      attributed grants → `countLine` exactly **“2 trusted individually”**, singular form exactly
      **“1 trusted individually”**, and `marked` is exactly the attributed `PackageID`s — one value,
      read by the row **and** the header. *(PT5.1, TM12.7, DD-6)*
- [ ] 4.7 **RED.** `TapProjectionTests · nothingIsClaimedForUnreportedOrZero`: `countLine == nil` and
      `marked.isEmpty` for `.unreported` and for a decoded report with zero attributed grants; **no
      rendering anywhere contains “0 trusted individually”**, and no string says a package is
      untrusted, unsafe, unverified or unprotected. *(PT5.2, PT6.1, PT6.2, DD-7, D-c, TM11)*
- [ ] 4.8 **RED.** `TapProjectionTests · theCountIsScopedToItsOwnTap`: with `acme/tools` and
      `other/tools`, one grant published by each, one orphan tap grant and one unmatched package grant,
      each tap's count is exactly 1 and includes neither the orphan nor the unmatched entry. *(PT5.3)*
- [ ] 4.9 **RED — B1, B2, B3.** `TapProjectionTests · theSectionCopyIsExactAndDistinguishesTheStates`:
      `.unreported` → exactly **“This Homebrew does not report per-package trust.”**; a decoded report
      with no entries → exactly **“Homebrew records no packages trusted individually.”**; a non-empty
      orphan set → exactly **“Homebrew still records these grants. Cellar shows them; it does not
      remove them.”**; neither report-level state renders the other's copy or a count of `0`; nothing
      describes a grant as expired, stale, inactive or harmless. **RED because** the design's superseded
      strings would fail these byte comparisons. *(PT6.3, PT8.2)*
- [ ] 4.10 **RED.** `TapProjectionTests · theLedgersTapKeyNeverFeedsATrustState`: a ledger naming a tap
      in `taps` changes no badge, no count line and no package category, **even when it names that exact
      tap**; `TapProjection.trust(for:)`'s output is identical for every `TrustGrantState`.
      *(TM12.6, PT4.1's exclusion, DD-9)*
- [ ] 4.11 **RED — D-d, binding.** `TapShippingProofTests · theTapBadgeAndSummaryAreUnchangedByGrants`:
      `trust(for:)` and `packageSummary(for:)` produce byte-identical output for **every**
      `TrustGrantState`; the badge text and the condition producing it are unchanged. *(TM12.7)*
- [ ] 4.12 **RED — PD8.** `TapProjectionTests · aGrantMarksOnlyTheExactPackageItNames`:
      `grantsIndividually(_:publishedBy:in:)` is true only when kind, name **and** tap of origin match
      the entry exactly; a grant for `acme/tools/widget` marks neither `homebrew/cask`'s `widget` nor
      `other/tools`' `widget`; where identity cannot be established exactly the answer is false;
      `noGrantRecorded` and `unreported` both produce **no marker, no placeholder, no muted variant and
      no note**, and no string containing “trusted”. *(PD8.1, PD8.2, PD8.4)*
- [ ] 4.13 **RED — PD8.3.** `TapProjectionTests · theMarkerIsNotAProjectionField`: with a decoded report
      present, the catalog package-detail projection's exposed field set is **exactly** the one PD1
      pins, unchanged, and no field carries a trust state, a grant, a verdict, or a value meaning “this
      download is verified”. *(PD8.3, PD7 preserved by shape)*
- [ ] 4.14 **RED.** `TapProjectionTests · aGrantForAnUninstalledTapIsSurfacedNotDropped`: an entry whose
      owner/repo matches no installed tap appears in the unattributed totals, counted, and never in any
      tap's count. *(PT8.1, R7, D-e)*
- [ ] 4.15 **Prove RED** (all fourteen), then **GREEN**: `TapProjection.swift` — add
      `TapGrantPresentation { countLine: String?, marked: Set<PackageID> }`, `UnattributedGrants` with
      the **five-category** partition (B4: `orphanTapGrants`, `unmatchedFormulae`, `unmatchedCasks`,
      `other`, plus the `excluded` and `attributed` counts and a `total` that sums to the decoded
      count), `TrustGrantSection { unreported, noneRecorded, nothingToShow, unattributed(_) }` (B1),
      `grants(for:in:)`, `grantsIndividually(_:publishedBy:in:)`, `unattributedSection(in:taps:)`, and
      the **one private** `attribute(_:kind:to:)` expressing DD-5's two required conditions, used by
      every caller. Exact copy per B1–B3 and PT5.
- [ ] 4.16 Focused command green **and** every shipped `TapProjectionTests` / `TapShippingProofTests`
      case still green; commit WU4
      (`feat(taps): attribute per-package grants without ever splitting a token`).

## Phase 5: WU5 — the guards and the absences (PM10.7–.9; PT7.2)

Runner: `swift test --package-path Packages/CellarCore --filter 'MutationCommandTests|TapShippingProofTests'`

- [ ] 5.1 **RED — the one deliberate edit to a shipped guard.** `MutationCommandTests ·
      anUntrustedTapNeverPreBlocksAMutation` (`:471-479`): the C1 ban list gains the **single prefix
      token `"TrustGrant"`** (covering all five new type names) **and `"grantsIndividually"`**, and
      `MutationCommand.swift` still contains none of them. Assert the list **covers** those names as a
      full name or shared prefix, so the assertion is about coverage rather than about prose. **RED
      because** the list names only the tap-trust types today. *(PM10.8, D-g, DD-11)*
- [ ] 5.2 **RED.** `MutationCommandTests · aPerPackageGrantStateNeverPreBlocksAMutation`: the same
      package with its per-package state in turn `granted`, `noGrantRecorded` and `unreported`, plus a
      machine whose report **failed to load** — the mutation is built and submitted normally in every
      case, no affordance is disabled, no request is refused and **no warning is attached** on the
      basis of grant state. *(PM10.7)*
- [ ] 5.3 **RED.** `MutationCommandTests · thePerPackageReadIsNotACommandOnTheMutationSpine`: the
      grant read is not one of the spine's command families, enqueues nothing, produces no activity
      item, declares no invalidation domain of its own, and the spine's qualified-token enumeration
      covers **exactly** the families it covered before. *(PM10.9, PT7.2)*
- [ ] 5.4 **Prove RED** (three), then **GREEN**: extend the ban list at `MutationCommandTests.swift`
      `:471-479` with the two tokens, and make 5.2/5.3 pass **without touching**
      `MutationCommand.swift` — the mutation surface must simply never consult the new types.
- [ ] 5.5 **Binding, asserted not assumed.** `MutationCommandTests.swift:500-613`
      (`noPackagePositionEverCarriesAQualifiedToken`, **C2**) is **byte-identical**: verify with
      `git diff main -- Packages/CellarCore/Tests/BrewClientTests/MutationCommandTests.swift` that the
      only hunk is the ban-list edit. Widening C2 to cover the read would change its meaning — the read
      spine's absence is task 2.5's own test. *(PM10.5, D-f)*
- [ ] 5.6 **Binding, asserted not assumed.**
      `git diff --stat main -- Packages/CellarCore/Sources/BrewClient/MutationCommand.swift` →
      **empty output**. A **0-line diff**, as in `m7-tap-trust`. Also confirm
      `Packages/CellarCore/Sources/BrewClient/BrewMutating.swift` and `.../TapCommand.swift` are
      untouched — DD-3 removes the reason to touch either.
- [ ] 5.7 Focused command green; commit WU5
      (`test(mutations): ban the per-package trust types from the mutation surface`).

## Phase 6: WU6 — the four surfaces and the DI wiring (PT5.4; PT7.1, .3; PD8.4; TM12.7)

Runners: `swift test --package-path Packages/CellarCore --filter 'TapShippingProofTests'`,
`xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests/PerPackageTrustCompositionTests`,
and `… -only-testing:cellarUITests/PerPackageTrustUITests`.
`TapShippingProofTests` lives in `Packages/CellarCore/Tests/BrewClientTests/`, so it runs under
`swift test`, **not** `xcodebuild`.

- [ ] 6.1 **RED.** `TapShippingProofTests · noNewControlSubmitsAnythingAndTheSurfaceIsDisplayOnly`:
      `TapManagementAction.allCases` and the pinned `staticButtonLabels` set are **unchanged** (this
      change adds **no action** — TM11 needs no delta); `Button {` is still absent; invoking every new
      surface spawns nothing; every interactive element the per-package surface offers is a navigation,
      filter, copy or refresh affordance and **none** grants, revokes, installs, upgrades or removes
      anything; the enumeration is asserted **non-vacuous**. *(PT7.1, PT7.3, D-f)*
- [ ] 6.2 **RED.** `TapShippingProofTests · everyPerPackageStringIsPositiveAndNeverAVerdict`: every
      string the new surfaces present states a grant Homebrew records or is an accounting of one; none
      is a verdict, ranking or recommendation; nothing inspects, scores or recommends for or against a
      package or a grant. *(PT6.1, PT6.4, TM11.2, R3)*
- [ ] 6.3 **RED.** New file `cellarTests/PerPackageTrustCompositionTests.swift` ·
      `rowHeaderAndRowsReadOneProjection`: the tap list row, the tap detail header **and** the tap
      detail package rows all call `TapProjection.grants(for:in:)`; none computes a count or a marker
      locally; `PackageDetailView` calls `grantsIndividually`. `cellarTests/` is a
      `PBXFileSystemSynchronizedRootGroup`, so the new file needs **no** `project.pbxproj` edit.
      *(PT5.1, DD-6, DD-10)*
- [ ] 6.4 **RED.** `PerPackageTrustCompositionTests · theMarkerIsAdditiveOnThePackageRow`: a `granted`
      **installed** row and a `granted` **withheld-tap** row each carry the exact marker copy
      **“Trusted individually”** *and* each still carries its own unchanged TM1 install-state copy and
      its **Show in Installed** handoff — the marker replaces, suppresses and rewords nothing.
      *(PT5.4, TM1 preserved)*
- [ ] 6.5 **RED.** New file `cellarUITests/PerPackageTrustUITests.swift` (XCUITest, not Swift Testing) ·
      `theCountLineAndSectionAppearOnlyWhenReported`: the count line is present for `.granted` and
      absent for both `.noGrants` and `.unreported`; the “Other trusted packages” section renders its
      three distinct states; the **“Untrusted”** badge text is byte-unchanged in every case. *(TM12.7)*
- [ ] 6.6 **Prove RED** across all three runners, then **GREEN**: `cellar/cellarApp.swift` — construct
      `TrustGrantStore(source:)` (plus `AppTestTrustGrantPayloadSource` under the UI-test flag, mirroring
      the shipped tap idiom), pass it to `TapRefreshCoordinator(grants:)` and to `ContentView`.
- [ ] 6.7 **GREEN.** `cellar/ContentView.swift` — thread the store to `TapsListView`, `TapDetailView`
      and `PackageDetailView`. `PackageDetailView` takes `let trustGrants: TrustGrantStore` (**DD-10** —
      an `@Observable` reference, not a closure and not a pre-computed `Bool`, so the marker updates on
      refresh); update both construction sites, including `#Preview`.
- [ ] 6.8 **GREEN.** `cellar/Taps/TapsListView.swift:52` — the count line as an **added `·` component**
      beside the existing `packageSummary`, never replacing it; plus the “Other trusted packages”
      section rendering `TrustGrantSection`'s four cases (B1: `.noneRecorded` renders its own exact
      sentence — it does **not** render nothing).
- [ ] 6.9 **GREEN.** `cellar/Taps/TapDetailView.swift` :57-65 (header meta component) and :149-180
      (the `"Trusted individually"` marker on package rows), both from the one projection value.
      `cellar/Browse/PackageDetailView.swift:557` — the marker beside the existing `fact("Tap", …)`.
- [ ] 6.10 All three runners green; commit WU6
      (`feat(taps): show individual grants on the tap row, the detail and package detail`).

## Phase 7: WU7 — the doc-only sweep

- [ ] 7.1 `README.md` :44-47 — the qualified-token sweep. **Doc-only**: it writes no spec delta,
      `release-distribution` D-2's canonical three-line install is **untouched**, and no requirement in
      that capability is added, modified, removed or renamed.
- [ ] 7.2 Confirm the sweep changed nothing executable: `git diff main -- README.md` shows prose only,
      and the three-line install block is byte-identical. Commit WU7
      (`docs(readme): describe qualified tokens without implying Cellar grants trust`).

## Phase 8: Verification and bindings

- [ ] 8.1 Full core suite: `swift test --package-path Packages/CellarCore` → the Phase 0 baseline
      **plus** every new case, **0 failures**. Assert counts, never a bare success line.
- [ ] 8.2 App target:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`
      → the Phase 0 baseline plus the new composition cases, 0 failures.
- [ ] 8.3 `xcodebuild test … -only-testing:cellarUITests/PerPackageTrustUITests` → green.
- [ ] 8.4 **Bindings proof.**
      `git diff --stat main -- Packages/CellarCore/Sources/BrewClient/MutationCommand.swift Packages/CellarCore/Sources/BrewClient/BrewMutating.swift Packages/CellarCore/Sources/BrewClient/TapCommand.swift scripts/ .github/workflows/ cellar.xcodeproj/project.pbxproj`
      → **empty output**. `MutationCommand.swift` is a **0-line diff**; any line there means a gate or a
      new domain was added. Confirm no new `InvalidationScope` member exists anywhere. A deviation is
      reported before merge, never absorbed.
- [ ] 8.5 **Regression guards that must never have moved**: `MutationCommandTests:500-613` (C2,
      byte-identical), `TapProjection.trust(for:)` and `packageSummary(for:)` output, the shipped
      TM12.1–.5 and PM10.1–.6 assertions, `TapShippingProofTests`' `Button {` ban and
      `staticButtonLabels` set.
- [ ] 8.6 `git diff --stat main` for the whole branch — record the authored total, **split into the
      code+test bucket and the artifact bucket**, and compare each with its own forecast
      (2,736–3,312 and 1,900–2,300). A large miss is information for the next forecast, not a failure.
      **This is the m7 learning-E follow-through: the artifact bucket is measured separately.**
- [ ] 8.7 Open the PR(s) per the resolved chain decision. The body states up front: (a) this change
      **grants and revokes nothing** — it shows what `brew trust --json v1` already reports; (b) a
      per-package grant **survives an untap**, so an orphan grant re-arms on a re-tap and Cellar shows
      it without claiming to close it (R7); and (c) on a Homebrew without the `trust` verb every
      surface renders **nothing**, never “0 grants” (R4).

## Phase 9: `manual-evidence` (maintainer's Mac, Homebrew 6 — not merge blockers, not test tasks)

> **BINDING — never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (obs `#7724`).

Each transcript is captured **verbatim into the verify report** — the artifact that carries evidence in
this repository.

- [ ] 9.1 **ME1 — PT4.5.** Capture the raw `brew trust --json v1` payload, run the read again, and
      compare the payload's entry count with the count Cellar's accounting produces: they MUST be
      equal. Hash and stat `trust.json` before and after: **byte-identical**, so the read granted
      nothing. Both counts and the captured payload go in the verify report.
- [ ] 9.2 **ME2 — PT8.3.** With a third-party tap installed and one of its packages granted
      individually and listed by `brew trust --json v1`: untap that tap from inside Cellar, read the
      report again, and confirm the package entry is **still listed** and that Cellar presents it as an
      orphan or unmatched grant rather than dropping it.
- [ ] 9.3 **Not re-run here.** `package-mutation` PM10's two `manual-evidence` scenarios (the formula
      refusal wording; a real refusal rendering the typed outcome) were captured in `m7-tap-trust`
      Phase 9 and survive **byte-identical** in this delta. Record that they are carried forward, and
      do **not** re-execute them for this change.
- [ ] 9.4 Record that the probe blocking design Open Question 2 is **already CLEARED** by measurement
      (obs `#7764`, 2026-08-24) and MUST NOT be re-run as a gate. Open Question 3 (does the report ever
      publish an **unqualified** entry?) is answered opportunistically by 9.1's payload; if unqualified
      entries turn out to be common rather than theoretical, the section copy needs one more sentence
      and **no code change**.

## Phase 10: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [ ] 10.1 `package-trust` is **established** by this change: create
      `openspec/specs/package-trust/spec.md`, promote the eight ADDED requirements in order as
      **PT1–PT8**, add the file header, the `## Requirements` wrapper, and a `## Provenance` section
      recording this change, its binding decisions and what each rejected (per-package grant/revoke
      controls; extending `tap-info`; a dedicated invalidation domain; any negative per-package copy).
- [ ] 10.2 Promote the three MODIFIED/ADDED blocks as **whole-block replacements**: TM12 into
      `tap-management` (→ 13 req / 57 sc, TM1–TM11 and TM13 untouched), PM10 into `package-mutation`
      (→ 10 req / 63 sc, PM1–PM9 untouched), and PD8 appended after PD7 in `package-detail`
      (→ 8 req / 30 sc, PD1–PD7 byte-identical).
- [ ] 10.3 Record in provenance: the argv prohibition was **reaffirmed, not relaxed** (C2 unchanged;
      the C1 ban list extended — the one deliberate guard edit); **DD-3** adds **no new invalidation
      domain**; and **PD8 is expected to render nothing** on today's shipped surface (PD6), existing so
      the bare-name hazard is impossible to ship.
- [ ] 10.4 Record the measured payload facts PT4 rests on (obs `#7764`) — namespaces **not disjoint**,
      `@` in names, present-and-empty namespaces, side-effect-free read — because they are cheap to lose
      and expensive to re-derive, and the captured payload **is** the fixture.
- [ ] 10.5 Record the deferrals: per-package grant/revoke controls stay out of scope until the
      `brew untrust --formula|--cask <qualified>` probe answers whether the revocation itself registers
      a grant through `explicitly_allowed?` before removing it; and `BrewfileDiff.isPresent` (**R15**)
      is deliberately not in this change.
- [ ] 10.6 Record the **five binding reconciliations B1–B5** as design-vs-spec deviations resolved in
      the spec's favour, so a future reader does not mistake `design.md`'s superseded copy and
      three-category accounting for the shipped shape.
