# Exploration: `m6-tip-jar` — StoreKit 2 consumable tip jar (M6, first slice)

Repository evidence read at clean `main` `745057d`. Artifact store is hybrid; the Engram copy lives at
topic `sdd/m6-tip-jar/explore` (observation 7636). This file is the OpenSpec copy, persisted by the
orchestrator because the exploration executor ran read-only.

**Product decision already taken by the user and not re-litigated here**: the tip jar is a **$0.99
consumable StoreKit 2 in-app purchase**, and Cellar targets the Mac App Store. PRD §9 Q2 ("tip jar
provider") is therefore **resolved as StoreKit**, superseding PRD.md:186. What this document *does* do —
because the task asked for it — is surface the distribution consequences of that pivot as risks and open
questions, since they are load-bearing for the proposal and for M6 as a whole.

---

## 1. Exact PRD scope, and every line the pivot touches

| PRD line | Text (verbatim) | Effect of the pivot |
|---|---|---|
| 3 | "A native Homebrew GUI for macOS — SwiftUI, no backend, **free with tip jar**." | unchanged |
| 9 | "**Distribution** \| Direct download (Developer ID + notarized, Sparkle updates) **and** Homebrew cask" | **contradicted** — MAS is now a third (or replacing) channel |
| 10 | "**Monetization** \| Free, ad-free, **external tip jar**" | **superseded** — "external" is now wrong |
| 25 | "**Free forever.** All features free… Optional tip jar." | unchanged |
| 124 | "**Settings**: brew path, refresh/scan schedules, notifications, menu bar toggle, appearance, **tip jar**, Sparkle update channel." | placement candidate A |
| 186 | "**Tip jar**: **StoreKit is unavailable outside the App Store**, so tips are external links (GitHub Sponsors / Ko-fi / Stripe Payment Link — pick at M6) opened in the browser from a Support screen. Copy is gratitude-based, never nagging; a single subtle **\"Support\" sidebar item**." | **first half superseded**; the copy rule and the sidebar-item idea survive |
| 212 | "**M6 — Ship** … Sparkle integration; CI signing/notarization pipeline; self-hosted tap; landing page; **tip jar**." | this change is M6's first slice |
| 234 | "§9 Q2. Tip jar provider (GitHub Sponsors vs Ko-fi vs Stripe Payment Link)." | **resolved: StoreKit** |

PRD.md:186's own reasoning — "StoreKit is unavailable outside the App Store" — is **factually correct**,
and is exactly what the pivot inverts by changing the distribution channel rather than the API. Developer
ID distribution provides no StoreKit; StoreKit IAP on macOS requires App Store distribution. The PRD did
not choose external links out of preference; it chose them out of a constraint that disappears only if
Cellar ships on the Mac App Store.

Not in conflict: PRD.md:30's non-goal "Mac App Store update integration — deferred" is about Cellar
*managing* MAS-installed apps, not about Cellar's own channel.

### The MAS pivot's cost, stated plainly (headline finding)

`cellar.xcodeproj/project.pbxproj` carries, in **both** Debug (line 425) and Release (line 458):

    ENABLE_APP_SANDBOX = NO;
    ENABLE_HARDENED_RUNTIME = YES;

`openspec/config.yaml` records the same as project context. PRD.md:157 states the reason: "**Sandbox:
off.** Hardened runtime on, sandbox off (required to exec brew)."

Mac App Store distribution requires `com.apple.security.app-sandbox` on the main executable. Three
consequences, each independently sufficient to block a MAS submission of Cellar itself:

1. **A sandboxed parent's children inherit its sandbox.** A sandboxed Cellar spawning
   `/opt/homebrew/bin/brew` gives brew Cellar's container, not the user's environment: brew could not
   write `/opt/homebrew`, read `~/Library/Caches/Homebrew`, or spawn `git`/`curl` freely. `brew` is the
   product (PRD principle 2), so this is not a degradation — it is total.
2. **Guideline 2.5.2 / 2.4.5** — App Store apps may not download or install executable code. Every
   `brew install` does exactly that.
3. **The quarantine manager** (PRD §3.5, shipped in M4 as `SecurityKit` `removexattr` handling) and the
   disk walks over `/opt/homebrew` are sandbox-hostile by construction.

**Therefore: the tip jar is buildable and locally testable today, but its *transacting* ship path is
unproven and may not exist.** This is an open product question for the proposal, not a blocker for this
change — Xcode's StoreKit Testing runs against a locally signed, unsandboxed build with no App Store
Connect record at all (§4.4).

---

## 2. Where the tip surface belongs

### 2.1 The three candidate homes, all already built

**Settings** (`cellar/Settings/SettingsView.swift`) — a `ScrollView` of `group(_:rows:)` cards. It
already closes with `freeCard` (:160–175), the design's verbatim copy: "Cellar is free, and stays free" /
"No accounts, no telemetry, no paid tier.", drawn with
`.themeCard(fill: theme.tint(0.07), stroke: theme.tint(0.24))`. A tip card belongs directly beside it: a
tip jar does not create a paid tier, so that copy survives untouched and the two read as one statement.
PRD.md:124 names the tip jar under Settings. **Zero `AppSection` churn.**

**A `Support` sidebar item** — PRD.md:186's "single subtle 'Support' sidebar item".
`AppSection.sidebarFooter` (`cellar/Shell/AppSection.swift:182`) is exactly the right shelf:
`static let sidebarFooter: [AppSection] = [.settings]`, rendered by `SidebarView` (:53–61) below a
`Theme.separator` hairline. `[.support, .settings]` is a one-line change to the array — but see §2.2 for
what it costs everywhere else.

**About** (`cellar/Shell/AboutView.swift:80–88`) — `linksCard` already carries two `linkRow`s (web page,
email) with an `arrow.up.right.square` affordance and `Link(destination:)`. A "Support Cellar" row here is
the smallest possible surface. **Caution**: in a MAS binary, outbound links to *payment* destinations
violate Guideline 3.1.1; the existing two links are informational and are fine.

### 2.2 What a new `AppSection` case actually costs

`AppSection` has 21 cases and the placement suite pins them **deliberately and loudly**
(`cellarTests/AppSectionPlacementTests.swift`):

- `:34` — `#expect(order.count == 21)`
- `:52–60` — the exact `rawValue` array, in order
- `:80–87` — `sidebarGroups.flatMap(\.sections) + sidebarFooter` must equal `allCases` **exactly once
  each**, and `#expect(AppSection.sidebarFooter == [.settings])`
- `:139–168` — a source scanner asserting **≥4** exhaustive `AppSection` switches with **no `default:`
  arm**, and specifically 3 in `ContentView.swift`
- `:180–201` — `pinnedHeaderSections` must cover **every** `AppSection.allCases` member

A `.support` case therefore touches, at minimum:

| File | What changes |
|---|---|
| `cellar/Shell/AppSection.swift` | new case + `title` arm (:104) + `systemImage` arm (:141) + `sidebarFooter` (:182) |
| `cellar/Shell/SidebarView.swift` | `badge(for:)` exhaustive arm (:201–207) |
| `cellar/ContentView.swift` | content switch (:469), `detailPane` (:477–479), `shellTitleBarAccessories` (:606–609), `pinnedHeaderSections` (:570), `shellTitleBarSections` (:579) |
| `cellarTests/AppSectionPlacementTests.swift` | 3 pinned literals updated |

Roughly 60–100 authored lines of churn plus a test-literal rewrite. None of it is hard; all of it is
deliberate friction the placement suite exists to create.

### 2.3 Recommendation on placement

**Settings card + an About link-card row, with no new `AppSection`.** It satisfies PRD.md:124 literally,
keeps the "single subtle" instruction of PRD.md:186 (subtle is the operative word), costs zero
placement-suite churn, and leaves `.support` available as a later, cheap addition. The About row should be
a *button that opens Settings*, not a second purchase surface — one purchase call site is easier to prove
correct and to test structurally.

---

## 3. Codebase integration points

### 3.1 The seam idiom to copy is `BrewfileSourceChoosing`, exactly

`Packages/CellarCore/Sources/BrewClient/BrewfilePublication.swift:15–21`:

    public protocol BrewfileDestinationChoosing: Sendable { func chooseDestination() async -> URL? }
    public protocol BrewfileSourceChoosing: Sendable { func chooseSource() async -> URL? }

The doc comment states the rule verbatim: "Declared here and conformed in the app target, so `CellarCore`
imports no AppKit and the store stays testable without a window server." Conformers live in
`cellar/Taps/BrewfilePanels.swift` as `nonisolated Sendable` structs that hop to `@MainActor` internally.
`cellarApp.swift:442` injects `AppTestFixtures.brewfileSourceChooser`.

`config.yaml` `rules.design` makes this binding: "Keep all logic in `Packages/CellarCore`; the app target
holds views, scenes, and DI wiring only" and "Define protocol boundaries for every external dependency
(Process, FileManager, network)." StoreKit is an external dependency in exactly that sense — network, a
payment sheet, and the user's Apple Account.

That same file also records the **latent sandbox trap** (:28–42) the MAS pivot makes urgent:
`ENABLE_USER_SELECTED_FILES = readonly` sits inert beside `ENABLE_APP_SANDBOX = NO`, and if the sandbox is
ever switched on, "a `readonly` user-selected-files entitlement **permits the import's read** and **blocks
the export's write**". The fix is recorded in place: `readwrite`, not a security-scoped bookmark.

### 3.2 The structural-composition test idiom

`cellarTests/SecurityCompositionSupport.swift:42–69` (`AppSecuritySources`) reads `cellar/` off disk via
`#filePath`, strips comments, and lets a test make claims about what the app target does *not* contain.
`cellarTests/HealthCompositionTests.swift:467–485` narrows it to one directory (`HealthSources`).
`cellarApp.swift:268–272` records the purpose for `OSVSource`/`NVDSource`: "reachable from this file and
from nowhere else in the app… `SecurityCompositionTests` asserts that structurally."

**A `TipCompositionTests.swift` should assert the identical thing**: `import StoreKit` appears in exactly
one file under `cellar/`, and no view file references `Product`, `Transaction`, or `AppStore`. That is the
only honest way to prove the seam holds, since the conformer cannot be unit-tested without StoreKit's
runtime.

### 3.3 Store, loop and wiring precedents

- `cellarApp.swift` owns every store as `@State`, builds every seam in `init()`, and injects fixtures via
  `AppTestFixtures.isEnabled` (:189–196). A `TipStore` follows.
- `LoopOwner` (:181; `.task { loops.start("catalog") { … } }` at :480–492) is the app's
  idempotent-per-id long-lived-loop mechanism. The StoreKit skill's `Task.detached` in `App.init()` is the
  generic pattern; **`loops.start("tips") { await tips.observeTransactions() }` is this repo's**, and it is
  strictly better (a second window joins rather than starting a second listener). The file's own warning at
  :488–491 — a `LoopOwner` slot stays claimed for the launch, so anything that must restart cannot live
  there — does not apply: a `Transaction.updates` listener must never return.
- `ReleaseNotesStore` is the closest analogue: a store with **no cadence at all**, whose "only caller is a
  button" (:88–91).

### 3.4 Theme and control idioms

`Theme` (`cellar/Theme/Theme.swift:33`), `Theme.mono(_:weight:)` (:115), `.themeCard(…)` (:139),
`ShellChipButtonStyle` (`cellar/Shell/ShellToolbar.swift:87`). `SettingsView`'s
`group`/`row`/`separator` are private helpers; a tip card either lives in `SettingsView.swift` or
re-implements the card shape (`AboutView` already re-implements its own `card`/`row`, so duplication is
house-accepted). Accessibility identifiers are mandatory — existing forms are `settings-section`,
`accent-\(name)`, `sidebar-\(rawValue)`; a tip surface needs `tip-jar-card`, `tip-jar-purchase` because
XCUITest queries by them.

### 3.5 Target placement in `CellarCore`

`Packages/CellarCore/Package.swift` has 7 library products with explicit, comment- and test-enforced
dependency discipline: `Catalog` stays brew-free (CS1); `Persistence` is the deliberate outermost node; no
target may see both `BrewClient` and `SecurityKit` except `Persistence`; `ReleaseNotes` depends on
`Catalog` alone so "release notes spawn no `brew` process" is a build-graph fact.

A tip jar has **zero** legitimate edges. A new `TipJar` target with **no dependencies** — the
`CellarTestSupport` shape, but as a product — makes "the tip jar cannot reach brew, the catalog, the
network client, or SwiftData" a build-graph fact, and keeps the capability one `git revert` away (the
`ReleaseNotes` precedent, `Package.swift:107–108`).

---

## 4. StoreKit 2 specifics for a macOS consumable

### 4.1 What a consumable changes versus the skill's generic checklist

| Generic StoreKit rule | Applies to a $0.99 consumable tip? |
|---|---|
| `Product.products(for:)` to load | **Yes** — and an **empty array is a real, reachable state** (product not configured, not yet approved, storefront restricted). It must be a typed case, not a permanent spinner. |
| `product.purchase()` → `.success` / `.userCancelled` / `.pending` / `@unknown default` | **Yes**, all four. `.pending` is Ask to Buy — the tip is not complete and the copy must say so. |
| Verify `VerificationResult` before granting | **Yes** — but a tip grants *nothing*, so `.unverified` means "do not say thank you", not "withhold content". Finish it anyway so it does not replay. |
| `transaction.finish()` after delivery | **Yes, and it is the whole lifecycle.** An unfinished consumable reappears in `Transaction.unfinished` forever. |
| `Transaction.currentEntitlements` | **No — structurally irrelevant.** A finished consumable never appears there. Any code consulting it for a tip is wrong. |
| **Restore purchases button** | **No.** Consumables are not restorable. A restore button here would be misleading UI, not compliance. |
| `Transaction.updates` listener at launch | **Yes** — catches Ask to Buy approvals, a purchase made on another Mac on the same Apple Account, and refunds/revocations. Also drain `Transaction.unfinished` at launch. |
| ToS / privacy-policy links | **No** — those are `SubscriptionStoreView` requirements. |
| `product.displayPrice`, never a hardcoded price | **Yes, strictly.** "$0.99" is a *price tier*, not a string. PRD prose may say $0.99; the UI may not. |
| `.appAccountToken(…)` | **No.** Cellar has no accounts and no backend (PRD principle 3). |
| `.quantity(n)` | Optional; a "tip more" affordance is a product decision, not a default. |
| `AppStore.canMakePayments` | **Yes** — parental restriction is a real state the card must render honestly. |
| `SubscriptionStoreView` / `StoreView` / `ProductView` | **No.** Merchandising containers with their own chrome; PRD §5 forbids competing chrome. A single custom button calling `product.purchase()` is correct. |

**Repeat purchases are the point.** A consumable can be bought again — exactly what a tip jar wants and
what a non-consumable would forbid.

### 4.2 Guideline 3.1.1 — the classification is correct, and it is exclusive

Apple requires IAP for "digital tips or donations" to the developer. A tip to the app's developer is a
consumable IAP; a *charitable* donation is the case that must **not** use IAP. Cellar's is the former.

The exclusivity matters: 3.1.1 also forbids "links, buttons, or language directing users to purchase
outside the app". A MAS binary therefore **cannot** also carry a Ko-fi/Sponsors/Stripe link, and a
Developer ID binary cannot transact StoreKit. One binary cannot serve both channels without a
compile-time or runtime seam. See §6c.

### 4.3 Entitlements and privacy manifest

- **In-App Purchase requires no entitlement.** `com.apple.developer.in-app-payments` is **Apple Pay
  merchant IDs**, a different feature. `com.apple.developer.storekit.external-purchase-link` is for
  external-purchase links, which this change explicitly does not use.
- What MAS distribution *does* require is `com.apple.security.app-sandbox` plus Apple Distribution signing
  and a provisioning profile — i.e. §1's blocker, not a tip-jar entitlement.
- **There is no `PrivacyInfo.xcprivacy` in this repo** (verified). The tip jar collects nothing — Apple,
  not Cellar, handles the transaction — so it adds no nutrition-label obligation of its own. But the app
  *already* uses `UserDefaults`, file timestamps, and disk space — all required-reason API categories on
  the platforms where manifests are enforced. **Whether macOS App Store submissions enforce
  required-reason manifests is not established here and must be probed (U22).**

### 4.4 Local testing without App Store Connect — the enabling fact

A `.storekit` **configuration file** lets Xcode serve synthetic products locally with no App Store Connect
record, no sandbox Apple Account, and no network. It is referenced from the **scheme's `LaunchAction`**:

    <StoreKitConfigurationFileReference identifier = "../../../Cellar.storekit">

and the `.storekit` file **must have no target membership**. This works on macOS as well as iOS.

Two repo-specific hazards:

1. **`cellar/` is a `PBXFileSystemSynchronizedRootGroup`** (`project.pbxproj:41–57`). Files dropped inside
   it are auto-added to the target — precisely what a `.storekit` file must *not* be. Placing it
   **outside** `cellar/` is the safe default. **U17 decides.**
2. **The scheme edit is a real, shared diff.** `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme`
   is the only scheme `config.yaml`'s five commands use, and its `TestAction` carries
   `shouldUseLaunchSchemeArgsEnv = "YES"` (:30). Whether a StoreKit configuration reference on the
   `LaunchAction` therefore also applies to `xcodebuild test` is **unmeasured. U18 decides.** A second,
   StoreKit-only scheme is the escape hatch.

`SKTestSession` (the `StoreKitTest` framework) can drive purchases programmatically, including
`disableDialogs`, buy/refund/expire, and Ask-to-Buy simulation. It lives in the **app test target**, not
in `swift test --package-path Packages/CellarCore`. **U19** must establish whether it works headlessly on
macOS 26 / Xcode 26.6 from a Swift Testing `@Test`.

---

## 5. SDD / house conventions this change must follow

- **`openspec/config.yaml`**: `artifact_store: hybrid`, `delivery_strategy: single-pr`,
  `review_budget_lines: 5000`, `testing.strict_tdd: true`. `rules.proposal` requires naming the PRD
  milestone explicitly (**M6**) and a rollback plan "for anything touching the Xcode project file or
  target membership" — this change touches the **scheme** and adds a `Package.swift` target, so a rollback
  plan is mandatory.
- `rules.design`: no `#available` branches (macOS 26 floor); document actor isolation and `Sendable` for
  anything crossing a concurrency domain; protocol boundary for every external dependency.
- `rules.tasks`: RED before GREEN for every behavioral task; forecast the budget explicitly.
- **Change folder layout**, from the three most recent archives: `explore.md`, `proposal.md`, `design.md`,
  `specs/{capability}/spec.md`, `tasks.md`, `apply-progress.md` (when apply spans sessions),
  `verify-report.md`, then `archive/YYYY-MM-DD-{change}/` plus `archive-report.md`.
- **20 main capabilities** exist under `openspec/specs/`. A tip jar is a **new capability** (`tip-jar`),
  ADDED-only — no destructive delta.
- **Sizing history**: M5 slices 3 and 4 both overshot forecasts; slice 5's exploration recorded a measured
  **1.9–2.3× correction** to bottom-up counts. Applied to ~1,200 authored lines bottom-up, the honest
  forecast is **2,300–2,800**. The first M6 slice that should not need a size exception.
- **`PBXFileSystemSynchronizedRootGroup` gives 0-line `project.pbxproj` diffs** for new `cellar/<Group>/`
  directories. A new `cellar/Support/` group is free; the `.storekit` file is the one thing that must stay
  out of it.

---

## 6a. Approaches — architecture

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **StoreKit directly in the SwiftUI view** | Fewest files; ~120 lines | Violates `rules.design`; untestable, so **strict TDD has nothing to write a RED test against** | Low |
| **B** | **New dependency-free `TipJar` target in `CellarCore`** declaring `TipProduct` (plain `Sendable`), `TipCatalogLoading` / `TipPurchasing`, a `TipPurchaseOutcome` enum (`completed / cancelled / pending / unverified / failed(reason) / unavailable(reason)`) and an `@Observable @MainActor TipStore`; a `StoreKitTipSource` conformer in the app target; `TipCompositionTests` proving `import StoreKit` appears in exactly one app file | Matches `BrewfileSourceChoosing` exactly; every state fake-driven from `swift test`; zero edges means one `git revert` | One more `Package.swift` target (rollback note required); the conformer stays unit-untested unless U19 says `SKTestSession` works | Medium |
| **C** | **B, but `TipJar` imports StoreKit itself** | One fewer indirection | Puts a payment-sheet framework inside `CellarCore`; `swift test` would link StoreKit | Medium |

**Recommendation: B.**

## 6b. Approaches — surface placement

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **Settings card only** (beside `freeCard`) | PRD.md:124 literally; zero churn | Discoverable only via Settings | Low |
| **B** | **New `.support` `AppSection`** in `sidebarFooter` | PRD.md:186 literally | 22nd case; 6 exhaustive switches + 3 pinned test literals | Medium |
| **C** | **About window row only** | Smallest | Least discoverable | Low |
| **D** | **A + C**: Settings card is the only purchase surface; About gains a row that *opens Settings* | Two entry points, one call site; zero placement-suite churn | Two files; the About row is a button, not a `Link` | Low |

**Recommendation: D.**

## 6c. Approaches — what the un-transactable Developer ID build does

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **Always render the card** with honest unavailable copy | One code path, exercised daily | Ships a permanently inert control — what `SettingsView`'s doc comment refuses | Low |
| **B** | **Compile-time flag** (`MAS_BUILD`) | No inert UI | Second build configuration; `#if` branches | Medium |
| **C** | **Runtime distribution seam**: a `TipAvailability` value composed once, card hidden when tipping cannot transact | Single code path; shipped surface honest; fake-able | Needs a defensible "is this a MAS build" signal (**U20**) | Medium |
| **D** | **External links in Dev ID build, StoreKit in MAS build** | Everyone can tip | Two payment stories; 3.1.1 forbids coexistence | High |

**Recommendation: C, with A as fallback if U20 shows no clean signal.**

---

## 7. Affected areas

- **New** `Packages/CellarCore/Sources/TipJar/` — `TipProduct.swift`, `TipSeams.swift`,
  `TipPurchaseOutcome.swift`, `TipStore.swift`. **No dependencies.**
- **New** `Packages/CellarCore/Tests/TipJarTests/` — fake-driven coverage of every state.
- `Packages/CellarCore/Package.swift` — one `.library` + one `.target` + one `.testTarget`. **Rollback
  plan required.**
- **New** `cellar/Support/` — `StoreKitTipSource.swift` (the only app file importing StoreKit) and
  `TipJarCard.swift`.
- `cellar/Settings/SettingsView.swift` — the tip card beside `freeCard`.
- `cellar/Shell/AboutView.swift` — one row in `linksCard` (6b-D).
- `cellar/cellarApp.swift` — `@State` TipStore, seam construction, fixture swap,
  `loops.start("tips") { await tips.observeTransactions() }`.
- `cellar/AppTestFixtures.swift` — a no-network, no-StoreKit fake.
- **New** `cellarTests/TipCompositionTests.swift` — the structural sweep.
- **New** `Cellar.storekit` — **outside** `cellar/`, no target membership (U17).
- `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme` — `StoreKitConfigurationFileReference` (U18;
  may instead become a second scheme).
- **New** `openspec/specs/tip-jar/spec.md` via an **ADDED-only** delta.
- `PRD.md` — lines 9, 10, 186, 234 and §6 amended.
- **Not touched** (a binding, under 6b-D): `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`,
  `cellarTests/AppSectionPlacementTests.swift`.

---

## 8. Risks

1. **The MAS ship path is unproven and may not exist.** Sandbox inheritance would put `brew` inside
   Cellar's container; Guideline 2.5.2 forbids downloading/installing executables; the quarantine manager
   is sandbox-hostile. The feature is still buildable and locally testable — but the proposal must say so.
2. **PRD contradiction shipping in-repo** unless PRD.md:9/10/186/234 are amended in the same PR.
3. **Guideline 3.1.1 mutual exclusion** between StoreKit and external links in one binary.
4. **A permanently inert purchase button** violates `SettingsView`'s own stated rule.
5. **The shared scheme edit affects every test invocation.**
6. **The `.storekit` file must not gain target membership** (synchronized root group hazard).
7. **The StoreKit conformer may be unit-untestable** — strict TDD RED-first applies to the CellarCore
   half; must be declared in design.
8. **Price is a tier, not a string.**
9. **`Transaction.updates` must never be missed**; an unfinished consumable is retried forever.
10. **Real verification is blocked behind risk 1.**
11. **The baseline suite was not green at `7d48779`** (`ReleaseNotesUITests` 4 cases/7 failures,
    unowned); re-baseline at current main (U21).
12. **No CI.**

---

## 9. Probes required before design (U-gates)

- **U16 — does local StoreKit testing work here at all?** Throwaway `.storekit` + scratch scheme;
  `Product.products(for:)` from a development-signed, unsandboxed build. *The gate.*
- **U17 — `.storekit` file placement** inside vs outside the synchronized root group.
- **U18 — scheme reference vs `xcodebuild test`** with `shouldUseLaunchSchemeArgsEnv = "YES"`.
- **U19 — `SKTestSession` on macOS 26 from a Swift Testing `@Test`**, headless.
- **U20 — a clean "can this build transact" signal** (`AppStore.canMakePayments`, `AppTransaction.shared`
  behavior in a Dev ID build).
- **U21 — baseline suite state at current main.**
- **U22 — (M6-level, not blocking)** macOS privacy-manifest enforcement; sandbox feasibility spike
  (`ENABLE_APP_SANDBOX = YES` + `brew list`).

---

## 10. Product decisions required before proposal

1. **Surface placement** — 6b-D recommended.
2. **Product identifier and tier count** — one consumable, `com.juancasanueva.cellar.tip` recommended.
3. **What the Developer ID build shows** — 6c-C recommended, 6c-A fallback.
4. **Does this change amend `PRD.md`?** Recommend yes, same PR, rewritten-in-place style.
5. **Does Cellar remember that the user tipped?** Recommend a single local flag — no date, no count, no
   sync — stated in the spec.
6. **Copy**: gratitude-based, never nagging, never a launch-time modal (PRD.md:186's surviving rule).
7. **`ReleaseNotesUITests` still needs an owner** (risk 11).

---

## 11. Ready for Proposal

**Yes, after a decision round on §10.1–§10.5 and probes U16–U18.** U16 is the gate. U19–U21 can run
during design. U22 is M6-level: its answer determines whether the tip jar ever transacts, but it does not
block building it.

Architecture (6a-B) is settled by existing convention. Sizing forecast: 2,300–2,800 authored lines
against the budget — `single-pr` should hold.
