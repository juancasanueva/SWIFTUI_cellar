# Proposal: Health Dashboard, `brew doctor` & Bulk Pin/Snooze (`m5-health`)

Anchors PRD.md **M5 "Pro-parity flows"** (§7); features **§3.4 "Health (dashboard)"**, **§3.2
"Bulk operations"** (pin/snooze half), **§5** (sidebar), and settles **§9 Q5** (`brew doctor` parsing
depth). Slice **5 of 5 — the FINAL M5 slice**. Exploration:
`openspec/changes/m5-health/explore.md` (Engram obs 7530). Probes U10, U11, U12, U14 executed and
reported (obs 7531; U13 skipped as unnecessary, U15 deferred to verify). Product decisions 1–4 taken
by the maintainer (obs 7532) and binding.

## Intent and Users

Cellar can already answer eight separate questions about a Mac's Homebrew installation — what is
outdated, what is vulnerable, what is orphaned, what duplicate versions squat in the Cellar, how big
the cache is. It answers each of them on a different screen, on demand, and never together. A user who
wants to know *"is my setup healthy right now, and what should I do about it?"* has to visit five
sections and hold the answers in their head.

This slice delivers the one surface that answers that question at a glance: a Health section that
composes the five resident signals, adds the two that are genuinely missing (**how stale is Homebrew
itself**, and **what does `brew doctor` say**), projects a transparent 0–100 composite score over
them, and puts the already-shipped remediation verbs one click from the row that motivated them.

It also closes the PRD's bulk-operations promise. §3.2 lists **pin** and **snooze** as bulk verbs;
they were deliberately narrowed out on 2026-08-02 and the maintainer has now **reversed that ruling**.
Health is where "remediate everything at once" belongs, so the reversal ships here.

M5 closes with this slice. Every deferral below is a **recorded v1.1 item**, not an implication.

## Binding Invariants

### 1. The doctor payload rule — a deliberate, quarantined double inversion

`brew doctor` inverts **both** rules the three shipped JSON payload sources
(`InstalledPayload` / `ServicesPayload` / `TapPayload`) hold as absolute. Probe U10 measured it on
this machine: **exit 1 with warnings present, stdout = 1 byte (a bare newline), the entire 622-byte
payload on stderr**, byte-identical across two consecutive runs.

- **A non-zero exit is an ordinary outcome carrying the document**, never a failure. This is not a
  violation of the layer below — `brew-execution`'s *Terminal result and exit handling* already says
  "a non-zero status MUST NOT be raised as a thrown error, **because `brew` uses exit codes
  semantically**". That sentence licenses this slice verbatim; `brew-execution` is **not modified**.
- **The document arrives on stderr.** The trio's rule ("stderr never enters the document, at any
  position") is correct for a JSON document and wrong for doctor. Both streams are preserved
  verbatim, separately, and never concatenated.
- **The rule is quarantined to the doctor capability.** A structural test MUST prove
  `InstalledPayload` / `ServicesPayload` / `TapPayload` still reject non-zero exits and still admit
  only stdout, so a future "simplification" in either direction fails a test rather than a review.
- Doctor is classified **`.read`** — U14 confirmed it mutates nothing (FETCH_HEAD mtime identical
  before and after two runs under Cellar's pinned `HOMEBREW_NO_AUTO_UPDATE=1` environment).

### 2. Score honesty

- The score is a **pure function** of a `HealthInputs` value: no store, no clock, no I/O, no network,
  no subprocess. Every branch is unit-testable without a fixture or a process.
- **`unknownInputs` is structurally inseparable from the number.** `HealthScore` MUST be
  unrepresentable without it (the shipped `DiscoverSectionState` technique), so no surface can render
  the value while dropping the caveat.
- **`notCovered`, `unavailable`, `unknown` and `partial` NEVER map to clean.** `CoverageTotals`'s own
  doc comment records why ("the summary can still read '0 vulnerabilities' over an inventory nobody
  could answer for"); a single number is the one surface where the user cannot see the substitution.
- **Weights are visible in the breakdown.** Each contribution names its input, its weight and its
  penalty, so the number is arguable and falsifiable rather than authoritative.

### 3. Layering

- **No core target may see both `BrewClient` and `SecurityKit`** except `Persistence`. The score
  therefore computes over injected scalars in a dependency-free position; composition happens in the
  **app target**, exactly as M4 composed the same two.
- **Health is a pure projection**, in the shipped `DiscoverProjection` idiom: `@concurrent static func`
  over already-resident values. **No `HealthStore` that polls** — rendering the section triggers no
  request, no subprocess, no sync. Health owns **only the two new acquisitions** (doctor, last-update).
- `BrewClient` MUST NOT link SwiftData. Bulk snooze stays app-side (see below).

### 4. The last-update reader is invocation-free

`${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD` is what Homebrew's own `auto-update.sh` stats to decide "how
old is Homebrew", so its mtime is not a heuristic Cellar invented (U12 confirmed it moves with a real
auto-update). Resolution costs **zero brew invocations**: probe `<prefix>/Homebrew/.git` (the
`/usr/local` shape PRD §3.9 explicitly supports) then `<prefix>/.git`, in that order — U11 validated
both arms. The reader returns **typed cases — read / absent / unreadable / future-dated — and MUST
NOT invent a `Date`** (no `distantPast`, no negative age). It needs a **new, narrow file-metadata
seam** sized like `ReleaseNotesFileAccess` (one protocol, one `System…` implementation), because
neither `CatalogFileSystem` nor `ReleaseNotesFileAccess` exposes a modification date today.

## Scope

**In:** a `brew doctor` acquisition (`.read`) with a `DoctorOutcome { clean | issues | unavailable }`
over a `DoctorEvidence` built in the `CleanupEvidence` idiom (raw stdout/stderr verbatim, counted
`Warning:` grouping, `unknownLines: [Data]`, typed parse issues, `isPartial`, parser provenance); the
invocation-free last-update reader and its file-metadata seam; a pure `HealthScore` value type over
`HealthInputs` with contributions and `unknownInputs`; a `HealthProjection` composing the five
resident signals plus the two new ones; a **tenth `AppSection` case `.health`, placed between Services
and Security, with **Home retained** as the landing section**; per-row one-click remediation reusing
only shipped verbs (`MutationCommand.upgradeAll`, `CleanupCommand(.autoremove)`,
`CleanupCommand(.global)`, re-run doctor); **bulk pin and bulk unpin as two independent verbs** in
`BulkSelection.Action`, each with its own eligibility projection; **bulk snooze via its own app-side
path**; the II13 reversal delta; byte-exact `Fixtures/Doctor/` to the `Fixtures/Bundle` standard.

**Out (non-goals; each is a recorded v1.1 item, not an omission):** background/periodic health
re-checks, notifications and the menu-bar health badge (PRD §3.8, **M6**); the disk treemap (§9 Q4,
explicit v1 stretch); `brew doctor --list-checks`-driven per-check attribution (approach 7a-C —
**unnecessary**, U10 proved the grouping byte-stable); historical health trend or score over time;
any *new* remediation verb (no `brew doctor --fix` exists — doctor never fixes anything); a
`brew update` remediation (it would be a `.mutate` and §3.4 does not list it); quarantine/codesign
rows (M4 shipped those on Security; §3.4 does not list them); a second "API catalog last downloaded"
row from the `jws.json` mtime (a different question, differently labelled); folding Home into Health;
any new SwiftPM target; any `CatalogPackage` / `CatalogSnapshot` / `currentSchemaVersion` change;
adopting or extending `cellarTests/SecurityCompositionSupport.swift`'s false-zero
`CompositionRequestSpy`.

## Capabilities

- **New `system-health`** (ADDED-only) — the doctor acquisition and its inverted-and-quarantined
  payload rule with its stated reason; the doctor evidence model, grouping and unknown-line counting;
  the last-update reader's typed cases and invocation-free resolution; the score's purity,
  `unknownInputs` inseparability, no-unknown-counts-as-clean rule and weight transparency; the
  projection's no-new-acquisition guarantee; the remediation vocabulary and the "doctor re-measures,
  fixes nothing" copy rule. Its **Provenance** records that the doctor exit-code rule is *licensed by*
  `brew-execution`'s existing semantic-exit-code sentence rather than contradicting it — so
  `brew-execution` itself stays **untouched**.
- **Modified `installed-inventory` (DESTRUCTIVE)** — *Multi-select is explicit, ordered, and offered
  only for bulk-eligible verbs* (spec.md:490) and its scenario *Only upgrade and uninstall are offered
  for a selection* (:531–536) are **rewritten, not extended**: a prohibition is being removed, so the
  delta is genuinely not a superset. See "The II13 sc4 reversal" below. *A bulk action's label counts
  exactly the set it submits* (II14, :544) applies unchanged to the new verbs' counts.
- **Modified `local-package-metadata` (likely)** — *A snooze is scoped to a version, never to a
  duration* (:94) and *A snooze suppresses the outdated badge until the offered version changes*
  (:120) re-read for a bulk snooze: N packages record N *different* version strings, and the copy MUST
  NOT imply one duration. The existing structural test asserting no comparator is reachable from
  snooze MUST still pass.
- **Read from, unmodified:** `brew-execution`, `vulnerability-scanning`, `cleanup-operations`,
  `disk-usage`, `package-mutation`, `operation-activity`, `service-management`.

## The II13 sc4 reversal — a deliberate destructive spec modification

Requirement II13 currently states "pin, unpin, snooze, favorite and note MUST offer **no** bulk
affordance", and its Provenance (spec.md ~:680) records that PRD §3.2's pin and snooze "were
**deliberately narrowed out** (settled 2026-08-02) — the restriction is proven exhaustively over
`BulkSelection.Action.allCases`". **The maintainer has reversed that ruling** (obs 7532, decision 1).

This proposal names it as what it is: a **destructive delta into a shipped main spec**, firing
`openspec/config.yaml` `rules.archive` ("Warn before merging destructive deltas"). Slice 4 established
the method for that path and it is reused: byte-slice the exact replaced ranges and diff them, treat
the delta's claims as claims to be tested. The rewritten requirement MUST preserve everything the old
one carried that is *not* being reversed — selection ordering, the leave-the-inventory rule, and above
all **"a bulk control that cannot act on the current selection MUST be unavailable rather than
inert"** (II13 sc5), which is exactly what forbids guessing on a mixed pinned/unpinned selection.
Favorite and note stay prohibited.

**Two tests pin it and both are REWRITTEN, never deleted:**

| Test | Why it breaks | Required outcome |
|---|---|---|
| `BulkSelectionTests.swift:70–79` `onlyUpgradeAndUninstallAreBulkEligible()` | Asserts `allCases == [.upgrade, .uninstall]`, `count == 2`, **and loops the joined lowercased titles for `pin/unpin/snooze/favorite/note`** — the title scan fails on `case pin` even after the count is fixed | Becomes an exhaustive assertion over the **new** vocabulary `[.upgrade, .uninstall, .pin, .unpin]`, still proving snooze/favorite/note are absent from the enum |
| `ServiceSubmissionTests.swift:213–231` `theInstalledBulkVocabularyIsUnchanged()` | A **services** test (about `service-management` SM4 sc5) that re-asserts the same two-case vocabulary to prove no service verb leaked into the package enum | **Its intent survives the widening** and MUST be preserved: rewritten to assert no *service* verb entered `BulkSelection.Action`, not that the vocabulary is frozen |

`ServiceRowControl.allCases.count == 5` in the same file is unaffected and MUST stay at a zero diff.

## Approach

**Bulk pin and unpin are two verbs, not a toggle** (decision 1). Each gets its own eligibility
projection alongside the existing `upgradable` / `uninstallable` id lists, and each is **unavailable
rather than inert** when it cannot act. Both travel the shipped spine untouched:
`MutationCommand.pin(formula:)` / `.unpin(formula:)` already exist, are formula-only by construction,
and `OperationCenterBulk.request`'s doc comment already records that pin and unpin **require no
confirmation** — so no confirmation sheet, no `ConfirmationDisclosure` change, no touch to the DD1
`first.disclosure` fix. The work is one `case` in two exhaustive switches plus two eligibility rules.

**Bulk snooze ships on its own app-side path** (decision 2) and **NEVER enters `BulkSelection.Action`
or `OperationCenter`**. It spawns no process, submits no operation and writes no history entry; it
calls `MetadataStore.snooze(_:offering:)` per package with that package's own offered version. The
enum's only consumer, `OperationCenterBulk.commands(for:over:) -> [MutationCommand]`, **cannot
represent snooze** — a `case snooze: []` arm would be a silent no-op the type system could not catch —
and `MetadataStore` lives in `Persistence` while `BulkSelection` lives in `BrewClient`, which must not
link SwiftData. The copy says what it does ("snooze until a new version is offered"), never a
duration: `createdAt` is provenance, never policy.

**Doctor is approach 7a-B**, settled by measurement rather than preference. U10 proved the `Warning:`
grouping byte-stable across consecutive runs, which is the explore's own stated condition for **not**
needing 7a-C. This settles PRD **§9 Q5** in the only way that satisfies both readings: §3.4's "warnings
parsed and grouped, full output viewable" *and* §9's "start raw" — raw bytes preserved verbatim, a
counted grouping projected over them, and every unparsed line carried in `unknownLines: [Data]` rather
than dropped. Elapsed time is 2–3 s, so no long-running-progress UI is needed. The **clean-case
fixture must be hand-authored and visibly marked as such** (this machine has real warnings and cannot
produce an exit-0 capture) per the `Fixtures/Bundle` captured-vs-authored separation.

**"Run doctor" is a remediation row whose copy tells the truth**: it **re-measures and fixes nothing**.
Homebrew's own manpage de-emphasises its output — "these warnings are just used to help the Homebrew
maintainers with debugging if you file an issue" — and that framing MUST reach both the copy and the
score's weighting. A dashboard that renders doctor warnings as *the user's problems* overstates them.

**Sidebar: `.health` is a tenth `AppSection` case between Services and Security, and Home stays**
(decision 4). The explicit slice-5 TODO at `cellar/Shell/AppSection.swift:17–20` ("moving it is slice
5's decision, once the Health dashboard exists (D4)") **resolves as "keep Home"** and MUST be recorded
as resolved rather than deleted. `cellar/Health/` lands as a `PBXFileSystemSynchronizedRootGroup`, the
pattern proven twice, for a **0-line `project.pbxproj` diff**.

| Area | Impact |
|---|---|
| `Sources/BrewClient/DoctorCommand.swift`, `DoctorSource.swift`, `DoctorParser.swift`, `DoctorEvidence.swift`, `DoctorOutcome.swift` | New — own documented payload rule |
| Last-update reader + new narrow file-metadata seam (`ReleaseNotesFileAccess`-sized) | New — target choice open at design; **must not widen `DiskRootsIdentity`** without checking `DiskUsageCache.load`'s `schemaVersion == 1` gate |
| `HealthInputs`, `HealthScore`, `HealthContribution`, `HealthProjection` | New — dependency-free position, composed in the app target |
| `Sources/BrewClient/BulkSelection.swift` | Modified — `Action` widening + two new eligibility projections |
| `Sources/BrewClient/OperationCenterBulk.swift` | Modified — `commands(for:over:)`, `submitBulk`, and the doc comment that currently *explains* the two-case restriction |
| `cellar/Installed/BulkActionBar.swift` (8 call sites, **no covering tests**), `InstalledListView.swift` (11) | Modified |
| `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellar/cellarApp.swift` | Modified — tenth case, exhaustive arm, composition |
| `cellar/Health/` | New — synchronized root group, **0-line pbxproj diff** |
| `Tests/BrewClientTests/Fixtures/Doctor/` | New — byte-exact, `probe-manifest.txt`, per-stream SHA-256, captured/authored visibly separated |
| `Packages/CellarCore/Package.swift`, `cellar.xcodeproj` | **Untouched** |

## Probe Gate — closed

| Probe | Result |
|---|---|
| **U10** (decisive) | exit 1 with warnings; **stdout 1 byte, entire payload on stderr**; byte-identical across consecutive runs; 2–3 s. Settles the payload rule, §9 Q5, and 7a-B over 7a-C |
| **U11** | `<prefix>/Homebrew/.git` then `<prefix>/.git` probe order validated; repository == prefix on Apple Silicon; invocation-free resolution confirmed |
| **U12** | FETCH_HEAD moved with this session's own auto-update, alongside the API cache — FETCH_HEAD is authoritative |
| **U14** | Doctor mutates nothing under `HOMEBREW_NO_AUTO_UPDATE=1` → `.read` |
| **U13** | **Skipped** — U10's stability result removed the need |
| **U15** | Deferred to verify — re-confirm the pre-existing baseline so this slice's gate subtracts it honestly |

## Risks

| Risk | L | Mitigation |
|---|---|---|
| The doctor inversion leaks onto the JSON trio, or is "simplified" back | **High** | Both rules are **requirement text with reasons**, plus a structural test asserting the trio still rejects non-zero and still admits stdout only |
| The score reads `notCovered`/`unknown` as clean, reintroducing M4's false negative on the app's most prominent surface | **High** | `unknownInputs` structurally inseparable from the value; the mapping is a spec requirement with its own scenario; pure function, so every unknown branch is unit-tested |
| Invented weights nobody can defend | Med | The breakdown renders each weight and its contribution; doctor is weighted per Homebrew's own de-emphasis, not as user-facing defects |
| A naive `prefix/.git/FETCH_HEAD` is silently wrong on `/usr/local` (PRD §3.9 supports it) | Med | Probe-order resolution validated by U11; "silently wrong" is barred by the typed absent/unreadable cases |
| Destructive II13 delta fires `rules.archive`; two pinning tests in two suites, one a *services* file | Med | Named here as deliberate with the maintainer ruling cited; byte-slice diff method from slice 4; both tests rewritten with intent preserved |
| Doctor output drift — the least schema-stable thing this app parses (PRD §8 top risk) | Med | Raw bytes verbatim; every unparsed line counted in `unknownLines: [Data]`; a deliberately *odd* grouping fixture |
| Health composes SecurityKit and is the likeliest slice yet to add a call site to the live false-zero `CompositionRequestSpy` | Med | Stated non-goal; per-instance tagged ledgers only, per slice 3's verify-1 CRITICAL |
| **Forecast overrun** | **High** | See Delivery — slices 3 and 4 both needed a user-accepted `size:exception` |
| `ReleaseNotesUITests` (4 cases / 7 failures) is pre-existing, undiagnosed and **unowned** — FULL is not green at `7d48779` | Med | Raised twice, still unassigned. Carried as an **open follow-up**, not silently inherited as background noise; U15 subtracts it honestly at verify |
| No CI — green suites are local snapshots | Low | Pre-existing project risk, not this slice's |

## Rollback Plan

Additive and revertible by a single `git revert` of the slice PR, **except** the II13 spec reversal,
which reverts as a spec-text restoration plus reverting the two rewritten tests to their archived form
(the byte-sliced ranges are recorded in the delta for exactly this purpose).

Per `rules.proposal`, the two project-level files are named explicitly: **`Packages/CellarCore/
Package.swift` and `cellar.xcodeproj/project.pbxproj` are untouched** — no new target, no new product,
no target-membership or build-setting change; new app sources land inside a new `cellar/Health/`
`PBXFileSystemSynchronizedRootGroup` and revert as plain file deletions. Adding the tenth `AppSection`
case is a source-level enum change with no persisted selection to migrate.

User state: **no cache file, no schema version, no Keychain item and no `UserDefaults` key is
introduced**, so a revert orphans nothing. Bulk snooze writes only existing `Snooze` rows through the
shipped `MetadataStore` API — reverting the UI leaves those rows valid and individually unsnoozable.
No `CatalogPackage` field is added, so `CatalogFootprintTests` and follow-up S4's ~2.4% headroom are
spent nowhere. Checks after revert: `swift build --package-path Packages/CellarCore` and
`xcodebuild build -scheme cellar`.

## Delivery

Session budget **5,000** lines, `single-pr`, strict TDD, RDD disabled. Calibrated honestly against
measurement, not optimism: slice 3 delivered ~9,800 authored lines against a 2,600–4,200 forecast;
slice 4 delivered 7,438 against a deliberately-raised 6,500–9,500 forecast and applied a **measured
1.9–2.3× correction** to a bottom-up count. **Both took a user-accepted `size:exception`.** This slice
composes five subsystems, adds a new brew surface with its own fixtures, a new sidebar section, a
score, a new filesystem seam, and a destructive spec reversal — it is at least slice 4's size.

**Forecast: 7,000–10,000 authored source+tests; 9,000–13,000 including lifecycle artifacts. The
5,000-line budget will be exceeded.** `sdd-tasks` MUST apply the 1.9–2.3× correction rather than
re-learning it, MUST emit the exact guard lines (`Decision needed before apply: Yes|No`,
`Chained PRs recommended: Yes|No`, `400-line budget risk: Low|Medium|High`), and MUST plan the
**natural two-batch cut**:

1. **Batch 1 — core acquisitions + score**: doctor command/source/parser/evidence + fixtures, the
   last-update reader and its seam, `HealthInputs`/`HealthScore`/`HealthProjection`. Autonomous, fully
   unit-testable, no UI.
2. **Batch 2 — section UI + bulk polish**: `.health` `AppSection`, `cellar/Health/` views, remediation
   rows, the II13 reversal, bulk pin/unpin, app-side bulk snooze.

The size decision (`size:exception` vs chained slices at that cut) MUST be surfaced to the maintainer
**before apply starts**, not discovered during it.

## Success Criteria

- [ ] The Health section shows all eight §3.4 signals in one view, and rendering it **launches no brew
      process and triggers no sync** — asserted structurally, not by convention.
- [ ] `brew doctor` exiting non-zero with warnings produces `DoctorOutcome.issues` carrying the
      evidence — **never a thrown error and never an empty document** — with the payload read from
      **stderr** and both raw streams preserved separately and unconcatenated.
- [ ] A structural test proves `InstalledPayload`, `ServicesPayload` and `TapPayload` **still** reject
      non-zero exits and still admit stdout only; `openspec/specs/brew-execution/spec.md` shows a
      **0-line diff**.
- [ ] Every doctor line that the grouping does not recognise is present in `unknownLines`, and the
      count is `0` — not absent — for a clean run.
- [ ] `HealthScore` cannot be constructed or rendered without its `unknownInputs`; a score computed
      over `notCovered`, `unavailable`, `unknown` or `partial` inputs is never reported as clean —
      reachable in unit tests with no store, no clock and no process.
- [ ] Every weight in the score is readable from the breakdown, and the score function has **no**
      store, clock, filesystem or process dependency in its signature.
- [ ] The last-update reader resolves the repository with **zero brew invocations** on both the
      `/opt/homebrew` and `/usr/local` shapes, and returns a typed case — never an invented `Date` —
      for absent, unreadable and future-dated FETCH_HEAD.
- [ ] Bulk pin and bulk unpin are two independently-eligible verbs; on a mixed selection each is
      **unavailable rather than inert**, and neither raises a confirmation.
- [ ] Bulk snooze records the correct per-package offered version, appears **nowhere** in
      `BulkSelection.Action` or `OperationCenter`, submits no operation, writes no history entry, and
      its copy implies no duration. `BrewClient` still does not link SwiftData.
- [ ] "Run doctor" re-measures and its copy claims no fix.
- [ ] Both rewritten tests pass with their original intent intact — `ServiceSubmissionTests` still
      proves no service verb entered the package bulk vocabulary.
- [ ] `Package.swift`, `project.pbxproj`, `CatalogFootprintTests.swift` and
      `openspec/specs/brew-execution/spec.md` all show **0-line diffs**.
- [ ] The final gate subtracts only the U15-confirmed pre-existing baseline
      (`ReleaseNotesUITests` 4/7, `OperationCenterCancelTests:183`, 3 SwiftLint errors) and nothing else.

## Resolved Decisions (binding)

D1–D4 were taken by the maintainer (obs 7532); D5–D7 are settled here per the exploration's
recommendations and measurement. All are fixed — specs derive from them and MUST NOT reopen them.

- **D1 — Bulk pin and unpin are two verbs**, each with its own eligibility, unavailable-not-inert, no
  confirmation. **Rejected:** a single toggle whose availability depends on selection homogeneity —
  II13 sc5 forbids guessing on a mixed selection.
- **D2 — Bulk snooze ships on its own app-side path**, per package, version-scoped, never entering
  `BulkSelection.Action` or `OperationCenter`. **Rejected:** a fifth enum case with a `[]` arm (a
  silent no-op the type system cannot catch), and dropping bulk snooze from PRD §3.2 entirely.
- **D3 — Score is 7b-B: answered inputs only**, with `unknownInputs` structurally inseparable from the
  value. **Rejected: 7b-A** (weighted deduction where an unknown either flatters or punishes — both
  lies) and **7b-C** (a graded status with no number, which would amend PRD §3.4's explicit "0–100").
- **D4 — `.health` is a tenth `AppSection` case between Services and Security; Home stays** the
  landing section. The `AppSection.swift:17–20` slice-5 TODO **resolves as "keep"**. **Rejected:**
  folding Home into Health, despite PRD §5's sidebar list not naming Home.
- **D5 — Doctor is 7a-B**, settled by U10's stability measurement. **Rejected: 7a-A** (non-zero as an
  error — the exact defect this slice exists to avoid) and **7a-C** (`--list-checks` attribution),
  which the explore's own rule makes unnecessary once the grouping is proven stable; C is recorded as
  a **v1.1** item, not discarded.
- **D6 — PRD §9 Q5 is settled as "raw AND grouped"**: raw bytes verbatim, counted grouping projected
  over them, unparsed lines carried. This is the only reading that satisfies both §3.4 and §9.
- **D7 — `brew-execution` is not modified.** The doctor exit-code rule is licensed by its existing
  "brew uses exit codes semantically" sentence; that licence is recorded in the new capability's
  **Provenance** instead of touching a shipped main spec unnecessarily.
