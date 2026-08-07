# Design: Brewfile Import & Export (`m5-brewfile`)

Derives from proposal (obs 7521, D1–D6 + Security Invariants binding), decisions (obs 7520), probes
U6/U8/U9 (obs 7519), explore §2/§6/§11. Repository claims re-verified at `main` `7d48779`.

## Technical Approach

All logic lands in `BrewClient` (already sees `BrewProcess`, `Catalog`, `DiskUsage`) — `Package.swift`
untouched. Import (A2) is a pure, offline pipeline: bytes → `BrewfileParser` → `BrewfileDocument`
(typed entries + counted skips) → `BrewfileDiff` against resident `InstalledInventory`/`TapInventory`
→ selection → `BrewfilePlan` → `[AnyBrewMutation]` → `OperationCenter`. Export (E3) is
`BundleDumpSource` → Cellar temp → preview → `NSSavePanel` → `CatalogFileSystem.write(_:to:)`
(`.atomic`). The app target gets views plus two AppKit seam conformers only.

**Structural enforcement of the invariants**: `BrewfileEntry` stores *already-constructed* `TapName` /
`FormulaID` / `CaskID`, never raw strings. A name that fails those initialisers never becomes an
entry — it becomes a counted skip at parse time. `BrewfilePlan` therefore cannot fail and cannot emit
free text, and no user-chosen `URL` exists anywhere on a `BrewCommand.arguments` path.

## Architecture Decisions

### DD1 — `tapTrust` disclosure is **lost** under `[AnyBrewMutation]` (defect found; must be fixed)

The proposal asserts a mixed batch "raises exactly one confirmation carrying the `tapTrust`
disclosure". **Verified false against shipped code.** `OperationCenterBulk.swift:141` reads
`disclosure: (first as? TapCommand)?.disclosure ?? .packageRemoval`, and `AnyBrewMutation`
(`BrewMutating.swift:144-161`) copies seven projections but **not** `disclosure`. An erased batch
therefore confirms with "This removes installed software." — wrong text, and it breaks success
criterion "a tap it names still raises the `tapTrust` confirmation".

| Option | Tradeoff | Decision |
|---|---|---|
| Add `disclosure` to `BrewMutating` (extension default `.packageRemoval`); `AnyBrewMutation` copies it; `request` reads `first.disclosure` | Touches the shipped spine; behaviour-identical at every existing call site (`submitBulk` → `.packageRemoval`; single `TapCommand` → `.tapTrust`; `requestCleanup` builds its request directly) | **Chosen** |
| Split into two requests (taps, then installs) | Two confirmations; declining the tap would still install — breaks all-or-nothing | Rejected |
| New `BrewfileMutation` conformer | Proposal forbids a new conformer; the cast still fails | Rejected |

Consequence: `BrewfilePlan` **MUST** order tap-adds before installs (`request` reads `commands.first`),
which is also the correct execution order. **Spec impact**: `package-mutation` needs a *second*
MODIFIED requirement beyond the provenance restatement.

### DD2 — Parser: line-oriented, `@concurrent`, refuse-by-skip

`@concurrent public static func decode(_ data: Data) async throws(BrewfileParseError)` — attribute
**before** the modifier (M1 convention), `TapDecoder` shape. Grammar per trimmed line:

| Construct | Outcome |
|---|---|
| blank, `#…` comment (U6: emitted without `--describe`) | ignored, not counted |
| `tap "n"` / `tap "n", "url"` / `…, trusted: true\|{…}` (U9) | `.tap` entry; `trustedClaim` retained for display only |
| `brew "n"` / `cask "n"` | `.formula` / `.cask` entry |
| any option key other than `trusted:` (`postinstall:`, `args:`, `link:`) | skip `.unsupportedOption(key)` — an option changes what the author asked for; installing a stripped entry is not what they wrote |
| trailing `if` / `unless` / any Ruby residue (D6) | skip `.rubyConditional` — condition **never** evaluated |
| `mas`,`vscode`,`go`,`cargo`,`uv`,`npm`,`krew`,`flatpak`,`winget` (D5) | skip `.unsupportedEntryKind(String)` |
| name rejected by `TapName`/`FormulaID`/`CaskID` | skip `.unrepresentableName` |
| anything else, or non-UTF-8 bytes | skip `.unrecognisedLine` |

`trusted:` is parsed, surfaced as "a claim by the file's author", and confers nothing (D4).
`skips.count` is `0`, never absent, for a clean file. Input bound: >8 MiB → `.tooLarge`, parsed never.

### DD3 — Export (E3) ordering: dump → preview → panel → publish

`BundleDumpCommand` is a `BrewCommand.read` with U6-pinned argv `bundle dump --file <temp> --force
--formula --cask --tap`. `BundleDumpSource` mirrors `CleanupPreviewSource` (a `Sendable` struct over
`any ProcessLaunching`, `withTaskCancellationHandler`). Temp is `<tmp>/cellar-brewfile/<UUID>/Brewfile`,
created via `CatalogFileSystem.createDirectory` and removed in `defer` on **both** paths. The save
panel opens only after a successful preview, so a dump failure writes nothing to the user's disk and
`--force` can never reach a user file. Errors carry the `CleanupPreviewError` shape — the only shipped
payload error preserving `rawStdout` **and** `rawStderr`.

### DD4 — `NSSavePanel`/`NSOpenPanel`, not `fileExporter`/`fileImporter`

`fileExporter` requires a `FileDocument`/`Transferable` and performs the write itself, which would take
publication away from `CatalogFileSystem` and dissolve E3's atomicity guarantee. Panels return a plain
`URL` and leave the write to Cellar. Sandbox is OFF, so no security-scoped bookmarks are needed;
`ENABLE_USER_SELECTED_FILES = readonly` stays a recorded latent trap, unchanged. Per `rules.design`,
AppKit is reached through seams (`BrewfileDestinationChoosing` / `BrewfileSourceChoosing`, declared in
`BrewClient`, conformed in the app target) so `CellarCore` imports no AppKit and the store is testable.

### DD5 — Store and load states

`@MainActor @Observable public final class BrewfileStore` with `private(set)` state and closed enums
(`ServicesLoadState`/`InstalledLoadState` idiom): `importState = .idle | .reading | .parsed(BrewfileDiff)
| .failed(BrewfileImportError)`; `exportState = .idle | .dumping | .preview(BrewfileDocument) |
.published(URL) | .failed(BrewfileExportError)`. Selection is `Set<BrewfileEntry.ID>`, initialised to
the **missing** set; present entries render disabled (confirmed decision 2). Skips never gate import
(confirmed decision 3).

### DD6 — Sudo-password cask failure: a Brewfile-scoped advisory

`SystemProcess` sets `standardInput = .nullDevice`, so a cask needing an admin password fails opaquely.
Widening `MutationCommand.classify` would change **every** install path's outcome vocabulary. Instead
`BrewfileApplyAdvisory` is derived by `BrewfileStore` from the terminal item's log and states: this
cask needs an administrator password, Cellar cannot supply one, install it from Terminal. Rejected:
a new `MutationOutcome` case (leaks into `package-mutation` and `HistoryDraft`). Prompting for a
password remains a stated non-goal.

## Data Flow

    IMPORT (no process, no Ruby, no brew argv from the file)
    NSOpenPanel ─URL→ CatalogFileSystem.contentsMappedIfSafe ─Data→ BrewfileParser.decode (@concurrent)
        └→ BrewfileDocument{entries:[TapName|FormulaID|CaskID], skips:[reason]}
             └→ BrewfileDiff(installed:taps:) → present | missing | skipped
                  └→ selection → BrewfilePlan → [AnyBrewMutation]  (taps first)
                       └→ OperationCenter.request(_:) → ONE confirmation (.tapTrust, per DD1)
                            └→ confirm → submit ×N → queue items, logs, HistoryDrafts

    EXPORT (brew writes only Cellar's temp)
    BundleDumpSource ──argv(U6)──→ brew bundle dump --file <tmp/UUID/Brewfile> ...
        └→ read temp bytes → preview sheet → NSSavePanel → CatalogFileSystem.write(.atomic)
             └→ defer { removeItem(tmp dir) }   // success and failure alike

## File Changes

| File | Action | Description |
|---|---|---|
| `Sources/BrewClient/BrewfileEntry.swift` | Create | Entries carrying validated identities; `BrewfileSkip` + `BrewfileSkipReason`; `BrewfileDocument` |
| `Sources/BrewClient/BrewfileParser.swift` | Create | `@concurrent static decode(_ Data)`; grammar of DD2 |
| `Sources/BrewClient/BrewfileDiff.swift` | Create | Pure projection vs `InstalledInventory` + `TapInventory` |
| `Sources/BrewClient/BrewfilePlan.swift` | Create | Selection → `[AnyBrewMutation]`, taps first |
| `Sources/BrewClient/BrewfileStore.swift` | Create | `@MainActor @Observable`; both load-state enums; picker seams |
| `Sources/BrewClient/BundleDumpCommand.swift` | Create | U6-pinned `.read` argv |
| `Sources/BrewClient/BundleDumpSource.swift` | Create | `CleanupPreviewSource` shape; temp lifecycle |
| `Sources/BrewClient/BrewMutating.swift` | Modify | `disclosure` protocol requirement + default; `AnyBrewMutation` carries it (DD1) |
| `Sources/BrewClient/OperationCenterBulk.swift` | Modify | `request`: `first.disclosure`, cast removed (DD1) |
| `Sources/BrewClient/MutationCommand.swift` | Modify | Provenance reasoning block only — no behaviour change |
| `Sources/Catalog/CatalogFileSystem.swift` | Unchanged | Reused as-is; **no widening** → S4 headroom untouched |
| `cellar/Taps/TapsListView.swift` | Modify | `.toolbar` import/export affordances |
| `cellar/Taps/BrewfileImportSheet.swift`, `BrewfileExportSheet.swift`, `BrewfilePanels.swift` | Create | Diff preview, export preview, AppKit seam conformers — **0-line pbxproj diff** |
| `Tests/BrewClientTests/Fixtures/Bundle/` | Create | Byte-exact, `Fixtures/Cleanup` standard |

## Interfaces / Contracts

```swift
public struct BrewfileEntry: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {          // Only representable identities exist here.
        case tap(TapName, url: URL?, trustedClaim: BrewfileTrustClaim?)
        case formula(FormulaID)
        case cask(CaskID)
    }
    public let kind: Kind
    public let lineNumber: Int
}

public enum BrewfileSkipReason: Sendable, Hashable, CaseIterable {
    case unsupportedEntryKind(String), unsupportedOption(String)
    case rubyConditional, unrepresentableName, unrecognisedLine, undecodableBytes
}

public protocol BrewfileDestinationChoosing: Sendable { func chooseDestination() async -> URL? }
public protocol BrewfileSourceChoosing: Sendable { func chooseSource() async -> URL? }
```

## Testing Strategy

Strict TDD — RED before GREEN for every behavioural task. Inner loop
`swift test --package-path Packages/CellarCore`.

| Layer | What | Approach |
|---|---|---|
| Unit — parser | Every grammar row of DD2; U9 `trusted:` lines verbatim; hostile Ruby (`File.write`), shell metacharacters, non-UTF-8, >8 MiB | Pure `Data` in, `BrewfileDocument` out; **no process** |
| Unit — diff/plan | present/missing/skipped; official taps read present; tap-before-install ordering; plan totality | Fixture inventories |
| Unit — spine (DD1) | **RED first**: erased tap batch confirms with `.tapTrust`; every shipped call site's disclosure unchanged | `OperationCenter` + `AnyBrewMutation` |
| Unit — dump source | Exact argv; exit 0; non-zero → `.dumpFailed` with both streams; empty document; temp removed on both paths | `RecordingProcessLauncher` |
| Unit — store | Both state machines; selection defaults to missing; present unselectable | Fake seams, per-instance |
| Structural | No `BrewCommand.arguments` element derives from a user-chosen URL; `brew bundle` argv contains only Cellar-owned paths | Assertion over the plan + dump command |
| App composition | Taps affordances wired; picker seams injected | Per-instance tagged ledgers + `Mutex`; **do not** copy `cellarTests/SecurityCompositionSupport.swift`'s `CompositionRequestSpy` |
| Regression | `CatalogFootprintTests` passes unchanged and un-rebased | Run as-is |

Fixtures: `Fixtures/Bundle/` = `dump-file.brewfile`, `dump-stderr.txt`, `README.md` (Homebrew 6.0.15,
exact argv, exit 0), `probe-manifest.txt` (SHA-256 per stream and per file), plus hand-authored
`hostile-ruby.brewfile`, `mixed-kinds.brewfile`, `trusted-taps.brewfile`. U10 (Cellar's reading vs a
real dump) runs during apply as a divergence check, not a gate.

## Concurrency (Swift 6 strict)

`CellarCore` uses SwiftPM nonisolated defaults; the app defaults to `MainActor`. All Brewfile models
are `Sendable` value types, so a decoded document crosses back to the main actor with no lock and no
`@unchecked`. Parsing is `@concurrent` (off-main, attribute before modifier). `BundleDumpSource` is a
nonisolated `Sendable` struct; `BrewfileStore` is `@MainActor` and only assigns awaited results. Picker
seams are `Sendable` protocols whose AppKit conformers hop to `@MainActor` internally. No new actor,
no `nonisolated(unsafe)`, no `#available`.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths (a Brewfile is evaluated Ruby — U8 proved `brew bundle check` executes it) | **Applicable** | The file is data, never an argument. Parsed as bytes; `postinstall:`/conditionals become counted skips; brew is never pointed at a path Cellar did not write | Hostile-Ruby fixture executes nothing and installs nothing; structural test that no brew argv carries a user-chosen path |
| Argument composition from a file-sourced name (project-specific row) | **Applicable** | Names admitted only via `TapName`/`FormulaID`/`CaskID`; unrepresentable → counted skip; `BrewCommand` is argv-only, never `/bin/sh -c` | Metacharacter and unrepresentable-name fixtures produce skips, not commands |
| Subprocess file authority (project-specific row) | **Applicable** | `--file` always a fresh Cellar-owned temp; `--force` cannot reach a user file; temp removed on both paths | Argv-pinning test; temp-cleanup-on-failure test |
| Git repository selection / commit state / push state / PR commands | **N/A** | No VCS or PR automation in this change | None |

## Migration / Rollout

No migration. No cache file, schema version, `UserDefaults` key or Keychain item is introduced. Purely
additive; one `git revert` restores `main`. `Packages/CellarCore/Package.swift` and
`cellar.xcodeproj/project.pbxproj` are untouched.

## Apply-Time Amendments

Recorded during apply, never absorbed silently. Batch 1 covered Phases 0–8 (A1–A8); batch 2 covered
Phases 9–10 and added A9–A12.

### A1 — `BrewfileTrustClaim` moved from `Kind.tap` onto `BrewfileEntry`

The design's inventory put `trustedClaim` inside `Kind.tap(TapName, url:, trustedClaim:)`. **The real
capture forced the change**: `dump-file.brewfile` carries `trusted: true` on nine `brew` lines as well
as on four `tap` lines. Design's shape had nowhere to keep a claim made on a package line, so it
would have been silently discarded — which BF5 forbids ("MUST NOT be silently discarded from the
presentation, because it is security-relevant content"). The claim is now a sibling of `kind`:
`BrewfileEntry(kind:lineNumber:trustedClaim:)`, with `Kind.tap(TapName, url: URL?)`. It still confers
nothing, on any kind of line.

### A2 — `BrewfileSkipReason` is not `CaseIterable`; it projects a `Category`

Two cases carry associated values (`unsupportedEntryKind(String)`, `unsupportedOption(String)`), so
`CaseIterable` cannot be synthesised. BF4 needs "reasons distinguishable by a consumer without
inspecting free text", which is satisfied by `BrewfileSkipReason.Category: String, CaseIterable` plus
a `detail: String?` projection. Grouping and counting switch on the category; only rendering reads the
detail.

### A3 — the parser has its own literal grammar for names, narrower than `MutationName.isSafe`

`isSafe` rejects only empty, leading `-`, and whitespace, so `` `id` `` and `$(id)` would pass it.
BF2/TM2 require metacharacter names to be **named refusals**, so `BrewfileParser.isRepresentableToken`
admits only the character set a Homebrew token is spelled with — ASCII alphanumerics plus `@._-+/` —
and rejects Ruby interpolation (`#{`). This is **narrower at the file boundary**, which PM9 permits
explicitly ("subject to exactly these rules and to no weaker ones"). `MutationName.isSafe` is
unchanged and remains the single shared gate; verified against all 79 names of the real capture.

### A4 — `ConfirmationDisclosure` gained `Hashable`

`AnyBrewMutation` is `Hashable` and now stores a `ConfirmationDisclosure`, so the enum had to be
`Hashable` rather than merely `Equatable`. Both payloads (`TapName`, `Set<PackageID>`) were already
hashable, so the conformance is synthesised and no equality semantics changed. The widened equality it
implies — two commands identical in argv but differing in what they warn about are now different
erased values — is asserted deliberately in `BrewMutatingTests`, per task 0.1.

### A5 — DD1's blast radius measured: **zero** shipped test edits

Task 0.7's checkpoint. `ConfirmationBacklogTests`, `ForceDenialRecoveryTests`, `BulkFanOutTests`,
`TapCommandTests` and `OperationCenterTests` all passed untouched after the spine change. The only
existing test-support edit was one additive line on the `ProbeMutation` fake
(`environmentOverrides`), needed so the 0.1 guard could vary all seven pre-existing projections.

### A6 — `MutationCommandTests`' `*Command.swift` structural scan gained a named exemption

`BundleDumpCommand.swift` matches the shipped `*Command.swift` glob but names **no package**, so the
scan's `MutationName.isSafe` requirement was inapplicable. The rule was **extended, not weakened**: a
named `namesNothing` set exempts it from the name-gate requirement and, in exchange, requires the
stronger claim that it cannot carry a name at all — no `PackageID`/`PackageTarget`/`FormulaID`/
`CaskID`/`TapName`, no reference to `isSafe`, exactly one initialiser (`init(fileURL: URL)`), and no
stored `String`.

### A7 — U10 divergence check result: **no divergence**

Task 8.4, run against `Fixtures/Bundle/dump-file.brewfile` (Homebrew `6.0.15-125-g7372067`, exit 0).
148 lines: 69 `#` comments ignored without being counted, and all 79 meaningful lines accounted for —
78 typed entries (9 taps, 58 formulae, 11 casks) and **1** named skip, `unsupportedOption("link")` for
`brew "dotnet@9", link: true`. **Zero** `unrecognisedLine`. No grammar row had to be added.

Two shapes the capture confirmed and the grammar already covered: the `tap "n", "url"` positional
(U9), and ten tap-prefixed `brew "user/repo/token"` entries — which the revision-2 amendment had
already corrected the spec for, and which would otherwise have dropped every third-party package.

### A8 — U8 re-verified first-hand during apply

`brew bundle check --file <tmp>/Hostile.brewfile` on the same binary, 2026-08-07: exit 1, and
`<tmp>/marker.txt` existed afterwards containing `evaluated`. The Brewfile's `File.write` was executed.
Recorded in `Fixtures/Bundle/README.md`; the hostile file and its marker were written under the session
scratchpad and removed, deliberately not committed.

### A9 — a container-level `accessibilityIdentifier` **replaces** its descendants'

Both sheets originally carried `.accessibilityIdentifier("brewfile-…-sheet")` on their root `VStack`,
matching `ReleaseNotesSheet`. On macOS that identifier propagates *down* and overrides every
descendant's own identifier wherever the hierarchy is not broken by a `List`: the accessibility dump
showed the header lines, the attribution and **all four footer buttons** — including the Import button
the whole E2E case depends on — reporting `brewfile-import-sheet`. The rows inside the `List` kept
theirs, which is why the skip assertions passed while the button was unaddressable.

The sheets now carry no root identifier; the title (import) and the headline (export) carry the
sheet's name instead. `ReleaseNotesSheet` is unaffected in practice because everything its UI tests
query sits inside a `ScrollView`, so this is recorded rather than fixed there.

### A10 — `TapShippingProofTests`' bounded-tap-surface guard was **extended**, not weakened

`assertBoundedUIControls` enumerated the tap section's four button labels and asserted that nine
capabilities — **including the literal "Brewfile"** — appear nowhere in `TapsListView.swift` or
`TapDetailView.swift`. D3 makes Brewfile an *owned* capability of that section, so the guard's premise
changed. Two things were done rather than one:

1. The two affordances **joined the enumeration**: they are spelled `Button("Import Brewfile", systemImage:)`
   rather than the trailing-closure form, so the shipped `staticButtonLabels` regex still reads them
   and the existing `Button {`-is-forbidden assertion still holds unchanged. The expected label set
   went from four to six.
2. "Brewfile" left the excluded list, and was **paid for with a stronger claim**: the tap UI may name
   Brewfile only in its two enumerated buttons and the two sheet presentations that open them
   (bounded by occurrence count), may name **no** Brewfile logic at all
   (`BrewfileParser`/`BrewfilePlan`/`BrewfileDiff`/`BundleDumpCommand`/`BrewfilePublication`/
   `bundle dump`/`--file`/`--force`/`trusted:`), must present exactly two `.sheet(isPresented:)`, and
   must add no `navigationDestination`.

Net effect on the file: **+32 lines, zero assertion lines removed**. This is the A6 discipline applied
a second time, and it is the only shipped test this change edited in either batch.

### A11 — the UI-test import fixture is inline, not the `Fixtures/Bundle` file

Task 9.6 names `mixed-kinds.brewfile`. That fixture lives under
`Tests/BrewClientTests/Fixtures/Bundle/` and is reachable only through `Bundle.module` in the package
test target; reaching it from the **app** target would mean declaring a bundle resource, and this
change is bound to a **zero-line `project.pbxproj` diff**. `AppTestFixtures.brewfileDocument` therefore
carries an inline document of the same shape — three unsupported kinds, one unsupported option, one
Ruby conditional, one tap the fixture tap inventory lacks, and one package the fixture installed
inventory holds, so the present-and-unselectable row is reachable too. The bytes still travel the
shipped path: written to a temp file, read through `CatalogFileSystem`, decoded by `BrewfileParser`.

The `NSOpenPanel` seam is swapped for `AppTestBrewfileSourceChooser` under `--ui-testing-m5-brewfile`,
chosen once in the composition root (`cellarApp` → `ContentView` → `TapsListView`) exactly as
`cleanupPreviewSource` and the launcher factory already are, so the Taps list holds no
launch-argument knowledge.

### A12 — a fourth app-target concern lives inside `BrewfileImportSheet.swift`

The design's file table names three new app files. The import sheet needs testable presentation
values — `BrewfileImportRow`, `BrewfileSkipGroup`, `BrewfileSkipCopy`, `BrewfileImportSummaryCopy` and
`BrewfileImportAction` — following the `PackageInspectionRow` idiom, where what a surface *says* is a
plain value type provable without rendering. They are declared **in that same file** rather than in a
fourth one, so the design's file inventory holds exactly. `BrewfileExportPresentation` sits in
`BrewfileExportSheet.swift` for the same reason.

## Rollback

One `git revert` of the merge restores `main`. No migration, no cache file, no schema version, no
`UserDefaults` key and no Keychain item is introduced anywhere in this change.

Deleting the four app files (`cellar/Taps/Brewfile{Panels,ImportSheet,ExportSheet}.swift` and
`cellarTests/BrewfileCompositionTests.swift`, plus `cellarUITests/BrewfileImportUITests.swift`) and
reverting `TapsListView.swift`, `ContentView.swift`, `cellarApp.swift`, `AppTestFixtures.swift`,
`SecurityPreviews.swift` and `TapShippingProofTests.swift` removes the app layer on its own, leaving
the CellarCore capability intact and green. There are **zero** `project.pbxproj` objects to remove:
the files live in the existing synchronized root group.

**The spine revert must not stop halfway.** Phase 0's change to `BrewMutating.swift` and
`OperationCenterBulk.swift` is the only shipped-code modification in the change. Reverting the
`disclosure` protocol requirement without reverting the gate read leaves `request(_:)` uncompilable;
reverting the gate read alone silently restores the tapTrust downgrade — an erased tap+install batch
confirming with "This removes installed software." A partial revert of those two files is worse than
either the change or its absence.

## Open Questions

- [ ] None blocking. DD1 requires `sdd-spec` to add a second MODIFIED `package-mutation` requirement
      ("a confirmation disclosure survives command erasure") beyond the provenance restatement — noted
      here rather than raised as a maintainer decision, because the alternative options break shipped
      all-or-nothing semantics.
