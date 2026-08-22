# Design: StoreKit 2 Consumable Tip Jar (`m6-tip-jar`)

## Technical Approach

Approach **6a-B** from `explore.md` §6a: a dependency-free `TipJar` target in `CellarCore` owns every
rule (catalog → availability → purchase → outcome → gratitude) behind `Sendable` protocol seams; the
app target holds one conformer, two view surfaces and the DI wiring. StoreKit's `Product` and
`Transaction` never leave `cellar/Support/StoreKitTipSource.swift`. No `#available`, no `#if`, no
scheme edit, no pbxproj edit (`cellar/Support/` lands in the existing synchronized root group).

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| D-A | `TipJar` target with **zero dependencies**; seams declared there, conformed in the app | `TipJar` imports StoreKit (6a-C) | "The tip jar cannot reach brew, the catalog, the network client or SwiftData" becomes a build-graph fact; `swift test` links no StoreKit. Exact `BrewfileSourceChoosing` idiom |
| D-B | Availability is a typed state machine driven by product-list emptiness | `AppStore.canMakePayments` (U20: always `true`); `MAS_BUILD` flag | One code path, both states fake-testable, no inert control |
| D-C | Thank-you flag = **`UserDefaults`, one boolean**, behind a third seam `TipGratitudeRecording` conformed in the app | `MetadataStore` (SwiftData/`Persistence`) | `Persistence` is the graph's outermost node (`BrewClient` + `SecurityKit`); depending on it would destroy D-A. Its shape is per-`PackageID` metadata, wrong for a global flag. `SecurityConsentPreference` is the shipped precedent: preference → defaults, greppable key, revert leaves an inert key. CellarCore holds **no** `UserDefaults` and must keep holding none |
| D-D | `TipStore` reaches `SettingsView`/`AboutView` through **`.environment(tips)`**, not initializer arguments | Thread through `SettingsView(brewDetection:…)` | `SettingsView` is constructed in `ContentView.swift`, which is a **0-line-diff binding**. Environment injection is the only diff-free route |
| D-E | The About row is a **static informational row** ("Support → Settings"), hidden unless `.available` | A button that selects `AppSection.settings` | `section` is `@State` **inside** `ContentView`; navigating to it requires a `ContentView.swift` diff, which outranks D2's literal wording. Text is a discovery point, not an inert control, and keeps one purchase call site. **Acknowledged by the maintainer** (obs 7642) |
| D-F | One `LoopOwner` slot `"tips"` runs `TipStore.start()`: hydrate flag → load catalog → drain unfinished → observe forever | Separate `.task` for the catalog load | The card cannot load its own catalog (it does not render until `.available`). `start()` never returns, so the never-restart caveat does not apply |
| D-G | `purchase()` re-resolves the StoreKit `Product` by id | Cache `Product` in the conformer | Keeps `TipProduct` a plain value; one extra fetch per tip is free next to a payment sheet |
| D-H | The conformer filters `Transaction.updates` / `.unfinished` by `TipProductIDs.all` | Finish everything observed | The tip path must never finish a transaction it does not own |

## Interfaces / Contracts

`Packages/CellarCore/Sources/TipJar/` — all types `public`, all values `Sendable`.

```swift
public enum TipProductIDs { public static let tip = "com.juancasanueva.cellar.tip"
                            public static let all = [tip] }

public struct TipProduct: Sendable, Equatable, Identifiable {
    public let id: String; public let displayName: String
    public let description: String            // spec `tip-jar` :46–47 — the product description
    public let displayPrice: String
}

public enum TipCatalogLoad: Sendable, Equatable { case loaded([TipProduct]), failed(reason: String) }
public enum TipUnavailableReason: Sendable, Equatable { case emptyCatalog, loadFailed(String) }
public enum TipAvailability: Sendable, Equatable {
    case unknown, loading, available(TipProduct), unavailable(TipUnavailableReason)
}
public enum TipPurchaseOutcome: Sendable, Equatable {
    case completed, cancelled, pending, unverified, failed(reason: String), unavailable(reason: String)
}
public enum TipPurchaseState: Sendable, Equatable { case idle, inFlight, settled(TipPurchaseOutcome) }

public protocol TipCatalogLoading: Sendable { func loadTips() async -> TipCatalogLoad }

public protocol TipPurchasing: Sendable {
    func purchase(_ product: TipProduct) async -> TipPurchaseOutcome   // finishes every transaction
    func drainUnfinished() async                                       // launch-time replay drain
    func transactionOutcomes() -> AsyncStream<TipPurchaseOutcome>      // nonisolated; never finishes
}

public protocol TipGratitudeRecording: Sendable {
    func hasTipped() async -> Bool
    func recordTip() async
}

@MainActor @Observable public final class TipStore {
    public private(set) var availability: TipAvailability
    public private(set) var purchase: TipPurchaseState
    public private(set) var hasTipped: Bool
    public var showsTipSurface: Bool          // true only for .available
    public init(catalog: any TipCatalogLoading, purchases: any TipPurchasing,
                gratitude: any TipGratitudeRecording)
    public func start() async                  // never returns (D-F)
    public func tip() async                    // no-op while .inFlight
}
```

**Isolation and `Sendable` (required by `rules.design`).** `TipStore` is `@MainActor @Observable`; every
property mutation happens on the main actor and views read it directly. The three seams are `Sendable`
protocols with `async` requirements; the conformers are `nonisolated` immutable `struct`s (the
`BrewfilePanels` shape), so under SwiftPM/Swift 6 defaults their `async` bodies run off the main actor
and only `Sendable` values (`TipProduct`, `TipCatalogLoad`, `TipPurchaseOutcome`, `Bool`) cross back.
`AsyncStream<TipPurchaseOutcome>` is `Sendable` because its element is. `TipThankYouPreference` follows
`SecurityConsentPreference`: `@MainActor @Observable final class` satisfying a `Sendable` protocol via
`async` requirements. Nothing in `TipJar` imports StoreKit, AppKit, SwiftUI, `UserDefaults` or Foundation
networking.

**Outcome rules (spec-bearing).** `.completed` → `recordTip()`, `hasTipped = true`, thank-you.
`.unverified` → **finished, no thank-you**. `.pending` → says the tip is **not** complete, no flag.
`.cancelled` → silently back to `.idle`. `.failed`/`.unavailable` → honest reason, no flag. Repeat
purchase is legal (consumable). `Transaction.currentEntitlements` appears nowhere; no restore button;
no `.appAccountToken`; no `.quantity`.

## Data Flow

    SettingsView ──@Environment──► TipStore ──TipCatalogLoading──► StoreKitTipSource ──► Product.products
      TipJarCard  ◄──availability──┤        ──TipPurchasing─────►                 ──► product.purchase()
                                   │        ◄─AsyncStream(updates/unfinished, finished always)
    AboutView   ──@Environment─────┘        ──TipGratitudeRecording──► TipThankYouPreference ► UserDefaults
    cellarApp: loops.start("tips") { await tips.start() }

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Sources/TipJar/{TipProduct,TipSeams,TipPurchaseOutcome,TipAvailability,TipStore}.swift` | Create | The whole rule set; no dependencies |
| `Packages/CellarCore/Tests/TipJarTests/{TipFakes,TipAvailabilityTests,TipPurchaseTests,TipGratitudeTests,TipTransactionTests}.swift` | Create | Fake-driven, every state |
| `Packages/CellarCore/Package.swift` | Modify | `.library(TipJar)` + `.target(TipJar, swiftSettings: [.swiftLanguageMode(.v6)])` (no deps) + `.testTarget(TipJarTests, deps: [TipJar, CellarTestSupport])` |
| `cellar/Support/StoreKitTipSource.swift` | Create | **The only `import StoreKit` in the app**. Maps `Product → TipProduct(id: product.id, displayName: product.displayName, description: product.description, displayPrice: product.displayPrice)` — all four fields read from StoreKit, none composed here |
| `cellar/Support/TipThankYouPreference.swift` | Create | One key, `tip.jar.hasTipped`; UI-test launches get a per-launch suite name |
| `cellar/Support/TipJarCard.swift` | Create | `tip-jar-card` / `tip-jar-purchase`; `.themeCard(fill: Color.white.opacity(0.02))`, `Theme.mono` only for non-price mono text; price is `product.displayPrice` verbatim |
| `cellar/Settings/SettingsView.swift` | Modify | `@Environment(TipStore.self)`; card **above** `freeCard`; `freeCard` copy untouched |
| `cellar/Shell/AboutView.swift` | Modify | One `linksCard` row (D-E), rendered only when `showsTipSurface` |
| `cellar/cellarApp.swift` | Modify | `@State private var tips: TipStore`; seams built in `init()`; `.environment(tips)` on the main **and** About scenes; `.task { loops.start("tips") { await tips.start() } }` |
| `cellar/AppTestFixtures.swift` | Modify | `AppTestTipSource` conforming to all three seams — no StoreKit, no network, a fixed `description` value, sentinel `displayPrice` (never a currency literal) |
| `cellarTests/{TipCompositionTests,StoreKitTipSourceTests}.swift`, `cellarTests/Tip.storekit` | Create | Structural sweep + SKTestSession suite; `.storekit` is a **test-bundle** resource (U17) |
| `PRD.md` :9, :10, :186, :234 | Modify | Rewritten in place, reason recorded, ship path stated unproven |
| `AppSection.swift`, `ContentView.swift`, `AppSectionPlacementTests.swift`, `cellar.xcscheme`, `project.pbxproj` | **Untouched** | 0-line diffs — binding |

## Testing Strategy

| Layer | What | Approach | Strict TDD |
|---|---|---|---|
| Unit (`swift test`) | Every `TipAvailability` and `TipPurchaseOutcome` case; gratitude only on `.completed`; re-entrancy guard; repeat purchase; drain-then-observe ordering; flag hydration | `TipJarTests` + `Mutex`-backed `Sendable` fakes (`CellarTestSupport` idiom) | **RED-first, mandatory** |
| Structural (`cellarTests`) | `import StoreKit` in exactly **one** file under `cellar/` and it is `Support/StoreKitTipSource.swift`; no `Product`/`Transaction`/`AppStore`/`currentEntitlements`/`appAccountToken` outside it; no currency literal (`$` + decimal) in any `.swift` under `cellar/` or `cellarTests/`; `Tip.storekit` present in `cellarTests/`, absent from `cellar/` | `TipCompositionTests` reusing `AppSecuritySources.load()` (comment-stripped, `#filePath`-anchored) | **RED-first, mandatory** |
| Behavioral, environment-dependent (`cellarTests`) | Product resolves with a non-empty `displayPrice`; purchase → `.completed`; nothing unfinished for the tip id afterwards; Ask-to-Buy → `.pending`, approval arrives on the stream as `.completed`; `drainUnfinished()` clears a leftover | `@Suite(.serialized)` `SKTestSession(configurationFileNamed: "Tip")`, `resetToDefaultState()` + `disableDialogs = true` + `clearTransactions()` per test | Written test-first, but its RED **is not admissible proof** — see below |
| E2E | None added | The `AppTestFixtures` fake exists to keep existing UI-test launches at zero StoreKit and zero egress, not to add UI tests | N/A |

**Strict-TDD declaration.** RED-before-GREEN is binding for **all `TipJarTests` and all
`TipCompositionTests`**. The `SKTestSession` suite is behavioral but **environment-dependent**: the
StoreKit agent persists per-app state at `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/`
across runs (U16/U19), so a RED there can be caused by leftover state rather than by missing code.
Consequence, binding on `sdd-tasks`: **no assertion in that suite may depend on a cold store** — every
test asserts only on the effect of an action it performed itself after `resetToDefaultState()`, and no
test asserts "zero products without a configuration". Verification must count executed tests, never
trust `TEST SUCCEEDED` alone (`-only-testing` needs the trailing `()`).

## Threat Matrix

N/A — no routing, shell command, subprocess, VCS/PR automation, executable-file classification or
process integration. `TipJar` has zero dependencies, so it cannot reach `BrewProcess`; the only external
boundary is StoreKit, and it is behind three protocol seams with a structural test proving containment.

## Migration / Rollout

No migration, no cache file, no schema version, no Keychain item. `Package.swift` rollback: delete the
three added declarations plus `Sources/TipJar/` and `Tests/TipJarTests/` — no existing target's
dependency list changes (the `ReleaseNotes` precedent, `Package.swift:107–108`). A single `git revert`
of the PR leaves only the inert `tip.jar.hasTipped` defaults key. If `project.pbxproj` or
`cellar.xcscheme` shows any diff at apply time, report it before merge rather than absorbing it.

## Open Questions

- [x] **D-E — resolved: acknowledged by maintainer, static row** (Engram obs 7642). The About row is a
      static informational row with no navigation, because `ContentView.swift` must stay at a 0-line
      diff. No longer pending.
- [ ] Exact card / button / thank-you / pending copy (spec-time, unless the maintainer authors it).
- [ ] U22 (MAS feasibility) remains an M6 follow-up; this slice's success is build + local verification.
