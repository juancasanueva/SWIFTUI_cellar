# Tasks: StoreKit 2 Consumable Tip Jar (`m6-tip-jar`)

Session config: `execution_mode=auto`, `artifact_store=hybrid`, `delivery_strategy=single-pr`,
`review_budget_lines=4000` (session value governs over `config.yaml`'s 5000), `strict_tdd=true`.
Threat matrix: **N/A** (design) — no routing, subprocess, VCS or executable-file surface.
Copy: no final wording authored — use spec-rule-compliant placeholders and flag for maintainer
review at PR time. Not-touched binding: `AppSection.swift`, `ContentView.swift`,
`AppSectionPlacementTests.swift`, all schemes, `project.pbxproj`, no `PrivacyInfo.xcprivacy`.

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 2,300–2,800 (≈1,200 bottom-up × the house 1.9–2.3× correction) |
| Governing budget | 4,000 (session) — 400 default superseded |
| Risk vs governing budget | Low — fits with ~1,200 lines of headroom |
| Chained PRs recommended | No — one PR, four internal work units |
| Delivery strategy | single-pr |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 default; that default does **not**
govern this chain. Against the 4,000 session budget the risk is Low, so no `size:exception` is
required and no decision blocks apply.

### Suggested Work Units

| Unit | Goal | PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | `TipJar` core (Phases 1–3) | PR 1 | `swift test --package-path Packages/CellarCore --filter TipJarTests` | N/A — pure values, no runtime | Delete `Sources/TipJar/`, `Tests/TipJarTests/`, 3 manifest lines |
| 2 | Conformers (Phase 4) | PR 1 | `xcodebuild test … -only-testing:'cellarTests/StoreKitTipSourceTests'` | `SKTestSession(configurationFileNamed: "Tip")`, headless (U19) | Delete `cellar/Support/{StoreKitTipSource,TipThankYouPreference}.swift`, `cellarTests/Tip.storekit` |
| 3 | Structural sweep (Phase 5) | PR 1 | `xcodebuild test … -only-testing:'cellarTests/TipCompositionTests'` | N/A — file-text assertions | Delete `cellarTests/TipCompositionTests.swift` |
| 4 | Wiring, surfaces, PRD (Phases 6–7) | PR 1 | `xcodebuild test … -only-testing:cellarTests` | `xcodebuild build -scheme cellar` + launch, check Settings and About | Revert the 5 modified app files + `PRD.md` |

## Phase 1: Target scaffold

- [x] 1.1 `Packages/CellarCore/Package.swift`: add `.library("TipJar")`, `.target("TipJar", dependencies: [], swiftSettings: [.swiftLanguageMode(.v6)])`, `.testTarget("TipJarTests", dependencies: ["TipJar", "CellarTestSupport"])`.
- [x] 1.2 Create empty `Sources/TipJar/` and `Tests/TipJarTests/`; confirm `swift test --package-path Packages/CellarCore` still builds (proves the zero-dependency graph).

## Phase 2: Values and seams (spec reqs 1–2)

- [x] 2.1 `Tests/TipJarTests/TipFakes.swift`: `Mutex`-backed `Sendable` fake catalog / purchasing / gratitude recorders (support code, no assertions).
- [x] 2.2 **RED** `TipAvailabilityTests` — req 1 scenarios: one product loads, empty list settles as unavailable, loading is observable and settles once, a throw is `failed` distinguishable from empty.
- [x] 2.3 **GREEN** `Sources/TipJar/{TipProduct,TipAvailability,TipSeams}.swift`: `TipProductIDs` (single id constant), `TipProduct(id/displayName/description/displayPrice)`, `TipCatalogLoad`, `TipUnavailableReason`, `TipAvailability`, the three `Sendable` protocols. No StoreKit, no Foundation networking.
- [x] 2.4 **RED** `TipPurchaseTests` — req 2's six scenarios: completed, cancelled (silent), pending, unverified (not `failed`), failed with typed reason, unavailable with the recorder seeing no attempt.
- [x] 2.5 **GREEN** `Sources/TipJar/TipPurchaseOutcome.swift`: `TipPurchaseOutcome`, `TipPurchaseState`, and the outcome mapping the tests demand.

## Phase 3: `TipStore` state machine (spec reqs 3–6)

- [x] 3.1 **RED** `TipGratitudeTests` — req 6: thank-you recorded only on `completed`; each of cancelled/pending/unverified/failed/unavailable leaves the flag unset; `start()` hydrates the flag; no network or process seam is touched.
- [x] 3.2 **GREEN** `Sources/TipJar/TipStore.swift`: `@MainActor @Observable`, availability derived from catalog emptiness, `showsTipSurface` true only for `.available`, `tip()` no-op while `.inFlight`.
- [x] 3.3 **RED** `TipTransactionTests` — req 3: drain-before-observe ordering, both drained transactions finished with the thank-you for the verified one only, a later approval on the stream records the thank-you, `start()` twice yields one observation that is never cancelled.
- [x] 3.4 **GREEN** `TipStore.start()`: hydrate → load catalog → `drainUnfinished()` → consume `transactionOutcomes()` forever (D-F).
- [x] 3.5 **RED** req 4: a recorded thank-you neither refuses a second `completed` purchase nor removes the surface, and the price still comes from the loaded product.
- [x] 3.6 **GREEN** make the repeat path pass; assert nothing consults entitlements.

## Phase 4: App-side conformers (spec reqs 6, 9)

- [x] 4.1 **RED** `cellarTests/TipThankYouPreferenceTests.swift` (new file beyond design's list, same folder, no pbxproj impact): per-test `UserDefaults` suite; `recordTip()` then a fresh instance reads `true`; exactly one namespaced key `tip.jar.hasTipped` is written.
- [x] 4.2 **GREEN** `cellar/Support/TipThankYouPreference.swift` in the `SecurityConsentPreference` shape (`@MainActor @Observable final class`, per-launch suite name under UI-test fixtures).
- [x] 4.3 Add `cellarTests/Tip.storekit`: one consumable for `com.juancasanueva.cellar.tip` (U17 — test-bundle resource only, never `cellar/`).
- [x] 4.4 **Test-first, RED not admissible proof** (design's declaration — StoreKit agent state persists at `~/Library/Caches/com.apple.storekitagent/Octane/`): `cellarTests/StoreKitTipSourceTests.swift`, `@Suite(.serialized)`, `SKTestSession(configurationFileNamed: "Tip")` with `resetToDefaultState()` + `disableDialogs = true` + `clearTransactions()` per test. Every assertion is state-independent — only effects of an action the test performed itself. Cover: product resolves with a non-empty `displayPrice`; purchase → `completed`; nothing unfinished for the tip id afterwards; `drainUnfinished()` clears a leftover it seeded. Never assert "zero products without a configuration".
- [x] 4.5 **GREEN** `cellar/Support/StoreKitTipSource.swift` — the app's only `import StoreKit`. Maps all four `Product` fields (`id`, `displayName`, `description`, `displayPrice`) with none composed locally; finishes every transaction including `unverified`; re-resolves the `Product` by id per purchase (D-G); filters `Transaction.updates` and `.unfinished` by `TipProductIDs.all` (D-H); `@unknown default` → `failed`; no `currentEntitlements`, `AppStore.sync`, `appAccountToken`, `quantity`.

## Phase 5: Structural sweep (spec reqs 7–9)

- [x] 5.1 **RED** `cellarTests/TipCompositionTests.swift` reusing the comment-stripping `Source`/`load()` idiom in `cellarTests/SecurityCompositionSupport.swift`: `import StoreKit` appears in exactly one file under `cellar/` and it is `Support/StoreKitTipSource.swift`; no other file references `Product`, `Transaction`, `AppStore`, `canMakePayments`, `currentEntitlements` or `appAccountToken`; no `#if`/`#available` decides availability.
- [x] 5.2 **RED** same file: no currency literal in any **`.swift`** under `cellar/` or `cellarTests/` — scope the sweep to `.swift` so `Tip.storekit`'s tier value cannot trip it; no external payment or donation URL; `Tip.storekit` present in `cellarTests/`, absent from `cellar/` and from the app target's bundled resources; the `TipJar` target's manifest dependency list is empty and `Sources/TipJar/` contains no `import StoreKit`.
- [x] 5.3 **GREEN** fix any violation the sweep reports (expected: none if 4.5 held).

## Phase 6: Wiring and surfaces (spec req 8)

- [ ] 6.1 `cellar/cellarApp.swift`: `@State private var tips: TipStore`, seams constructed in `init()`, `.environment(tips)` on the main scene **and** on `Window(id: "about")`, `.task { loops.start("tips") { await tips.start() } }`.
- [ ] 6.2 `cellar/AppTestFixtures.swift`: `AppTestTipSource` conforming to all three seams — no StoreKit, no egress, fixed `description`, sentinel non-currency `displayPrice`.
- [ ] 6.3 **RED** in `TipCompositionTests`: exactly one file invokes the purchasing seam, and `AboutView.swift` invokes neither it nor any navigation.
- [ ] 6.4 **GREEN** `cellar/Support/TipJarCard.swift` + `cellar/Settings/SettingsView.swift`: `@Environment(TipStore.self)`, card above `freeCard`, identifiers `tip-jar-card` / `tip-jar-purchase`, rendered only when `showsTipSurface`, price is `product.displayPrice` verbatim. `freeCard` copy stays byte-identical. Placeholder gratitude copy — no nag, no countdown, no feature claim; flag the wording for maintainer review in the PR body.
- [ ] 6.5 **GREEN** `cellar/Shell/AboutView.swift`: one **static** `linksCard` row naming Settings as where tipping lives (D-E) — no `Link`, no button, no action — gated on the same `tips.showsTipSurface` value Settings consumes, so both surfaces read one availability answer.

## Phase 7: Documentation and verification

- [ ] 7.1 `PRD.md` :9, :10, :186, :234 — rewrite in place with the reason recorded (StoreKit supersedes external links), and state that the MAS ship path is unproven (U22 is an M6 follow-up).
- [ ] 7.2 Confirm 0-line diffs on `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`, `cellar.xcscheme`, `project.pbxproj`; report any deviation before merge rather than absorbing it.
- [ ] 7.3 Full verification: `swift test --package-path Packages/CellarCore` **and** `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`. Assert **executed test counts** (baseline 171 + the new tests), never `TEST SUCCEEDED` alone; any `-only-testing` function identifier needs its trailing `()` or zero tests run and the build still reports success.
