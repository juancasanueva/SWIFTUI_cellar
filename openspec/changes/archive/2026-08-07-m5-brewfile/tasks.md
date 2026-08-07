# Tasks: M5 Brewfile Import & Export

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | **6,500–9,500** authored source+tests+fixtures+app (~1,800–2,200 CellarCore source, ~2,500–3,400 CellarCore tests, ~450–650 fixtures + README/manifest, ~650–850 app, ~250 `cellarTests`, ~150 `cellarUITests`); **7,700–11,000** including this change's lifecycle markdown |
| Session review budget | **5,000** lines (`openspec/config.yaml` `review_budget_lines`) |
| 5,000-line budget risk | **High — the forecast exceeds the budget outright**, not at its top edge |
| 2,000-line budget risk | High |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 = Phases 0–2 (spine + fixtures + parser); PR 2 = Phases 3–8 (diff, plan, export, publication, store, structural guards); PR 3 = Phases 9–10 (app layer + close-out) |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

**Why the forecast is not the proposal's.** The proposal offered 2,600–4,200 authored. Prior-slice
calibration says that shape of estimate has been wrong twice, in the same direction: slice 1 measured
**3,619** against a 1,500–2,100 forecast (1.9×); slice 3 measured **9,736** against a 3,700–4,700
forecast (2.3×). This slice is *larger* than slice 3 by requirement count (11 requirements / 43
scenarios vs 9 / 39), carries a shipped-spine modification slice 3 did not, and adds an app-side
import/export UI. Forecasting under 5,000 here would be low-balling a number that has already been
observed to double. The range above applies the measured 1.9–2.3× correction to a bottom-up count.

This is a real fork and therefore a decision, not an assumption:

- **Option A — single PR with `size:exception`.** Honours `delivery_strategy: single-pr`. Requires a
  maintainer to accept a diff that is likely twice the budget. Slice 3 needed exactly this.
- **Option B — three PRs, feature-branch-chain.** PR 1 base = the feature/tracker branch, PR 2 base =
  PR 1 branch, PR 3 base = PR 2 branch. Each slice below is separately provable and separately
  revertible; every slice is forecast under 5,000 on its own.
- **Option C — two PRs.** PR 1 = Phases 0–2 (the spine change lands early and alone-ish, where a
  regression is cheapest to attribute); PR 2 = Phases 3–10.

The cut points are pre-agreed either way. If the real diff crosses 5,000 mid-apply, cut at **Phase 3**
first and **Phase 9** second. Nothing in Phases 0–2 depends on later phases, and no requirement in
either delta spec is app-side (D3 is carried by tasks, not by a requirement).

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | The DD1 spine change (`disclosure` becomes a `BrewMutating` requirement), the `Fixtures/Bundle/` capture, and the whole parser: grammar, `trusted:`, counted skips, hostile input (Phases 0–2) | PR 1 | `FAST --filter "BrewMutating\|ConfirmationDisclosure\|BrewfileEntry\|BrewfileParser\|BrewfileSkip\|BrewfileFixtureManifest\|ConfirmationBacklog\|ForceDenialRecovery\|BulkFanOut\|TapCommand"` | Replay the captured real `brew bundle dump` output (task 1.1) through `BrewfileParser.decode` offline: every line must land as a typed entry or a *named* skip, with zero `.unrecognisedLine` surprises (this is U10, run as a divergence check, not a gate) | `git revert` the merge. `Sources/BrewClient/Brewfile{Entry,Parser}.swift` and `Tests/BrewClientTests/Fixtures/Bundle/` are removed; `BrewMutating.swift` and `OperationCenterBulk.swift` return to `(first as? TapCommand)?.disclosure ?? .packageRemoval`. No existing target gains a dependency and `Package.swift` is untouched, so nothing else can break |
| 2 | Diff, plan, export dump, atomic publication, the store, and the structural argv guards (Phases 3–8) | PR 2 | `FAST --filter "BrewfileDiff\|BrewfilePlan\|BundleDump\|BrewfilePublication\|BrewfileStore\|BrewfileArgvStructure\|CatalogFootprint"` | Run a real `brew bundle dump --file <tmp>/cellar-brewfile/<UUID>/Brewfile --force --formula --cask --tap` through `BundleDumpSource` against the live binary: exit 0 produces a document, the temp directory is gone afterwards, and `ls` of the user's home shows no new file | `git revert` the merge; the five new `Brewfile*`/`BundleDump*` sources and their suites disappear. Phase 0's spine survives independently, so PR 1 does not have to be reverted with it |
| 3 | AppKit panel seams, the import and export sheets, the two Taps-toolbar affordances, composition + E2E, close-out (Phases 9–10) | PR 3 | `APP --only-testing:cellarTests/BrewfileCompositionTests` then `FULL` | Launch: Taps toolbar → Import, choose `mixed-kinds.brewfile`; missing entries are pre-selected, installed entries are visible and unselectable, skips show counts with named reasons and line numbers, and the import button is still enabled. Import a tap-carrying selection and read the confirmation text: it must be the tapTrust text, **not** "This removes installed software." | Delete `cellar/Taps/Brewfile{ImportSheet,ExportSheet,Panels}.swift` and revert `cellar/Taps/TapsListView.swift`. **Zero** `project.pbxproj` objects to remove — the files live in the synchronized root group |

If chained, PR 2 base = PR 1 branch and PR 3 base = PR 2 branch (feature-branch-chain).

### Legend

- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `cellarTests/`, `cellarUITests/`
  or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `APP` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- `BUILD` = `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Spec tags — `brewfile-management` (ADDED-only, 9 req / 38 sc): **BF1** brew is never pointed at a
  file Cellar did not write, **BF2** an imported Brewfile is bytes and nothing in it is evaluated,
  **BF3** the grammar is exactly tap/brew/cask with their pinned serialisations, **BF4** every
  unaccepted construct is a counted skip with a named reason and the count is zero not absent,
  **BF5** `trusted:` is parsed, surfaced, and confers nothing, **BF6** the diff is a pure offline
  projection costing no new acquisition, **BF7** a selection becomes existing typed mutations and
  nothing else, **BF8** export dumps to a Cellar-owned temp and the subprocess never touches the
  user's disk, **BF9** publication is Cellar's atomic write to a destination chosen for that export.
  `package-mutation` (2 whole-block MODIFIED, 43 → 48 sc): **PM1** a confirmation disclosure survives
  command erasure, **PM9** a file-sourced name is validated at construction with no bypass.
- Design tags **DD1**–**DD6** (`design.md`). Threat-matrix tags — **TM1** documentation-like paths (a
  Brewfile is evaluated Ruby; U8 proved `brew bundle check` executes it), **TM2** argument composition
  from a file-sourced name, **TM3** subprocess file authority. Git repository selection, commit state,
  push state and PR commands are `N/A` — no VCS or PR automation — and have no task.
- Strict TDD (`config.yaml` `apply.tdd: true`): every `RED` task lands a failing test; the following
  `GREEN` task makes it pass. No production line without a red test. A task marked `GUARD` is a
  characterisation test that is green before *and* after its phase — it is written first anyway,
  because its job is to catch a regression the phase could silently introduce.
- Binding: `@concurrent` goes on its **own line before** `public static func` on
  `BrewfileParser.decode` — the other order does not compile and cost an apply cycle in M1.
- Binding: `Package.swift` and `cellar.xcodeproj/project.pbxproj` are **UNTOUCHED**. New fixtures go
  under the already-declared `Tests/BrewClientTests/Fixtures/` resource; new app views go inside the
  existing `cellar/Taps/` synchronized root group. Confirm with `git diff --stat` at 10.1.
- Binding: `MutationName.isSafe` (`MutationCommand.swift:104-108`) rejects only empty, leading `-`,
  and whitespace. `/` passes, so `brew "user/repo/token"` is representable and there is **no gate
  widening task** — do not add one.
- Binding: any new app-target spy is **per-instance** (tagged ledger + `Mutex`). Do **not** copy
  `cellarTests/SecurityCompositionSupport.swift`'s `CompositionRequestSpy` — that is the slice-3
  false-zero shape and it will assert nothing.
- Binding: `Sources/Catalog/CatalogFileSystem.swift` is **reused as-is, never widened**, so the
  carried follow-up S4 consumes zero headroom. `CatalogFootprintTests` must pass unchanged and
  un-rebased (task 8.3), with a zero-line diff.

---

## Phase 0: The spine change (DD1, PM1) — lands first, before any new feature file exists

The only shipped-code modification in this change. It goes first so a regression surfaces against the
existing suite rather than against six new files.

- [x] 0.1 GUARD `Tests/BrewClientTests/BrewMutatingTests.swift`: characterise `AnyBrewMutation`'s
      equality and hashing **before** it gains a stored property — two erased values are equal iff
      their projections match, `ConfirmationRequest ==` is what gates `confirm`/`decline`
      (`OperationCenterBulk.swift:151,158`), and `ActivityItem.command.verb` still drives
      `MutationConfirmation.isZap`. Then extend it deliberately: after 0.5, two commands differing
      **only** in `disclosure` are unequal and hash apart. State that in the test, do not discover it
      in `ConfirmationBacklogTests`.
- [x] 0.2 RED create `Tests/BrewClientTests/ConfirmationDisclosureTests.swift` (**PM1**): a mixed
      batch erased to `[AnyBrewMutation]` whose first element is a `TapCommand.addTap` produces a
      `ConfirmationRequest` carrying `.tapTrust`, identical to the unerased batch. **Fails today** —
      `OperationCenterBulk.swift:141` downcasts and falls back to `.packageRemoval`.
- [x] 0.3 RED same file: an erased install-only batch produces `.packageRemoval`; every shipped call
      site's disclosure is unchanged (`submitBulk(.uninstall)` → `.packageRemoval`, a single unerased
      `TapCommand` → `.tapTrust`, `requestCleanup` builds its request directly and is untouched); a
      command declaring no disclosure supplies `.packageRemoval` **by protocol default, not by caller
      fallback**.
- [x] 0.4 RED same file, structural: a `#filePath`-rooted scan of `Sources/BrewClient/` finds no
      `as? TapCommand`, `is TapCommand`, case switch or verb-string inspection on a **disclosure**
      path. The shipped `isZap` verb read stays explicitly permitted — it selects a title, not a
      disclosure, and the spec says so.
- [x] 0.5 GREEN `Sources/BrewClient/BrewMutating.swift`: add `var disclosure: ConfirmationDisclosure
      { get }` to `BrewMutating` with an extension default of `.packageRemoval`; `AnyBrewMutation`
      stores it and copies it in `init(_:)` — the eighth projection. `ConfirmationDisclosure` is the
      module-level enum in `TapCommand.swift:43`; `TapCommand.disclosure` (`:115`) already satisfies
      the requirement unchanged.
- [x] 0.6 GREEN `Sources/BrewClient/OperationCenterBulk.swift:141`: `request(_ commands:)` reads
      `first.disclosure`; the cast is removed.
- [x] 0.7 Checkpoint: `FAST` and `APP` green with the spine changed and **no** new capability file in
      the tree. `ConfirmationBacklogTests`, `ForceDenialRecoveryTests`, `BulkFanOutTests`,
      `TapCommandTests` and `OperationCenterTests` must pass untouched. If one needs editing, that
      edit is the DD1 blast radius and belongs here, not four phases later.

## Phase 1: Fixtures (BF3, BF5, BF8, TM1) — the capture still owed from the probe round

- [x] 1.1 Capture `Tests/BrewClientTests/Fixtures/Bundle/` from the real binary:
      `brew bundle dump --file <tmp> --force --formula --cask --tap` on Homebrew 6.0.15. Record
      `dump-file.brewfile` (the file brew wrote, verbatim) and `dump-stderr.txt` (U6 saw an unrelated
      libtiff/webp warning at **exit 0** — that stream split is the point of the fixture).
- [x] 1.2 `Fixtures/Bundle/README.md` + `probe-manifest.txt` to the `Fixtures/Cleanup` standard:
      capture date, brew version, the exact argv, the exit status, the provenance of every stream, and
      a SHA-256 per stream and per file. Record U8's marker-file evidence here — `brew bundle check
      --file <path>` **evaluated** a `File.write` payload — because that is *why* `dump` is the only
      `bundle` subcommand this change may ever construct (**BF1**).
- [x] 1.3 Hand-author the adversarial fixtures beside them: `hostile-ruby.brewfile` (`File.write`,
      backticks, `$(...)`, `;`, `system(...)`), `mixed-kinds.brewfile` (mas/vscode/whalebrew/go/cargo/
      uv/npm/krew/flatpak/winget lines + `#` comments + blanks + a trailing comma + both quote styles
      + `brew "user/repo/token"` + `postinstall:`/`args:`/`link:` option hashes),
      `trusted-taps.brewfile` (U9's three lines **verbatim**, including the URL-positional form),
      `undecodable.brewfile` (invalid UTF-8 in one line only), `empty.brewfile` (zero bytes).
- [x] 1.4 RED create `Tests/BrewClientTests/BrewfileFixtureManifestTests.swift`
      (`SecurityKitTests/FixtureManifestTests` idiom): every stream named in `probe-manifest.txt`
      exists, loads from `Bundle.module`, and hashes to the recorded SHA-256. A silently re-saved
      fixture fails the suite.

## Phase 2: The entry model and the parser (BF2, BF3, BF4, BF5, PM9, TM1, TM2, DD2)

- [x] 2.1 RED create `Tests/BrewClientTests/BrewfileEntryTests.swift`: `BrewfileEntry.Kind` holds
      already-constructed `TapName`/`FormulaID`/`CaskID` and **no raw string**; there is no
      string-taking initialiser on any case; the entry is `Sendable, Hashable, Identifiable` and
      carries its `lineNumber`. A name that fails those initialisers is *unrepresentable as an entry*
      — that is the structural half of **PM9**.
- [x] 2.2 GREEN create `Sources/BrewClient/BrewfileEntry.swift`: `BrewfileEntry`, `BrewfileSkip`
      (line number + raw line + reason), `BrewfileSkipReason` (`unsupportedEntryKind(String)`,
      `unsupportedOption(String)`, `rubyConditional`, `unrepresentableName`, `unrecognisedLine`,
      `undecodableBytes`), `BrewfileTrustClaim`, `BrewfileDocument { entries, skips }`.
- [x] 2.3 RED create `Tests/BrewClientTests/BrewfileParserTests.swift`, the accepted grammar
      (**BF3**): `tap "n"`, `tap "n", "url"` (U9's positional URL), `brew "n"`, `cask "n"`; both quote
      styles; a trailing comma; and — from U6 — `#` comment lines and blank lines are **ignored, not
      counted as skips**, because this brew version emits descriptions without `--describe`.
- [x] 2.4 RED same file (**BF3**, the revision-2 amendment): `brew "user/repo/token"` from a
      third-party tap becomes a **formula entry**, not a skip. `MutationName.isSafe` accepts `/`, so
      degrading these lines would silently drop every third-party package from a real dump.
- [x] 2.5 RED same file (**BF5**, D4): `trusted: true` and `trusted: { casks: ["x", "y"] }` parse as
      grammar and are retained as a `BrewfileTrustClaim` **attributed to the file's author**; the
      claim records no trust, suppresses and downgrades no confirmation, and never enters argv. A tap
      it names still raises `.tapTrust` with identical text (proven end-to-end at 4.3).
- [x] 2.6 RED create `Tests/BrewClientTests/BrewfileSkipTests.swift` (**BF4**, D5): each unsupported
      kind (mas, vscode, whalebrew, go, cargo, uv, npm, krew, flatpak, winget) yields
      `.unsupportedEntryKind` naming it; an option key other than `trusted:` yields
      `.unsupportedOption(key)` — installing a stripped entry is not what the author wrote; each skip
      carries its line number and raw line; the reasons are mutually distinct; and a clean file
      reports `skips.count == 0`, **not** an absent collection.
- [x] 2.7 RED same file (**BF4**, confirmed assumption 3): **no skip class blocks the import.** A
      document that is 100% skips still parses to a usable document with an empty entry set, distinct
      from a read failure.
- [x] 2.8 RED same file (**BF2**, **TM1**, **TM2**) over `hostile-ruby.brewfile`: every Ruby residue
      line becomes `.rubyConditional`/`.unrecognisedLine` and the condition is **never evaluated**; a
      recording file seam proves nothing was written (no marker file appears) and a recording process
      seam proves **zero** launches; shell metacharacters in a name yield `.unrepresentableName`,
      never a command. `brew "gnupg" if OS.mac?` produces the identical skip on any host (D6).
- [x] 2.9 RED same file (**BF2**): invalid UTF-8 is tolerated at **line** granularity — one
      `.undecodableBytes` skip, the surrounding lines still parse; `empty.brewfile` yields a typed
      empty parse distinct from a read failure; input over 8 MiB throws `.tooLarge` and is **parsed
      never**.
- [x] 2.10 RED same file (**BF2**): parsing is pure — no environment read, no filesystem access beyond
      the `Data` it was handed, no network, and the result is host-independent. `decode` takes `Data`
      and returns a document; there is no URL-taking overload.
- [x] 2.11 GREEN create `Sources/BrewClient/BrewfileParser.swift` (DD2, `TapDecoder` shape):
      `@concurrent` on its own line before
      `public static func decode(_ data: Data) async throws(BrewfileParseError) -> BrewfileDocument`.
      Line-oriented, refuse-by-skip, never whole-file refusal except `.tooLarge`.

## Phase 3: The diff (BF6, D1, confirmed assumption 2)

- [x] 3.1 RED create `Tests/BrewClientTests/BrewfileDiffTests.swift`: three typed states — **missing**
      (defaults to *selected*), **present** (visible but **unselectable**), **skipped** (visible with
      its named reason and line number, unselectable). Selection state is a property of the diff, not
      of a view.
- [x] 3.2 RED same file: empty document, all-present and all-skipped are three distinct outcomes, none
      of them an empty list rendered as "nothing to do"; an official tap already in the resident
      `TapInventory` reads present.
- [x] 3.3 RED same file (**BF6**): the diff is computed against the resident `InstalledInventory` and
      `TapInventory` the caller already holds — a recording process seam sees **zero** launches, no
      network, and no forced re-snapshot. The result is presented as Cellar's reading of the file, not
      as brew's verdict.
- [x] 3.4 GREEN create `Sources/BrewClient/BrewfileDiff.swift`.

## Phase 4: The plan and the erased submission (BF7, PM1, PM9, DD1)

- [x] 4.1 RED create `Tests/BrewClientTests/BrewfilePlanTests.swift` (**BF7**): each selected entry
      becomes exactly one **existing** command — `TapCommand.addTap` or `MutationCommand.install` —
      one subject per argv; no new `BrewMutating` conformer, no new `InvalidationScope` bit; the plan
      contains the selected entries and nothing else; nothing is submitted without explicit selection.
- [x] 4.2 RED same file (**BF7**, DD1): taps are ordered **before** installs even when the tap was
      selected **last**. This is load-bearing twice — install sequencing, and disclosure selection,
      because `request(_:)` reads `commands.first`. Assert both consequences, not just the ordering.
- [x] 4.3 RED same file (**BF7**, **PM1**, **BF5**): a tap-carrying plan erased to
      `[AnyBrewMutation]` and passed to `OperationCenter.request` raises **exactly one**
      confirmation carrying `.tapTrust` — including when the file claimed `trusted:` for that tap.
      Confirming submits every command; declining submits **none**, never a partial subset.
- [x] 4.4 RED same file (**PM9**, **BF1**): every name reaching the plan was admitted through
      `TapName`/`FormulaID`/`CaskID` via `PackageTarget`; there is no file-sourced convenience
      constructor and no "already validated" bypass; a refused name is a typed **counted refusal**
      that reaches no queue, no argv and no process by any other path.
- [x] 4.5 GREEN create `Sources/BrewClient/BrewfilePlan.swift`. It cannot fail and cannot emit free
      text, because its inputs are already-constructed identities.
- [x] 4.6 `Sources/BrewClient/MutationCommand.swift`: replace the provenance reasoning block — the
      premise "names come from brew's own snapshot or the catalog, never free text" no longer holds
      now that a user file is a name source, and **PM9** requires that restatement to be deliberate.
      Comment only: `git diff` must show zero changed executable lines in this file, and `FAST` must
      be green without touching a single existing assertion.

## Phase 5: The export dump (BF1, BF8, TM3, DD3)

- [x] 5.1 RED create `Tests/BrewClientTests/BundleDumpCommandTests.swift` (**BF8**, U6): the argv is
      pinned **exactly** to `bundle dump --file <temp> --force --formula --cask --tap`, kind `.read`.
- [x] 5.2 RED same file (**BF1**), structural by enumeration: enumerate every constructible `bundle`
      argv this change can produce — `dump` is the only subcommand; `install`, `upgrade`, `check`,
      `cleanup`, `list`, `exec`, `sh`, `env`, `add`, `remove`, `edit` and `--global` are
      unrepresentable, not merely unused. U8 is why `check` is on that list.
- [x] 5.3 RED create `Tests/BrewClientTests/BundleDumpSourceTests.swift` over
      `Fakes/RecordingProcessLauncher.swift` (**TM3**): `--file` is a **fresh** `<tmp>/cellar-brewfile/
      <UUID>/Brewfile` per export, so `--force` can never reach a user file; a user-obtained path
      appears in **no** brew argv at any stage.
- [x] 5.4 RED same file (**BF8**): exit 0 → the document is read from the temp **file**; stderr never
      enters the document; a non-empty stderr at exit 0 is still a success (replay
      `dump-stderr.txt`).
- [x] 5.5 RED same file (**BF8**): a non-zero exit is a typed failure preserving **both** raw streams
      (the `CleanupPreviewError` shape — the only shipped payload error that keeps stdout and stderr).
- [x] 5.6 RED same file (**BF8**): the temp directory is removed on success, on failure **and** on
      cancellation, proven with a recording file seam; and the export forces no re-snapshot, submits
      no mutation, and writes no history entry.
- [x] 5.7 GREEN create `Sources/BrewClient/BundleDumpCommand.swift` and
      `Sources/BrewClient/BundleDumpSource.swift` — a `nonisolated Sendable` struct over
      `any ProcessLaunching` with `withTaskCancellationHandler`, mirroring `CleanupPreviewSource`,
      with the temp removal in a `defer` on **both** paths.

## Phase 6: Publication (BF9, D2, DD4, confirmed assumption 1)

- [x] 6.1 RED create `Tests/BrewClientTests/BrewfilePublicationTests.swift` (**BF9**): published bytes
      are **byte-identical** to the dump document, written through the existing
      `CatalogFileSystem.write(.atomic)` seam. `CatalogFileSystem` is reused unwidened — its public
      surface must be unchanged (assert it), which is what keeps follow-up S4's headroom at zero.
- [x] 6.2 RED same file (**BF9**): the destination is chosen **per export** — a
      `#filePath`-rooted scan finds no `UserDefaults`, no `@AppStorage` and no security-scoped
      bookmark on this path, and no default or well-known Brewfile location is ever written unless the
      user chose it. A remembered destination is M6 Settings, not this change.
- [x] 6.3 RED same file (**BF9**): a failed write leaves a pre-existing file **unchanged** with no
      partial artefact beside it; cancelling at the panel publishes nothing and still removes the
      temp.
- [x] 6.4 GREEN create the picker seams in `Sources/BrewClient/` (DD4): `BrewfileDestinationChoosing`
      and `BrewfileSourceChoosing`, `Sendable` protocols returning a plain `URL?`. CellarCore imports
      **no AppKit** — assert that structurally in the same suite.

## Phase 7: The store (DD5, DD6, BF6, BF9)

- [x] 7.1 RED create `Tests/BrewClientTests/BrewfileStoreTests.swift`: both state machines as **closed
      enums** (the `ServicesLoadState`/`InstalledLoadState` idiom) — `importState` = idle | reading |
      parsed | failed; `exportState` = idle | dumping | preview | published | failed. All state is
      `private(set)`; no state is an empty value, `nil`, or a never-settling pending case.
- [x] 7.2 RED same file: selection initialises to the **missing** set; present entries are rendered
      unselectable; skips never gate the import button (confirmed assumptions 2 and 3, restated at the
      store level where the UI actually reads them).
- [x] 7.3 RED same file (DD6): a cask install that failed because it needed an administrator password
      (`SystemProcess` sets `standardInput = .nullDevice`, so it fails opaquely) yields a
      **Brewfile-scoped** `BrewfileApplyAdvisory` derived from the terminal item's log — it names the
      cask, says Cellar cannot supply a password, and says to install it from Terminal. Assert that
      `MutationCommand.classify`'s shipped outcome vocabulary is **unchanged**: no new
      `MutationOutcome` case, nothing leaking into `package-mutation` or `HistoryDraft`. Prompting
      stays a non-goal.
- [x] 7.4 GREEN create `Sources/BrewClient/BrewfileStore.swift`: `@MainActor @Observable public final
      class`, `@ObservationIgnored` internals, awaiting nonisolated results and assigning them. No new
      actor, no `nonisolated(unsafe)`, no `#available`.

## Phase 8: Structural guards and regression (BF1, TM1, TM2, TM3)

- [x] 8.1 RED create `Tests/BrewClientTests/BrewfileArgvStructureTests.swift` (**BF1**): across the
      whole Brewfile surface, **no** `BrewCommand.arguments` element derives from a user-chosen URL or
      from a raw file line; every `--file` value is a Cellar-created temp path. This is the one test
      that proves the change's headline invariant rather than assuming it.
- [x] 8.2 RED same file, source scan of `Sources/BrewClient/Brewfile*.swift` and `BundleDump*.swift`
      (the `SecurityCompositionSupport` comment-stripping idiom, so a doc comment quoting a forbidden
      string does not fail the build): no `Process`, no `/bin/sh`, no `import AppKit`, no Ruby
      evaluation, and none of the forbidden `bundle` subcommand strings from 5.2.
- [x] 8.3 RED regression (carried follow-up **S4**): `Tests/CatalogTests/CatalogFootprintTests.swift`
      runs **unchanged and un-rebased**, with a **zero-line** diff, and passes beside this change.
      Do not touch that file. `CatalogFileSystem` was reused, not widened, so its headroom is intact.
- [x] 8.4 U10 divergence check (**not a gate**): parse the captured real dump from 1.1 with
      `BrewfileParser` and confirm every line lands as a typed entry or a **named** skip, with zero
      `.unrecognisedLine`. Any divergence becomes a grammar row recorded in `design.md` →
      *Apply-Time Amendments*, never a silent parser tweak.

## Phase 9: App layer (D3, DD4) — 0-line `project.pbxproj` diff

- [x] 9.1 GREEN create `cellar/Taps/BrewfilePanels.swift`: `NSOpenPanel`/`NSSavePanel` conformers for
      `BrewfileSourceChoosing`/`BrewfileDestinationChoosing`, hopping to `@MainActor` internally. The
      sandbox is off, so no security-scoped bookmarks; record `ENABLE_USER_SELECTED_FILES = readonly`
      here as the latent trap it is (inert behind `ENABLE_APP_SANDBOX = NO`; if the sandbox is ever
      enabled it blocks the export write and permits the import read).
- [x] 9.2 RED create `cellarTests/BrewfileCompositionTests.swift` with a **per-instance** tagged
      ledger guarded by a `Mutex` — explicitly **not** `SecurityCompositionSupport`'s
      `CompositionRequestSpy`, whose shared shape produced slice 3's false zero. Assert through the
      composed app wiring that a tap-carrying import surfaces **exactly one** confirmation carrying
      the tapTrust disclosure.
- [x] 9.3 GREEN create `cellar/Taps/BrewfileImportSheet.swift`: the diff list — missing pre-selected,
      present visible and disabled, skips as counts with named reasons and line numbers; the import
      button stays enabled when only skips are present.
- [x] 9.4 GREEN create `cellar/Taps/BrewfileExportSheet.swift`: the preview of the dump document,
      then the save panel. The panel opens **only after** a successful preview, so a dump failure
      never reaches the user's disk.
- [x] 9.5 GREEN `cellar/Taps/TapsListView.swift`: two `.toolbar` affordances inside the **existing**
      Taps section (D3). No new `AppSection` case, no new navigation destination. Confirm
      `git diff --stat cellar.xcodeproj` is **empty** — the files land in the synchronized root group.
      Check: `BUILD`.
- [x] 9.6 RED then GREEN in `cellarUITests`: importing `mixed-kinds.brewfile` shows counted skips with
      named reasons and still permits import; a tap-carrying import shows the **tapTrust** text and
      not "This removes installed software." — the DD1 defect, proven at the surface a user reads.

## Phase 10: Close-out

- [x] 10.1 Run `FAST`, `APP`, `FULL` and `BUILD` green. Confirm the `@Test` count is strictly above the
      pre-change count and that no pre-existing assertion was deleted or weakened — `git diff -U0`
      over `Tests/`, `cellarTests/` and `cellarUITests/` must remove no assertion line. Confirm
      `git diff --stat` shows **zero** changes to `Packages/CellarCore/Package.swift` and
      `cellar.xcodeproj/project.pbxproj`, and a zero-line diff on `CatalogFootprintTests.swift`.
- [x] 10.2 Record in `design.md` → *Apply-Time Amendments*: U10's divergence result (8.4), any grammar
      row the real dump forced, the DD1 equality consequence from 0.1, and anything else evidence
      forced. Recorded, never absorbed silently.
- [x] 10.3 Rollback note: one `git revert` restores `main`. No migration, no cache file, no schema
      version, no `UserDefaults` key, no Keychain item is introduced. Note that Phase 0's spine change
      is the only shipped-code modification — reverting it restores
      `(first as? TapCommand)?.disclosure ?? .packageRemoval` and the tapTrust downgrade with it, so a
      partial revert must not stop halfway.
- [x] 10.4 Surface to the user, **before the PR opens** (slice-2 and slice-3 precedent): the
      `BrewfileApplyAdvisory` copy from 7.3, and the skip-reason wording from 2.6 — a user reading
      "9 entries skipped" must be able to tell why without opening the file. The tests prove these are
      named constants that render; they do not prove the wording is honest enough.
      Presented verbatim to the user 2026-08-07 (advisory, six skip-reason sentences, on-screen skip
      group shape, four import-summary lines); **accepted as-is** with no rewording (obs #7520).
