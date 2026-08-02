# Proposal: M2-1 — Installed Inventory

PRD milestone **M2** (§3.1–§3.2, §4.2, §7), slice 2 of 4 (Engram `sdd/m2-mutations-installed/slicing` #7065).
Artifact store: hybrid — mirrored in Engram `sdd/m2-installed-inventory/proposal`.
Sources: `openspec/changes/m2-mutations-installed/explore.md` §1–§5, §7 (M2-1 row), §8–§9; settled product decisions Engram #7079.

## Intent

Cellar can browse the whole Homebrew catalog but cannot tell the user what *they* have. There is no installed list, no outdated signal, no way to filter Browse by installed state — `CatalogFilterBar` even carries a comment explaining why. Users must drop to Terminal to answer "what do I have and what needs updating?", which is the daily reason to open the app.

## Scope

### In Scope

| Area | Deliverable |
|---|---|
| Target | New `BrewClient` target depending on **both** `BrewProcess` and `Catalog` — one-directional, keeps catalog-sync CS1 (catalog works with brew absent) intact |
| Read | One `brew info --installed --json=v2` probe answers the whole list; slim wire models with asymmetric decoding (formula `installed` = keg array, cask `installed` = String) |
| Derivation | Outdated, on-request vs dependency-only (`installed_on_request`, no `installed_as_dependency` key exists), pin state, install date; catalog join on `PackageID` |
| State | `@MainActor @Observable InstalledStore`, mirroring the M2-0-corrected `BrewDetectionStore` single-flight exemplar |
| UI | Installed sidebar section, list, filters, badges; auto-updating casks rendered separately and **never** counted as outdated; default filter = on-request only, dependency-only behind a toggle |
| Browse | Installed / not-installed / outdated filters composed from the inventory — `package-search` PS4 stays verbatim untouched |
| Freshness | `InstalledChangeObserving` seam + FSEvents impl + debounce, with focus and post-mutation refresh as the always-on baseline |
| Ownership | App-level owner for scene-lifetime loops, closing M1 follow-ups #8/#9 once for both loops |
| Fold-in | brew-detection S1 vocabulary nit (`native`/`rosettaCarryOver` vs `BrewPrefix.appleSilicon`/`.intelCarryOver`); `BrewDetectionStore` request-keyed single-flight fix (M2-0's nominated open question — user-approved scope addition, design D6) |

### Out of Scope

- Mutations, queue, activity UI, "copy command" → M2-2.
- SwiftData `Persistence`, favorites, notes, snooze, history → M2-3.
- Release notes, adopt, size on disk, last-used → M5.
- `brew outdated --json=v2` as a second probe (reserved for the cask-greedy question only, if the design probe proves divergence).

## Capabilities

### New Capabilities

- `installed-inventory`: acquiring, projecting, and joining the installed snapshot; outdated / pinned / on-request derivation; self-updating cask classification; composed installed-state filtering; freshness and invalidation; brew-absent empty-inventory behaviour.

### Modified Capabilities

- `brew-detection`: MODIFIED — align the spec's `native` / `rosettaCarryOver` vocabulary with the code's `BrewPrefix` cases (S1 nit; declined in M1 only because that change did not touch `BrewProcess`).
- `package-search`: **unchanged, deliberately.** PS4 ("no filter MUST depend on installed, not-installed, or outdated state") remains correct and verbatim; composition happens above the index.

## Approach

1. **One probe, slim-projected.** Decode `info --installed --json=v2` off-main into an `InstalledPackage` projection, dropping `bottle`, `urls`, `artifacts`, `ruby_source_checksum` — the M1 catalog pattern.
2. **Derive, don't re-probe.** `outdated`, `pinned`, `installed_on_request`, `versions.stable`, and install timestamps all come from that one payload (verified: `outdated: true` count matches `brew outdated` exactly).
3. **Join above both packages.** `BrewClient` owns the join so `Catalog` never learns about `BrewProcess`, and `PackageID`/`PackageKind` are reused rather than duplicated.
4. **Compose filters, don't weaken the index.** Browse asks the inventory for a membership set and intersects; with brew absent the set is empty and the filters render disabled.
5. **Watcher as pure invalidation.** FSEvents (recursive, unlike a non-recursive `DispatchSource`, which would miss every upgrade) behind a seam with a fake, debounced on an injected `Clock`, suppressed while a mutation is in flight, re-snapshotting once.
6. **Solve loop ownership once**, at app level, before M2-2 adds a third loop.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift` | Modified | `BrewClient` target/product + `BrewClientTests` |
| `Sources/BrewClient/` | New | Wire models, `InstalledSnapshot`, derivation, join, `InstalledStore`, `InstalledChangeObserving` + FSEvents impl |
| `Sources/BrewProcess/BrewPrefix.swift` | Modified | S1 vocabulary alignment (rename, no behaviour change) |
| `cellar/cellarApp.swift` | Modified | App-level loop ownership; `InstalledStore` wiring |
| `cellar/ContentView.swift` | Modified | Installed sidebar section |
| `cellar/Installed*` views | New | List, filters, badges, self-updating separation, empty/brew-absent states |
| `cellar/CatalogFilterBar.swift` | Modified | Installed-state filter composition (replaces the "deliberately absent" comment) |
| `cellar.xcodeproj/project.pbxproj` | Modified | Link `BrewClient` into the app target |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Cask `outdated` greedy semantics unverified (0 outdated casks on probe machine) — could nag about self-updating casks or hide real cask updates | High | Live probe during design is a gate; product decision already fixes the safe side (auto-updating casks never badge as outdated) |
| Snapshot cost scales with install count (1.27 s / 663 KB for 156 formulae; ~3–4 s at 500 unverified) | Med | Off-main `@concurrent` decode, debounced watcher, single re-snapshot per terminal event |
| FSEvents C callback + context pointer under Swift 6 strict concurrency | Med | Confine in a seam with a documented invariant and a fake; all logic tested through the fake, never through CoreServices |
| Multi-keg `installed` arrays unverified (none on probe machine) | Med | Decode as a list per schema; explicit scenario for the multi-keg case |
| App-level loop ownership regresses the "second window must not start a second loop" guard | Med | Keep the `isRunning` guard semantics; regression test for open→close→open |
| Review budget: 2,200–2,800 authored lines vs 1,500 | High | `size:exception` already accepted by the user (Q4, #7079) for one PR |

## Rollback Plan

Single PR. `git revert` the merge commit removes the `BrewClient` target, its app-target link, and all Installed UI; M2-0 behaviour returns exactly, because nothing here changes a persisted format, a schema version, or an on-disk artifact. Project-file edits (target membership + link) live in that same commit — if the Xcode project fails to open after a partial revert, restore `cellar.xcodeproj/project.pbxproj` from the pre-merge commit and re-run the build command. The `BrewPrefix` rename is source-level only and reverts with it.

## Dependencies

- `m2-catalog-hardening` (M2-0) merged — supplies the corrected single-flight and off-main-adoption exemplars this slice copies. Already archived.
- Live `brew` 6.x on an arm64 machine for the design-phase cask-outdated probe.
- Accepted `size:exception` for the single PR.

## Success Criteria

- [ ] The Installed list renders from exactly one `brew info --installed --json=v2` invocation, decoded off the main actor.
- [ ] Formula (keg array) and cask (String) `installed` shapes both decode; multi-keg formulae are represented, not dropped.
- [ ] Default view shows on-request packages only; dependency-only formulae appear only when the toggle is on.
- [ ] Auto-updating casks (`auto_updates` true **or** null) never contribute to the outdated badge and are visually separated.
- [ ] Browse offers installed / not-installed / outdated filters; `openspec/specs/package-search/spec.md` PS4 is byte-identical after the change.
- [ ] With brew absent or invalid, the Installed section renders read-only guidance, the inventory is empty, and catalog browse/search are unaffected.
- [ ] An external `brew install` performed in Terminal is reflected without user action, debounced, and not re-snapshotted repeatedly during a long `brew upgrade`.
- [ ] Closing the window that started the app no longer stops the refresh loops (#8/#9 closed).
- [ ] `Catalog` still has no dependency on `BrewProcess` (CS1 asserted by the target graph).
- [ ] Full suite green; `swift test --package-path Packages/CellarCore` remains the inner loop.
