# Archive Report: M4 Security

`m4-security` closed PRD milestone **M4** on 2026-08-06. The change shipped two new capabilities
(`vulnerability-scanning`, `artifact-integrity`), narrowed one existing capability's structural
guarantee (`local-package-metadata`), passed independent verification with zero CRITICAL findings,
merged to `main` as PR #15, and moved to the dated OpenSpec archive.

The defining result of the milestone is not the feature. It is that **four defects were found by a
human running ten manual-verification checks against a suite of 1,090 green tests that could not see
any of them** — each sat at a boundary *between* individually tested layers. That is recorded below
as the milestone's carried lesson, not as a footnote.

## Closure Status

| Check | Final state |
|---|---|
| Requirements | 15/15 COMPLIANT |
| Scenarios | 28/28 COMPLIANT — zero UNTESTED, FAILING or PARTIAL |
| Tasks | 113/113 checked in the archived `tasks.md`; zero unchecked; no reconciliation needed or authorized |
| Verification | **PASS** — 0 CRITICAL, 2 WARNING, 3 SUGGESTION |
| Manual verification | 10/10 MV checks run live by the user on a real build (Engram 7458–7466) |
| Delivery | Merged to `main` as **PR #15** at `b9e8f5b` (2026-08-06); feature branch deleted |
| Delivery policy | Receipt-driven development **off, decided by `clone_local`**; ordinary repository policy |
| Review authority | **No receipt exists for this candidate**, by user decision — see *Delivery Record* |
| Size policy | Maintainer-approved `size:exception`, recorded and then reconfirmed against the measured number |

`reviewGate` is structurally absent because the kill switch is off for this clone. There is no
`disabled/unmanaged` value to check and no receipt was required. Archive proceeds under ordinary
repository policy. Nothing was silently approved: the green gates and the verify report below are the
evidence standing in place of a receipt.

## Scope Shipped

**ADDED `vulnerability-scanning`** — 8 requirements / 14 scenarios. Advisory acquisition (OSV
`querybatch` discovery over a curated, fixture-tested formula→ecosystem table; NVD enrichment by
`cveIds` only, never per-package discovery), a four-state `CVEScanOutcome` in which `notCovered` and
`unavailable` are structurally incapable of collapsing into "clean", severity tiering with a real
`unrated` bucket, fix-version semantics gated on strict SemVer on both sides, dismissal, provenance
and freshness, offline-readable caching, and opt-in consent with a plain transmission disclosure.

**ADDED `artifact-integrity`** — 6 requirements / 8 scenarios. Read-only, unprivileged,
subprocess-free visibility into signing identity, notarization verdict, and quarantine/provenance
extended attributes for brew-managed artifacts, with an explicit "could not assess" that is neither a
pass nor a fail. No clearing or remediation affordance exists in v1.

**MODIFIED `local-package-metadata`** — 1 requirement / 6 scenarios (5 pre-existing, 1 new). Snooze
behaviour is unchanged — equality is still the whole rule. What changed is the *scope* of the
no-comparator guarantee: `m4-security` introduces a strict-SemVer comparator inside
`vulnerability-scanning`, so the repository-wide absence claim became false. The requirement narrows
it to reachability from this capability and the structural guard was **extended, not weakened**.

**Not shipped, deliberately**: quarantine clearing, cask CVE scanning, a Homebrew version comparator,
per-package NVD discovery, a local advisory index (declared **v1.1**), `/Applications` sweeps (M5),
and any new `BrewMutating` family — the security upgrade is the existing `MutationCommand.upgrade`.

## Specs Synced

| Domain | Action | Result |
|---|---|---|
| `vulnerability-scanning` | **Created** | Promoted the full 8-requirement / 14-scenario specification byte-for-byte to `openspec/specs/vulnerability-scanning/spec.md`. The apply-time amendment survives verbatim: the dismissal key's first component is `advisoryID`, not `cveID`, carrying its struck-through original and the Deviation-39 rationale note. |
| `artifact-integrity` | **Created** | Promoted the full 6-requirement / 8-scenario specification byte-for-byte to `openspec/specs/artifact-integrity/spec.md`. |
| `local-package-metadata` | **Updated** | Replaced 1 requirement as a whole block and added 1 scenario. 7 requirements / 21 scenarios → **7 requirements / 22 scenarios**. All six unrelated requirements are byte-identical, **all five pre-existing snooze scenarios survive unchanged**, and the replacement is a strict superset of the text it replaced. A provenance bullet records the amendment. |

The `advisoryID` amendment is preserved rather than tidied because the reasoning is the value: `GHSA-`,
`RUSTSEC-` and `PYSEC-` advisories routinely publish no CVE alias, so a `cveID`-keyed dismissal would
file every unaliased finding for one package at one version under the empty string — dismissing one
would silence findings the user never answered.

## Final Gates (measured at the merged candidate)

Every number below was re-measured by `sdd-verify` at `b0b9467`, not copied forward from apply. Both
`b0b9467` and the verify-report commit `daffc2e` are in `main` via the PR #15 merge at `b9e8f5b`.

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1090 tests / 152 suites passed**, 1 pre-existing known issue, 0 failures, exit 0 |
| `xcodebuild build` | BUILD SUCCEEDED, **zero** concurrency/Sendable warnings, exit 0 |
| `xcodebuild test` | `cellarTests` **32 cases / 5 suites**; `cellarUITests` **20 executed / 0 failures** (incl. both `SecurityIdentityUITests`), exit 0 |
| `swiftlint --quiet` | **117** — one *below* the 118 baseline; the shell-preview relocation re-wrapped a pre-existing 126-char line. Zero authored findings. Not drift. |
| File length | Zero new `.swift` files over 400 lines |
| Tasks | 113 checked / 0 unchecked, counted from the file |
| Validator | `gentle-ai sdd-verify-validate --requirements 15 --scenarios 28` → `valid: true, verdict: pass`; admitted bytes are the persisted bytes (sha256 `c00a918e…`) |

Design conformance was re-verified independently rather than accepted from the record: `Package.swift`
edges exact (`SecurityKit → ["Catalog"]`, `Persistence → ["BrewClient","SecurityKit"]`,
`BrewClient → ["BrewProcess","Catalog","DiskUsage"]` with **no** SecurityKit); four-state
`CVEScanOutcome` with **no `isClean` accessor**; `NotCoveredReason` exactly three cases;
`EcosystemMapping` seven fingerprinted entries; `NVDSource` enriches by `cveIds` only, with no path
taking a package name; `ScanConsent.authorise()` **throws** rather than returning `Bool`; Keychain
seam with `kSecAttrAccessibleAfterFirstUnlock`; **zero** `removexattr`/`setxattr` call sites; **zero**
`SecAssessmentTicketLookup` call sites; `String` appears in `FixVersionComparison.swift` exactly once
and only in a comment; **zero** `@unchecked Sendable` / `nonisolated(unsafe)`; `DismissalStore.swift`
is the sole Persistence importer of SecurityKit.

Assertion quality: **zero tautologies**; 899 `#expect`/`#require` in `SecurityKitTests` plus 83 in
`cellarTests`; the 6 empty-collection assertions all carry companion non-empty tests; no ghost loops,
no smoke-only tests, no type-only-alone assertions.

## Manual Verification Evidence

Ten of ten MV checks passed on a real build, on this machine, executed by the user rather than by an
agent (Engram observations 7458–7466). The three that describe what the feature actually is, carried
verbatim:

- **MV-3 — the feature's honest self-description.** Vulnerable **0** (rendered as an explicit "0"),
  Not covered **163**, Clean **7**, Unavailable **0**. The Clean 7 are exactly the seven curated
  mapping entries (`bat`, `eza`, `ripgrep`, `sd`, `uv`, `protobuf`, `llhttp`). Against a ~170-package
  inventory that is **≈4.1% real coverage**, inside the 3–5% band probe U1 predicted and the band the
  feature was sized against. The typed-coverage design exists precisely so this number can be shown
  rather than hidden.
- **MV-6 — volume follows findings, not inventory.** Exactly **one** TCP connection from the process
  (`192.168.1.125:55556 ↔ wa-in-f121.1e100.net:443`, Google-hosted `api.osv.dev`), **zero** NVD
  connections, ~6.7 KB in / 4.8 KB out. **One request against a ~170-package inventory.**
- **MV-7 — identity parity.** All three signing-identity fields are literal matches against
  `codesign -dv --verbose=4`, obtained without Cellar spawning anything.

**MV-4 is recorded with its limit stated rather than overclaimed**: the user held zero snoozes and
zero notes before migrating, so history survival is the complete real-store proof and the
snooze-suppression half is **vacuously satisfied**. `MigrationTests` against real SQLite covers that
half instead. This is one of the two non-blocking verify WARNINGs.

## The Four MV-Found Defects

Each defect sat at a boundary *between* tested layers. Each layer was individually tested; the
boundary past it was not. The suite reached 1,090 green tests without any of them being catchable.

| Defect | What was missing | Fixed in |
|---|---|---|
| `caskArtifacts: [:]` — 468 artifacts located, zero casks among them | **supplier** | `b92f071` |
| Identifier and chain reached the report; the view never read them | **consumer** | `3410e45` |
| The identity disclosure drew no indicator and took no click | **interaction** | `e4de71d` |
| A container's `accessibilityIdentifier` overrode its descendants' | **addressability** | `e4de71d` |

Recorded as Deviation 71. The lesson is about where this change put its tests, not about any one bug:
layer-local tests plus a green suite prove nothing about an end-to-end path. Verify independently
confirmed the pattern held — the prohibition guards and value projections are excellent, and every gap
was at a wiring seam.

## Deviations

**73 recorded deviations**, numbered 1–73 contiguously in the archived `apply-progress.md`. Verify
checked ~73 of them in **both directions** and found **no unrecorded divergence**: every
`SecurityKit`/`cellar/Security` file absent from the design's file table maps to a numbered deviation
or a task (`AdvisoryQuery` 10, `SecurityScanEvents` 33, `SecurityScanPipeline` 57,
`SecurityFindingPresentation` 45, `ArtifactSignatureModels` batch-5 lint split, `SecurityPreviews` 60,
`ArtifactIntegrityStore` 56, `SecurityKit.swift` task 1.7, `SecurityPresentation` task 16.3,
`ArtifactIdentityPresentation` batch-5 third corrective).

Deviations worth carrying forward as project conventions:

- **U3 is CLOSED, and not the way the design guessed**: `SecAssessmentTicketLookup` is *absent from the
  public macOS 26.5 SDK*, not merely privileged. Non-stapled notarization is therefore
  `.couldNotAssess(.assessmentUnavailable)` — a weaker feature, not a different architecture.
- `CVEScanOutcome` is `.covered(.findings(…))` / `.covered(.clean(…))`.
- `SecurityScanEngine` takes `AdvisoryScanRequest { queries, predecided }` — building entries only for
  queried packages left ~150 of 159 formulae off the surface entirely.
- A container's `accessibilityIdentifier` overrides every descendant's (Deviation 69).
- A batch's `apply-progress` section records what was true when written and is **never** edited by a
  later batch (Deviation 59).
- Absence claims must be mutation-proven: three separate guards passed against their own mutations on
  first writing and had to be rewritten.
- **The declared task count was five short for five batches** (Deviation 72). The plan said "108" from
  `sdd-tasks` onward while the file always held 113 checkboxes, so every earlier batch reported against
  a wrong denominator. Corrected in place at 18.1; the work never changed, only the arithmetic.

## Delivery Record

- **Merged to `main` as PR #15** at `b9e8f5b` — *"feat(security): M4 — vulnerability scanning,
  artifact integrity, and honest coverage"* — on 2026-08-06, carrying 31 commits. The local feature
  branch was deleted.
- **Single PR under a recorded and reconfirmed `size:exception`** (Engram 7456). Chained PRs were
  recommended by both the tasks forecast and the orchestrator, and declined by the user.
- **Size measurements, reconciled**: forecast 11,600–14,600 changed lines against a 5,000-line session
  budget. Measured at the verify candidate `b0b9467`: 147 files, 22,972 insertions / 184 deletions =
  **23,156 changed lines**, the figure the `size:exception` was reconfirmed against. The merged PR is
  148 files, 23,367 / 184 = **23,551**; the difference is exactly the verify-report commit `daffc2e`
  (+395), which landed after the reconfirmation. **1.6× the top of the forecast band, 4.7× the
  budget** — the fourth consecutive under-price and the widest yet. Largest miss in proportion:
  `openspec/` at 3,929 lines against 800–900 = **4.4×**. Measured rule for next time: price docs at
  ~4× the intuitive figure past three work-unit batches, and carry a manual-verification defect
  contingency (~600 lines here existed only because two MV checks failed).
- **Receipt-driven development: no receipt exists for this candidate, by user decision.** A review
  start created lineage `review-81b740ee85f5bca7` that negotiated `status --next-transition` could not
  route — an upstream provider defect (Engram 7469). The user declined to file the defect report and
  disabled RDD clone-locally; `review mode status` reads **off / `clone_local`**. Delivery proceeded
  under ordinary repository policy. This is recorded as fact, not as approval: nothing about this
  change was reviewed by a receipt, and the green gates plus the verify report are the evidence in
  its place.

## Open Questions Carried to v1.1

Registered rather than closed, per Deviation 73 and task 18.4. **None is a defect in what shipped**,
and none should disappear because the milestone ended.

1. **The ~4% coverage ceiling.** Seven of ~170 packages are answerable today. This is the honest limit
   this release ships with, and the whole typed-coverage design exists to state it rather than hide
   it. **Declared fix: the v1.1 local advisory index**, already named as a non-goal in the proposal.
2. **The mapping table's growth path.** U1 proved that name matching is dominated by identity
   collisions, which is why the table is curated data rather than inference. There is no safe growth
   procedure yet — adding entries by hand does not scale, and heuristics were rejected for cause.
3. **Stale-cask artifact visibility.** `the-unarchiver`-shaped casks yield no artifact at all, where a
   visible "not assessable" row would serve the user better than silence. Pinned by the passing test
   `aStaleCaskroomDirectoryShellYieldsNothing`, so the behaviour is specified and locked rather than
   accidental.

## Verify Warnings and Suggestions (non-blocking, closed as recorded)

- **WARNING** — Deviations 11 and 37 are test-after-code cycles. Both were closed by mutation proof
  and recorded plainly rather than dressed up as TDD.
- **WARNING** — MV-4's snooze half is vacuously satisfied (see *Manual Verification Evidence*).
- **SUGGESTION** — the reconfirmed `size:exception` (22,887) trailed HEAD's 23,156 by 269 doc-lines;
  reconciled above.
- **SUGGESTION** — price `openspec/` at ~4× past three batches and carry an MV-defect contingency.
- **SUGGESTION** — adopt the Deviation-71 rule: assert that something real is plugged into every seam,
  not merely that the seam resolves what it is handed.

## Engram Traceability

The following full observations were read (not previews) and used:

| Artifact | Observation |
|---|---:|
| Proposal | #7449 |
| Proposal-round decisions | #7450 |
| Specification | #7452 |
| Design (rev 2) | #7453 |
| Design gate | #7454 |
| Tasks | #7455 |
| Delivery decision (`size:exception`) | #7456 |
| Apply progress | #7457 |
| MV-0…MV-10 live results | #7458–#7466 |
| RDD provider defect | #7469 |
| Verify report | #7470 |
| This archive report | `sdd/m4-security/archive-report` |

## Mechanical Archive Evidence

Every artifact was copied and moved with `cp`/`mv`/`git mv` only; no file content passed through a
Read→Write path. Every `diff -r` readback was empty. The archive move comparison happened against a
pre-move recursive snapshot, before this additive report was created.

### `vulnerability-scanning` delta → temporary

```text
```

### `vulnerability-scanning` delta → `openspec/specs/vulnerability-scanning/spec.md`

```text
```

### `artifact-integrity` delta → temporary

```text
```

### `artifact-integrity` delta → `openspec/specs/artifact-integrity/spec.md`

```text
```

### `local-package-metadata` delta requirement block → merged candidate block

```text
```

### `local-package-metadata` main head (lines 1–119) → merged head

```text
```

### `local-package-metadata` main tail (lines 164–end) → merged tail

```text
```

### Merged candidate → installed `openspec/specs/local-package-metadata/spec.md`

```text
```

### Change source → pre-move recursive snapshot

```text
```

### Pre-move recursive snapshot → archived destination

```text
```

The merged `local-package-metadata` spec was assembled by byte-slicing rather than by regeneration:
`head -n 119` of the original main spec, then the delta file's requirement block verbatim
(`tail -n +5`), then `tail -n +164` of the original. The head, tail and inserted block were each
diffed independently against their sources and all three diffs were empty, so the only authored bytes
in that file are the additive provenance bullet.

## Archive Integrity

- Archived at `openspec/changes/archive/2026-08-06-m4-security/`.
- Proposal, exploration, design, tasks, all three specs, apply progress and the final verify report
  are present.
- The active source directory `openspec/changes/m4-security` is gone.
- Archived tasks remain **113/113 checked**; no reconciliation was needed or authorized.
- `openspec/changes/m3-4/` and `openspec/changes/m3-services-cleanup-taps/` remain separate active
  artifacts and were neither moved nor modified.
