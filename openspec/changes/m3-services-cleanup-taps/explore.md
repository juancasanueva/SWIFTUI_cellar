# Exploration: M3 — Services, Cleanup & Taps

PRD milestone M3 (§3.3, §3.6, §3.8 first half, §4.1–4.2, §7). Umbrella investigation only — no
implementation. This document plays the role `openspec/changes/m2-mutations-installed/explore.md`
played for M2: the single investigation the M3 slices propose from.

Artifact store: hybrid — Engram topic `sdd/m3-services-cleanup-taps/explore`; OpenSpec file
`openspec/changes/m3-services-cleanup-taps/explore.md`.
Live brew probes captured by the orchestrator on **2026-08-03** (Homebrew **6.0.14-50-g7b0f22a**,
`/opt/homebrew`). Codebase read at `main` after M2 archive (M2-3 merged `66af57c`).

**As-of anchor.** Everything below describes the repository *as of 2026-08-03, before any M3 slice
lands*. Present-tense statements about code are statements about that moment. Probe findings (§2)
and slicing rationale (§4) are anchored to the probe date and are what this file will still be
consulted for after the slices ship. (M2's explore had to be retro-corrected for exactly this;
the anchor is stated up front this time.)

---

## 1. Current-state map — what each M3 feature touches

### 1.1 The package graph today

`Packages/CellarCore/Package.swift` (tools 6.0, `.macOS("26.0")`, `.swiftLanguageMode(.v6)` on every
target). Five targets, four library products:

```
CellarTestSupport  (no deps — TestClock, TestPoll)
BrewProcess        (no deps — Process, detection, BrewRunner, queue projection)
Catalog            (no deps on BrewProcess — CS1: catalog works with brew absent)
BrewClient         (→ BrewProcess, Catalog — the only target that sees both)
Persistence        (→ BrewClient — outermost node; nothing depends back on it)
```

App target `cellar/` (thin): `Shell/`, `Home/`, `Browse/`, `Installed/`, `Activity/`, `History/`,
`cellarApp.swift`, `ContentView.swift`. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app
target only, which is why every store lives in the package (design D1, unchanged since M1).

Tests at M2 close: **555 `@Test` in 73 suites** (`swift test --package-path Packages/CellarCore`),
plus `cellarTests` and a `cellarUITests` target that is **skipped** in the verify command.
Main specs: **ten capabilities, 80 requirements, 263 scenarios**.

### 1.2 The mutation spine M3 must decide about

The established path for anything that spawns `brew` and changes state:

```
MutationCommand (typed, BrewClient/MutationCommand.swift)
  → OperationCenter.submit(_:versions:)          BrewClient/OperationCenter.swift:151
      → gate?.begin()                            InstalledMutationGate (suppress watcher)
      → ActivityItem (id, command, log ring 2000, queuePhase, outcome)
      → BrewRunner.start(command.brewCommand)    BrewProcess/BrewRunner.swift:149
          → .mutate joins the FIFO gate (mutationTail), .read spawns immediately
      → drain operation.lines → item.append
      → MutationOutcome.classify(exit:fault:log:) BrewClient/MutationOutcome.swift:57
      → finish(item, with:) — the single idempotent terminal funnel
          → gate?.end()  (forces exactly one inventory re-snapshot)
          → history.record(HistoryDraft)          BrewClient/HistoryRecording.swift
```

Everything M3 spawns as a mutation (`services start/stop/restart/run`, `cleanup`, `autoremove`,
`tap`, `untap`) has to either enter this funnel or run beside it. §6-A is the decision.

**Hard coupling points a generalization must cross** (each read verbatim):

| Site | Coupling |
|---|---|
| `OperationCenter.submit(_ command: MutationCommand, versions:)` | concrete parameter type |
| `ActivityItem.command: MutationCommand` (`ActivityItem.swift:65`) | stored property; `arguments`, `displayCommand`, `copyText`, `packageID`, `requiresConfirmation` all derive from it |
| `MutationOutcome.message(for command: MutationCommand)` (`:139`) | every user-facing sentence |
| `MutationOutcome.forcesReSnapshot` (`:132`) | **hardcoded `true`** for every outcome |
| `OperationCenter.request(_ commands: [MutationCommand]) -> ConfirmationRequest?` (`OperationCenterBulk.swift:112/122`) | confirmation gate |
| `HistoryDraft` (`HistoryRecording.swift:31`) | `packageID: PackageID?` — **already nullable** (grouped `upgradeAll` names none), `verb: String`, `argv: [String]` |
| `BulkSelection.Action` (`BulkSelection.swift:25`) | `CaseIterable`, exactly two cases, asserted exhaustively by installed-inventory II13 sc4 |

`HistoryDraft.packageID` and `MutationCommand.packageID` being optional already is the single
biggest piece of luck here: a non-package operation is *representable* in the durable record without
a schema change.

### 1.3 The read spine M3 will copy

`BrewInfoPayloadSource` (`BrewClient/InstalledPayloadSource.swift:85`) is the exemplar for every new
`brew` read:

- a **compile-time constant argv** (`BrewCommand.read(["info", "--installed", "--json=v2"])`), no
  interpolation, no parameter — an explicitly documented threat response;
- a `…PayloadSourcing` protocol seam producing `Data`, so store/decoder/coordinator are testable
  with zero processes;
- `InstalledPayload.payload(from:exit:)` — a pure function encoding "non-zero exit is an error, never
  an empty result", "stderr never enters the document", "blank document is malformed";
- a closed `InstalledInventoryError` enum (`brewUnavailable`, `commandFailed`, `malformedPayload`,
  `cancelled`).

Each M3 read surface (`services list --json`, `services info --json`, `tap-info --json`,
`cleanup -n`, `autoremove -n`) should instantiate this shape rather than invent one. The
`cleanup -n` / `autoremove -n` sources are the exception: their payload is **prose, not JSON**.

### 1.4 The store/refresh spine

- `InstalledStore` (`BrewClient/InstalledStore.swift`) — `@MainActor @Observable`, single-flight slot
  keyed by request URL **plus** an invalidation mark, ordinal-guarded adoption, last-good survives
  failure. The correct pattern for `ServicesStore`, `TapStore`, `DiskUsageStore`.
- `InstalledRefreshCoordinator` (`BrewClient/InstalledChangeObserving.swift:77`) — three inputs in
  trust order: baseline (launch + `didBecomeActiveNotification`), debounced external change on an
  injected `any Clock<Duration>` (2 s quiet window), and our own mutations (suppressed in flight,
  settled exactly once at the terminal).
- `InstalledMutationGate` (`:24`) — depth-counted, `terminals: AsyncStream<Void>`; `end()` yields
  unconditionally.
- `LoopOwner` (`BrewClient/LoopOwner.swift`) — app-lifetime loops keyed by id, dependency-free.
  Any M3 polling loop belongs here, not in a scene `.task`.
- `FSEventsInstalledObserver` — watches the Homebrew roots. **Relevant to disk usage** (Cellar bytes
  change when the roots change) and **irrelevant to services** (launchd state is not a file).

### 1.5 Feature → surface map

| M3 feature | Reads | Mutates | New capability? | Touches |
|---|---|---|---|---|
| **Services list + status** | `brew services list --json` (new probe) | — | `service-management` | new store, new decoder, new sidebar section, `LoopOwner` poll loop |
| **Service log/plist paths** | `brew services info --json` (new probe) | — | same | detail pane; `NSWorkspace` open-in-Console |
| **start / stop / restart / run** | — | 4 new argv shapes | same | the mutation spine (§6-A), `MutationOutcome` widening, re-snapshot scope (§6-B) |
| **Disk usage engine** | filesystem enumeration (no brew) | — | `disk-usage` | **new SPM target** (§6-C); FSEvents invalidation |
| **Cleanup dry-run preview** | `brew cleanup -n` (prose) | — (probably; see gate U4) | `cleanup-operations` | new prose parser, confirmation surface |
| **Cleanup / prune / scrub** | — | 3 argv shapes | same | mutation spine; invalidates inventory + disk usage |
| **Autoremove (+ orphans)** | `brew autoremove -n` (prose) | `brew autoremove` | same | mutation spine; invalidates inventory |
| **Taps list + packages per tap** | `brew tap`, `brew tap-info --json` | — | `tap-management` | new store; **must not** enter `PackageSearchIndex` (§6-E) |
| **tap / untap** | — | 2 argv shapes | same | mutation spine; `untap --force` is a wide-blast destructive action |

**Explicitly out of M3** (PRD §7 assigns them elsewhere; holding this line is worth ~3k lines):
Health dashboard + health score + one-click remediation rows (§3.4 → M5); Brewfile import/export
(§3.8 second half → M5); per-package "size on disk" *column in the Installed list* and last-used
heuristics (§3.2 → M5 — but note the **engine** that would compute the size is M3, see §6-C);
treemap visualization (§9 open question 4 — list only in v1); duplicate/orphan surfacing *on the
Health dashboard* (the Cleanup-side surfacing is M3).

---

## 2. Live brew facts

Homebrew **6.0.14-50-g7b0f22a**, `/opt/homebrew`, 2026-08-03. Anything not directly observed is
marked **UNVERIFIED** and carries a gate id for the design phase.

### 2.1 `brew services list` / `--json` — VERIFIED

- Text form: columns `Name / Status / User / File`. **0.53 s wall.**
- JSON form works and is an **array** (not an envelope like `{"formulae":…}`):
  `[{"name","status","user","file","exit_code"}]`.
- Observed row: `{"name":"atuin","status":"none","user":null,"file":"/opt/homebrew/opt/atuin/homebrew.mxcl.atuin.plist","exit_code":null}`.
- `user` and `exit_code` are **nullable**. Decode as optionals; a null `user` is "not currently
  claimed by a domain", not an error.
- **Exactly one service installed on the probe machine, status `none`.** Every other status is
  unobserved locally (§8 risk 8).

**Status vocabulary — VERIFIED from Homebrew source**
(`Library/Homebrew/services/formula_wrapper.rb`, `status_symbol`), evaluated in this order:
`started` (has a PID) → `none` (not loaded) → `scheduled` (exit code 0 **and** timed) →
`stopped` (exit code 0) → `error` → `unknown` → `other`.

**Seven values: `started`, `none`, `scheduled`, `stopped`, `error`, `unknown`, `other`.**
Decode tolerantly — an unrecognised string must map to a catch-all case, never fail the payload.
PRD §3.3's "color-coded status (started/stopped/error)" under-counts: the UI needs seven, and
`none` (the only one observed) is the *most common* state.

### 2.2 `brew services info --json` — schema VERIFIED from source, execution UNVERIFIED

`to_hash` (same file) emits: `name`, `service_name`, `running`, `loaded`, `schedulable`, `pid`,
`exit_code`, `user`, `status`, `file`, `registered`, `loaded_file`, and — when the service defines a
command — `command`, `working_dir`, `root_dir`, **`log_path`**, **`error_log_path`**, `interval`,
`cron`.

This is the **only** source for PRD §3.3's "view service log file paths and open them in Console.app;
show the plist location" (`file` = plist; `log_path`/`error_log_path` = logs). `services list --json`
does not carry them.

> **Gate U1 (UNVERIFIED).** Wall time and exact emitted shape of `brew services info --json <formula>`
> and of `brew services info --all --json`; whether `--all` is affordable per refresh, and whether the
> optional keys are omitted or emitted as null. **Probe before design.**

### 2.3 `brew tap` — VERIFIED

Nine third-party taps installed: `agavra/tap`, `cloudmanic/spice-edit`, `gentleman-programming/tap`,
`guria/tap`, `jnsahaj/lumen`, `kitlangton/tap`, `letstri/tap`, `modem-dev/tap`, `nkzw-tech/tap`.

**`homebrew/core` and `homebrew/cask` do not appear** — they are API-based and untapped on a modern
default install. Product consequence: the Taps view lists *only* third-party taps by default and
needs honest copy explaining that the two official taps are served from the JSON API and are not
local git clones. A user who reads "you have no core tap" as breakage will file it as a bug.

> **Gate U2 (UNVERIFIED).** `brew tap-info --installed --json` shape and cost — expected to carry
> `name`, `user`, `repo`, `path`, `installed`, `official`, `formula_names`, `cask_tokens`, `remote`,
> `custom_remote`, `private`. This is the only structured source for "packages per tap" (PRD §3.8).
> **Probe before design.**

### 2.4 `brew cleanup --dry-run` — VERIFIED

**2.6 s wall.** Output is **prose, not JSON** — there is no `--json` for cleanup. Shape:

```
Would remove: <path> (<size>)          ← one line per item
…                                       (cache downloads, cask archives, bootsnap, stale logs, empty dirs)
==> This operation would free approximately 68.7MB of disk space.
```

Parsing rules this dictates:
- the **footer total is authoritative**; the sum of per-row sizes must never be presented as the
  headline number (rows include empty directories with no size, and brew rounds);
- unparsed rows must be *carried through verbatim*, never dropped and never fatal;
- `HOMEBREW_COLOR=0` / `HOMEBREW_NO_EMOJI=1` are already set by `BrewEnvironment.current()`, which is
  what makes the `==>` marker stable.

### 2.5 `brew autoremove --dry-run` — VERIFIED (as an empty result)

Produced **no removable formulae** on the probe machine. That is a real state the UI must render as a
first-class "nothing to remove" — not an error, not a spinner that never resolves.

> **Gate U3 (UNVERIFIED).** The **non-empty** output shape of `brew autoremove -n`. Zero orphans
> existed locally, so the parser has no ground truth. Needs either a probe on a machine with orphans
> or a fixture captured from brew's own source/tests. **Blocking for the cleanup slice's parser.**

### 2.6 Flag surface (docs.brew.sh Manpage, fetched 2026-08-03)

```
brew services list [--json] [--debug]
brew services info (formula|--all) [--json]
brew services run     (formula|--all) [--file=]
brew services start   (formula|--all) [--file=]
brew services stop    [--keep] [--no-wait|--max-wait=] (formula|--all)
brew services kill    (formula|--all)
brew services restart (formula|--all) [--file=]
brew services cleanup
  global: --sudo-service-user  (when run as root on macOS, run the service(s) as this user)

brew cleanup [--prune=days] [--prune-prefix] [-n|--dry-run] [-s|--scrub] [formula|cask …]
brew autoremove [-n|--dry-run]
brew tap [--custom-remote] [--repair] [-f|--force] [user/repo] [URL]
brew untap [-f|--force] tap […]
brew tap-info [--installed] [--json] [tap …]
brew list [--formula] [--cask]
```

Notes worth carrying:
- **`start` vs `run` is exactly PRD §3.3's "start at login" toggle**: `start` registers to launch at
  login/boot, `run` does not. This is not a flag on one verb — it is two verbs, so the toggle must
  submit a different command, not a different argument.
- `brew services stop --keep` stops but leaves it registered; `brew services kill` stops but keeps it
  registered too. Three "stop-ish" verbs. PRD names only start/stop/restart/run-once — recommend
  shipping exactly those four and leaving `kill`/`--keep` out with a recorded rationale.
- `--all` exists on every service verb. **Do not use it for mutations.** It is the same trap
  `upgradeAll` was: one invocation, one log, one outcome for N services, and a mid-batch failure
  attributes to nothing. The M2 fan-out ruling (one invocation per package, selection order) applies
  verbatim — see package-mutation PM2 sc2.
- `brew cleanup` accepts `[formula|cask …]`, which is what makes PRD §3.6's "cleanup per-package"
  buildable. Per-package cleanup argv must reuse `PackageTarget` so the `-`-prefix rejection still
  applies.
- **"Purge download cache" must be `brew cleanup -s --prune=all`, not `rm -rf $(brew --cache)`.**
  PRD principle 2 ("Cellar never manipulates the Cellar/Caskroom directly for mutations") governs.
- `--prune=all` is a documented special value of `--prune [days]`; the manpage text only describes
  the numeric form. Low-risk, but confirm at design (Gate U6).

### 2.7 The gates, collected

| Gate | Question | Blocks |
|---|---|---|
| **U1** | `brew services info --json` shape/cost for one formula and for `--all` | services slice design |
| **U2** | `brew tap-info --installed --json` shape/cost | taps slice design |
| **U3** | Non-empty `brew autoremove -n` output shape | cleanup slice parser |
| **U4** | Do `brew cleanup -n` / `autoremove -n` take Homebrew's lock? If yes they are `.mutate`, not `.read`, and every preview queues behind an in-flight install | **all** cleanup design; changes the UX |
| **U5** | `brew services start` on a **root-domain** service with stdin `/dev/null`: does it fail fast, hang, or emit a sudo signature? (M2-2 follow-up #9 is the same question, now reachable) | services slice; §8 risk 6 |
| **U6** | `brew cleanup --prune=all` accepted as documented | cleanup slice (low) |
| **U7** | `du`-equivalent wall time and inode count over `/opt/homebrew/Cellar` + `Caskroom` + `$(brew --cache)` on the dev machine | disk-usage slice sizing; §8 risk 4 |
| **U8** | `brew services start` on an **already started** service — idempotent success, or non-zero? | services outcome classification |

None of these is expensive. All eight should be captured in one probe session **before `sdd-propose`
for the affected slice**, exactly as M2's G1 was.

---

## 3. Spec contradiction analysis

Ten main specs, 80 requirements, 263 scenarios. M3 must not silently break any.

| Spec | M3 impact | Detail |
|---|---|---|
| `catalog-sync` | **Untouched** | M3 adds no catalog behaviour |
| `package-search` | **Untouched** | Nothing in M3 needs a catalog filter. PS4 (no installed/outdated predicate) survived the whole of M2 and must survive M3 |
| `brew-detection` | **Untouched behaviourally** | Every M3 surface renders absent/invalid as read-only guidance, same as PM7 |
| `local-package-metadata` | **Untouched** | Favorites/notes/snooze are package-scoped; services and taps get none |
| `package-detail` | **Untouched — and this is load-bearing** | PD6: "every snapshot record MUST report `homebrew/core` or `homebrew/cask`", third-party packages are an ordinary not-found. The taps manager **must not** weaken this. See §6-E. This is M3's analogue of M2's PS4 problem, and the answer is the same: resolve architecturally, never by weakening a shipped requirement |
| `brew-execution` | **MODIFIED — small, prelude-driven** | Only the S1 fix: `exit(of:)` answers an unknown id with a fabricated `BrewExit(status: 0)` (`BrewRunner.swift:284-292`). "Terminal result and exit handling" needs a typed unknown-operation result. BE5 (serialized mutations / concurrent reads) is **unchanged** — every new M3 mutation is `.mutate` and inherits it |
| `package-mutation` | **MODIFIED — required, two requirements** | (a) **PM6** "Every terminal outcome forces one re-snapshot" is now wrong: a `services start` changes nothing in the installed set, and forcing a 1.27 s / 663 KB `brew info --installed --json=v2` after every service toggle is pure waste. Needs a typed invalidation scope (§6-B). (b) **PM1** "exactly six mutating commands" survives *literally* under the protocol route (§6-A option 1) and is **contradicted** under the add-cases route (option 2). PM4 (typed sudo failure) may need widening pending gate U5; PM7 (no mutation when brew absent) should be generalised or restated per new capability |
| `operation-activity` | **MODIFIED — required** | OA1 already says "the package identity it acts on **when it has one**" — a non-package operation is already in-contract, no change needed. **OA6** "Every terminal outcome records exactly one history entry" needs (i) the W1 fix (the no-runner submit path at `OperationCenter.swift:159-163` writes **zero** entries today, a live violation) and (ii) a clause covering non-package operations |
| `installation-history` | **MODIFIED — required** | **IH1** "Each mutation Cellar submits MUST produce exactly one history entry" forces a product decision: does toggling a service ten times write ten rows? Either IH1 is modified to define the non-package verb vocabulary and null-package form, or **IH3** ("Only mutations submitted through Cellar are recorded") gains an explicit carve-out. **Do not leave this implicit** — the funnel writes by construction, so silence here means "yes, ten rows" ships by default. IH5 (searchable, newest-first) needs the new verbs in its vocabulary |
| `installed-inventory` | **MODIFIED — small** | II10 (external changes invalidate, debounced) is unchanged in substance but the gate it drives becomes scoped (§6-B). **Trap: II13 sc4** proves exhaustively over `BulkSelection.Action.allCases` that exactly two bulk verbs exist. A naive "add `.stopService`" breaks a shipped scenario. A services multi-select must be **its own type over its own entity**, not an extension of `BulkSelection` |

**New capabilities proposed for M3**: `service-management`, `disk-usage`, `cleanup-operations`,
`tap-management`. Four new capabilities → fourteen total.

**Destructive-delta count: zero.** Everything above is ADDED or a whole-block MODIFIED superset,
matching the M2 precedent (14 ADDED / 5 MODIFIED / 0 REMOVED / 0 RENAMED across the whole milestone).

---

## 4. Slicing recommendation

Session preflight: **interactive / hybrid / single-pr / 2000**, with per-slice `size:exception`
available.

> **Housekeeping, before any forecast is written.** `openspec/config.yaml:7` still declares
> `review_budget_lines: 800`. The session preflight says **2000**. Reconcile the file or every
> `sdd-tasks` guard line will cite the wrong number. Also: `openspec/changes/m2-mutations-installed/`
> is the **last M2 artifact outside `archive/`** — the M2-3 archive report explicitly nominated it for
> archival alongside the milestone. Both are one-line jobs and belong with M3-0.

### 4.1 Calibration from M2 actuals

| Slice | Forecast | Delivered | Ratio vs band top |
|---|---|---|---|
| M2-0 catalog-hardening | 800–950 | **1,586** | 1.67× |
| M2-1 installed-inventory | 2,300–2,700 | **4,918** | 1.82× |
| M2-2 mutations-activity | 4,000–5,000 | **4,538** | 0.91× (in band) |
| M2-3 local-metadata-history | 4,000–5,400 | **6,425** | 1.19× |

The launch-prompt rule holds and is refined by the data: **1.2× tests-to-production for familiar
layers**, and a first slice on unfamiliar ground under-prices by ~25%. Two additional lessons the
table shows that the rule does not: **small preludes overrun proportionally worse than large slices**
(M2-0 was the worst ratio of the four), and **the one slice that landed in band was the one whose
layers were all already exercised** (M2-2 reused M2-1's spine end to end).

M3's unfamiliar ground is narrow: no new persistence framework, no new concurrency model. The one
genuinely new layer is **deep filesystem enumeration at scale** in the disk-usage engine. Applying
1.2× to everything and **1.4×** to the disk-usage engine.

### 4.2 Recommended: one prelude + four feature slices

| # | Slice | Contents | Forecast (authored, src+tests) | vs 2,000 |
|---|---|---|---|---|
| **M3-0** | `m3-hardening-prelude` | M2-2 #12 (catalog adoption ordinal — one-line guard); W1, W2, W3, W4; S1; S2; VS1; M2-0 #4 (`.timeLimit` on the watcher loop); config budget reconcile; archive the M2 umbrella explore | **900–1,500** | **Fits** |
| **M3-1** | `m3-services` | The command generalization (§6-A) with services as first consumer; typed invalidation scope (§6-B); `services list --json` + `services info --json` sources, decoders, `ServicesStore`; poll cadence on `LoopOwner` + injected clock + visibility gate; four verbs (start/stop/restart/run) with per-service fan-out; root-domain read-only; Services sidebar section, list, row, detail with log/plist paths + open-in-Console; absorbs VS2, M2-2 #6, #9 | **2,600–3,400** | exception |
| **M3-2** | `m3-taps` | `brew tap` / `tap-info --json` source + `TapStore`; taps list with official-vs-third-party framing and the "core/cask are API-based" copy; per-tap installed-package cross-reference from `InstalledPackage.tap`; `tap` / `untap` mutations reusing M3-1's generalization; third-party trust warning; `untap --force` as a wide-blast confirmed destructive action naming every affected package | **1,700–2,300** | borderline |
| **M3-3** | `m3-disk-usage` | New `DiskUsage` SPM target; `DirectoryMeasuring` seam + fake; Cellar per-package/per-version, Caskroom, cache, unlinked-keg sizing; off-main, cancellable, incrementally published; FSEvents-driven invalidation + cache; `DiskUsageStore`; sortable list surface | **2,800–3,800** | exception |
| **M3-4** | `m3-cleanup` | `cleanup -n` / `autoremove -n` prose parsers (tolerant, footer-authoritative, verbatim passthrough); dry-run preview surface with reclaimable bytes; `cleanup` (all / per-package) / `--prune=all` / `-s` / `autoremove` mutations; orphan list; empty-state handling; Cleanup view composing M3-3's engine | **2,400–3,200** | exception |

**Total ≈ 10.4k–14.2k authored lines** — comparable to M2's ~17.4k across four slices, and M3 is a
smaller milestone. Three slices need an accepted `size:exception`; M3-2 is borderline and may land
inside 2,000 if the tap-info decode is as thin as expected.

### 4.3 Why this order

1. **M3-0 first and unconditionally.** Same argument M2-0 won on: three of the four feature slices
   replicate patterns M3-0 corrects, and W3 (two `ModelContainer`s over one store file) is the only
   open item with a data-integrity tail — it must not sit behind a services feature. M3-0 is also the
   only slice that fits the budget, so it merges without a negotiation.
2. **M3-1 second, because it forces the generalization.** Services is the smallest new brew surface
   (one JSON array, seven status values) and the first non-package mutation family. Doing the
   generalization here — with a real consumer in the same slice — avoids M2-1's `InstalledMutationGate`
   pattern (shipped with zero callers and noted for it at archive).
3. **M3-2 third, because it is the cheapest consumer of M3-1's work** and proves the generalization
   on a second family before the two expensive slices depend on it.
4. **M3-3 before M3-4**, so the Cleanup view renders real byte figures rather than only brew's
   estimate, and so the riskiest unknown (U7, traversal cost) is de-risked in a slice that ships no
   destructive action.

### 4.4 Alternatives

- **Merge M3-1 + M3-2** (one "brew subsystems" slice, 4.2k–5.6k). Fewer PRs, but a single slice
  carrying the generalization *and* two feature families; M2-1 at 4,918 lines is the precedent for
  how that reads in review. **Not recommended.**
- **Split M3-3/M3-4 into engine / parser / view thirds** (seven slices total, each ~1,300–2,000, no
  exception anywhere). Buys budget compliance at the cost of two more review cycles and one slice
  that ships no user-visible behaviour. Offer this if the user prefers no exceptions at all.
- **Defer M3-3 wholesale to M5** and ship M3-4 on brew's own "would free approximately X" footer
  alone. PRD §7 names the disk-usage engine as M3, so this is a scope reduction requiring an explicit
  product ruling — but it is the single largest lever if M3 must fit a smaller envelope.

---

## 5. Follow-up register — fold-in assessment

Seventeen open at M2 close. Verdicts:

| # | Follow-up | Verdict | Rationale |
|---|---|---|---|
| **M2-2 #12 / M2-0 #1** | `CatalogStore` adoption ordinal stamps on call arrival (`Sources/Catalog/CatalogStore.swift:185-186`) — a later-entering *older* snapshot takes a higher ordinal and installs over a newer catalog. `CatalogSnapshotRevision.ordinal` is already monotonic, so the guard is one line | **Prelude (M3-0)** | Oldest open defect in the project. Survived three consecutive slices. Both the M2-2 and M2-3 archives asked, in writing, that it be closed standalone rather than carried again. Doing it a fourth time would make the register decorative |
| **W1** | No-runner submit settles `.launchFailed` **without writing a history entry** (`OperationCenter.swift:159-163` bypasses `finish()`) | **Prelude (M3-0)** | It is a live violation of operation-activity OA6, not a nicety. And M3-1 restructures exactly this method — fixing it *before* means the restructure inherits correct behaviour and the RED test survives the refactor instead of being written against code about to change |
| **W2** | Failed Clear History silently masked — `clearAll()` sets the availability reason, then an unconditional `reload()` overwrites it to `.available` and `lastError` is never set (`HistoryStore.swift:181-190`) | **Prelude (M3-0)** | Self-contained, ~60 lines, zero M3 coupling. A clear that did not delete currently renders as if it had |
| **W3** | Two `ModelContainer`s over one store file (`cellarApp.swift:50` and `:63` both default to `PersistenceContainer.defaultURL()`); design D3 intended one injected container | **Prelude (M3-0)** | The only open finding with a data-integrity tail. M3 adds three more stores to the same composition root — fix the root before a third container appears. The M2-3 archive named this specifically as "should not sit behind a services feature" |
| **W4** | Uncommitted note draft lost on package switch — only commit trigger is focus loss, while `onChange(entry.id)` resets the draft first; the doc comment claims an `onSubmit` commit that does not exist (`PackageMetadataSection.swift`) | **Prelude (M3-0)** | ~40 lines. In Browse, which M3 never otherwise opens — so it is prelude or never. Grouped with W1–W3 as the archive recommended |
| **S1** | `BrewRunner.exit(of:)` fabricates `BrewExit(status: 0)` for an unknown id (`BrewRunner.swift:286, :291`); only the `isReleased` gate keeps it unobserved | **Prelude (M3-0)** | M3-1 puts three more operation families through the same runner. A fabricated *success* is the worst possible default, and every new submitter widens the path to it. Modifies `brew-execution`'s "Terminal result and exit handling" |
| **S2** | Bulk multi-add appends in flat inventory order, not the displayed three-section order its own comment claims (`InstalledListView.swift:117`) | **Prelude (M3-0), cheap** | Code-vs-comment divergence, no scenario violated. ~20 lines. The fix is *deciding which of the two is right* — do that while the M2 context is warm rather than in six months |
| **VS1** | Give the display-only structural scan a positive anchor (`HistoryRecorderTests > aStoredRowCannotBecomeACommand` is pure-negative and can pass vacuously) | **Prelude (M3-0)** | ~5 lines. Same technique the G5 scan already uses |
| **M2-0 #4** | `CatalogAdoptionTests.swift:182` watcher loop unbounded, suite carries no `.timeLimit` | **Prelude (M3-0)** | M3-1 adds a polling loop and M3-3 adds a cancellable traversal; both are test-hang shapes. Establish the `.timeLimit` habit before, not after |
| **VS2** | `OperationCenter.pendingConfirmation` widened to `public internal(set)`; a `ConfirmationBox` type would restore `private(set)` | **Absorb into M3-1** | M3-1 rewrites the confirmation surface anyway (cleanup and `untap --force` both need it). Restore the compiler guarantee in the same breath |
| **M2-2 #6** | A mutation's own post-terminal FSEvents echo costs one redundant `brew info --installed` (~3 s later). Conforming, not a defect | **Absorb into M3-1** | M3-1 must already replace the unconditional re-snapshot with a typed invalidation scope (§6-B). The post-terminal grace window is the same code and the same design question — solving it twice would be waste |
| **M2-2 #9** | Sudo signature set (`MutationOutcome.Signature.privilege`) unprobed against a live sudo-requiring path | **Absorb into M3-1** | Gate U5 makes this reachable *safely* for the first time: a root-domain `brew services start` is a real privilege path that fails harmlessly. Probe it, widen the signature list if the wording differs |
| **M2-2 #7** | Duplicate submission of the same install accepted (benign "already installed" outcome). Permitted by design | **Absorb narrowly into M3-1; general rule deferred** | Services makes this materially worse — a start/stop toggle is a *button a user double-clicks*, and two queued opposite operations are a confusing outcome. Ship a services-scoped guard; leave the general dedup rule deferred |
| **VS4** | `HistoryDraft.date` is `Date()` at the terminal, not an injected clock | **Absorb into M3-1 if needed, else defer** | M3-1 introduces a clock-driven poll loop; if any assertion needs a deterministic timestamp, add the additive `clock:` seam then rather than reaching for `Date()` a second time. Nothing is flaky today |
| **VS3** | Phase-8 app-target UI carries residual risk with no automated coverage; `cellarUITests` exists but is skipped | **Defer the broad version; take a scoped decision in M3-1 propose** | M3 adds four more untested UI surfaces, so the gap widens by a factor. But standing up an XCUITest harness inside a feature slice is how feature slices overrun. Recommend: an explicit product ruling in M3-1's proposal — accept manual evidence again (and *plan* the manual checks, given M2-3's IH6 CRITICAL), or fund a small harness as its own slice |
| **M2-2 #8** | Carry `standardInput` through `ProcessSpec` so "standard input is never interactive" is testable at the recording seam | **Defer** | Behaviour is correct at the composition root; only observability is missing. Gate U5 may change this verdict — if a root-domain service start *hangs* rather than failing, stdin observability stops being cosmetic |
| **M2-2 #10** | `skippedRecordCount` never surfaced — decode tolerance is silent | **Defer, but note the pattern** | M3 adds three more tolerant decoders (services status, tap-info, cleanup prose) each with its own skipped-count. Whoever finally surfaces this should surface all four at once, so do not solve it for one |
| **M2-2 #13** (rest) | M2-0 #5–#7, M1 #4/#5: poisoned-snapshot recovery gated on staleness; undelivered engine-side zero-package guard; latency test via the synchronous initialiser; payload size cap; unwired `payloadByteLimit` | **Defer** | Catalog-side hardening bundle. No M3 coupling. Belongs in a catalog slice or M5 |
| **M2-1 #8 / #9** | `DetectionTests` display-name prose, `InstalledRefreshTests` count assertion | **Defer** | Test-prose nits, untouched since M2-1, no coupling |

**Prelude bundle (M3-0)**: M2-2 #12, W1, W2, W3, W4, S1, S2, VS1, M2-0 #4, plus the two housekeeping
items. Forecast **900–1,500** authored lines — the only slice that fits 2,000 without an exception,
and the one that de-risks the other four.

---

## 6. Key approach decisions to carry into `sdd-propose`

### A. Reuse the mutation spine — generalize the command, do not add cases

Every M3 mutation must serialize against Homebrew's **process-external** lock. A `brew cleanup`
running concurrently with a `brew install` fails on that lock (M2 live-probed the exact message,
`MutationOutcome.Signature.lock`). Cellar's FIFO gate is the only thing preventing that, and it is
`OperationCenter` + `BrewRunner`. **A parallel path is not on the table** — it would also duplicate
activity, log streaming, cancel, copy-command and history four times over.

The real question is *how* the new families enter it.

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **1. Generalize to a `BrewMutating` protocol** (recommended) — `{ arguments, kind, verb, packageID: PackageID?, displayCommand, requiresConfirmation, invalidates }`; `MutationCommand` conforms **unchanged**; `ServiceCommand`, `CleanupCommand`, `TapCommand` conform beside it | `package-mutation` PM1 ("exactly six") stays **literally true** with zero spec edit; each family owns its own verb vocabulary, its own confirmation rule and its own invalidation scope; new families cost one conformance, not one enum edit + N exhaustive-switch updates | `ActivityItem.command`, `MutationOutcome.message(for:)`, `OperationCenter.submit/request/confirm` all become generic or existential; ~6 call-site families to retype (M2-3's `PackageTarget` retype cost 56 mechanical edits against a 40–60 estimate — that estimate held, so this one can be trusted too) | Medium |
| **2. Add cases to `MutationCommand`** | Smallest immediate diff; no generics | **Directly contradicts PM1**; puts `startService` next to `pin` in a type whose `packageID` and `verb` are package-shaped; every future family re-opens a shipped spec; `MutationOutcome.message(for:)`'s exhaustive switch grows to ~18 cases | Low now, high later |
| **3. Parallel `OperationCenter` per subsystem** | Perfect isolation | **Breaks FIFO against brew's global lock** — the one thing the spine exists for. Four copies of activity/history/cancel | Rejected |

**Recommend option 1.** It is also the only route under which `HistoryDraft` needs no change at all
(`packageID` is already `PackageID?`, `verb` is already `String`).

### B. Replace the unconditional re-snapshot with a typed invalidation scope

`MutationOutcome.forcesReSnapshot` is hardcoded `true` (`MutationOutcome.swift:132`) and
`OperationCenter.submit` calls `gate?.begin()` unconditionally (`:169`). Correct for M2, wrong for M3:

| Family | Inventory | Services | Taps | Disk usage |
|---|---|---|---|---|
| install / uninstall / upgrade / pin | ✅ | — | — | ✅ (M3-3 onward) |
| services start/stop/restart/run | — | ✅ | — | — |
| cleanup / prune / scrub | ✅ (old kegs) | — | — | ✅ |
| autoremove | ✅ | — | — | ✅ |
| tap / untap | ✅ (`untap --force` uninstalls) | — | ✅ | — |

Recommend an `InvalidationScope: OptionSet` carried by the command (not by the outcome), with the
gate fanning out to the right stores. This **MODIFIES `package-mutation` PM6** — write the delta
deliberately rather than letting a `services start` quietly pay a 1.27 s / 663 KB inventory probe.
Note the invariant that must survive: *every terminal outcome still owes exactly one refresh of
whatever it does invalidate*, including cancelled and failed ones (PM6's real point, which stays
correct).

### C. Disk-usage engine: a new `DiskUsage` target, measuring the filesystem directly

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **A. New `DiskUsage` SPM target** (recommended) — depends on `BrewProcess` (for `BrewInstallation`/prefix) and `Catalog` (for `PackageID`), sibling of `BrewClient`; `DirectoryMeasuring` seam + fake | Matches PRD §4.1 verbatim; headless-testable against a temp tree in the `swift test` loop; keeps `Catalog` brew-free (CS1) and keeps `Persistence` outermost; the one-directional edge mirrors `BrewClient`'s | One more target to carry; needs a real seam to stay testable | Medium |
| B. Inside `BrewClient` | Zero package-graph change | `BrewClient` is already the fattest target; couples pure filesystem measurement to brew process plumbing; contradicts PRD §4.1 | Low |
| C. Shell out to `du -sk` | Trivial | A subprocess per measurement, no incremental progress, no fine-grained cancellation, and output parsing where a typed API exists. Also queues behind the mutation gate if made `.mutate` | Low |

**Recommend A**, measuring with `FileManager.enumerator` + `URLResourceValues.totalFileAllocatedSizeKey`
(allocated, not logical — a user comparing against Finder expects allocated), off-main, with explicit
`Task.isCancelled` checks and **incremental publication** (PRD §3.6: "sizes computed off the main
thread with incremental display"). Cache the result and invalidate from the existing FSEvents
observer rather than re-walking on every view appearance.

**Scope boundary worth stating in the proposal**: the *engine* is M3; the per-package **size column in
the Installed list** is M5 by PRD §7. M3 should expose the engine's per-package figures on the
Cleanup surface only, and resist the one-line temptation to also decorate `InstalledRow`.

Gate U7 governs whether any of this is affordable. If the traversal is multi-second, the mitigation
is a persisted cache, not a faster walk.

### D. Services: poll, do not try to observe

launchd state is **not a filesystem fact**, so FSEvents — the whole M2-1 watcher apparatus — buys
nothing here. Observing other domains' launchd state without private API is not available.

| Option | Pros | Cons |
|---|---|---|
| **A. Poll `brew services list --json` while the view is visible** (recommended) | Exactly what PRD §3.3 asks for; 0.53 s per probe; reuses `LoopOwner` + injected `any Clock<Duration>`, so the cadence is testable without wall-clock sleeps | A subprocess on a timer; needs a visibility gate or it burns CPU in the background |
| B. `launchctl` / `SMAppService` observation | Push, not poll | Not available for the general case without private API; would also mean reading state brew owns, contradicting "brew is the source of truth" |
| C. Refresh on demand only | Cheapest | Contradicts PRD §3.3's "auto-refresh while the Services view is visible" |

**Recommend A**, with four rules mirroring `InstalledRefreshCoordinator`: (1) baseline refresh on
section appearance; (2) poll on an injected clock **only while visible** — stop on disappear, not
merely slow down; (3) forced refresh at every service-mutation terminal; (4) suppression while a
services mutation is in flight, so a `restart` mid-flight does not produce a flickering status.
Cadence is a product question — **suggest 5 s visible / never hidden**, and record it as settled
rather than leaving it as a magic number.

`brew services info --json` should be fetched **lazily for the selected service only** (detail pane),
not `--all` on every poll tick — pending gate U1.

### E. Taps: a separate inventory, never the search index

`package-detail` **PD6** requires that every catalog record report `homebrew/core` or
`homebrew/cask`, with third-party packages returning an ordinary not-found. The taps manager must not
touch that.

**Recommend**: a `TapInventory` built from `brew tap-info --installed --json` (`formula_names` /
`cask_tokens`), rendered in the Taps view as **plain names with no detail navigation**, plus a
cross-reference against `InstalledPackage.tap` — which the slim projection already carries — so a
tap's *installed* packages **are** navigable (they resolve through the existing inventory, not the
catalog). A third-party package that is not installed gets honest "not in Cellar's catalog" copy.

This keeps PD6 byte-identical, keeps the 14k index and its p95 latency assertion meaningful, and
still delivers PRD §3.8's "show packages per tap". It is the same architectural resolution M2 used
for the PS4 conflict, and it worked: PS4 was never touched across the whole of M2.

Two further tap rules to settle in the proposal:
- **`brew untap --force` uninstalls every package from the tap.** Its blast radius dwarfs a single
  uninstall. It must be confirmed with the **full list of affected installed packages named
  individually**, following the M2-3 bulk-uninstall precedent ("a bulk uninstall is confirmed once,
  naming every package") — never a count, never an elided subset.
- **Plain `brew untap` should be the default affordance** and `--force` a separate, separately
  confirmed choice, exactly as `zap` is separate from `uninstall` today.

### F. Cleanup previews: tolerant prose parsing, footer authoritative

No `--json` exists. The parser must: treat the `==>` footer total as the headline figure; carry
unrecognised lines through **verbatim** into the preview rather than dropping them; never fail the
whole preview on an unparsed row; and render an empty result as a first-class "nothing to clean"
state (which is exactly what `autoremove -n` produced on the probe machine).

Follow `MutationOutcome`'s existing discipline verbatim: parsing brew's prose is acceptable **only**
because nothing is extracted from it that reaches argv. The dry-run preview is display-only; the
command that actually runs is Cellar's own typed command, never a path parsed out of the preview.
State that as a structural rule with a scan test, as M2-3 did for `HistoryDraft`.

---

## 7. §8-style risks

1. **`brew cleanup` has no `--json`.** PRD §8 row 1 ("brew output/JSON schema changes across
   versions") lands squarely here: a prose parser over `Would remove: <path> (<size>)` is the most
   version-fragile thing M3 ships. Mitigation: footer-authoritative totals, verbatim passthrough,
   tolerant rows, fixture-driven tests, and never letting a parse failure block the operation.
2. **Dry-run may not be free (gate U4).** If `brew cleanup -n` takes Homebrew's lock, previews must be
   `.mutate` and will queue behind an in-flight install — a materially different UX from "click
   Preview, see numbers". Resolve before the M3-4 proposal, not during apply.
3. **`brew autoremove -n`'s non-empty shape is unknown (gate U3).** The only observed state was empty.
   The parser has no ground truth and cannot be honestly TDD'd without a fixture.
4. **Disk-usage traversal cost is unmeasured (gate U7).** `/opt/homebrew/Cellar` on a 156-formula
   machine holds a large, unknown number of inodes. Risk of a multi-second scan and of re-walking on
   every view appearance. Mitigations: off-main, cancellable, incremental publish, cached with
   FSEvents invalidation.
5. **Seven service statuses, one observed.** `started`/`scheduled`/`stopped`/`error`/`unknown`/`other`
   are all unexercised locally; only `none` was seen. Decode tolerantly with a catch-all case —
   an unrecognised status must never fail the payload. PRD §3.3's three-colour model under-counts.
6. **Root-domain services and stdin (gate U5).** PRD §4.2 forbids privilege escalation, and
   `SystemProcess` hard-wires `standardInput = FileHandle.nullDevice`. A `brew services start` on a
   root-domain service may fail fast, emit a sudo signature, or **hang until cancelled**. This is the
   direct descendant of M2's stdin risk and M2-2 follow-up #9, now finally probeable safely. Needs an
   explicit product decision (detect-and-explain vs. render read-only up front) before M3-1 apply.
7. **`brew untap --force` is the widest destructive action in the app.** It uninstalls every package
   from a tap. Confirmation must name every affected installed package, and `--force` must be a
   separate choice from a plain untap.
8. **The dev machine is a weak oracle for every M3 surface.** One service (status `none`), zero
   orphans, zero outdated kegs at probe time, and nine taps that are all third-party. "Many services
   running", "orphans to remove", "a tap with installed packages" are all unexercised states.
   Fixture-first is mandatory, and manual verification will be thin — M2-3's IH6 CRITICAL (a scenario
   with neither a test nor a manual observation, caught only by the validator) is the precedent for
   what that costs.
9. **Review budget.** ~10.4k–14.2k forecast against a 2,000-line `single-pr` budget. M3-0 fits; M3-1,
   M3-3 and M3-4 each need an accepted `size:exception` **before** apply starts, exactly as all four
   M2 slices did. M3-2 is borderline.
10. **`openspec/config.yaml:7` says 800, the session preflight says 2000.** Reconcile before any
    `sdd-tasks` forecast is written or the guard lines will cite a budget nobody is using.
11. **Scope creep from §3.4 Health and §3.8 Brewfile.** The Cleanup view will look like the natural
    home for the health score and one-click remediation, and the Taps view for Brewfile export. PRD §7
    assigns both to M5. Holding this line is worth roughly 3k lines.
12. **`service` is deliberately absent from the installed wire projection** (`InstalledWire.swift:18`
    names it among the ignored fields). If services derivation ever wants "which installed formulae
    define a service", that is a decode change inside a shipped capability. Prefer `brew services list`
    as the sole source and leave the slim projection alone.
13. **`BulkSelection.Action` is proven exhaustive at exactly two cases** (installed-inventory II13
    sc4). Any "stop all services" multi-select must be a **new type over a new entity**; extending the
    existing enum breaks a shipped scenario.
14. **Four new capabilities in one milestone.** M2 added five and needed three archive
    reconciliations across its slices. Requirement/scenario counts will grow steeply; budget verify
    time accordingly and keep each capability's boundary statement (the "owned by … / referenced,
    never restated" header) written before the first delta, as M2's specs did.

---

## 8. Ready for proposal

**Yes**, with two conditions:

1. **Run the eight probes (U1–U8) in one session before `sdd-propose` for the affected slice.** None
   is expensive; all eight are blocking for at least one slice's design. This is the M2 G1 precedent.
2. **Settle three product questions before M3-1's proposal**: (a) do service toggles write history
   rows (installation-history IH1/IH3); (b) the services poll cadence and its visibility gate; (c)
   the VS3 ruling — manual evidence again, or fund a UI-test harness as its own slice.

Recommended first action: **`sdd-propose m3-hardening-prelude`** (M3-0). It fits the budget, closes
the project's oldest open defect, and de-risks all four feature slices.
