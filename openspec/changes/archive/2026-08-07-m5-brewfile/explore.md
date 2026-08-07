# Exploration: Brewfile import/export (`m5-brewfile`, M5 slice 4 of 5)

PRD anchor: **§3.7 "Taps & Brewfile"**, milestone **M5** (§7). Repository evidence read at clean
`main` `7d48779` (slice 3 `m5-release-notes` archived). Artifact store hybrid; Engram topic
`sdd/m5-brewfile/explore`.

**Executor limitation, stated up front:** this run had **no shell and no Write tool**. No probe was
run, and the OpenSpec copy of this document was not written by me. Everything below is from repository
source (read via codegraph/Read/Grep), the archived M5 artifacts, and Homebrew's published
documentation. The three findings marked **INFERENCE** are explicitly not verified facts.

---

## 1. What the PRD actually scopes for slice 4

PRD.md §3.7, verbatim:

> **Brewfile import/export**: generate a Brewfile from current state (`brew bundle dump` semantics —
> taps, formulae, casks; MAS entries excluded in v1), export to file/share sheet; import a Brewfile
> with a diff preview (what would be installed/missing) and selective apply via `brew bundle --file`.

Four obligations: (1) export a Brewfile of taps + formulae + casks, MAS excluded; (2) a file/share
export affordance; (3) an import **diff preview** naming what is installed vs missing; (4) **selective**
apply. Nothing else in the PRD constrains it. §9's open questions do not mention Brewfile.

Explicitly **out of scope** for this slice (slice 5 `m5-health` owns them): `brew doctor`, the health
dashboard and score, last-`brew update`, and the bulk pin/snooze polish that reverses
installed-inventory II13 sc4.

The shared M5 exploration (`openspec/changes/m5-pro-parity/explore.md` §4) already recorded a
recommendation for this slice: fan out a selection into ordinary `MutationCommand`s rather than write
a filtered temporary Brewfile. **That recommendation survives this exploration and is now supported by
concrete repository evidence** (§4 below) — but its stated rationale ("first untrusted-argv source")
turns out to understate the problem by a category (§3).

---

## 2. Current state — what already exists that this slice consumes

### Target graph (`Packages/CellarCore/Package.swift`, read in full)

Products: `BrewProcess`, `Catalog`, `DiskUsage`, `BrewClient`, `SecurityKit`, `ReleaseNotes`,
`Persistence`. Edges: `Catalog` and `BrewProcess` are leaves; `DiskUsage → {BrewProcess, Catalog}`;
`BrewClient → {BrewProcess, Catalog, DiskUsage}`; `SecurityKit → {Catalog}`;
`ReleaseNotes → {Catalog}` (added by slice 3); `Persistence → {BrewClient, SecurityKit}` as the
outermost node. All `.swiftLanguageMode(.v6)`, platform `macOS 26.0`.

**No new target is needed.** Brewfile work is brew-facing and inventory-facing, so it belongs in
`BrewClient`, which already sees `BrewProcess`, `Catalog` and `DiskUsage`. Unlike slice 3, `Package.swift`
can stay untouched — which also keeps rollback at one `git revert`.

### The data the export needs is already resident

| Need | Already held by | Notes |
|---|---|---|
| Formulae + casks, on-request vs dependency | `InstalledInventory` / `InstalledPackage` (`InstalledModels.swift`) | `isOnRequest` is `kegs.contains(where: \.installedOnRequest)`; `packages(includingDependencies:)` already filters |
| Taps | `TapInventory` / `TapRecord` (`TapWire.swift`) | carries `name`, `user`, `repository`, `remote` (already credential-redacted by `TapDecoder.redactedURL`) |
| Package identity that is safe in argv | `PackageTarget` / `FormulaID` / `CaskID` / `TapName` | `TapName` additionally enforces exactly two `/`-separated ASCII components |

So a Brewfile can be generated **with zero new brew invocation**, reusing the "costs no new
acquisition" idiom slices 1 and 2 both shipped as a spec requirement.

### Command / mutation spine (all shipped, all reusable unchanged)

- `BrewCommand` (`BrewProcess/BrewCommand.swift`) — argv only, `.read` vs `.mutate`, never a shell
  string, never `/bin/sh -c`; `standardInput = FileHandle.nullDevice` in `SystemProcess`.
- `BrewMutating` (`BrewClient/BrewMutating.swift`) — `arguments`, `verb`, `packageID`,
  `requiresConfirmation`, `invalidates: InvalidationScope` (`installedInventory | services | taps |
  diskUsage`), `diskAreas`, `environmentOverrides`, `classify(...)`; `AnyBrewMutation` erases it and
  **itself conforms to `BrewMutating`**.
- `OperationCenter.submit(_:versions:)` / `.request([some BrewMutating])` / `.confirm(_:)` —
  one confirmation covering N commands, all-or-nothing (`OperationCenterBulk.swift:126-154`).
  `finish(...)` writes exactly one `HistoryDraft` per terminal outcome by construction.
- `OperationCenterBulk.commands(for:over:)` keyed on `BulkSelection.Action`, **`CaseIterable` with
  exactly two cases** so "no bulk pin/unpin/snooze exists" is a test assertion (II13 sc4). Brewfile
  apply needs **install**, which is not one of those two — see §4 for why that is not a blocker.
- `TapCommand` (`TapCommand.swift`) — `.addTap` already `requiresConfirmation == true` and carries
  `ConfirmationDisclosure.tapTrust(TapName)`: *"Adding \(tap) trusts third-party formulae and casks
  that can distribute code."* Exactly the disclosure a Brewfile's `tap` lines need.
- `CleanupCommand` + `CleanupPreviewSource` — the shipped **preview-then-mutate** pair. `previewCommand`
  is a `.read` dry-run; `CleanupPreviewError.commandFailed(status:rawStdout:rawStderr:)` is the only
  payload error in the repo that **preserves both raw streams** on a non-zero exit.

### Payload-rule precedent (this matters — see §3.2)

`InstalledPayload`, `ServicesPayload` and `TapPayload` all encode the same three rules verbatim:
non-zero exit is an **error**; **stderr never enters the document, at any position**; blank document is
malformed. `ServicesPayloadSource.swift:115-159` states the reasoning in a comment.

### App shell

`cellar/Shell/AppSection.swift` has nine cases: `home, discover, browse, installed, taps, services,
cleanup, security, history`. There is **no** `brewfile` case. `cellar/Taps/TapsListView.swift` is a
plain list + add-bar with no export/import affordance. The new-sidebar-section pattern
(`AppSection` case + `ContentView` arms + a `PBXFileSystemSynchronizedRootGroup` view directory, zero
`project.pbxproj` diff) is proven twice (Discover, and slice 5 will reuse it for Health).

### Consent vocabulary

`ScanConsent` (M4) and `ReleaseNotesConsent` (slice 3) are the same mechanism applied twice: a value
with one constructor requiring a date, an `authorise()` that **throws** rather than returning `Bool`,
a `…ConsentProviding` seam, and the preference owned in the app target (`UserDefaults`) because the
library target is structurally forbidden from reading defaults. Brewfile import involves **no network
egress**, so this vocabulary does **not** transfer directly — but its *shape* (a typed, dated,
throw-on-refusal gate with a disclosure constant) is the right template for a code-execution or
tap-trust gate if one is needed.

---

## 3. How `brew bundle` actually works, and the three things that change the design

`brew bundle` is **built into Homebrew** (no `homebrew/bundle` tap). Subcommands: `install`/`upgrade`,
`dump`, `check`, `cleanup`, `list`, `edit`, `add`, `remove`, `exec`, `sh`, `env`.
`dump` flags include `--file`, `--force`, `--describe`, and type filters `--formula`, `--cask`,
`--tap`, `--mas`, `--vscode`, `--no-vscode` plus "various `--no-*` variants". `--force` overwrites an
existing Brewfile; without it the existing file is preserved. `--global` targets
`$HOMEBREW_BUNDLE_FILE_GLOBAL` / `${XDG_CONFIG_HOME}/homebrew/Brewfile` / `~/.homebrew/Brewfile` /
`~/.Brewfile`.

### 3.1 FINDING — a Brewfile is Ruby, and that is a code-execution boundary, not an argv boundary

Homebrew's own documentation: *"Brewfiles are evaluated as Ruby so you can use Ruby logic in them"*
(hence `brew "gnupg" if OS.mac?`). Homebrew **6.0.0** (June 2026) shipped **tap trust** specifically to
stop arbitrary Ruby from third-party taps being evaluated without approval.

The M5 shared exploration recorded this slice as *"the first untrusted-argv source in the app"* and
concluded that `MutationName.isSafe` plus the `PackageTarget`/`FormulaID`/`CaskID` unrepresentability
gate already cover it. **That is true for argv and insufficient for the actual risk.** Handing a
stranger's Brewfile to `brew bundle install --file <their path>` does not merely place their strings in
argv — it asks Homebrew to `eval` their Ruby. `postinstall:` options run shell commands by design.

**INFERENCE (must be probed, U8 below): `brew bundle check --file <path>` almost certainly evaluates
the same Ruby**, because it has to read the entries to check them. If that holds, then *the "read-only
diff preview" the PRD asks for is itself a code-execution path* when implemented as `brew bundle check`.
I did not verify this and it must not be treated as settled.

Consequence, if the inference holds: both the preview **and** the apply must be computed by Cellar's
own parser over the file's bytes, and `brew bundle` must never be pointed at a file Cellar did not
write. That is a stronger conclusion than the shared exploration reached, and it decides the slice.

### 3.2 FINDING — `brew bundle check` contradicts every payload rule in this repo, exactly like `brew doctor`

`brew bundle check` *"provides a successful exit code if everything is up-to-date"* and **exits
non-zero when dependencies are unsatisfied**, printing
*"brew bundle can't satisfy your Brewfile's dependencies…"*; `--verbose` is the documented way to list
the unmet entries.

So for `check`, **exit 1 is the informative answer, not a failure** — precisely the hazard the M5
exploration flagged for `brew doctor` and attributed to slice 5 only. Building a bundle-check payload
source on the `TapPayload`/`ServicesPayload` template would report "your Brewfile is fully satisfied"
as a failed command and discard the only output that matters. `CleanupPreviewError.commandFailed`
(which carries `rawStdout` **and** `rawStderr`) is the closest usable precedent, and even it classifies
non-zero as failure.

Known upstream wrinkle: homebrew-bundle **#401** — `check --verbose` and bare `check` disagree on both
output and exit code **when the Brewfile contains `mas` entries**, which is exactly the entry kind the
PRD excludes in v1. Any design that depends on `check`'s exit code inherits that bug.

### 3.3 FINDING — Homebrew 6.0 widened the Brewfile grammar with a security-relevant option

Tap trust added a `trusted:` option that `brew bundle` **records in dumps**:

```ruby
tap  "user/repository", trusted: true
brew "user/repository/formula", trusted: true
cask "user/repository/cask", trusted: true
tap  "user/repository", trusted: { formula: "formula", casks: ["cask"], commands: ["command"] }
```

This project runs Homebrew **6.0.15** (`openspec/config.yaml` `layers.integration`; the BrewClient
fixture README records 6.0.14), so dumps taken on this machine may contain `trusted:`. The M5 shared
exploration's grammar list (`tap`, `brew`, `cask`, `mas`, `vscode`, `whalebrew`) predates this and is
now incomplete.

A parser that silently ignores `trusted:` is wrong in a way that matters: on import, `trusted:` is not
a package name, it is **a pre-granted trust decision authored by whoever wrote the file**. It must be
recognised, must never be honoured implicitly, and must be surfaced.

Other entry kinds current `dump` can emit: `vscode`, `mas`, and non-Homebrew managers (`go`, `cargo`,
`uv`, `npm`, `krew`, `flatpak`, `winget`). All are out of v1 scope and must be **counted skips with a
named reason**, following the shipped `skippedRecordCount` / `CleanupParseIssue` / `unknownLines: [Data]`
idiom — never silently dropped.

### 3.4 `--file=-` remains a bad idea

homebrew-bundle #405/#426 (recorded in the shared exploration) are stdout-mode breakages. A real path
avoids the whole class.

---

## 4. Selective apply through the existing spine — verified viable

The shared exploration recommended fan-out over a filtered temp Brewfile. Repository evidence confirms
it needs **no new mutation family and no new `InvalidationScope` bit**:

- A Brewfile entry becomes `TapCommand.addTap(TapName)` or
  `MutationCommand.install(PackageTarget)` — both already exist, both already gate their names.
- `OperationCenter.submit(_:)` gives each entry its own queue item, streamed log, copy-command,
  cancel, terminal outcome, `HistoryDraft` and scoped invalidation — for free, and this reuses the
  recorded 2026-08-02 fan-out ruling verbatim.
- Confirmation: `request(_ commands: [some BrewMutating])` is generic over **one** concrete type, so a
  mixed tap+install batch must be mapped to `[AnyBrewMutation]` first (`AnyBrewMutation` conforms to
  `BrewMutating`, so this compiles and loses nothing the request reads). Because
  `TapCommand.addTap.requiresConfirmation == true`, any batch containing a tap raises exactly one
  confirmation carrying the `tapTrust` disclosure — which is the correct behaviour, not a workaround.

**A Cellar-authored Brewfile *writer* is still required for export** (§5), but it is only ever read
back by Cellar and by the user, never handed to `brew bundle install`.

---

## 5. File I/O — entirely new surface for this app

`rg` over the whole repo for `NSSavePanel|NSOpenPanel|fileExporter|fileImporter|UTType|ShareLink|securityScoped`
returns **zero matches**. There is **no `.entitlements` file** in the repository at all.
`cellar.xcodeproj/project.pbxproj` (both configurations) carries:

```
ENABLE_APP_SANDBOX = NO;
ENABLE_HARDENED_RUNTIME = YES;
ENABLE_USER_SELECTED_FILES = readonly;
```

Sandbox off is deliberate (PRD §4.2 — required to exec brew), so `ENABLE_USER_SELECTED_FILES = readonly`
is currently inert. It is worth recording as a **latent trap**: if the sandbox is ever enabled, that
setting blocks writing the user's chosen Brewfile while still permitting the import read.

The existing testable file seam is `Catalog/CatalogFileSystem.swift` — a protocol
(`createDirectory/fileExists/contentsMappedIfSafe/write/replaceItem/moveItem/removeItem`) with
`DefaultCatalogFileSystem` writing `.atomic` and doing staged replace. `BrewClient` already depends on
`Catalog`, so this seam is reachable and should be reused rather than calling `FileManager` directly.

---

## 6. Test infrastructure relevant to this slice

- **Swift Testing** throughout; `swift test --package-path Packages/CellarCore` is the inner loop
  (1,396 tests / 176 suites green at slice 3's close, 1 pre-existing known issue in
  `OperationCenterCancelTests`). **Strict TDD is on** (`config.yaml` `apply.tdd: true`, `rules.tasks`
  requires RED before GREEN per behavioural task).
- Process fakes: `Tests/BrewProcessTests/Fakes/FakeProcessLauncher.swift` (45 call sites) and
  `Tests/BrewClientTests/Fakes/RecordingProcessLauncher.swift`. These, not HTTP fakes, are what this
  slice needs.
- **`RecordingURLProtocol` (slice 3) does not apply** — Brewfile involves no network. What *does*
  transfer is slice 3's hard-won lesson: **no process-global mutable state in a fake**. The
  `GlobalRequestSpy` false-zero defect was a CRITICAL verify blocker; the fix was per-instance tagged
  ledgers keyed by UUID with `Synchronization.Mutex`. Any spy this slice adds must be per-instance.
- **Carried follow-up that could bite here**: `cellarTests/SecurityCompositionSupport.swift:181`
  (`CompositionRequestSpy`) still has the false-zero shape (`static var count` + `install()` reset).
  If slice 4 writes an app-target composition test, it must not copy that spy. Re-locate the line
  numbers before citing them.
- **Fixture standard** (`Tests/BrewClientTests/Fixtures/README.md`, and the `Fixtures/Cleanup` standard):
  byte-exact captures, a README recording brew version + exact argv + exit code, `probe-manifest.txt`,
  SHA-256 per stream, hand-trimmed rather than pasted whole. `brew bundle` output is **not
  fixture-covered anywhere in the repo today**.
- Off-main decoding convention: `@concurrent static func decode(_:) async` — **attribute before the
  modifier** (the other order does not compile; recorded as having cost an apply cycle in M1). A
  Brewfile parser should follow `TapDecoder`'s shape.

---

## 7. Approaches

### Fork A — how the **import diff preview** is computed (this is the real decision)

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A1** | `brew bundle check --verbose --file <user path>` | Authoritative — brew's own answer; no parser to write; matches PRD's literal wording | Points brew at a stranger's file, so **INFERENCE 3.1 makes it a code-execution path**; needs a new payload rule contradicting three shipped sources (3.2); inherits homebrew-bundle #401's mas-entry exit-code bug; output format undocumented and unfixtured; a preview that can execute code is not a preview | Medium |
| **A2** | Cellar parses the Brewfile itself; the diff is computed against the resident `InstalledInventory` + `TapInventory` | **Never evaluates the user's Ruby** — the file is read as bytes, never handed to brew; zero new brew invocation, matching the "costs no new acquisition" requirement slices 1 & 2 both shipped; no new payload rule; pure and totally testable without a process; `trusted:`/`mas`/`vscode`/other-manager entries become typed counted skips; the diff is instant and offline | A Brewfile grammar is new work (Ruby-shaped DSL, quoting, options hashes, `if OS.mac?` conditionals it must refuse rather than evaluate); Cellar's answer can differ from brew's; must be honest that it is *Cellar's* reading of the file | Medium-High |
| **A3** | Hybrid: A2 for the preview and for selective apply, plus an explicit "run this whole file with brew" escape hatch behind a code-execution disclosure | Keeps the safe default and still serves power users who want brew's exact semantics | Two paths to maintain; the escape hatch needs a disclosure at least as strong as the tap-trust one; scope growth in the slice already forecast largest-but-one | High |

### Fork B — how the **export** is produced

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **E1** | `brew bundle dump --file <user path>` directly | Byte-identical to what brew produces; guaranteed round-trip outside Cellar | The **subprocess** writes to the user's chosen path, so Cellar controls neither atomicity nor content; `--force` overwrite becomes a destructive action needing confirmation vocabulary; needs the mas/vscode exclusion flag set verified (U6) | Medium |
| **E2** | Cellar writes the Brewfile from `InstalledInventory` + `TapInventory` | Zero new brew surface, zero fixtures to capture; MAS/vscode exclusion is free (Cellar holds no such data); atomic write through the existing `CatalogFileSystem` seam; fully unit-testable | It is *Cellar's* Brewfile, not brew's — divergence risk against `brew bundle dump` is real and must be measured, not assumed | Low-Medium |
| **E3** | `brew bundle dump --file <Cellar temp path>`, then Cellar reads it, shows it, and writes it to the user's destination atomically | Brew's authoritative content **and** Cellar's controlled write; `--force` never touches the user's file because the temp path is always fresh; the intermediate bytes can be shown before anything lands | Two steps; still needs the dump argv/exclusion probe (U6); temp file must be cleaned up | Medium |

---

## 8. Recommendation

**A2 for import + E3 for export.**

- **A2** is recommended on a security ground, not a stylistic one. If the §3.1 inference holds, A1 makes
  the "read-only preview" execute a stranger's Ruby, and that is not a preview. Even if the inference
  is wrong for `check` specifically, A1 still requires inventing a fourth payload rule that contradicts
  the three shipped ones (§3.2) and still inherits #401. A2 also lands the "costs no new acquisition"
  guarantee this codebase has now shipped twice as a spec requirement, and it makes every hostile
  Brewfile shape reachable in a unit test without a process.
- **E3** keeps brew authoritative for content (the user's whole reason for exporting is portability)
  while keeping Cellar responsible for what lands on the user's disk. E2 is the cheaper fallback if the
  dump probe (U6) shows the exclusion flags are awkward on 6.0.15, and E2 remains defensible against the
  PRD's exact words ("`brew bundle dump` **semantics**", not "the `brew bundle dump` command").
- **Selective apply: fan-out** (§4) — confirmed viable against shipped code, adds no `BrewMutating`
  conformer, no `InvalidationScope` bit, no Brewfile writer on the apply path.
- Whatever is chosen, **`brew bundle` must never be pointed at a file Cellar did not write**, and the
  reasoning block at the head of `MutationCommand.swift` — which reasons from "names come from brew's
  own snapshot or from the catalog, never from free text" — must be restated deliberately, because that
  premise stops being true in this slice.

---

## 9. Probes needed before design (U-gate convention; U1–U5 are taken by earlier M5 slices)

- **U6** — `brew bundle dump` on Homebrew 6.0.15: exact argv accepted (`--file`, `--force`, and whether
  `--formula --cask --tap` and/or `--no-mas` / `--no-vscode` give the PRD's exclusion), exit codes,
  stdout/stderr split, and **whether `trusted:` appears in the output on this machine**. Capture a
  byte-exact fixture to the `Fixtures/Cleanup` standard.
- **U7** — `brew bundle check --verbose --file <path>`: exit code satisfied vs unsatisfied, which
  stream the unmet list is written to, and its exact line format. Decides whether a bundle-check payload
  source is needed at all (it is not, under A2).
- **U8** — **the decisive probe.** In a scratch directory, does `brew bundle check --file <path>`
  evaluate the Brewfile's Ruby? (e.g. a Brewfile whose only content is a side effect such as writing a
  marker file.) Settles §3.1 and therefore settles Fork A. Must be run in a disposable directory.
- **U9** — a real `dump` from a machine carrying a third-party tap, to pin the exact `trusted:`
  serialisation this parser must accept.
- **U10** *(cheap, worth it under E2/E3)* — diff Cellar's generated Brewfile against a real
  `brew bundle dump` on the same machine, to price the divergence risk instead of assuming it away.

---

## 10. Product decisions required before proposal

1. **Import shape** — A2 (Cellar parses; brew never reads the user's file), A1 (brew-driven), or A3
   (hybrid with an explicit escape hatch)? *Recommended: A2, pending U8.*
2. **Export shape** — E3 (dump to temp, Cellar publishes), E1 (dump straight to the user's path), or
   E2 (local writer)? *Recommended: E3, with E2 as the fallback if U6 is unfavourable.*
3. **Where the UI lives** — a new `AppSection.brewfile` case, or an export/import affordance inside the
   existing Taps section (PRD §3.7 groups the two under one heading)? The shared M5 exploration assumed
   a `cellar/Brewfile/` directory but named no `AppSection` case. *No recommendation without the
   maintainer; it is a navigation decision, and slice 5 is already adding `.health`.*
4. **`trusted:` entries on import** — refuse the file, strip the option and install untrusted, or
   surface it as an explicit trust decision? *Recommended: parse it, never honour it implicitly, and
   route any tap it names through the existing `ConfirmationDisclosure.tapTrust` gate.*
5. **Unsupported entry kinds** (`mas`, `vscode`, `go`, `cargo`, `uv`, `npm`, `krew`, `flatpak`,
   `winget`) — counted skips with a named reason, following `skippedRecordCount`? *Recommended: yes,
   and the count must be `0` rather than absent when clean, per the precedent slice 2 shipped.*
6. **Ruby conditionals** (`brew "gnupg" if OS.mac?`) — refuse the whole file, or skip-and-count the
   conditional lines? *Recommended: skip-and-count; refusing a whole file over one common idiom is
   hostile, and a counted skip is honest.*

---

## 11. Affected areas

- **New** `Packages/CellarCore/Sources/BrewClient/BrewfileEntry.swift` (typed entry model + counted
  skip reasons), `BrewfileParser.swift` (`@concurrent static func` over `Data`, `TapDecoder` shape),
  `BrewfileWriter.swift` (export projection over `InstalledInventory` + `TapInventory`),
  `BrewfileDiff.swift` (pure projection: present / missing / skipped), `BrewfilePlan.swift`
  (entries → `[AnyBrewMutation]`), `BrewfileStore.swift` (`@MainActor @Observable`, `private(set)`
  state, closed load-state enum, last-good survival).
- **New, only under E1/E3** `Packages/CellarCore/Sources/BrewClient/BundleDumpSource.swift` +
  a `BundleCommand`.
- `Packages/CellarCore/Sources/BrewClient/MutationCommand.swift` — **comment block only**: restate the
  provenance premise (§8). No behavioural change expected.
- `Packages/CellarCore/Sources/Catalog/CatalogFileSystem.swift` — reused as-is; possibly widened if the
  export needs a capability it lacks. Any widening touches shipped `catalog-sync` territory and must be
  weighed against carried follow-up **S4**.
- `cellar/Shell/AppSection.swift` + `cellar/ContentView.swift` + `cellar/cellarApp.swift` — only if
  decision 3 adds a section.
- **New** `cellar/Brewfile/` (a `PBXFileSystemSynchronizedRootGroup`, so a **0-line** `project.pbxproj`
  diff, as proven by slice 2).
- **New** `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Bundle/` to the `Fixtures/Cleanup`
  standard.
- `Packages/CellarCore/Package.swift` — **untouched** under every option above.
- Likely spec surface: a **new `brewfile-management` capability**; `installed-inventory` and
  `tap-management` are read from, not modified; `package-mutation` may need a MODIFIED requirement
  covering the provenance restatement.

---

## 12. Risks

1. **A Brewfile is executable Ruby.** Any design that hands a user-supplied file to `brew bundle` —
   including, per the §3.1 inference, a `check`-based "read-only" preview — is a code-execution path,
   not an argv path. This is the slice's defining risk and U8 must settle it before design.
2. **`brew bundle check` inverts this repo's payload rule** (non-zero exit is the informative answer),
   exactly as `brew doctor` does. Reusing the `TapPayload`/`ServicesPayload` template ships a preview
   that calls a satisfied Brewfile a failed command.
3. **The Brewfile grammar this slice must accept is wider than the shared M5 exploration recorded** —
   Homebrew 6.0's `trusted:` option is security-relevant and is written into dumps on this machine's
   version. A parser built to the pre-6.0 grammar drops it silently.
4. **homebrew-bundle #401** — `check` and `check --verbose` disagree on output and exit code when `mas`
   entries are present, which is precisely the entry kind v1 excludes.
5. **First file-system read/write surface in the app.** Zero existing `NSOpenPanel`/`NSSavePanel`/
   `fileExporter`/`ShareLink` usage, no `.entitlements` file, and `ENABLE_USER_SELECTED_FILES = readonly`
   sitting inert behind `ENABLE_APP_SANDBOX = NO`. Harmless today, a trap if the sandbox is ever enabled.
6. **`brew bundle` is unfixtured anywhere in the repo.** Exit codes and stream split on 6.0.15 must be
   captured, not assumed.
7. **Forecast risk is high.** The shared exploration priced slice 4 at 1,800–2,600 authored lines, but
   slice 1 measured 3,619 against a 1,500–2,100 forecast and slice 3 measured 9,736 against 3,700–4,700
   and needed a user-accepted `size:exception`. A grammar plus a writer plus a diff plus a plan plus a
   store plus app UI, under strict TDD, will very likely exceed 2,600. Budget is 5,000; delivery is
   `single-pr`.
8. **Mixed confirmation batches** need `[AnyBrewMutation]` mapping (§4) — small, but it is the kind of
   detail that surfaces as a compile error mid-apply if design does not name it.
9. **Casks needing a sudo password will fail**: `SystemProcess` sets `standardInput = FileHandle.nullDevice`.
   Pre-existing for single installs, but a Brewfile import is the first surface that triggers it at scale,
   so the failure mode needs a named, honest outcome rather than an opaque non-zero exit.
10. **Catalog footprint follow-up S4** — the encoded-snapshot bound has 2.4% headroom. This slice should
    consume none of it (no `CatalogPackage` field, no schema move), and `CatalogFootprintTests` must pass
    **unchanged and un-rebased**. Confirm rather than assume.
11. **No CI.** Green suites remain local snapshots — pre-existing project risk, not slice scope.
12. **`openspec/config.yaml` line 56 was corrected to 5,000** at slice 3's archive, so the stale
    2,000-line prose follow-up is closed; recorded here so it is not re-raised.

---

## 13. Ready for proposal

**Yes, after U8 and a short decision round.** U8 (does `brew bundle check` evaluate the file's Ruby?)
decides Fork A and therefore decides the slice's shape; U6 decides Fork B. Decisions 1, 2 and 3 change
what this slice *is* rather than how it is built. Decisions 4–6 are parser policy and can be settled
inside the proposal if the maintainer prefers.
