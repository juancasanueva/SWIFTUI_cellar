# Proposal: Brewfile Import & Export (`m5-brewfile`)

Anchors PRD.md **M5** (§7); feature **§3.7 "Taps & Brewfile"**. Slice **4 of 5** of the recorded M5
decision round. Exploration: `openspec/changes/m5-brewfile/explore.md` (Engram obs 7518). Probes U6,
U8, U9 executed and reported (obs 7519). Product decisions 1–3 taken by the maintainer (obs 7520)
and binding. Slices 1–3 archived; slice 5 (`m5-health`) owns everything this slice defers.

## Intent and Users

Cellar can tell a user what is installed on *this* Mac and nothing more. Moving that setup to a new
machine, sharing it with a teammate, or reproducing a colleague's environment means dropping back to
the terminal — the exact workflow the app exists to replace. A Brewfile is Homebrew's portable answer
to that, and today Cellar neither produces one nor understands one.

This slice serves two moments. **Export**: a user who has curated an install set wants it as a file
they can commit, share, or carry. **Import**: a user holding someone else's Brewfile wants to know,
*before* anything happens, which entries they already have and which would be installed — and then
apply only the ones they choose.

The second moment is where the slice earns its design. A Brewfile is **evaluated Ruby**, and probe U8
proved that `brew bundle check --file <path>` executes it: a Brewfile whose only content was
`File.write(".../marker.txt", ...)` left the marker on disk after a "read-only check". The PRD's
literal wording ("diff preview … selective apply via `brew bundle --file`") describes a preview that
runs a stranger's code. This proposal delivers the PRD's *product outcome* while refusing that
implementation.

## Security Invariants (binding, non-negotiable)

- **`brew bundle` is never pointed at a file Cellar did not write.** The user's imported Brewfile is
  read as bytes and parsed by Cellar. It never reaches brew's argv, at any stage, including preview.
- **Import performs no code execution.** Ruby is never evaluated, by Cellar or by a subprocess. There
  is no escape hatch in v1 (A3 rejected).
- **`trusted:` is never honoured implicitly.** It is a pre-granted trust decision authored by whoever
  wrote the file, not a package name. It is parsed, surfaced, and discarded as authority; any tap it
  names still goes through the shipped `ConfirmationDisclosure.tapTrust` gate.
- **Names still cannot become free text in argv.** Every imported entry is admitted only by
  constructing `TapName` / `FormulaID` / `CaskID` / `PackageTarget`; anything unrepresentable is a
  counted, named skip. The provenance premise at the head of `MutationCommand.swift` ("names come
  from brew's own snapshot or the catalog, never from free text") stops being true in this slice and
  is restated deliberately rather than left stale.
- **The export subprocess never writes to the user's disk.** `brew bundle dump` writes only to a
  Cellar-owned temp path; publication to the user's destination is Cellar's atomic write.
- **Import issues no implicit mutation.** Parsing and diffing are pure and offline; nothing is
  installed without an explicit selection and the existing `OperationCenter` confirmation.

## Scope

**In:** a Brewfile grammar parser over `Data` (`tap` / `brew` / `cask`, quoting, the optional tap URL
positional, inline `trusted:` hashes, `#` comment lines, Ruby conditionals) producing a typed entry
model plus typed counted skips; a pure diff projection (present / missing / skipped-with-reason)
against the resident `InstalledInventory` and `TapInventory`; a selection → `[AnyBrewMutation]` plan
fanned out through the shipped `OperationCenter`; a `brew bundle dump` source writing to a Cellar temp
path with the U6-pinned argv, plus atomic publication to a user-chosen destination through the
existing `CatalogFileSystem` seam; a `@MainActor @Observable` Brewfile store; import/export
affordances and a diff-preview surface inside the existing Taps section; byte-exact `brew bundle`
fixtures, the repo's first.

**Out (non-goals):** anything `m5-health` owns — `brew doctor`, the health dashboard and score, last
`brew update`, bulk pin/snooze polish; MAS, VSCode, and non-Homebrew manager entries (`go`, `cargo`,
`uv`, `npm`, `krew`, `flatpak`, `winget`) — parsed only far enough to be counted skips, never applied;
`brew bundle install`, `check`, `cleanup`, `exec`, `sh`, `env`, `add`, `remove`, `edit`; `--global`
Brewfile locations; evaluating Ruby, ever; `postinstall:` and other option hashes beyond `trusted:`
recognition; Brewfile *editing* inside Cellar; a new `AppSection` case; any `CatalogPackage`,
`CatalogSnapshot`, or `currentSchemaVersion` change; any new SwiftPM target.

## Capabilities

- **New `brewfile-management`** — the accepted grammar and its refusal rules, the typed entry model,
  the skip taxonomy and its counting rule, the diff projection, the selection-to-mutation plan, the
  dump-to-temp acquisition and its exit/stream contract, atomic publication, and every security
  invariant above.
- **Modified `package-mutation`** — one requirement restating the argv-provenance premise now that a
  user-supplied file is a name source: file-sourced names MUST be admitted only through the existing
  unrepresentability gate, and MUST NOT reach argv by any other path.
- **Read from, unmodified:** `installed-inventory`, `tap-management`, `operation-activity`,
  `brew-execution`.

## Approach

**Import is A2, on a security ground, not a stylistic one.** Cellar reads the file's bytes and parses
them itself; the diff is computed against inventory the app already holds, so the preview costs *zero*
new brew invocation — the same "costs no new acquisition" guarantee slices 1 and 2 shipped as spec
requirements. A1 is rejected by U8 as fact, not inference. This also sidesteps homebrew-bundle #401
(`check` and `check --verbose` disagree on exit code with `mas` entries — precisely the entry kind v1
excludes) and avoids inventing a fourth payload rule that would contradict the three shipped
`InstalledPayload` / `ServicesPayload` / `TapPayload` sources by treating a non-zero exit as the
informative answer.

**Selective apply is fan-out, not a filtered temp Brewfile.** Each chosen entry becomes an existing
`TapCommand.addTap(TapName)` or `MutationCommand.install(PackageTarget)`, submitted through
`OperationCenter`. That inherits per-entry queue items, streamed logs, copy-command, cancel, terminal
outcomes, one `HistoryDraft` per outcome, and scoped invalidation, for free. It adds **no**
`BrewMutating` conformer and **no** `InvalidationScope` bit. A mixed tap+install batch maps to
`[AnyBrewMutation]` before `request(_:)` (which is generic over one concrete type); because
`addTap.requiresConfirmation == true`, any batch containing a tap raises exactly one confirmation
carrying the `tapTrust` disclosure — the correct behaviour, not a workaround.

**Export is E3.** `brew bundle dump --file <Cellar temp> --force --formula --cask --tap` (U6: exit 0,
document on the file, diagnostics on stderr, mas/vscode excluded by the positive type filters,
`#` description comments emitted by default on this version). Cellar then reads those bytes, shows
them, and writes the user's destination atomically through `CatalogFileSystem`. Brew stays
authoritative for content — portability is the user's whole reason for exporting — while Cellar stays
responsible for what lands on the user's disk, and `--force` can never overwrite a user file because
the temp path is always fresh. The export path issues no package mutation and invalidates no
inventory. **E2** (a pure Cellar writer) remains the recorded fallback if the dump source proves
awkward during apply.

**Placement is the existing Taps section**, matching PRD §3.7's own grouping. No `AppSection` case, no
`ContentView` arm, no `cellarApp` scene change — and because `cellar/Taps/` is already a
`PBXFileSystemSynchronizedRootGroup`, new view files produce a **0-line `project.pbxproj` diff**.

| Area | Impact |
|---|---|
| `Sources/BrewClient/BrewfileEntry.swift`, `BrewfileParser.swift`, `BrewfileDiff.swift`, `BrewfilePlan.swift`, `BrewfileStore.swift` | New |
| `Sources/BrewClient/BundleDumpCommand.swift`, `BundleDumpSource.swift` | New (E3) |
| `Sources/BrewClient/MutationCommand.swift` | Modified — provenance reasoning block only, no behaviour change |
| `Sources/Catalog/CatalogFileSystem.swift` | Reused as-is; any widening must leave `catalog-sync` and follow-up S4 untouched |
| `cellar/Taps/` — import picker, diff preview, export sheet | New/Modified, **0-line pbxproj diff** |
| `Tests/BrewClientTests/Fixtures/Bundle/` | New — byte-exact, to the `Fixtures/Cleanup` standard |
| `Packages/CellarCore/Package.swift`, `cellar.xcodeproj` | **Untouched** |

## Probe Gate — U6, U8, U9 reported; gate closed for design

| Probe | Result |
|---|---|
| **U8** (decisive) | **CONFIRMED**: `brew bundle check --file <path>` evaluates the Brewfile's Ruby (marker-file proof; exit 1 with "can't satisfy your Brewfile's dependencies"). Explore §3.1 inference is now fact; A1 is off the table. |
| **U6** | Dump argv pinned: `--file <path> --force --formula --cask --tap` → exit 0, only `tap`/`brew`/`cask` lines plus `#` description comments (emitted **without** `--describe` on this version), stderr carried an unrelated warning at exit 0 — stream split confirmed. |
| **U9** | `trusted:` serialisation pinned from a real dump on this machine: `tap "name"[, "url"], trusted: { casks: [...] }`. The grammar **MUST** accept the optional URL second positional. |
| **U7** | Moot under A2 — no bundle-check payload source exists. |
| **U10** | Deferred to apply — requires Cellar's projection to exist before it can be diffed against a real dump. Under E3 it is a divergence check, not a gate. |

## Risks

| Risk | L | Mitigation |
|---|---|---|
| A future contributor "simplifies" import by passing the user's file to `brew bundle` | High | The invariant is a spec requirement with a test, not a comment; U8's evidence is recorded in the spec rationale |
| Grammar gaps make Cellar's reading silently wrong | High | Every unrecognised construct is a **counted, named skip** — never a silent drop; the count is `0`, not absent, when clean (slice 2 precedent) |
| **Forecast overrun** | **High** | See Delivery. The shared M5 forecast (1,800–2,600) is not trusted: slice 1 measured 3,619 against 1,500–2,100 and slice 3 measured 9,736 against 3,700–4,700 and needed a user-accepted `size:exception`. `sdd-tasks` MUST forecast honestly and may need to recommend slicing |
| Casks needing a sudo password fail opaquely — first surface to hit this at scale (`standardInput = FileHandle.nullDevice`) | Med | A named, honest terminal outcome rather than a bare non-zero exit; a stated non-goal to prompt for a password |
| First file-picker surface in the app; `ENABLE_USER_SELECTED_FILES = readonly` sits inert behind `ENABLE_APP_SANDBOX = NO` | Med | Recorded as a latent trap: if the sandbox is ever enabled, that setting blocks the export write while still permitting the import read. Not changed in this slice |
| `brew bundle` is unfixtured anywhere in the repo | Med | Byte-exact fixtures with brew version, exact argv, exit code, `probe-manifest.txt`, per-stream SHA-256 |
| Cellar's diff disagrees with brew's | Med | The UI states this is **Cellar's** reading of the file; U10 prices divergence during apply |
| A new spy repeats the slice-3 `GlobalRequestSpy` false-zero defect | Med | Per-instance tagged ledgers only; do **not** copy `cellarTests/SecurityCompositionSupport.swift`'s `CompositionRequestSpy` |
| Catalog footprint follow-up S4 (2.4% headroom) | Low | This slice spends none of it; `CatalogFootprintTests` must pass **unchanged and un-rebased** |
| Temp dump files leak | Low | Cellar-owned path, removed on both success and failure; asserted |

## Rollback Plan

Purely additive and revertible by a single `git revert` of the slice PR. Per `rules.proposal`, the two
project-level files are named explicitly: **`Packages/CellarCore/Package.swift` and
`cellar.xcodeproj/project.pbxproj` are untouched** — no new target, no new product, no target-membership
or build-setting change, and new app sources land inside the existing `cellar/Taps/`
`PBXFileSystemSynchronizedRootGroup`, so they revert as plain file deletions. Checks after revert:
`swift build --package-path Packages/CellarCore` and `xcodebuild build -scheme cellar`.

User state: no cache file, no schema version, no Keychain item, no `UserDefaults` key is introduced,
so a revert orphans nothing. Brewfiles already exported to the user's disk are ordinary user files and
survive by design; temp dump files are removed at the end of every export attempt.

## Delivery

Session budget **5,000** lines, `single-pr`, strict TDD. Honest forecast, stated with the overrun
history above in view: **2,600–4,200** authored source+tests, **4,200–6,500** including lifecycle
artifacts. **The 5,000-line budget is at genuine risk.** No exception is requested here; the review
workload guard resolves at `sdd-tasks`, which MUST produce the explicit guard lines and, if the
forecast holds high, either recommend chained slices (parser+diff, then apply+export, then UI) or
surface a `size:exception` for user decision before apply starts.

## Success Criteria

- [ ] A user can export their current taps, formulae and casks to a Brewfile of their choosing, and
      the bytes that land are the bytes `brew bundle dump` produced.
- [ ] A user can open someone else's Brewfile and see, offline and instantly, what they already have,
      what is missing, and what was skipped and why.
- [ ] **No brew process is ever launched with a path Cellar did not write** — asserted structurally,
      not by convention.
- [ ] Importing a hostile Brewfile (Ruby side effects, `postinstall:`, shell metacharacters in names,
      unrepresentable identifiers) executes nothing and installs nothing — reachable in unit tests
      with no process.
- [ ] A `trusted:` option never grants trust; a tap it names still raises the `tapTrust` confirmation.
- [ ] Every unsupported entry kind is counted with a named reason, and the count is `0` — not absent —
      for a clean file.
- [ ] Selective apply installs exactly the selected entries and nothing else, through the existing
      `OperationCenter`, with one `HistoryDraft` per terminal outcome.
- [ ] `CatalogFootprintTests` passes **unchanged**; `Package.swift` and `project.pbxproj` show a
      0-line diff.
- [ ] D1–D6 are each traceable to a spec requirement before design closes.

## Resolved Decisions (binding)

D1–D3 were taken by the maintainer in the pre-proposal decision round (obs 7520) and are fixed. D4–D6
are settled here, per the exploration's recommendations, and are equally binding: specs derive from
them and MUST NOT reopen them. Each names what was rejected.

- **D1 — Import is A2: Cellar parses the Brewfile itself.** The file is read as bytes; the diff is
  computed against the resident `InstalledInventory` and `TapInventory`. **Rejected: A1**
  (`brew bundle check --file <user path>`), disqualified by probe U8 as a code-execution path, and
  additionally by homebrew-bundle #401 and by the payload-rule inversion it would require.
  **Also rejected: A3**, the hybrid "run the whole file with brew" escape hatch — a second path to
  maintain and a disclosure obligation, in the slice already forecast largest-but-one.
- **D2 — Export is E3: dump to a Cellar temp path, publish atomically.** Brew remains authoritative
  for content; Cellar remains responsible for the write. **Rejected: E1** (dump straight to the user's
  path), which hands atomicity and `--force` overwrite semantics to a subprocess. **E2** (a pure
  Cellar writer) is recorded as the fallback, defensible against the PRD's exact words ("`brew bundle
  dump` **semantics**"), not discarded.
- **D3 — The UI lives inside the existing Taps section.** No new `AppSection` case, matching PRD
  §3.7's own grouping and keeping the sidebar flat while slice 5 adds `.health`. **Rejected:** the
  shared M5 exploration's assumed `cellar/Brewfile/` sidebar section.
- **D4 — `trusted:` is parsed, surfaced, and never honoured implicitly.** It is recognised as grammar
  (including the optional tap URL positional pinned by U9) so it cannot corrupt parsing, is shown to
  the user as a trust claim made by the file's author, and confers nothing: any tap it names still
  raises `ConfirmationDisclosure.tapTrust`. **Rejected:** silently ignoring the option (drops
  security-relevant content), and refusing any file containing it (dumps taken on this machine's
  Homebrew 6.0.15 routinely contain it).
- **D5 — Unsupported entry kinds are counted skips with a named reason.** `mas`, `vscode`, `go`,
  `cargo`, `uv`, `npm`, `krew`, `flatpak`, `winget` and anything unrecognised each carry a typed
  reason, following the shipped `skippedRecordCount` / `CleanupParseIssue` / `unknownLines` idiom. The
  count is `0`, not absent, when the file is clean. **Rejected:** silent drops, and refusing files
  that contain them — a MAS-heavy Brewfile still has usable formulae and casks.
- **D6 — Ruby conditionals are skip-and-count, not whole-file refusal.** `brew "gnupg" if OS.mac?` is
  a common idiom; the condition is **never evaluated**, the line is skipped, and the skip is counted
  with its own reason so the user knows their file was read partially. **Rejected:** refusing the
  whole file over one common idiom (hostile), and evaluating the condition (violates the invariant).
