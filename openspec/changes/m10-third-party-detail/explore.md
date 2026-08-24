# Exploration: m10 — third-party detail surface

A reduced detail pane for installed packages the catalog does not carry, rendered from the `brew info --installed --json=v2` receipt Cellar already decodes. No new brew invocation.

Hybrid store: this file is canonical; Engram observation #7781 (topic `sdd/m10-third-party-detail/explore`) is the searchable mirror. Section 8 (probe result) was added by the orchestrator after the exploration agent returned.

---

## 1. Current state

### 1.1 The detail surface already has a non-catalog branch

`cellar/Browse/PackageDetailView.swift:48-71` routes on **catalog presence**, not on tap:

```swift
if let package = catalog.package(id) {
    content(for: package)
} else if let snapshot = installed.inventory.package(id) {
    // No catalog record, but the machine has it (installed-inventory II7).
    uncatalogedContent(for: snapshot)
} else {
    ContentUnavailableView("Package details unavailable", …)
}
```

`uncatalogedContent(for:)` (`:369-390`) already renders the **shared identity header** — icon tile, display name, version story, kind, status pill, favorite heart — from the `InstalledPackage` snapshot alone, then fills the remaining space with `ContentUnavailableView("No further details", systemImage: "shippingbox", description: Text("This installed package is not in Cellar's core/cask catalog."))`.

**This corrects a premise in the m10 brief.** PD8 is *not* "structurally unreachable because `PackageDetailView` renders only `CatalogPackage`". The view already renders a second, snapshot-fed path. What is missing is (a) the body of that pane and (b) the tap-of-origin fact the PD8 marker must sit beside. The header helper `header(id:displayName:versionStory:installed:primaryButton:)` (`:395-436`) is already kind-agnostic and shared by both branches — the reuse seam exists.

### 1.2 Entry points into that branch

`PackageDetailView` is constructed in exactly one place — `cellar/ContentView.swift:533-544` — for the `.browse`, `.installed`, `.favorites` and `.updates` sections, with all seven stores wired (`catalog`, `installed`, `operations`, `metadata`, `diskUsage`, `trustGrants`, plus cask assets). `cellar/Taps/TapDetailView.swift` does **not** navigate to it; it offers a *Show in Installed* handoff (TM5 state 1 and 2) that selects by `PackageID` in the Installed section — which then lands on this same branch. So the branch is already reachable from Taps, indirectly, today.

### 1.3 What reaches the view layer

`InstalledStore.inventory` → `InstalledInventory.package(_:)` → `InstalledPackage` (`Packages/CellarCore/Sources/BrewClient/InstalledModels.swift:29-151`). `InstalledInventory` is `Sendable` by composition and is produced off-main by `InstalledDecoder.decode(_:)` (`@concurrent`, `InstalledDecoder.swift:18-23`). Nothing in the render path is async.

### 1.4 Adjacent surfaces already provable on a catalog-less package

| Surface | Needs a `CatalogPackage`? | Notes |
|---|---|---|
| `sizeOnDisk(for: PackageID)` (`PackageDetailView.swift:629-636`) | No — keyed by `PackageID` | Reads `DiskUsageStore`; starts no scan |
| `PackageMetadataSection(entry:metadata:)` | No — takes `PackageEntry` | `PackageEntry(installed:catalog:id:)` accepts `catalog: nil` (used in `cellarTests/HealthCompositionSupport.swift:60`) |
| `installedAs(for:)` (`:640-643`) | No | Reads `isOnRequest` from the snapshot |
| `PackageTarget(id)` / `MutationCommand` | No — built from `PackageID` | Every verb is expressible |
| `TapProjection.grantsIndividually(_:publishedBy:in:)` | No | Takes `PackageID` + a **non-optional** `String` tap |
| `ReleaseNotesSection(package:installedVersion:)` | **Yes** — takes `CatalogPackage` | Not reusable as-is (see §5.7) |

---

## 2. Fields actually available from the installed receipt

Verified against the wire types, not assumed.

### 2.1 Wire → model (`InstalledWire.swift`, `InstalledDecoder.swift`)

| Model field | Type | Formula source | Cask source | Notes |
|---|---|---|---|---|
| `kind` | `PackageKind` | synthesized | synthesized | Always present |
| `name` | `String` | `name` (required) | `token` (required) | The only non-optional wire key |
| `displayName` | `String` | `= name` | `name?.first ?? token` | |
| `desc` | `String?` | `desc` | `desc` | Absence preserved |
| `homepage` | `URL?` | `homepage` | `homepage` | `url(_:)` drops empty strings → `nil` |
| **`tap`** | **`String?`** | `tap` | `tap` | **`nil` when Homebrew withholds it for an untrusted tap** (`InstalledModels.swift:39-47`, obs #7721) |
| `catalogVersion` | `String` | `versions.stable ?? primary.version` | `version ?? installed` | Falls back — never absent, so "offered version" can silently equal "installed version" |
| `kegs` | `[InstalledKeg]` | `installed[]` array | one synthesized keg | Formulae can be multi-version |
| `primaryKeg` | `InstalledKeg` | `linked_keg` match, else newest | the single keg | Never empty by construction |
| `linkedKeg` | `String?` | `linked_keg` | always `nil` | Formula-only |
| `snapshotOutdated` | `Bool` | `outdated ?? false` | `outdated ?? false` | |
| `isPinned` / `pinnedVersion` | `Bool` / `String?` | `pinned`, `pinned_version` | same keys | |
| `declaresAutoUpdates` | `Bool?` | always `nil` (not a formula concept) | `auto_updates` | Tri-state preserved (II2) |

Derived, free: `installedVersion`, `installedAt`, `isSelfUpdating`, `isOutdated`, `hasNewerVersion`, `isOnRequest`, and `formulaLinkState` (`InstalledDiskUsageProjection.swift:3-8`).

### 2.2 Two nullability traps

1. **`tap` is optional and is `nil` exactly for untrusted-tap packages.** Any tap fact must render as absent, never as `""` or `"unknown"`. See §5.1 and §8.
2. **`installedAt` collapses absence.** `InstalledDecoder.date(_:)` (`:131-133`) maps a missing `time` / `installed_time` to `Date(timeIntervalSince1970: 0)`. Nothing shipped renders an install date, so the collapse is currently invisible. A pane showing "Installed on" would print **1 January 1970** for any record whose timestamp brew omitted. A latent defect the new surface would expose, not one it creates.

### 2.3 Not available without a trust-sensitive tap-source read — must stay out

License, caveats, dependencies, dependents, install count / analytics, deprecated & disabled status with reasons and dates, cask `url` / `sha256` / artifact stanzas / `depends_on` / `conflicts_with`, formula stable & head source URLs. These are the exact fields PD1 owns, and they exist only in the catalog dump. Rendering an empty row for any of them would violate PD1's absence discipline by imitation.

---

## 3. Spec homework

### 3.1 PD6 — verbatim

> ### Requirement: Third-party tap packages are outside catalog scope
>
> The catalog covers the `homebrew/core` and `homebrew/cask` taps only. A package published by any other tap MUST be absent from the snapshot, MUST NOT appear in search results, and a detail lookup for it MUST return the ordinary not-found result. Its absence MUST NOT be reported as a sync failure, a decode failure, or an error state.
>
> *(scenarios: "A third-party tap package is a normal not-found"; "Every snapshot record belongs to a covered tap")* — `openspec/specs/package-detail/spec.md:232-249`

**Reading.** Every clause constrains the **catalog**: the snapshot, search results, and the *catalog detail lookup*. m10 changes none of them. The receipt-backed pane is not a catalog lookup and produces no catalog record, so PD6 is not literally violated.

**But** the m9 archive reads it as a blanket prohibition (`archive-report.md:440`, `tasks.md:72`, `specs/package-detail/spec.md:105-107`: *"this change adds no third-party detail fallback"*). Shipping m10 against an unamended PD6 leaves a documented contradiction.

**Recommendation: MODIFIED PD6**, adding one boundary sentence — the catalog exclusion is about the catalog projection, and a rendering fed exclusively by the installed receipt is not a catalog detail — while both existing scenarios survive byte-identical. PD6 is only 18 lines, so a whole-block MODIFIED is cheap. Search absence stays untouched: the "MUST NOT appear in search results" clause is reproduced verbatim.

### 3.2 PD8 — verbatim (opening paragraphs)

> ### Requirement: A per-package grant is shown beside the tap of origin, resolved by exact identity
>
> Where a package detail is presented and the `package-trust` capability reports that package's state as `granted`, the detail MUST carry the exact marker copy "Trusted individually", positioned beside the existing tap-of-origin fact, because the grant is a fact *about that origin* and is unreadable apart from it.
>
> The state MUST be resolved by **exact identity** — kind, name and tap of origin together, matched against the grant entry's published qualified identity. A bare name MUST NOT match a qualified entry: a grant for `acme/tools/widget` MUST NOT mark `homebrew/core/widget`, and MUST NOT mark a package whose tap the detail does not know exactly. Where identity cannot be established exactly, the marker MUST be absent.
>
> The marker MUST be **positive-only**. […] The marker MUST NOT become a field of the detail projection this capability owns […] — `openspec/specs/package-detail/spec.md:292-314`

**Two hard constraints for m10.** (a) The marker must sit **beside a tap-of-origin fact** — so the new pane must render a Tap fact, or PD8 has nowhere to attach. (b) A package **whose tap the detail does not know exactly** must carry no marker.

Shipped implementation: `PackageDetailView.grantMarker(for:)` (`:612-616`) calls `TapProjection.grantsIndividually(package.id, publishedBy: package.tap, in: trustGrants.grants)`; `publishedBy` is a **non-optional `String`** (`TapProjection.swift:309-320`). An `InstalledPackage`'s `tap` is `String?`, so an `if let` guard satisfies PD8's unknown-tap clause with no new logic.

### 3.3 TM1 — verbatim, and the m9 mis-citation

> ### Requirement: One structured snapshot supplies tap list and detail
>
> Each tap refresh MUST run exactly one `brew tap-info --installed --json` invocation. Its successful array envelope MUST supply both the tap list and every selected tap's detail; the capability MUST NOT run textual `brew tap` or another detail probe to complete that refresh. Cancellation, non-zero exit, blank stdout, and a malformed non-array envelope MUST remain distinct user-visible outcomes. — `openspec/specs/tap-management/spec.md:9-15`

**TM1 does not contain a no-third-party-detail-fallback constraint.** It is a one-invocation rule about *tap* detail acquisition. The m9 archive's repeated citation of "TM1 forbids a third-party detail fallback" (`archive-report.md:440`, `specs/package-detail/spec.md:20`) is a **mis-citation**.

The real clause is **TM5**, `openspec/specs/tap-management/spec.md:147-149`:

> Tap packages MUST NOT enter the catalog snapshot, catalog search, or catalog detail; PD6 remains unchanged and selection MUST NOT create a third-party detail fallback.

**Reading.** In context, "selection" is *tap-package row selection on the Taps surface*, and the prohibition pairs with "MUST NOT enter … catalog detail" — i.e. selecting a tap package must not fabricate a catalog record for it. m10 fabricates nothing and adds no Taps navigation. But the bare phrase is broad enough to read as a blanket ban.

**Recommendation: MODIFIED TM5**, narrowing that clause to what it means (no catalog record is created, and no tap-source read is performed to complete a package detail), and noting that the existing *Show in Installed* handoff already lands on a receipt-backed pane. Cost note: TM5 is a ~90-line block and a MODIFIED must reproduce it whole, including unchanged scenarios.

TM1 itself contributes a genuine constraint by analogy that m10 must honour: **no additional brew invocation may be introduced to complete a detail.** §5.6 confirms that is satisfiable.

### 3.4 `package-trust` requirements the new surface must honour

- **PT3** *"Attribution rests on published qualified identity, never on splitting a string"* (`:150-164`): "A bare name MUST NOT match a qualified entry … or a package whose tap the installed snapshot withholds. Where the identity cannot be established exactly, the state MUST be `noGrantRecorded`, never `granted`."
- **PT5** *"One projection value supplies the count, and the marker states an exact fact"* (`:257-271`): one projection value supplies the count; exact copy `"Trusted individually"`; the marker is **additive** and must not replace or reword existing state copy.
- **PT6** *"Per-package copy is positive-only and is never a verdict"* (`:304-319`): no rendering for "no individual grant" — no badge, no muted marker, no tooltip, no empty state. Nothing may imply a package is untrusted or unverified.
- **PT7** *"This capability grants and revokes nothing"* (`:353-357`): the new pane must offer **no** trust control, asserted as an absence by test.

`cellarTests/PerPackageTrustCompositionTests.swift:59-75` already asserts, over the app target's source text, that **no** surface composes the strings `"trusted individually"` or `"Trusted individually"` locally. Any m10 rendering must go through `TapProjection.grantMarker` or that test fails.

### 3.5 The affirmative basis: installed-inventory II7

> ### Requirement: The catalog join happens above both packages
>
> […] An installed package with no matching catalog record (a tap-only or unpublished package) MUST still be listed with **everything the snapshot knows about it**, never hidden. The join MUST live above both the catalog and the brew-process layers: the catalog MUST NOT gain a dependency on brew process execution […] — `openspec/specs/installed-inventory/spec.md:229-236`

II7 is already the cited authority for the `uncatalogedContent` branch (`PackageDetailView.swift:55`), for `PackageRow` (`:16-19`) and for `InstalledRow` (`:14-17`). m10 is the detail surface finally honouring "everything the snapshot knows about it". **This is where the new requirement most naturally lives** — `installed-inventory` is owned by `BrewClient`, the target that owns `InstalledPackage`; `package-detail`'s own header scopes it to "a single **catalog** package … Owned by `Packages/CellarCore` target `Catalog`".

### 3.6 Recommended delta shape

| Spec | Op | Why |
|---|---|---|
| `installed-inventory` | **ADDED** — "The installed receipt supplies a reduced detail for a package the catalog does not carry" | Owner of `InstalledPackage`; II7 already promises it |
| `package-detail` | **MODIFIED PD6** (18-line block, both scenarios preserved) | Draws the catalog/receipt boundary so PD6 is not read as a blanket ban |
| `tap-management` | **MODIFIED TM5** (~90-line block) | Narrows "selection MUST NOT create a third-party detail fallback"; corrects the m9 TM1 mis-citation in provenance |
| `package-trust` | none | PD8/PT3/PT5/PT6/PT7 already bind the marker correctly; m10 activates them rather than changing them |

---

## 4. Approaches

### A. Receipt projection in CellarCore + rendered in `PackageDetailView`'s existing branch

A new `nonisolated struct` (working name `InstalledDetailProjection`) in `Packages/CellarCore/Sources/BrewClient/`, over `InstalledPackage` (+ `TrustGrantState`), exposing the ordered facts a pane should render with absence preserved. The app target replaces `uncatalogedContent`'s `ContentUnavailableView` body with a fact grid driven by that value, in a `PackageDetailView+Receipt.swift` extension. No routing change, no new store wiring.

- **Pros:** Satisfies `rules.design` ("keep all logic in `Packages/CellarCore`; the app target holds views, scenes and DI wiring only"). Unit-testable in `BrewClientTests` with no SwiftUI and no process. Dependency direction untouched — `Catalog` never learns about `BrewClient`. Reuses the already-shared `header(id:displayName:…)` helper. PD8 activates by adding one Tap fact. Absence discipline enforced in the value type where a test can enumerate it. Mirrors the shipped `TapProjection` / `ReleaseNotesPresentation` idiom.
- **Cons:** One more public type in `BrewClient`. `PackageDetailView.swift` is already 875 lines; needs the extension split to stay reviewable.
- **Effort:** Medium.

### B. Widen the existing detail model with an enum / optional catalog part

`enum DetailSubject { case catalog(CatalogPackage); case receipt(InstalledPackage) }` threaded through the detail path.

- **Pros:** One code path; the compiler forces both cases to be handled at every fact.
- **Cons:** If the enum lives in `Catalog` it makes `Catalog` depend on `BrewClient` — directly contradicted by II7's asserted scenario *"The catalog target does not depend on the brew-process target"*. If it lives in `BrewClient` the direction works (`BrewClient` already imports `Catalog`) but every existing catalog-only helper — `facts`, `analytics`, `dependencies`, `dependents`, `PackageInspectionSection`, `ReleaseNotesSection` — must grow a `case receipt` returning nothing, exactly the "empty row for an absent field" shape PD1 forbids by spirit. Large blast radius on a shipped, fully-specified path.
- **Effort:** High.

### C. Synthesize a `CatalogPackage` from the receipt

- **Pros:** Zero new view code; every existing section renders immediately.
- **Cons:** **Reject.** (1) PD6 scenario *"Every snapshot record belongs to a covered tap"* becomes false the moment such a value can exist near the store — and `PackageSearchIndex` has 15 call sites consuming `CatalogPackage`, so leakage into search is one refactor away. (2) PD1's uniformity rule is violated by construction: a synthetic record publishes no license, no dependencies, no analytics, yet the tabs would render "This package declares no direct dependencies" and "Homebrew published no analytics entry for this package" — **false claims about the catalog** rather than statements about an absent record. (3) `catalog.tap` is non-optional `String`, so the withheld-tap case needs a sentinel — precisely what `InstalledModels.swift:39-47` exists to prevent.
- **Effort:** Low to write, high to unship.

### D. A standalone `InstalledOnlyDetailView` in the app target

- **Pros:** Cleanest file-level separation; smallest diff to `PackageDetailView`.
- **Cons:** Duplicates the shared header (or re-exports it), splits the single detail entry point in two, and requires re-passing five stores through a second construction site. Two panes that must keep the same identity row is exactly the drift PT5's one-projection rule exists to prevent.
- **Effort:** Medium.

| Approach | Dependency direction | Swift 6 isolation | Test surface | PD8 activation | Leak risk | Effort |
|---|---|---|---|---|---|---|
| **A** projection + existing branch | Clean (`BrewClient` only) | `nonisolated` value; view stays `@MainActor` | `BrewClientTests` unit, no SwiftUI | Direct — add Tap fact | **None** | Medium |
| B enum widening | Risky if placed in `Catalog` | Same | Wide regression surface | Direct | Low | High |
| C synthesize `CatalogPackage` | Violates PD6/PD1 | Same | Existing tests pass falsely | Direct | **High** — 15 consumers | Low/High |
| D standalone view | Clean | Same | View-level only | Direct | None | Medium |

---

## 5. Open questions and risks

### 5.1 HIGH (retired by §8) — PD8 may not activate if `tap` is withheld for granted packages

`InstalledPackage.tap` is `nil` "for every package published by an untrusted tap" (obs #7721). TM5's middle state names the same fact. PT5's own scenario pairs the two explicitly:

> - GIVEN a tap detail row for a package that is `granted` and installed, and a second row for a package that is **`granted` and reports the withheld-tap middle state** — `openspec/specs/package-trust/spec.md:298`

If withholding survived a grant, the receipt-backed pane would show no Tap fact and therefore no PD8 marker. Two mitigations were identified:

1. **Measure first.** A `manual-evidence` probe on the maintainer's Mac: for a package listed by `brew trust --json v1`, does `brew info --installed --json=v2` report its `tap`? — **Executed; see §8. Answer: yes.**
2. **Resolve tap-of-origin from the tap snapshot instead of the receipt** via `TapProjection.grants(for:in:).marked`. No longer required as the primary route; remains available as a fallback for the withheld-tap state.

### 5.2 MEDIUM-HIGH — `installedAt` renders as 1 Jan 1970 when brew omits the timestamp

`InstalledDecoder.date(_:)` collapses `nil` to the epoch. An "Installed on" fact would print a false date. Either preserve absence through the decoder (a small `installed-inventory` delta touching a shipped decoder and its tests) or omit the fact from m10. Decide in `sdd-spec`, not `sdd-apply`.

### 5.3 MEDIUM — how to detect "outside catalog scope"

The shipped answer is a **catalog miss**, not a tap check — and it should stay that way, because the tap is exactly the field that can be absent. But a catalog miss has at least four causes: a third-party tap, an unpublished/locally-built package, a cold or never-synced catalog (II9, and the brew-absent path), and a package the current catalog page dropped. **The pane's copy must not claim "this is from a third-party tap".** Today's copy — *"This installed package is not in Cellar's core/cask catalog"* — is already correctly scoped; m10 must not "improve" it into a claim.

### 5.4 MEDIUM — which actions the reduced pane offers

`PackageTarget(id)` and every `MutationCommand` are expressible from a `PackageID` alone, so Uninstall / Reinstall / Pin / Zap / Upgrade are *technically* available. Two cautions: an upgrade of a third-party package can trip Homebrew's interactive trust prompt in a non-interactive process, and PT7 forbids any trust control on this surface. Today the branch deliberately renders **no verb at all** (`primaryButton: { EmptyView() }`, `PackageDetailView.swift:377-379`). Widening that is a product decision for `sdd-propose`.

### 5.5 LOW-MEDIUM — formula/cask asymmetry

Formulae carry `kegs` (multi-version), `linkedKeg` and `formulaLinkState`; casks carry `declaresAutoUpdates` (tri-state) and exactly one keg. The projection must expose each fact only for the kind that can publish it — PD1's uniformity rule as a model, applied to the receipt.

### 5.6 CONFIRMED — no new brew invocation is required

Everything the pane needs is already resident: `InstalledStore` (the receipt), `TrustGrantStore` (`brew trust --json v1`), `TapStore` (`tap-info`, only if §5.1 route 2 is taken), `DiskUsageStore` (settled or incremental), `MetadataStore` (favorite / note / snooze). Zero new process spawns, so TM1's one-invocation discipline and PD6's "no sync failure" clause are both untouched.

### 5.7 LOW — release notes are out of scope

`ReleaseNotesSection` takes a `CatalogPackage`. `InstalledRow.swift:115-121` already resolves a GitHub repository from the *snapshot's* `homepage` for II7 reasons, so a receipt-backed release-notes affordance is feasible — but it is `release-notes` D4 territory (explicit entry point, egress consent) and would materially widen the change. **Recommend explicitly out of scope, stated in the proposal so it is a decision rather than an omission.**

### 5.8 LOW — a mis-citation to correct in provenance

The m9 archive states "TM1 forbids a third-party detail fallback" in at least three places. The clause is TM5's. m10's archive provenance should record the correction.

---

## 6. Recommendation

**Approach A.**

1. Add `InstalledDetailProjection` (name provisional) to `Packages/CellarCore/Sources/BrewClient/` — a `nonisolated`, `Sendable`, `Hashable` value over `InstalledPackage`, exposing the ordered facts with absence preserved and no formula/cask cross-contamination. Unit-tested in `BrewClientTests` against hand-built fixtures, no SwiftUI, no process.
2. Render it from the **existing** `uncatalogedContent` branch, moved into a `cellar/Browse/PackageDetailView+Receipt.swift` extension so the 875-line view file does not grow. Keep the shared `header(id:displayName:versionStory:installed:primaryButton:)` — one identity row, two panes, by construction.
3. Add the **Tap fact** with the PD8 marker beside it, resolved by exact identity, absent whenever the tap of origin is not known exactly.
4. Reuse `PackageMetadataSection`, `sizeOnDisk(for:)` and `installedAs(for:)` unchanged — all three already work from a `PackageID` and an optional catalog record.
5. Spec deltas per §3.6.

Approach C is a trap and should be named as rejected in the design so nobody re-proposes it.

### Rough size against the 5,000-line review budget

| Area | Est. changed lines |
|---|---|
| `BrewClient` projection + presentation | 120–180 |
| `BrewClientTests` unit coverage | 200–300 |
| `PackageDetailView+Receipt.swift` (new) + branch edit | 130–200 |
| `cellarTests` composition assertions (PD8 marker, no trust control, no local copy) | 80–130 |
| Spec deltas (`installed-inventory` ADDED, PD6 MODIFIED, TM5 MODIFIED) | 180–280 |
| Proposal / design / tasks / verify artifacts | 350–550 |
| **Total** | **~1,060–1,640** |

**5,000-line budget risk: Low** — roughly a quarter to a third of budget, comfortably a single PR under the cached `single-pr` delivery strategy. The one thing that could push it up is deciding to fix `installedAt` absence (§5.2) inside m10, which touches a shipped decoder and its existing tests: add ~150–250.

---

## 7. Ready for proposal

**Yes.** The §5.1 gate has been measured (§8) and the PD8-activation claim stands. The maintainer's original complaint (Home-Cellar showing "No further details") is answered by the pane either way.

---

## 8. Probe result — §5.1 measured (orchestrator, 2026-08-24, maintainer's Mac)

Commands (read-only): `brew trust --json v1` and `brew info --installed --json=v2`, filtered to records whose `tap` is not `homebrew/core` / `homebrew/cask`.

`brew trust --json v1` reported one trusted tap (`juancasanueva/cellar`) and per-package formula grants for `gentleman-programming/tap/{engram,gentle-ai,gentleman-dots,gga}`, `cloudmanic/spice-edit/spice-edit`, `jnsahaj/lumen/lumen`, `kitlangton/tap/ghui`, `letstri/tap/druk`, `modem-dev/tap/hunk`, plus cask grants for packages not currently installed.

`brew info --installed --json=v2` reported a non-null `tap` for **every** one of those individually-granted, installed formulae (`letstri/tap`, `gentleman-programming/tap`, `kitlangton/tap`, `modem-dev/tap`, `jnsahaj/lumen`, `cloudmanic/spice-edit`) and for the tap-trusted cask `home-cellar` (`juancasanueva/cellar`, with `installed_time` present).

**Conclusion:** a per-package grant does not cause Homebrew to withhold `tap` from the installed receipt. PD8 can be resolved from the receipt's `tap` via the existing `TapProjection.grantsIndividually(_:publishedBy:in:)` path. The withheld-tap state remains a real, separately specified state (PT3/TM5) for packages with *no* grant at all, and the pane must still render no Tap fact and no marker in that case. §5.1 mitigation 2 is not needed for m10.
