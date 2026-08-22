# Proposal: StoreKit 2 Consumable Tip Jar (`m6-tip-jar`)

Anchors PRD.md **M6 "Ship"** (:212) — the **first M6 slice**. Delivers PRD §3.7 Settings' tip jar
(:124) and the gratitude-based copy rule (:186); **resolves PRD §9 Q2** (:234, tip-jar provider) as
**StoreKit**, superseding :186's external-links ruling. Exploration:
`openspec/changes/m6-tip-jar/explore.md` (obs 7636). Probes U16–U21 executed
(`probes.md`, obs 7638). Product decisions 1–4 taken by the maintainer (obs 7637) and **binding**.

## Intent

Cellar is free, ad-free and stays that way (PRD :25). The PRD promises a tip jar and, at the time it
was written, ruled it out as an in-app purchase for a correct reason: *"StoreKit is unavailable
outside the App Store"* (:186). The maintainer has since chosen StoreKit — inverting the
**distribution channel**, not the API.

The product outcome: a user who wants to thank the developer can do so **in the app, once, in two
clicks, with no account, no browser hop and no external site** — and Cellar never asks twice, never
nags, and never shows a launch-time modal. Today there is no way to tip at all, and the repository
carries a decision record that says tips will be browser links.

## Binding Constraints

1. **Ship path stated openly (decision 1).** The MAS channel that makes StoreKit transactable is
   **unproven and may not exist**: `ENABLE_APP_SANDBOX = NO` (pbxproj :425/:458) is required to exec
   `brew`; a sandboxed parent's children inherit its container; Guideline 2.5.2 forbids downloading
   executable code, which is what every `brew install` does. This slice **builds and fully tests** the
   tip jar; it does **not** claim it will transact for users. The sandbox feasibility spike (**U22**)
   is an **M6 follow-up**, tracked, not silently inherited.
2. **Guideline 3.1.1 is exclusive.** A MAS binary must not link out to Ko-fi/Sponsors/Stripe; a
   Developer ID binary cannot transact StoreKit. One binary cannot carry both stories.
3. **No telemetry claim is protected.** The tip records **one local boolean** — no date, no count, no
   sync, no identifier (decision 4). `.appAccountToken` is forbidden: Cellar has no accounts.
4. **Price is a tier, not a string.** Every surface reads `product.displayPrice`. "$0.99" may appear
   in PRD prose; it may never appear in UI or in a test assertion.
5. **A consumable leaves no entitlement.** `Transaction.currentEntitlements` is structurally
   irrelevant here and any code consulting it for the tip is wrong. `finish()` is the whole lifecycle.
6. **No inert control.** `SettingsView`'s own doc comment (:12–15) refuses present-but-inert rows.

## Scope

**In:** a dependency-free `TipJar` target in `CellarCore` (`TipProduct`, `TipCatalogLoading`,
`TipPurchasing`, `TipPurchaseOutcome`, `@Observable @MainActor TipStore`, `TipAvailability`); a
`StoreKitTipSource` conformer in a new `cellar/Support/` group — **the only app file importing
StoreKit**; one consumable product id **`com.juancasanueva.cellar.tip`**, one tier; a Settings tip card
beside `freeCard`; an About `linksCard` row that **opens Settings** (not a second purchase surface); a
`Transaction.updates` listener plus `Transaction.unfinished` drain on the `LoopOwner` `"tips"` slot; an
`AppTestFixtures` fake so UI tests stay at zero egress and zero StoreKit; `TipCompositionTests`
structural sweep; **SKTestSession-driven conformer tests** with `Tip.storekit` checked into
`cellarTests/`; PRD.md :9/:10/:186/:234 amended in the same PR.

**Out (non-goals — each recorded, not omitted):** a **restore-purchases button** (consumables are not
restorable; it would be misleading UI, not compliance); any `currentEntitlements` / entitlements UI; a
**tip ladder** or `.quantity(n)`; a new **`.support` `AppSection`** — `AppSection.swift`,
`ContentView.swift` and `AppSectionPlacementTests.swift` are a **not-touched binding** (decision 2);
any **external payment link** (Ko-fi / GitHub Sponsors / Stripe); **`.appAccountToken`**;
`SubscriptionStoreView` / `StoreView` / `ProductView` merchandising chrome; ToS/privacy-policy links
(subscription-only requirements); a `PrivacyInfo.xcprivacy`; **any sandbox, entitlement, signing or
App Store Connect work** (that is U22 / a later M6 slice); a second Xcode scheme; thank-you dates,
counts, history or sync; any launch-time prompt.

## Capabilities

- **New `tip-jar`** (ADDED-only — no destructive delta, so `rules.archive`'s warning does not fire):
  the tip seams and their `Sendable` value types; the six `TipPurchaseOutcome` cases
  (`completed / cancelled / pending / unverified / failed / unavailable`) and what each must and must
  not claim to the user; the finish-always rule including `.unverified`; the availability rule (empty
  product list ⇒ no tip surface); the local single-flag thank-you rule with its no-telemetry
  justification; the `displayPrice`-only rule; and PRD :186's copy rule promoted to **requirement
  text**: gratitude-based, never nagging, never a launch modal, never a repeated prompt.
- **Modified capabilities: None.** No shipped spec changes behaviour.

## Approach

**Architecture 6a-B.** A `TipJar` target with **zero dependencies** makes *"the tip jar cannot reach
brew, the catalog, the network client or SwiftData"* a **build-graph fact**, not a convention. It
declares `TipCatalogLoading` / `TipPurchasing` and conforms them in the app target — the exact
`BrewfileSourceChoosing` idiom, whose doc comment already states the rule. StoreKit's `Product` and
`Transaction` never cross into `CellarCore` or into a view; `TipProduct` is a plain `Sendable` value.
Every outcome — empty catalog, cancelled, pending (Ask to Buy), unverified, failed, repeat purchase,
unfinished drain — is fake-driven and reachable from `swift test` in milliseconds, which is what strict
TDD needs.

**The conformer gets real tests.** U19 proved `SKTestSession` works **headlessly** under plain
`xcodebuild test` (`disableDialogs`, `purchase()`, verified transaction). `Tip.storekit` lives in
**`cellarTests/`** (U17), where it bundles into `cellarTests.xctest` only and never ships in the app.
`TipCompositionTests` additionally asserts `import StoreKit` appears in exactly one file under
`cellar/` and that no view references `Product`, `Transaction` or `AppStore` — the shipped
`AppSecuritySources` / `OSVSource` treatment.

**Zero scheme changes (U16/U18).** `xcodebuild test` never applies a scheme's
`StoreKitConfigurationFileReference` to hosted unit tests — proven with relative and absolute paths,
all returning 0 products. `SKTestSession` replaces it entirely; the standard `cellar` scheme stayed
**171/171 green**. All scheme-editing tasks are dropped from the plan.

**Availability seam 6c-C, gated on the measured signal.** `AppStore.canMakePayments` is useless (U20:
always `true`). The clean Developer-ID signal is **`Product.products(for:)` returning an empty array**,
so `TipAvailability` derives from catalog emptiness: no products, no tip surface. One code path, no
`#if`, no `#available`, both states fake-testable, and no permanently inert button.

**Launch wiring.** `loops.start("tips") { await tips.observeTransactions() }` — the repo's idempotent
per-id mechanism, strictly better than the skill's generic `Task.detached` because a second window
joins rather than starting a second listener. The `LoopOwner` never-restart caveat does not apply: a
`Transaction.updates` listener must never return.

**PRD amendment, in this PR.** Lines **9** (distribution), **10** ("external tip jar"), **186**
(external-links ruling) and **234** (§9 Q2) are **rewritten in place with the reason recorded**, never
deleted — the repo's shipped convention for superseded decisions (`AppSection.swift:14–27`). The
amendment must state that the ship path is unproven, so the PRD does not overclaim either.

| Area | Impact |
|---|---|
| `Packages/CellarCore/Sources/TipJar/` | **New** — `TipProduct`, `TipSeams`, `TipPurchaseOutcome`, `TipAvailability`, `TipStore`; **no dependencies** |
| `Packages/CellarCore/Tests/TipJarTests/` | **New** — fake-driven, every outcome |
| `Packages/CellarCore/Package.swift` | **Modified** — one `.library` + `.target` + `.testTarget`; rollback plan below |
| `cellar/Support/` | **New** — `StoreKitTipSource.swift` (only StoreKit import), `TipJarCard.swift`; synchronized root group ⇒ 0-line pbxproj diff |
| `cellar/Settings/SettingsView.swift` | **Modified** — tip card beside `freeCard`; `freeCard` copy **unchanged** |
| `cellar/Shell/AboutView.swift` | **Modified** — one `linksCard` row opening Settings |
| `cellar/cellarApp.swift`, `cellar/AppTestFixtures.swift` | **Modified** — `TipStore` state, seam construction, fixture swap, `"tips"` loop |
| `cellarTests/TipCompositionTests.swift`, `cellarTests/StoreKitTipSourceTests.swift`, `cellarTests/Tip.storekit` | **New** |
| `openspec/specs/tip-jar/spec.md` (via ADDED-only delta) | **New** |
| `PRD.md` :9, :10, :186, :234 | **Modified** — rewritten in place |
| `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`, `cellar.xcscheme` | **Untouched — binding** |

## Risks

| Risk | L | Mitigation |
|---|---|---|
| **The MAS ship path is unproven; the tip jar may never transact for a user** | **High** | Stated openly here and in the PRD amendment; U22 spike tracked as an M6 follow-up; the slice's success criteria are *build + local verification*, never "users can tip" |
| PRD contradiction ships in-repo (StoreKit code beside "tips are external links") | **High** | :9/:10/:186/:234 amended **in the same PR**, rewritten-in-place with the reason |
| Guideline 3.1.1 mutual exclusion violated later by adding a Ko-fi link "for Dev ID users" | Med | Named as an explicit non-goal with its reason in spec text |
| A permanently inert purchase button — the exact thing `SettingsView`'s doc comment refuses | Med | 6c-C: the card is absent, not disabled, when the catalog is empty; both states unit-tested |
| Hardcoded "$0.99" in copy or a test assertion | Med | `displayPrice`-only is requirement text; the composition sweep can assert no literal price string |
| An unfinished consumable replays forever; an Ask-to-Buy approval arrives after quit | Med | `finish()` on every path **including `.unverified`**; `Transaction.unfinished` drained at launch on the `"tips"` loop |
| `Tip.storekit` gains app-target membership and ships in the bundle | Med | U17 settled: `cellarTests/` only; a composition test can assert it is absent from the app bundle inputs |
| `SKTestSession` state persists at `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/` across runs, contaminating no-config assertions | Med | Documented gotcha (obs 7638); tests must reset session state rather than assume a cold store |
| `-only-testing` for Swift Testing needs a trailing `()` or **zero tests run yet `TEST SUCCEEDED`** | Med | Recorded; verify must assert executed-test counts, not the exit code alone |
| Real (non-local) verification is blocked behind the MAS risk | Med | Accepted; out of scope for this slice by decision 1 |
| SwiftLint is not a usable gate (U21: 246 warnings + 20 pre-existing errors, no config) | Low | Baseline is `cellarTests` **171/171 green**; lint excluded from the gate, stated rather than quietly dropped |
| No CI — green suites are local snapshots | Low | Pre-existing project risk |

## Rollback Plan

Per `rules.proposal`, the project-level surfaces are named explicitly.

- **Single `git revert` of the slice PR restores everything.** The change is purely additive at the
  spec level (ADDED-only) and introduces **no cache file, no schema version, no Keychain item and no
  migration** — a revert orphans nothing.
- **`Packages/CellarCore/Package.swift` is the only project-manifest change**: one `.library`, one
  `.target`, one `.testTarget`, all with **zero dependencies**. Reverting those three declarations plus
  deleting `Sources/TipJar/` and `Tests/TipJarTests/` fully removes the target — the `ReleaseNotes`
  precedent (`Package.swift:107–108`). No existing target's dependency list changes.
- **`cellar.xcodeproj/project.pbxproj` and `cellar.xcshareddata/xcschemes/cellar.xcscheme` are expected
  at a 0-line diff.** U18 proved **no scheme edit is needed at all**; `cellar/Support/` lands inside the
  existing `PBXFileSystemSynchronizedRootGroup`, and `Tip.storekit` goes to `cellarTests/`. If either
  file nonetheless shows a diff at apply time, it is **reverted as part of the same PR revert** and the
  deviation must be reported before merge rather than absorbed.
- **The one local `UserDefaults` thank-you flag** is a single boolean; a revert leaves a stray key that
  is inert and readable by nothing. It must be namespaced in the shipped
  `SecurityConsentPreference` / `ReleaseNotesConsentPreference` style so it is greppable if ever
  cleaned up.
- **PRD.md reverts as plain text.** Post-revert checks:
  `swift build --package-path Packages/CellarCore` and `xcodebuild build -scheme cellar`.

## Delivery Forecast

Session budget **4,000** lines (session preflight value; `config.yaml` records 5,000 — **4,000
governs this chain**), `single-pr`, strict TDD, RDD disabled. The house's measured **1.9–2.3×**
correction over bottom-up counts (established by M5 slices 3–5) applied to ~1,200 bottom-up authored
lines gives **~2,300–2,800 corrected authored lines**. That fits inside 4,000 — this should be the
**first M6 slice needing no `size:exception`**. `sdd-tasks` MUST reuse the 1.9–2.3× correction rather
than re-deriving it, and MUST emit the exact guard lines
(`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`,
`400-line budget risk: Low|Medium|High`). The probes' removal of all scheme work is already netted out
of this figure.

## Success Criteria

- [ ] A `TipJar` target exists in `CellarCore` with **zero dependencies**, proven by the build graph;
      `swift test --package-path Packages/CellarCore` covers every `TipPurchaseOutcome` case with no
      StoreKit linkage.
- [ ] `import StoreKit` appears in **exactly one** file under `cellar/`, and no view file references
      `Product`, `Transaction` or `AppStore` — asserted structurally by `TipCompositionTests`.
- [ ] `StoreKitTipSource` is exercised by a **headless `SKTestSession`** test under plain
      `xcodebuild test`: the product loads, a purchase completes, and the transaction is verified.
- [ ] Every transaction is **finished**, including `.unverified` and `.pending`-then-approved; a
      launch-time `Transaction.unfinished` drain exists and is tested.
- [ ] `.unverified` shows **no thank-you** yet still finishes; `.pending` says the tip is **not
      complete**.
- [ ] With an **empty product catalog**, no tip surface renders anywhere — no disabled button, no
      placeholder row.
- [ ] No literal price string appears in any source or test; every price comes from
      `product.displayPrice`.
- [ ] The thank-you state is a **single local boolean** — no date, no count, no identifier, no
      network call from the tip path.
- [ ] `Transaction.currentEntitlements` appears **nowhere** in the change, and there is no restore
      button.
- [ ] `Tip.storekit` is present in `cellarTests/` and **absent from the app bundle**.
- [ ] `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`,
      `cellar.xcscheme` and `project.pbxproj` all show **0-line diffs**.
- [ ] PRD.md :9, :10, :186 and :234 are rewritten in place, record **why** StoreKit replaced external
      links, and state that the MAS ship path is unproven.
- [ ] `cellarTests` remains green at **171 + new tests**, with UI tests still at zero egress and zero
      StoreKit under `AppTestFixtures`.

## Resolved Decisions (binding)

Taken by the maintainer (obs 7637). Specs derive from these and MUST NOT reopen them.

- **D1 — Build now, risk stated.** StoreKit is implemented and locally verified; the MAS ship path is
  recorded as an **open product risk**, and U22 is an M6 follow-up. **Rejected:** waiting for the
  sandbox spike before building, and implying M6 ends with a transacting tip jar.
- **D2 — Placement 6b-D**: Settings card beside `freeCard` (the only purchase call site) + an About
  row that opens Settings. **Rejected: 6b-B**, a `.support` `AppSection` — PRD :186's literal reading,
  but a whole page for one button exceeds "subtle" and costs a 22nd case across six exhaustive
  switches. `.support` stays cheaply available later.
- **D3 — Developer ID build uses 6c-C**, a runtime `TipAvailability` seam gated on the empty product
  list. **Rejected: 6c-A** (always-visible unavailable copy — an inert control), **6c-B** (a
  `MAS_BUILD` compile flag, the nearest thing to the `#available` branches `rules.design` bans), and
  **6c-D** (links in one build, StoreKit in the other — 3.1.1 forbids their coexistence).
- **D4 — One consumable, `com.juancasanueva.cellar.tip`**, one tier. App Store Connect ids are
  globally unique and permanent. **Rejected:** a tip ladder.
- **D5 — A single local boolean thank-you flag.** **Rejected:** session-only (re-asks someone who
  already gave) and any dated/counted record (the no-telemetry claim is what this feature is most
  likely to be suspected of breaking).
- **D6 — PRD amended in this PR**, rewritten in place with reasons.

## Open Questions (non-blocking)

1. **U22 — MAS feasibility spike** (M6 follow-up, not this slice): build once with
   `ENABLE_APP_SANDBOX = YES` and attempt `brew list`; and establish whether macOS App Store
   submissions enforce required-reason privacy manifests. Its answer decides whether M6 ships
   Developer ID only, MAS, or both — and therefore whether this tip jar ever transacts.
2. **Exact tip copy** — PRD :186's gratitude rule becomes spec text; the specific wording of the card,
   the button and the thank-you is settled at spec time unless the maintainer wants to author it.
3. **`cellarUITests/ReleaseNotesUITests` still has no owner** (carried from m5-health). Not this
   slice's defect; the UI-test baseline was skipped at U21 and must not be silently inherited.
