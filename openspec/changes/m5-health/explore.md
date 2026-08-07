# Exploration: `m5-health` — Health dashboard + bulk pin/snooze polish (M5 slice 5 of 5, FINAL)

Repository evidence read at clean `main` `7d48779` (slice 4 `m5-brewfile` archived). Artifact store
is hybrid; the Engram copy lives at topic `sdd/m5-health/explore`.

**Executor limits on this run**: no Write/Edit tool, no shell, no Engram read tools. Prior context
was read from the on-disk archive copies, not from Engram observations. **No probe was run.**
Everything below is either source read verbatim, spec text quoted, or first-party documentation
fetched — nothing is a machine measurement, and the probes needed are listed as U10–U15.

---

## 1. Exact PRD scope for this slice

**PRD.md §3.4 "Health (dashboard)"** — "At-a-glance snapshot combining:"

| # | PRD bullet | Status |
|---|---|---|
| 1 | Outdated packages count (formulae/casks split) | resident — `InstalledStore` + `InstalledSections` |
| 2 | Vulnerable packages count (from CVE scanner) | resident — `SecurityStore.coverage(for:) -> CoverageTotals` |
| 3 | Orphaned dependencies (`brew autoremove --dry-run`) | resident — `CleanupCommand(scope:.autoremove).previewCommand` + `CleanupParser.parseAutoremove` |
| 4 | Duplicate old versions in the Cellar | resident — `DiskPackageUsage.versions: [DiskVersionUsage]` + `FormulaLinkState` |
| 5 | Cache size (`~/Library/Caches/Homebrew`) | resident — `DiskUsageSnapshot.cache: DiskObservation`, root `HomebrewRoots.cache` |
| 6 | Last `brew update` time; `brew doctor` summary (warnings parsed and grouped, full output viewable) | **both genuinely new** |
| 7 | Composite health score (0–100) with a transparent breakdown of how it is computed | **new, and the riskiest thing in the slice** |
| 8 | One-click remediation per row (upgrade all, autoremove, cleanup, run doctor) | commands exist: `MutationCommand.upgradeAll`, `CleanupCommand(.autoremove)`, `CleanupCommand(.global)`; "run doctor" is new |

**PRD §3.2 "Bulk operations": multi-select → upgrade, uninstall, pin, snooze.** The M5 exploration
assigned the pin/snooze half of this to slice 5 (it belongs where "remediate everything" lives), and
the user has ruled that II13 sc4 is to be **reversed**.

**PRD §5** lists Health in the sidebar between Services and Security.

### What PRD §9 leaves open, and what it does not

- **§9 Q5 — "`brew doctor` parsing depth: raw output vs structured grouping (start raw, iterate)"** is
  the only open question this slice owns. §3.4 says "warnings parsed and grouped, full output
  viewable"; §9 Q5 says "start raw". **These two do not agree**, and the slice must settle it rather
  than pick one silently. The M5 exploration recommended raw output *plus* a counted `Warning:`
  grouping with unparsed lines carried as `unknownLines` — that satisfies both readings.
- §9 Q1–Q4 are unrelated (name, tip jar, cask CVE coverage, treemap).
- **§3.4 says nothing about the score's formula, its weights, or what an `unknown` input does to it.**
  That is a product decision this slice must take, not a PRD reading.

### Explicitly out (M5 is closing — anything not in §3.4/§3.2-bulk is v1.1)

- Background/periodic health re-checks and notifications — PRD **§3.8**, milestone **M6**.
- Menu-bar health badge — §3.8, M6.
- Treemap for disk usage — §9 Q4, explicitly a v1 stretch/v1.1.
- Any *new* remediation verb not already shipped (no `brew doctor --fix` exists; doctor never fixes).
- Quarantine/codesign rows: M4 shipped those on the Security section; §3.4 does not list them.
- Historical health trend / score over time — not in §3.4.

---

## 2. `brew doctor` — behaviour, and the payload-rule problem

### 2.1 Documented behaviour (docs.brew.sh Manpage, fetched this session)

> **`brew doctor, dr, checkup [--list-checks] [--audit-debug] [diagnostic_check ...]`**
> "Check your system for potential problems. **Will exit with a non-zero status if any potential
> problems are found.**"
> `--list-checks` — "List all audit methods, which can be run individually if provided as arguments."
> `-D, --audit-debug` — "Enable debugging and profiling of audit methods."
> "Please note that these warnings are just used to help the Homebrew maintainers with debugging if
> you file an issue."

Three first-party facts follow, and they matter for the spec:

1. **Non-zero is the informative answer.** A clean machine exits 0 and prints "Your system is ready
   to brew."; a machine with warnings exits non-zero *and that is the payload*.
2. **`--list-checks` gives a stable, enumerable check vocabulary**, and individual checks are
   separately invocable by name. That is a real option for a structured dashboard (see §7a option C).
3. **Homebrew itself de-emphasises the warnings** ("just used to help the maintainers with
   debugging"). A dashboard that renders doctor warnings as *the user's problems* overstates them.
   This belongs in the copy and probably in the score weighting.

The stream split (stdout vs stderr) and whether the `Warning:`/`Please note` grouping is stable is
**not documented** and must be probed (U10). Whether any check mutates state is likewise not
documented; doctor is conventionally read-only and the repo would classify it `.read`, but that is an
assumption until U10/U14 confirm it.

### 2.2 The precedent situation is NOT what slice 4 established — correction

The task brief says the doctor inversion is "the same payload-rule inversion `brew bundle check` was
proven to have in slice 4". The inversion was **proven to exist** in slice 4, but **no inverted
payload rule shipped**. Verified in `openspec/specs/brewfile-management/spec.md` (provenance, lines
22–27) and in the fixture README:

- Probe U8 proved `brew bundle check --file <path>` **evaluates the Brewfile's Ruby** (a Brewfile
  containing `File.write(...)` left the marker on disk) and exits 1.
- Slice 4's answer was to **refuse the command entirely**. The diff preview is computed offline from
  parsed bytes; `dump` is the only representable `bundle` subcommand.
- `brewfile-management` BF8 therefore encodes the **ordinary** rule verbatim: "Exit `0` MUST mean the
  document is the bytes written to that path… A non-zero exit MUST be a typed failure preserving both
  raw streams."

**So slice 5 is the first place in this codebase where a non-zero exit must be an ordinary, expected
outcome carrying a document.** There is no shipped precedent to copy. Doctor cannot be avoided the
way `bundle check` was — its output *is* the product.

### 2.3 What the shipped payload rule says, and what the execution layer says

The trio is byte-consistent (`InstalledPayloadSource.swift:30–77`, `ServicesPayloadSource.swift`,
`TapPayloadSource.swift`). `InstalledPayload` states the rules in a doc comment:

> "- a non-zero exit is an **error**, never an empty inventory…
>  - **stderr never enters the document, at any position**;
>  - an empty or blank document is malformed, for the same reason."

and implements `guard exit.isSuccess else { throw .commandFailed(status:message:) }`, then joins
**only** `.stdout` lines. A doctor source built on this template reports a healthy-with-warnings
machine as a failed command and discards the only output that matters.

**But `brew-execution` — the main spec one layer below — already says the opposite.**
`openspec/specs/brew-execution/spec.md:74–81`, requirement *Terminal result and exit handling*:

> "A process that exits — successfully or not — MUST be reported as a `BrewExit` **value** carrying
> the exit status and a reason of `exited`; **a non-zero status MUST NOT be raised as a thrown error,
> because `brew` uses exit codes semantically.**"

This is the load-bearing finding for the design: **the execution layer is already correct and needs no
change.** The "non-zero = failure" rule lives only in the three *payload sources* above it, each of
which chose it for its own JSON-document reasons. A doctor source that classifies non-zero as an
ordinary outcome is **consistent with `brew-execution`, not a violation of it** — and the spec
sentence "brew uses exit codes semantically" is the exact quotation that justifies it. The new rule
must be written down explicitly in the doctor capability, and the trio's rule must be left untouched.

### 2.4 The closest shipped error shape

`CleanupPreviewError.commandFailed(status:rawStdout:rawStderr:)` (used at
`cellar/Cleanup/CleanupView.swift:282–288`, seam `CleanupPreviewSourcing`) is the **only** payload
error in the repo preserving both raw streams. `CleanupPreviewResult` likewise carries
`rawStdout: Data`, `rawStderr: Data`, `evidence`, `provenance`. It is the right *carrier* shape — but
it still classifies non-zero as failure, so it is a precedent for **what to keep**, not for **how to
classify**. See §7a for the three candidate shapes.

### 2.5 The evidence idiom to reuse

`CleanupEvidence` is the model to copy, not just to cite:
`rows` / `emptyDirectories` / `orphans: CleanupOrphans{.known|.notApplicable|.unknown}` /
`total: CleanupReportedTotal{.reportedFooter|.unknown}` / `unknownLines: [Data]` /
`issues: Set<CleanupParseIssue>` / `isPartial` / a `CleanupEvidenceFingerprint` (SHA-256 over a
canonical encoding) / `CleanupParserProvenance(parserVersion:footerForm:)`. Note `unknownLines` is
`[Data]`, not `[String]` — undecodable bytes survive. A `DoctorEvidence` in that shape gives "full
output viewable" and "warnings parsed and grouped" from one value, with every parse gap counted.

---

## 3. Last `brew update` — where it lives, and whether it costs an acquisition

### 3.1 Nothing in the repo touches this today

`rg` over the whole tree for `FETCH_HEAD|jws|--repository|HOMEBREW_REPOSITORY|doctor` finds **zero
shipped source files** — only PRD/OpenSpec prose and two unrelated fixture streams. This is entirely
new ground.

### 3.2 What Homebrew itself uses (`Library/Homebrew/utils/auto-update.sh`, fetched this session)

Homebrew's own "how old is Homebrew" test stats:

- `"${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD"` — always
- `"${HOMEBREW_CORE_REPOSITORY}/.git/FETCH_HEAD"` — only when `HOMEBREW_AUTO_UPDATE_CORE_TAP` is set
- `"${HOMEBREW_CASK_REPOSITORY}/.git/FETCH_HEAD"` — only when `HOMEBREW_AUTO_UPDATE_CASK_TAP` is set

against `HOMEBREW_AUTO_UPDATE_SECS`, whose default is **86400** in ordinary API mode (300 when
`HOMEBREW_NO_INSTALL_FROM_API` or `HOMEBREW_AUTO_UPDATE_TAP` is set; 3600 under `HOMEBREW_DEV_CMD_RUN`).
**No `api/*.jws.json` path appears in that decision** — `HOMEBREW_API_AUTO_UPDATE_SECS` governs the
separate question of how often the API JSON is re-downloaded.

This makes `${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD` **the** artifact: it is what brew itself calls
"when Homebrew was last updated", so reading its mtime is not a heuristic Cellar invented. The
M5 exploration's U2 ("FETCH_HEAD vs jws.json — which is authoritative?") is now answered at the
documentation level in favour of FETCH_HEAD; the jws mtime answers a different question ("when was
the catalog JSON last re-downloaded") and would be a **second, differently-labelled** row if wanted
at all.

### 3.3 Zero brew invocations — yes, with one real hazard

Reading a file mtime costs no subprocess. Two things make it non-trivial:

1. **`HOMEBREW_REPOSITORY ≠ HOMEBREW_PREFIX` on `/usr/local`.** `HomebrewRoots`
   (`Sources/DiskUsage/HomebrewRoots.swift:10–19`) derives `prefix` by stripping two path components
   off `installation.executableURL`, and knows only `prefix`/`cellar`/`caskroom`/`cache`. On Apple
   Silicon `/opt/homebrew`, repository == prefix. On an **x86_64 `/usr/local` install — which PRD §3.9
   explicitly supports as a Migration-Assistant carry-over** — `HOMEBREW_REPOSITORY` is
   `/usr/local/Homebrew`, and `/usr/local/bin/brew` is a symlink into it. A naive
   `prefix/.git/FETCH_HEAD` is therefore **silently wrong on exactly the install shape the PRD calls
   out**, and its failure mode is "no last-update time" or, worse, a stale one. Candidate resolutions,
   all cheap: resolve the executable's symlink target and strip `bin/brew`; or probe
   `<prefix>/Homebrew/.git` then `<prefix>/.git` in order; or spend one `brew --repository` read
   (which breaks "costs no new acquisition"). **U11 decides.**
2. **`HOMEBREW_CACHE` is already unhonoured.** `HomebrewRoots.cache` is hardcoded to
   `userCacheDirectory/Homebrew`. Pre-existing, out of scope, but worth not compounding.

### 3.4 There is no file-metadata seam

`CatalogFileSystem` (`createDirectory/fileExists/contentsMappedIfSafe/write/replaceItem/moveItem/removeItem`)
has **no** attribute or modification-date operation, and neither does `ReleaseNotesFileAccess`
(`contents/write/remove`). A last-update reader needs a **new, narrow seam** — the
`ReleaseNotesFileAccess` precedent is the right size: one protocol, one `System…` implementation, so
the absent/unreadable/future-dated cases are all reachable from a test with no real disk.

Honest states this reader must have, as typed cases rather than an optional `Date`: **read**,
**absent** (never updated, or not a git checkout — the API-only future), **unreadable** (permissions),
and it must never invent `Date.distantPast`. An mtime in the future is a real filesystem state and
should be its own case rather than a negative age.

---

## 4. The health score — what is resident, and what an honest score discloses

### 4.1 Resident inputs (nothing new required for five of eight rows)

- `InstalledStore` inventory + `InstalledSections(entries:outdatedIDs:)`, which already separates
  `outdated` from `selfUpdating` (casks that update themselves) and is fed the **snooze-narrowed**
  `outdatedIDs`. The formula/cask split is `PackageID.kind`.
- `SecurityStore.coverage(for:) -> CoverageTotals` — `vulnerable / clean / notCovered / unavailable`,
  plus `hasUnansweredPackages` and `isEntirelyAnswered`. `SecurityScanState` carries `.partial` as its
  own case and keeps a last-good result behind every non-answer.
- `CleanupOrphans.known(names:reportedCount:currentlyOnDiskBytes:) | .notApplicable | .unknown`.
- `DiskUsageSnapshot.packages[].versions` (duplicate old versions), `.cache` (cache size),
  `.isComplete`, `.warnings`, `.rootStates[DiskArea] = .present|.absent|.failed(String)`.
- New: doctor evidence; new: last-update age.

### 4.2 What an honest score must disclose about its inputs

M4's whole lesson applies here and the codebase already spells it out. `CoverageTotals`'s own doc
comment says it exists because "the summary can still read '0 vulnerabilities' over an inventory
nobody could answer for", and `SecurityCoverageState.notCovered` is deliberately **not** filed under
"clean" because "on a real inventory it is the state most packages are in". A score that maps
`notCovered → clean` reintroduces the exact M4 false-negative on the app's most prominent surface —
and unlike a list, a single number gives the user nowhere to notice the substitution.

Concretely, every one of these can be `unknown` and each has a shipped typed case for it:
`CoverageTotals.notCovered`/`.unavailable`; `CleanupOrphans.unknown`; `CleanupReportedTotal.unknown`;
`DiskUsageSnapshot.isComplete == false` / `DiskRootState.failed`; doctor unparsed lines; last-update
absent/unreadable. **A score is a lossy projection of exactly these**, so "transparent breakdown"
(§3.4) is not a nice-to-have — it is the only thing that makes the number falsifiable, and it is what
makes the score unit-testable as a pure function.

Architectural constraint carried from the M5 exploration and confirmed in `Package.swift`: **no core
target may see both `BrewClient` and `SecurityKit`** except `Persistence`. So the score calculator
must be a **pure value function over injected scalar inputs**, in a dependency-free position, with the
inputs composed in the app target — exactly how M4 composed the two. And Health must be a **pure
projection** over state the app already holds (`DiscoverProjection` is the shipped precedent: a
`@concurrent static func build(...)` over already-resident values, "no request, no subprocess, no sync
triggered by a section being rendered"), owning **only** the two new acquisitions. A `HealthStore`
that polls would double every existing refresh.

---

## 5. Bulk pin/snooze — what the reversal actually touches

### 5.1 What II13 sc4 asserts today

`openspec/specs/installed-inventory/spec.md:490–542`, requirement *Multi-select is explicit, ordered,
and offered only for bulk-eligible verbs*:

> "Bulk affordances MUST be offered for **upgrade and uninstall only**; pin, unpin, snooze, favorite
> and note MUST offer **no** bulk affordance…"

with scenario *Only upgrade and uninstall are offered for a selection* → "AND no bulk pin, unpin,
snooze, favorite or note control is present". The Provenance (line ~685) records that "PRD §3.2 also
lists pin and snooze as bulk verbs, and those were **deliberately narrowed out** (settled 2026-08-02) —
the restriction is proven exhaustively over `BulkSelection.Action.allCases`."

**Reversing this is a destructive spec MODIFICATION** to a shipped main spec, which fires
`openspec/config.yaml` `rules.archive` ("Warn before merging destructive deltas"). Slice 4 already
walked that path for `package-mutation` and left the method: byte-slice the exact replaced ranges and
diff them, treat the delta's prose claim of being a superset as a claim to be tested. Here the delta
is genuinely **not** a superset — a prohibition is being removed — so the archive-time warning is real
and the requirement text plus its scenario must both be rewritten, not extended.

### 5.2 The tests that pin it (two, in different suites)

1. `Packages/CellarCore/Tests/BrewClientTests/BulkSelectionTests.swift:70–79` —
   `onlyUpgradeAndUninstallAreBulkEligible()`: `allCases == [.upgrade, .uninstall]`, `count == 2`, and
   a loop asserting the joined lowercased `title`s contain none of `pin/unpin/snooze/favorite/note`.
   **That title scan is the sharp edge**: adding `case pin` with `title == "Pin"` fails the loop even
   if the count assertion is updated.
2. `Packages/CellarCore/Tests/BrewClientTests/ServiceSubmissionTests.swift:213–231` —
   `theInstalledBulkVocabularyIsUnchanged()`: a **services** test that re-asserts
   `allCases == [.upgrade, .uninstall]` to prove no service verb leaked into the package bulk
   vocabulary. Widening `Action` breaks a test that is about `service-management` SM4 sc5, in a file
   nobody would think to look in. Its *intent* (no service verb enters this enum) survives the
   widening and must be preserved, not deleted.

A third structural neighbour, `ServiceRowControl.allCases.count == 5` in the same test, is unaffected.

### 5.3 What widening `BulkSelection.Action` touches

- `BulkSelection.swift:13–95` — `Action` enum (+`title`, +`requiresConfirmation`), and **the two
  eligibility projections**: `ids(for:)` and `isAvailable(_:)`. `upgradable` and `uninstallable` are
  the only two stored id lists; pin and snooze need their **own** eligibility, and the "unavailable
  rather than inert" rule (II13 sc5) means each new verb must define what makes it inapplicable.
- `OperationCenterBulk.commands(for:over:)` (`OperationCenterBulk.swift:74–84`) — its doc comment
  currently *explains* the two-case restriction; the switch is exhaustive and will not compile until
  extended. **Snooze produces no `MutationCommand` at all**, so this function's return type
  (`[MutationCommand]`) cannot express it (see §5.5).
- `OperationCenterBulk.submitBulk(_:over:in:)` (:92–104) — reads `commands(for:over:)` then
  `request(commands)`.
- `cellar/Installed/BulkActionBar.swift` (8 `submitBulk` call sites) and
  `cellar/Installed/InstalledListView.swift` (11 `BulkSelection` call sites). `BulkActionBar` has
  **no covering tests** (codegraph blast radius).
- `BulkFanOutTests.swift`, `ConfirmationDisclosureTests.swift`.

### 5.4 Pin/unpin travels the existing spine cleanly

`MutationCommand.pin(formula:)` / `.unpin(formula:)` exist (`MutationCommand.swift:190–196`), are
**formula-only** by construction (`FormulaID`), and go through
`MutationCommand.naming(_:_:) -> MutationCommand?` like the other two. `OperationCenterBulk.request`'s
doc comment (:108–112) already states pin and unpin **require no confirmation** — so a bulk pin needs
no confirmation sheet, no `ConfirmationDisclosure`, and no change to the DD1 `first.disclosure` fix.
The whole thing is one more `case` in two switches plus one eligibility rule.

Two product wrinkles: (a) **pin vs unpin are two verbs, not a toggle** — a mixed selection (some
pinned, some not) has no single correct answer, and II13 sc5's "unavailable rather than inert" forbids
guessing; (b) `BulkSelection.upgradable` already excludes pinned packages, so bulk-pinning a selection
then bulk-upgrading it is a coherent flow only if the two counts are derived independently — which
`upgradableCount` already guarantees for upgrade (II14).

### 5.5 Snooze does **not** travel that spine — this is the structural crux

Snooze is pure SwiftData: `MetadataStore.snooze(_:offering:)` / `.unsnooze(_:)`
(`Sources/Persistence/MetadataStore.swift:130–149`), model `Snooze(kindRaw:name:snoozedVersion:createdAt:)`
with `#Unique<Snooze>([\.kindRaw,\.name])`. It spawns no process, submits no operation, writes no
history entry, and needs **the offered version** as its argument — `snooze(id, offering: version)` —
which `commands(for:over:)` does not have and `OperationCenter` has no business knowing.

So a naive fifth case in `BulkSelection.Action` puts a verb into an enum whose only consumer
(`commands(for:over:) -> [MutationCommand]`) **cannot represent it**, and whose sibling
`submitBulk` routes everything through `OperationCenter`. Either the return type becomes optional-ish
(a `case snooze: []` arm — a silent no-op that the type would not catch), or the enum is split. This
is a real design fork, not a mechanical widening. Also note `MetadataStore` lives in `Persistence`,
the deliberate outermost target, while `BulkSelection` lives in `BrewClient` — `BrewClient` must not
link SwiftData (`MetadataLookup` exists as a closure seam precisely for this).

Snooze also needs `local-package-metadata` LPM4/LPM5 to be re-read: snooze is version-scoped
(`PackageMetadata.isSnoozed` is **string equality**, deliberately, with a structural test asserting no
comparator exists anywhere near it). A bulk snooze over N packages records N *different* version
strings; the UI copy ("snooze 12 updates") must not imply one duration, because there is no duration —
`createdAt` is provenance, never policy.

---

## 6. Test-infrastructure fit

- **Fixture standard** (`Fixtures/Cleanup/` and the newer `Fixtures/Bundle/README.md`): a `README.md`
  recording capture date, exact Homebrew version (`6.0.15-125-g7372067` on this machine at slice 4),
  binary path, exact argv excluding `brew`, exit status, and a per-stream table with byte counts and
  provenance; a `probe-manifest.txt` with SHA-256 per stream; a `…FixtureManifestTests` suite hashing
  every named stream so a silently re-saved fixture fails the suite. Captured and hand-authored
  fixtures are kept visibly separate. **A `Fixtures/Doctor/` directory must follow this exactly**, and
  needs at least: a clean run (exit 0), a warnings run (non-zero) with both streams captured
  separately, and `--list-checks` output if option C is taken. It also needs a fixture whose
  `Warning:` grouping is *odd* — doctor's own output is the least schema-stable thing this app has
  parsed.
- **Strict TDD is on** for this session. Slice 4 recorded a 21-row cycle-evidence table with credible
  RED reasons and passed 7/7 checks; that is the bar.
- **Per-instance spies, not process-global counters.** Slice 3's verify-1 CRITICAL was a false-zero
  fake; the fix was a per-instance UUID-tagged `RecordingURLProtocol` with
  `Mutex<[String: Ledger]>` and **no** `install()`/`uninstall()`. Slice 4 honoured it with
  `BrewfileCompositionLedger` and deliberately did **not** reuse `CompositionRequestSpy`.
  **`cellarTests/SecurityCompositionSupport.swift:181` still holds the false-zero shape
  (`nonisolated(unsafe) private static var count = 0` + `install()` reset) and slice 3 added a call
  site to it.** Health composes SecurityKit, so this slice is the most likely one yet to want that
  spy. It must not add a call site; folding it into the per-instance shape would close a follow-up
  that has now survived two slices.
- **FULL is not green at clean `main`.** `cellarUITests/ReleaseNotesUITests` fails **4 cases / 7
  failures**, proven at `7d48779` before slice 4 existed, **undiagnosed and unowned**. XCUITest itself
  works (slice 4 ran `BrewfileImportUITests` 2/2 green), so this is a specific test failure, not the
  old machine-wide block. It blocks a clean full-suite signal for this slice too. **An owner is still
  needed and this slice should not silently inherit it as background noise.** Also pre-existing: 1
  known issue in `OperationCenterCancelTests.swift:183`, and 3 SwiftLint errors byte-identical at
  `7d48779`.
- **Sizing precedent**: slice 3 delivered ~9,800 authored lines against a 2,600–4,200 proposal
  forecast; slice 4 delivered 7,438 against a deliberately-raised 6,500–9,500 forecast (the first
  slice whose forecast was not beaten in the same direction), and applied a measured **1.9–2.3×
  correction** to a bottom-up count. Both took a user-accepted `size:exception` against the 5,000-line
  budget. `sdd-tasks` should apply that same correction here rather than re-learning it.
- **`cellar/Health/` as a `PBXFileSystemSynchronizedRootGroup`** gives a 0-line `project.pbxproj`
  diff. Proven twice (`cellar/Discover/`, and the m5-discover archive names this the pattern "slice 5
  reuses for Health"). `Package.swift` and `project.pbxproj` zero-line diffs were held as a binding in
  slice 4 and should be again — unless a new core target is proposed, which §7 argues against.

### Other things this slice inherits or must not break

- **`AppSection` has an explicit slice-5 TODO.** `cellar/Shell/AppSection.swift:17–20`: "Home keeps
  the landing spot for now — **moving it is slice 5's decision, once the Health dashboard exists**
  (D4)." `HomeView` is a two-block summary (brew detection + catalog freshness) that reads no
  inventory. So the slice must decide: add `.health` as a tenth case, or **replace `.home` with
  `.health`** (folding the two Home blocks into the dashboard). PRD §5's sidebar list names Health and
  does **not** name Home. This is a product decision, not a layout tweak.
- **`BrewEnvironment.pinned` sets `HOMEBREW_NO_AUTO_UPDATE=1` on every invocation** (with a documented
  reason: "keeps a read from silently mutating state"). Two consequences: a Cellar-run `brew doctor`
  cannot trigger an auto-update that would move FETCH_HEAD underneath the dashboard; and if a "run
  `brew update`" remediation is ever wanted it must be an explicit `.mutate`, which §3.4 does **not**
  list among the four remediations — so it is out.
- **`CommandOverride` is a closed allow-list** (one case, `.noAutoremove`). If doctor needs any
  command-local environment policy, it is a new case there, not a free-form dictionary.
- **S4 — the encoded-snapshot footprint bound has ~2.4% headroom.** This slice adds no
  `CatalogPackage` field and should keep `CatalogFootprintTests.swift` at a zero-line diff, as slices
  2–4 all did.

---

## 7a. Approaches — the doctor payload/outcome shape

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **`CleanupPreviewError`-shaped source, non-zero still failure**, with the UI reading `rawStderr` out of the error | Zero new vocabulary; reuses the one shipped both-streams carrier | Encodes "warnings found" as an **error**, which is the exact defect §2.2 identifies; every consumer must unwrap an error to render the normal case; the score would read a failure where there is none | Low |
| **B** | **New typed outcome, non-zero is ordinary**: `DoctorOutcome { case clean(DoctorEvidence), case issues(DoctorEvidence), case unavailable(reason) }` over a `DoctorEvidence` built in the `CleanupEvidence` idiom (`checks`, `unknownLines: [Data]`, `issues: Set<DoctorParseIssue>`, `isPartial`, provenance with a `parserVersion`), keeping `rawStdout`/`rawStderr` verbatim | Says what is true; `brew-execution` already licenses it ("brew uses exit codes semantically"); one `switch` is exhaustive over the three real cases; "full output viewable" and "warnings parsed and grouped" both fall out of one value; the score reads a value, never an error | New vocabulary that must be written down as a **requirement**, with a stated reason, so a later "simplification" back onto the trio's rule fails a test; the doctor payload rule must be explicitly quarantined so it never spreads to the JSON sources | Medium |
| **C** | **B, plus `--list-checks`-driven structure**: enumerate check names once, run doctor whole, attribute each warning block to a named check | Turns §9 Q5's "grouped" into a real, stable key instead of prose matching; individually re-runnable checks become a natural per-row remediation; unmatched blocks still land in `unknownLines` | Doubles the brew surface and needs its own fixture + a stability probe; the check-name↔output-block mapping is undocumented and may not be 1:1; §9 Q5 explicitly says "start raw" | Medium-High |

**Recommendation: B**, with the `--list-checks` half of C deferred as a v1.1 note rather than
attempted. B is the smallest shape that is *honest*, and it settles §9 Q5 in the way that satisfies
both the §3.4 text and the §9 guidance: raw bytes preserved verbatim, a counted grouping projected
over them, unparsed lines carried rather than dropped. C should only be taken if U10 shows the
grouping is unstable enough that prose matching cannot be trusted at all — in which case C is not an
enhancement but the minimum.

**Whichever is chosen, three things must be requirement text, not comments**: (i) doctor's non-zero
rule and *why* it differs; (ii) that the trio's rule is unchanged (a structural test over
`InstalledPayload`/`ServicesPayload`/`TapPayload` would make that a claim about the codebase); (iii)
that stderr and stdout are preserved separately and never concatenated — the `Fixtures/Bundle` README
records exactly why (a 399-byte stderr warning at exit 0 would otherwise land inside the document).

## 7b. Approaches — health-score composition

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **Weighted deduction from 100**, each input contributing a penalty; unknowns penalised at some fraction | Familiar; always yields a number | The weights are invented and unfalsifiable; **an unknown either flatters or punishes and both are lies**; reproduces M4's false-negative if `notCovered` scores as clean | Low |
| **B** | **Score over answered inputs only, with an explicit coverage denominator**: `HealthScore { value: Int, contributions: [Contribution], unknownInputs: [HealthInput] }`, where the surface must render `unknownInputs` beside the number and the score is never claimed complete while any input is unknown | Directly matches §3.4's "transparent breakdown"; a pure function over scalars, so every branch is unit-testable with no store; `unknownInputs` is the M4 `notCovered` discipline reapplied; the breakdown makes each weight arguable rather than hidden | Still needs weights chosen and defended; the UI must be built so the disclosure cannot be dropped (the score and the caveat should be one value, not two views) | Medium |
| **C** | **No single number — a graded status (`good/attention/action needed`) plus the eight rows** | Nothing to over-trust; nothing to invent | **PRD §3.4 explicitly requires "a composite health score (0–100)"** — this is a PRD amendment, not an implementation choice | Low |

**Recommendation: B.** It is the only one that satisfies §3.4 as written while surviving M4's lesson.
Two design constraints follow and should be pinned as requirements: (i) the score is a **pure
function** of a `HealthInputs` value with no store, clock, or I/O — the M5 exploration's
dependency-direction constraint (`BrewClient` and `SecurityKit` never meet outside `Persistence`)
makes this structurally necessary anyway; (ii) **a score computed over unknown inputs must be
unrepresentable without its `unknownInputs` list** — same technique as `DiscoverSectionState`, where
an empty section cannot reach a view without a reason attached.

C should be raised to the user only if they would rather amend the PRD than ship a number whose
weights nobody can defend.

---

## 8. Affected areas

- **New** `Packages/CellarCore/Sources/BrewClient/DoctorCommand.swift` + `DoctorSource.swift` +
  `DoctorParser.swift` + `DoctorEvidence` — its own, explicitly documented payload rule.
- **New** last-`brew update` reader + its file-metadata seam. Target choice is open: `DiskUsage`
  already owns `HomebrewRoots` and is the natural home, but `HomebrewRoots` would need a `repository`
  URL (§3.3 hazard 1) — that widening touches `DiskRootsIdentity`, which is compared for equality in
  `CleanupParser.currentlyOnDiskBytes` and persisted in `DiskUsageSnapshot`. **Check whether adding a
  field to `DiskRootsIdentity` invalidates the disk-usage cache** (`DiskUsageCache.load` gates on
  `schemaVersion == 1`); a separate value that composes `HomebrewRoots` may be cheaper than widening it.
- **New** health-score value type + `HealthSnapshot`/`HealthInputs` projection, in a dependency-free
  position, with composition in the app target.
- `Packages/CellarCore/Sources/BrewClient/BulkSelection.swift` — `Action` widening + new eligibility
  projections (only if the II13 sc4 reversal is confirmed).
- `Packages/CellarCore/Sources/BrewClient/OperationCenterBulk.swift` — `commands(for:over:)`,
  `submitBulk`.
- `cellar/Installed/BulkActionBar.swift`, `cellar/Installed/InstalledListView.swift`.
- `cellar/Shell/AppSection.swift` (`.health`, and the §6 Home decision), `cellar/ContentView.swift`
  (exhaustive switch + a `@State` selection if Health gets a detail column),
  `cellar/cellarApp.swift` (composition).
- **New** `cellar/Health/` as a synchronized root group (0-line pbxproj diff).
- **New** `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Doctor/` to the `Fixtures/Bundle`
  standard.
- **Spec deltas**: **new capability** (`health-dashboard` or similar) — ADDED-only; **MODIFIED
  `installed-inventory`** (II13 destructive, plus II14's label rule if the new verbs get counts);
  possibly **MODIFIED `local-package-metadata`** (bulk snooze); possibly **MODIFIED `brew-execution`**
  or a note recording that the doctor rule is licensed by its existing exit-code sentence rather than
  contradicting it (a note in the new capability's Provenance is probably enough — prefer not to touch
  `brew-execution`).
- Tests to rewrite, not delete: `BulkSelectionTests.swift:70–79`,
  `ServiceSubmissionTests.swift:213–231`.

---

## 9. Risks

1. **The doctor payload rule is the first inversion in this codebase, and it must not leak.** The
   trio's rule is correct for JSON documents; doctor's is correct for doctor. Both must be written
   down with reasons, and a structural test should prove the trio is unchanged.
2. **The health score is the app's most trusted number and its inputs are mostly typed unknowns.**
   Counting `notCovered` as clean reintroduces the M4 false negative on the most prominent surface,
   where — unlike a list — the user cannot see the substitution.
3. **`HOMEBREW_REPOSITORY ≠ prefix` on `/usr/local`**, which PRD §3.9 explicitly supports. A naive
   `prefix/.git/FETCH_HEAD` is silently wrong there, and "silently wrong" is the worst shape for a
   freshness claim.
4. **The II13 sc4 reversal is a destructive delta into a shipped main spec** and fires the
   `rules.archive` warning. Two tests in two different suites pin it, one of them in a *services* file.
5. **Bulk snooze does not fit `BulkSelection.Action`'s only consumer.** `commands(for:over:)` returns
   `[MutationCommand]` and snooze produces none; `BrewClient` must not link SwiftData. Resolve this at
   design time, not at apply time.
6. **`--list-checks` and doctor's grouping stability are unmeasured.** Doctor's output is the least
   schema-stable thing this app will have parsed, and PRD §8 already names brew output drift as a top
   risk.
7. **FULL is not green.** `ReleaseNotesUITests` (4 cases / 7 failures) is pre-existing, undiagnosed
   and unowned; it will contaminate this slice's final gate as it did slice 4's.
8. **`CompositionRequestSpy`'s false-zero shape is still live** in `cellarTests` and Health composes
   SecurityKit — the most likely slice yet to add a call site to it.
9. **Size.** Slices 3 and 4 both needed a user-accepted `size:exception`; this slice composes five
   subsystems, adds a new brew surface, a new sidebar section and a spec reversal. Forecast honestly
   and apply the measured 1.9–2.3× correction.
10. **This is the last M5 slice.** Anything deferred here becomes v1.1, so deferrals must be recorded
    as such rather than left implied.
11. **No CI.** Green suites remain local snapshots — a pre-existing project risk, not this slice's.

---

## 10. Probes required before design (U-gates, continuing from U10)

**None of these was run — this executor has no shell.** Each names the decision it unblocks.

- **U10 — `brew doctor`, clean and dirty.** Run on this machine; if it is clean, induce a warning
  reversibly. Capture: exit code both ways; the **exact stdout/stderr byte split**; whether any output
  reaches stdout at all; the `Warning:`/`Please note` block grammar and whether it is stable across two
  consecutive runs; and elapsed time (a dashboard that blocks for 30 s needs a different UI).
  *Decides the payload rule, §9 Q5, and approach 7a-B vs 7a-C.*
- **U11 — `HOMEBREW_REPOSITORY` resolution with zero brew invocations.** On this `/opt/homebrew`
  install: does `<prefix>/.git/FETCH_HEAD` exist? Is `<prefix>/Homebrew` present? What does
  `realpath $(which brew)` give? Cross-check against `brew --repository` **once**, as ground truth
  only. *Decides whether the reader can be invocation-free and how it must resolve the path.*
- **U12 — FETCH_HEAD vs the API cache.** Record mtimes of `<repo>/.git/FETCH_HEAD` and
  `$(brew --cache)/api/*.jws.json`; run `brew update`; re-record. *Confirms at runtime what §3.2
  establishes from brew's own source, and settles whether the jws mtime deserves a second row.*
- **U13 — `brew doctor --list-checks`.** Capture the list and its exit code; run two named checks
  individually; check whether a warning block can be attributed to the check that emitted it.
  *Only needed if U10 shows the grouping is unstable; decides 7a-C.*
- **U14 — does any doctor check mutate state?** Snapshot `<repo>/.git/FETCH_HEAD` mtime, the Cellar
  and the cache before and after a doctor run under Cellar's own pinned environment
  (`HOMEBREW_NO_AUTO_UPDATE=1`). *Decides `.read` vs `.mutate`, which decides whether doctor bypasses
  the mutation gate.*
- **U15 — baseline suite state at `7d48779`.** Re-confirm the pre-existing failures
  (`ReleaseNotesUITests` 4/7, `OperationCenterCancelTests:183`, 3 SwiftLint errors) so this slice's
  final gate can subtract them honestly rather than re-litigating them at verify time.

---

## 11. Product decisions required before proposal

1. **Bulk pin and bulk snooze — confirm the reversal, and confirm its shape.** The user has ruled that
   II13 sc4 is reversed. Two sub-decisions remain and are not implied by that ruling: (a) is it **pin
   and unpin as two verbs**, or one verb whose availability depends on selection homogeneity? (b) does
   **bulk snooze ship at all**, given it does not fit `BulkSelection.Action`'s only consumer (§5.5) —
   and if it does, is it a fifth case with a structural exception, or its own type?
2. **`brew doctor` depth (PRD §9 Q5).** §3.4 says "parsed and grouped"; §9 says "start raw". *Recommend
   raw bytes preserved verbatim **plus** a counted grouping with `unknownLines`, which satisfies both.*
3. **The score's weights, and what an unknown input does to it.** §3.4 mandates 0–100 and a transparent
   breakdown but specifies neither. *Recommend 7b-B: score the answered inputs, carry `unknownInputs`
   inseparably from the number.*
4. **Home vs Health as the landing section** — `AppSection.swift:17–20` defers this to slice 5 by name,
   and PRD §5's sidebar lists Health and not Home. Add a tenth case, or fold Home into Health?
5. **Is "run doctor" a remediation row, a toolbar action, or both?** §3.4 lists it among the four
   one-click remediations, but doctor fixes nothing — it only re-measures. The copy must not imply
   otherwise.
6. **Sizing/delivery.** `single-pr` is cached; slices 3 and 4 both needed a `size:exception`. Decide
   before apply whether this slice takes one, or splits at a pre-agreed cut point (the natural one:
   doctor + last-update + score in batch 1, `.health` section + remediation UI + bulk polish in
   batch 2).
7. **`ReleaseNotesUITests` needs an owner.** Not this slice's defect, but it is the reason FULL is not
   green and it has now survived one full slice unowned.

---

## 12. Ready for Proposal

**Yes, after a decision round and U10–U12.** U10 decides the doctor payload rule and therefore the
central requirement of the new capability; U11 decides whether the last-update reader can honour the
"costs no new acquisition" idiom at all; U12 confirms it. Decisions 1, 3 and 4 change *what this slice
is* rather than how it is built. Everything else is composition over state the app already holds.
