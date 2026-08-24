# Design: A read-only per-package trust surface (`m9-per-package-trust`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks`

**Inputs.** `proposal.md` (obs `#7760`), `explore.md` (obs `#7758`) and the maintainer's binding scope
decisions (obs `#7759`). Design rules **D-a … D-g** and risks **R1 … R8** are carried from the
exploration and are referenced by name below rather than restated. Anchors PRD §3.7 (:108).

> **Size note.** This document exceeds the 800-word default by explicit launch-brief instruction (new
> types, DI wiring, refresh sequencing, four view integration points, degradation and a Strict-TDD RED
> map). `openspec/config.yaml` `rules.design` additionally requires actor-isolation and
> protocol-boundary statements. `m7-tap-trust` overshot its artifact forecast 5–7× (R8); this document
> is deliberately ~⅓ of that design's length, with tables instead of prose.

## Technical Approach

Three separable pieces, ordered by how much they touch:

1. **A second read, in its own domain** — `brew trust --json v1` becomes `TrustGrantWire` /
   `TrustGrantPayloadSource` / `TrustGrantStore`, cloning the shipped `TapWire` / `TapPayloadSource` /
   `TapStore` spine byte-for-byte in shape (D-a). Compile-time-constant argv, in-flight coalescing,
   last-good retention, monotonic adoption.
2. **Attribution, as a pure projection** — `TapProjection` gains three total functions that map a
   ledger of fully-qualified grant entries onto the taps Cellar already holds. Nothing is composed from
   strings and nothing is split on `/` (D-e).
3. **Four additive view surfaces** — a count line on the tap row and the tap detail header (one value),
   a marker on tap-detail package rows and beside `PackageDetailView`'s `Tap` fact, and a dedicated
   unattributed-grants section in Taps. The `Untrusted` badge is byte-unchanged (D-d).

`rules.design` compliance is structural: every new type lives in
`Packages/CellarCore/Sources/BrewClient`, the app target gains view code and one DI line, the external
boundary stays the shipped `BrewCommand.read` → `BrewRunner` seam behind a new `TrustGrantSourcing`
protocol (no new `Process`, `FileManager` or network dependency), and there is no `#available` branch.

The engineering content is **not** the new read. It is DD-3 (why no new invalidation domain is added),
DD-5 (how a qualified entry is attributed without ever splitting it) and DD-11 (how the two shipped
mutation guards stay intact), because those are where this change could quietly become the thing PM10
forbids.

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-1** | `TrustGrantState { granted(TrustGrantLedger), noGrants, unreported }`, buildable only through a canonical `static func reported(_ ledger:)` that returns `.noGrants` for an empty ledger | `Optional<TrustGrantLedger>`; a free `granted(ledger)` case that may carry an empty ledger | **D-b**, and the m7 `TapTrustState` precedent. Three-valued is the whole Homebrew-without-`brew trust` mitigation (**R4**): a brew that cannot answer must not render as "0 grants". The canonical constructor removes the dual representation an empty `.granted` would create — two values describing "nothing" is the defect the enum exists to prevent |
| **DD-2** | Own wire, source, store: `BrewTrustGrantPayloadSource.command = BrewCommand.read(["trust", "--json", "v1"])`, a `static let` compile-time constant behind `TrustGrantSourcing` | Extending `TapPayloadSourcing` with a second method; deriving grants from `tap-info`; reading `~/.homebrew/trust.json` directly | **D-a**. `tap-info` does not carry per-package grants at all (explore). Direct file reads violate the standing apply rule *always shell out to `brew`* (`rules.apply`, and the XDG path is not stable). A constant argv is what makes DD-11's absence checkable |
| **DD-3** | **No new `InvalidationScope` member.** The grant store refreshes on the existing `.taps` domain | Adding `.packageTrust` and declaring it across `MutationCommand`, `ServiceCommand`, `CleanupCommand`, `TapCommand`, `MutationGates.domain(for:)`, `RefreshDomain` and their tests | This is the **direct answer to R2**. Per **D-f** no command Cellar can issue mutates a per-package grant: a grant is created only by naming a `/`-qualified token, which PM10 forbids everywhere; `brew trust <tap>` and `brew untap` touch tap grants only (that is exactly why orphan grants survive, **R7**). A domain no Cellar command can invalidate would be dead declaration surface on five families — a wide, shallow diff with no behaviour (R2). Reusing `.taps` also keeps TM12's MODIFY narrower: Cellar genuinely adds **no new invalidation domain**, only a second read |
| **DD-4** | `TapRefreshCoordinator` gains `grants: TrustGrantStore?` (default `nil`, the shipped `mutations:`/`refreshRegistry:` idiom) and refreshes both stores **concurrently** via `async let`. The **tap** store alone decides the returned `RefreshResult` | Sequential tap-then-grants (adds a full subprocess round trip to every refresh); a second coordinator; letting the grant store's failure produce `.failed` | **R5**. `BrewCommand.read` is explicitly designed to run concurrently with in-flight work (`BrewCommand.swift:40-41`), and the two payloads are independent, so neither read blocks the other's adoption. Keeping the receipt keyed to the tap store preserves TM9's "exactly one refresh per declared domain" and the shipped `MutationRefreshReceiptTests` unchanged: a degraded grant read must never turn a successful tap refresh into a failed one. The default-`nil` parameter keeps every shipped construction site compiling |
| **DD-5** | Attribution is **two conditions, both required**: the entry has the exact prefix `tap.name + "/"`, **and** `TapProjection.publishes(_:in:)` accepts its `bareToken`. Expressed once, in `private static func attribute(_ entry:kind:to:) -> PackageID?`, and used by every caller | `split("/")` and `last`/`dropFirst(2)`; prefix-match alone; `publishes` alone | **D-e**. A URL-shaped formula entry (`https://github.com/cloudmanic/spice-edit/spice-edit`, obs `#7721`) has four slashes and no owner/repo shape — every positional split misreads it (**R6**). Prefix-alone would attribute an entry for a package the tap does not publish; `publishes`-alone would attribute a bare `wget` to every tap publishing `wget`. Requiring both makes attribution deterministic and single-candidate by construction, because tap names are unique. Anything the rule refuses is **surfaced**, never dropped |
| **DD-6** | One projection value, `TapGrantPresentation { countLine: String?, marked: Set<PackageID> }`, from `TapProjection.grants(for:in:)`, read by the tap row, the detail header **and** the detail package rows | A `String?` sibling to `packageSummary`; extending `packageSummary(for:)`'s signature; each surface deriving its own | TM12's one-projection rule and the shipped `TapTrustPresentation` precedent — three facts that cannot disagree. Extending `packageSummary(for:)` was rejected because it changes a shipped signature and its call sites for no gain; the count is rendered as an **additional** `·` component beside it, which is what makes **D-d** ("the badge and the summary are byte-unchanged") mechanically true |
| **DD-7** | `countLine` is `nil` for `.unreported` **and** for zero attributed grants. There is no "0 trusted individually" and no negative marker anywhere | Rendering `"0 trusted individually"`; a "not individually trusted" marker | **D-c**. A package under a *trusted* tap is loadable with no per-package entry at all, so absence is not a fact about trust — and TM12 already forbids any string claiming a package is untrusted. A zero line beside an `Untrusted` badge would also read as a verdict, which TM11 prohibits outright (**R3**) |
| **DD-8** | `.unreported` and `.noGrants` are distinguished **in the Taps section**, not on the row: `.unreported` renders one sentence saying Homebrew reported nothing; `.noGrants` renders nothing at all | Distinguishing them on the tap row; collapsing them | Satisfies **R4**'s "distinguishable in the model *and* the copy" without violating DD-7 on the row. The row has nothing positive to say in either case; the section is the one place a total is stated, so it is the honest place to say "no total was reported" |
| **DD-9** | `TrustGrantLedger` decodes all four keys. `commands` is counted as **"other"** in the unattributed accounting (maintainer decision). `taps` is decoded and then **explicitly excluded** from package accounting, with the exclusion stated in code and pinned by a test | Ignoring `commands`; ignoring the `taps` key; letting `taps` feed a badge | **D-e**: nothing is dropped silently, and a documented exclusion is not a drop. `taps` must not feed any badge or count — **D-a**/TM12 keep a tap's own trust state coming from `tap-info` alone; consuming the ledger's `taps` key would create precisely the second source of truth TM12 forbids |
| **DD-10** | `PackageDetailView` takes `let trustGrants: TrustGrantStore` (a sixth store, beside `diskUsage`), not an injected closure | m7's DD-12 `@MainActor` closure idiom; passing a pre-computed `Bool` | The marker must **update when the store refreshes**, so the view needs the `@Observable` reference; a closure or a `Bool` computed by the parent would not re-render. Two construction sites (`ContentView`, `#Preview`). The closure idiom stays correct for m7's case, which was a one-shot lookup at press time |
| **DD-11** | C1's source-scanning ban list is extended with the **single prefix token `"TrustGrant"`** (covering all five new type names) plus `"grantsIndividually"`. C2 (`noPackagePositionEverCarriesAQualifiedToken`) is **byte-identical**. A **new, additive** test asserts the read spine's argv is a constant with no element containing `/` | Adding five separate ban entries; extending C2 to cover the read source; adding a per-package trust control | **D-f**, **D-g**. All five types share the `TrustGrant` prefix, so one token is stronger and shorter than five. C2 enumerates `BrewMutating` conformers; the new read is a `BrewCommand.read`, not a mutation, so widening C2 would change its meaning — the read spine gets its own absence test instead. `MutationCommand.swift` stays a **binding 0-line diff**, as in m7 |
| **DD-12** | TM12's single-source clause is MODIFIED **first**, in work unit 1, before any code | Shipping the code and amending the spec at archive | **R1**. TM12 :544-546 ("MUST NOT require a second probe, a second store, a second source of truth, or a new invalidation domain") reads as absolute. After DD-3 only two of those four are actually taken — a second probe and a second store — and the clause must be scoped to *a tap's own trust state* before the first line of code contradicts a promoted spec |

## Data Flow

    brew trust --json v1          brew tap-info --installed --json
            │ {taps, formulae,             │ trusted: Bool?
            │  casks, commands}            ▼
            ▼                        TapRecord.trust ──► TapProjection.trust(for:)
    TrustGrantDecoder                                          │  BADGE — byte-unchanged (D-d)
            │ reported(ledger) ⇒ .granted | .noGrants          │
            │ any failure      ⇒ .unreported  (R4)             │
            ▼                                                  │
    TrustGrantStore.grants: TrustGrantState                    │
            │                                                  │
            ├─► TapProjection.grants(for: tap, in: state) ──────┤  ONE value (DD-6)
            │        ├─ countLine: "2 trusted individually"  ──►├─ tap row subtitle
            │        │     (nil when unreported OR zero, DD-7) ►└─ detail header meta
            │        └─ marked: Set<PackageID> ─────────────────► detail package rows
            │
            ├─► TapProjection.grantsIndividually(id, publishedBy:, in:) ─► PackageDetailView Tap fact
            │
            └─► TapProjection.unattributedSection(in:, taps:) ──► Taps: "Other trusted packages"
                     .unreported     ⇒ one sentence, no totals   (DD-8)
                     .nothingToShow  ⇒ renders nothing
                     .unattributed   ⇒ formulae · casks · other  (commands, DD-9)

    Attribution (DD-5), for every entry, exactly once:
        entry.hasPrefix(tap.name + "/")  AND  publishes(bareToken(entry, publishedBy: tap.name), in: tap)
        ⇒ PackageID          otherwise ⇒ unattributed  (never dropped, never split on "/")

    Refresh (DD-3, DD-4):
        TapRefreshCoordinator.performRefresh
            async let tapRefresh   = store.refresh(using: installation)
            async let grantRefresh = grants?.refresh(using: installation)
            RefreshResult ← store.state ONLY   (grant failure never fails the tap receipt)
        Invalidation domain: .taps — no new InvalidationScope member exists

## Interfaces / Contracts

### 1. `TrustGrantWire.swift` (new)

```swift
/// What Homebrew reports about **per-package** trust grants.
///
/// Three-valued for exactly the reason `TapTrustState` is: a Homebrew that
/// cannot answer `brew trust --json v1` is `unreported`, which is not the same
/// fact as a Homebrew answering with an empty ledger (D-b, R4).
public enum TrustGrantState: Sendable, Equatable {
    case granted(TrustGrantLedger)
    case noGrants
    case unreported

    /// The only way to build a reported state, so `.granted` can never carry an
    /// empty ledger and the two reported cases cannot both mean "nothing".
    public static func reported(_ ledger: TrustGrantLedger) -> TrustGrantState {
        ledger.isEmpty ? .noGrants : .granted(ledger)
    }
}

/// Grant entries exactly as Homebrew published them — fully qualified, never
/// normalized here. Normalization is attribution's job (DD-5).
public struct TrustGrantLedger: Sendable, Equatable {
    public let formulae: [String]
    public let casks: [String]
    /// Decoded so nothing is dropped, and **never consumed** for trust state:
    /// a tap's own grant comes from `tap-info` alone (D-a, TM12, DD-9).
    public let taps: [String]
    /// The namespace Cellar has no other concept for. Counted as "other".
    public let commands: [String]

    /// Package emptiness, deliberately: `taps` alone is not a package grant.
    public var isEmpty: Bool { formulae.isEmpty && casks.isEmpty && commands.isEmpty }
}

public enum TrustGrantError: Error, Sendable, Equatable {
    case brewUnavailable
    case commandFailed(status: Int32, message: String)
    case blankOutput
    case malformedJSON
    case nonObjectEnvelope
    case cancelled
}

public enum TrustGrantDecoder {
    @concurrent
    public static func decode(_ data: Data) async throws(TrustGrantError) -> TrustGrantLedger
}
```

Decoding uses `decodeIfPresent([String].self) ?? []` per key, mirroring `TapWire`: an absent key is an
empty list, and a payload that is not a JSON object is `.nonObjectEnvelope`. Unknown keys are ignored
(forward compatibility), which is the one place D-e does not apply — an unknown key is not a grant
Cellar can classify, and inventing an "unknown namespace" bucket would surface noise, not a grant.

### 2. `TrustGrantPayloadSource.swift` (new)

```swift
public protocol TrustGrantSourcing: Sendable {
    func payload(using installation: BrewInstallation) async throws(TrustGrantError) -> Data
}

public struct BrewTrustGrantPayloadSource: TrustGrantSourcing {
    /// Compile-time constant. **No element contains `/`**, so naming a package
    /// — which *is* the grant on Homebrew 6 (`trust.rb#explicitly_allowed?`) —
    /// is impossible here by construction (D-f, DD-11).
    static let command = BrewCommand.read(["trust", "--json", "v1"])
    // Body clones BrewTapPayloadSource: BrewRunner.start, drain lines, exit,
    // and the same stdout/stderr split with a 12-line stderr tail.
}
```

### 3. `TrustGrantStore.swift` (new)

`@MainActor @Observable`, cloning `TapStore` member-for-member: `InFlightRefresh` coalescing keyed on
`(request, invalidationCount)`, `nextToken` / `installedSequence` monotonic adoption, `invalidate()`,
`refresh(for: BrewDetectionState)`, `refresh(using: BrewInstallation?)`, `clear(to:)`, `vacate(_:)`.
Public surface:

```swift
public private(set) var grants: TrustGrantState = .unreported
public private(set) var state: TrustGrantLoadState = .idle   // parity + tests; no view reads it
public init(source: any TrustGrantSourcing = BrewTrustGrantPayloadSource())
```

Adoption rule: on success `grants = .reported(ledger)`; on failure the **last good** `grants` is
retained and `state` becomes `.failed(error)`. A first-ever failure therefore leaves `.unreported`,
which is the correct answer, and a transient failure does not downgrade a good count to "unreported"
(the same last-good discipline the taps list already ships).

### 4. `TapProjection.swift` (modified — three additions)

```swift
public struct TapGrantPresentation: Sendable, Equatable {
    /// "2 trusted individually", or nil when nothing may be claimed (DD-7).
    public let countLine: String?
    /// Exactly the packages of this tap whose rows may show the marker.
    public let marked: Set<PackageID>
}

public static func grants(for tap: TapRecord, in state: TrustGrantState) -> TapGrantPresentation
public static func grantsIndividually(_ id: PackageID, publishedBy tap: String, in state: TrustGrantState) -> Bool
public static func unattributedSection(in state: TrustGrantState, taps: [TapRecord]) -> TrustGrantSection

public enum TrustGrantSection: Sendable, Equatable {
    case unreported
    case nothingToShow
    case unattributed(UnattributedGrants)
}

public struct UnattributedGrants: Sendable, Equatable {
    public let formulae: [String]
    public let casks: [String]
    /// The `commands` namespace, named "other" in copy (DD-9).
    public let other: [String]
    public var total: Int { formulae.count + casks.count + other.count }
}

/// The one attribution rule, used by all three (DD-5). Both conditions, always.
private static func attribute(_ entry: String, kind: PackageKind, to tap: TapRecord) -> PackageID? {
    let prefix = tap.name + "/"
    guard entry.hasPrefix(prefix) else { return nil }
    let id = PackageID(kind: kind, name: bareToken(entry, publishedBy: tap.name))
    return publishes(id, in: tap) ? id : nil
}
```

Copy (positive-only, D-c): `countLine` is `"1 trusted individually"` / `"N trusted individually"`.
Marker text is exactly `"Trusted individually"`. Section header is `"Other trusted packages"`, with the
sentence *"Homebrew grants these individually. Cellar cannot match them to an installed tap — a
per-package grant survives untapping the tap that published it."* (**R7**: this states the fact; it
does not imply the surface closes the hole). The `.unreported` sentence is *"Homebrew did not report
per-package trust grants."*

## File Changes

| File | Action | Description |
|---|---|---|
| `.../BrewClient/TrustGrantWire.swift` | **New** | `TrustGrantState`, `TrustGrantLedger`, `TrustGrantError`, `TrustGrantDecoder` |
| `.../BrewClient/TrustGrantPayloadSource.swift` | **New** | `TrustGrantSourcing`, `BrewTrustGrantPayloadSource`, payload split |
| `.../BrewClient/TrustGrantStore.swift` | **New** | `TrustGrantLoadState`, `TrustGrantStore` (TapStore clone) |
| `.../BrewClient/TapProjection.swift` | Modify | `TapGrantPresentation`, `grants(for:in:)`, `grantsIndividually`, `unattributedSection`, `UnattributedGrants`, `TrustGrantSection`, private `attribute` |
| `.../BrewClient/TapRefreshCoordinator.swift` | Modify | `grants:` parameter (default `nil`); concurrent refresh; `RefreshResult` still from the tap store (DD-4) |
| `.../BrewClient/BrewMutating.swift` | **Untouched — binding** | No new `InvalidationScope` member (DD-3) |
| `.../BrewClient/MutationCommand.swift` | **Untouched — binding** | 0-line diff, as in m7 (DD-11) |
| `.../BrewClient/TapCommand.swift` | **Untouched** | `invalidates` unchanged — DD-3 removes the reason to touch it |
| `cellar/cellarApp.swift` | Modify | `TrustGrantStore(source:)` (+ `AppTestTrustGrantPayloadSource` under UI test), passed to `TapRefreshCoordinator`, `ContentView` |
| `cellar/ContentView.swift` | Modify | Threads the store to `TapsListView`, `TapDetailView`, `PackageDetailView` |
| `cellar/Taps/TapsListView.swift` :52 | Modify | Count line as an added `·` component; new "Other trusted packages" section |
| `cellar/Taps/TapDetailView.swift` :57-65, :149-180 | Modify | Header meta component; `"Trusted individually"` marker on package rows |
| `cellar/Browse/PackageDetailView.swift` :557 | Modify | Marker beside the existing `fact("Tap", …)`; new `trustGrants` property + preview |
| `Tests/BrewClientTests/MutationCommandTests.swift` :471-479 | Modify | Ban list `+ "TrustGrant"`, `+ "grantsIndividually"`. `:500-613` **byte-identical** |
| `Tests/BrewClientTests/*` (5 files) + `cellarTests` (1 new) + `cellarUITests` | New/Modify | See *Testing Strategy* |
| `README.md` :44-47 | Modify | Qualified-token sweep (doc-only; the canonical three-line install is unchanged) |

## Concurrency, Isolation and Sendable (`rules.design`)

| Element | Isolation | Note |
|---|---|---|
| `TrustGrantState`, `TrustGrantLedger`, `TrustGrantError`, `TapGrantPresentation`, `UnattributedGrants`, `TrustGrantSection` | `nonisolated` value types, `Sendable, Equatable` | CellarCore SwiftPM `nonisolated` defaults; all members are `Sendable` |
| `TrustGrantDecoder.decode` | `@concurrent` | Mirrors `TapDecoder.decode` — JSON off the main actor |
| `BrewTrustGrantPayloadSource` | `nonisolated`, `Sendable` struct | Holds only a `ProcessLaunching`; same shape as `BrewTapPayloadSource` |
| `TrustGrantStore` | `@MainActor @Observable` | Same isolation, coalescing and adoption as `TapStore`; no detached work |
| `TapProjection.grants` / `grantsIndividually` / `unattributedSection` / `attribute` | `nonisolated`, pure, total | Functions of values a test can synthesise; no storage, no I/O |
| `TapRefreshCoordinator.performRefresh` | `@MainActor`, unchanged | `async let` over two `@MainActor` store methods; both suspend on their own subprocess, so the reads overlap without leaving the actor |
| Views | app-target `@MainActor` default | No new isolation |

**Protocol boundary.** One new seam, `TrustGrantSourcing`, whose production conformer is the only type
that touches a process. No `FileManager`, no network, no `#available`. `trust.json` is never read
directly (`rules.apply`).

## Degradation Behavior

| Condition | `grants` | Surfaces |
|---|---|---|
| brew absent / detection cleared | `.unreported` (ledger cleared) | No count line, no markers; section shows the `.unreported` sentence |
| `brew trust` verb missing → non-zero exit | `.unreported` on first read; last-good retained afterwards | Same. **Never "0 grants"** (R4) |
| Blank output, malformed JSON, non-object envelope | as above | Same |
| Cancelled refresh | previous value retained, no adoption | Unchanged surfaces |
| Answered with empty arrays | `.noGrants` | No count line, no markers; section renders **nothing** (DD-8) |
| Answered, all entries attributed | `.granted` | Count lines + markers; section renders nothing |
| Answered, some entries unattributable | `.granted` | Count lines + markers + the section, `commands` counted as "other" (R6, DD-9) |

## Testing Strategy

| Layer | What | Runner |
|---|---|---|
| Unit (core) | decode, three-valued state, attribution, projections, store coalescing/last-good, the two guards | `swift test --package-path Packages/CellarCore` |
| Unit (app) | one projection per surface; nothing spawns a trust command | `xcodebuild … -only-testing:cellarTests` |
| E2E | count line, marker and section visibility per state | `cellarUITests` |
| Manual evidence | real `brew trust --json v1` payload, and the side-effect probe (Open Questions 1–2) | maintainer's Mac, Homebrew 6 |

### Strict TDD — RED units

| # | RED test (file · name) | Asserts | RED because |
|---|---|---|---|
| 1a | `TrustGrantDecodeTests · anUnansweredBrewIsUnreportedNotZeroGrants` | failed read / blank / malformed / non-object → `.unreported`; empty arrays → `.noGrants`; the two are `!=` | the type does not exist (**R4**, D-b) |
| 1b | `TrustGrantDecodeTests · everyPublishedNamespaceIsDecodedVerbatim` | all four keys decode; an absent key is `[]`; entries are byte-identical to the payload; a URL-shaped formula survives decoding | — |
| 1c | `TrustGrantDecodeTests · anEmptyLedgerCannotBeGranted` | `.reported(.init())` == `.noGrants`; no construction path yields `.granted` with an empty ledger | the canonical constructor does not exist (DD-1) |
| 2 | `TrustGrantSourceTests · theGrantReadIsAConstantArgvWithNoQualifiedToken` | argv is exactly `["trust","--json","v1"]`, kind `.read`; **no element contains `/`**; the source file's argv literal is a `static let` | the source does not exist (**D-f**, DD-11) |
| 3a | `TapProjectionTests · attributionRequiresBothThePrefixAndThePublication` | prefix-only → unattributed; publication-only (bare `wget`) → unattributed; both → attributed; a URL-shaped entry → unattributed, **never crashed and never split** | the rule does not exist (**R6**, DD-5) |
| 3b | `TapProjectionTests · oneProjectionCarriesTheCountAndTheMarkedSet` | `grants(for:in:)` count line exact strings incl. the singular; `marked` is exactly the attributed IDs | DD-6 |
| 3c | `TapProjectionTests · nothingIsClaimedForUnreportedOrZero` | `countLine == nil` and `marked.isEmpty` for `.unreported` and `.noGrants`; **no string anywhere says "0", "not trusted" or "untrusted"** about a package | DD-7, D-c, TM11/TM12 |
| 3d | `TapProjectionTests · theSectionDistinguishesUnreportedFromNoGrants` | `.unreported` → `.unreported`; `.noGrants` → `.nothingToShow`; all-attributed → `.nothingToShow`; leftovers → `.unattributed` with `commands` in `other` and the exact total | **R4**, DD-8, DD-9 |
| 3e | `TapProjectionTests · theLedgersTapKeyNeverFeedsATrustState` | a ledger naming a tap in `taps` changes no badge, no count line and no `UnattributedGrants` member | DD-9, TM12's single source |
| 3f | `TapProjectionTests · aGrantForAnUninstalledTapIsSurfacedNotDropped` | an entry whose owner/repo matches no installed tap appears in `unattributed`, counted | **R7**, D-e |
| 4a | `TrustGrantStoreTests · concurrentRefreshesCoalesceAndAdoptMonotonically` | two overlapping refreshes spawn once; a stale token never overwrites a newer adoption; `invalidate()` defeats coalescing | the store does not exist (**R5**) |
| 4b | `TrustGrantStoreTests · aFailedRefreshKeepsTheLastGoodLedger` | success → `.granted`; a following failure keeps `.granted` and moves `state` to `.failed`; a first-ever failure leaves `.unreported` | — |
| 5a | `TapRefreshTests · aDegradedGrantReadNeverFailsTheTapReceipt` | the grant source throws; `RefreshResult == .refreshed`; the tap domain still receipts exactly once | DD-4 |
| 5b | `TapRefreshTests · bothReadsAreIssuedOnceForOneRefresh` | one coordinator refresh issues exactly one `tap-info` and one `trust` spawn, overlapping, and no `InvalidationScope` value beyond the shipped four is declared anywhere | DD-3, DD-4 |
| 6 | `MutationCommandTests · anUntrustedTapNeverPreBlocksAMutation` (**shipped, extended**) | ban list gains `"TrustGrant"` and `"grantsIndividually"`; `MutationCommand.swift` still contains none of them | **D-g** — a later change must not gate through the new store |
| 7 | `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken` (**shipped**) | **regression guard — byte-identical, must never go red** | **D-f** |
| 8a | `TapShippingProofTests · theTapBadgeAndSummaryAreUnchangedByGrants` | `TapProjection.trust(for:)` output and `packageSummary(for:)` output are identical for every `TrustGrantState` | **D-d** |
| 8b | `TapShippingProofTests · everyPerPackageStringIsPositive` | every string the new surfaces present states a grant that exists; none is a verdict, ranking or recommendation | TM11, D-c (**R3**) |
| 8c | `TapShippingProofTests · noNewControlSubmitsAnything` (existing scans re-run) | `TapManagementAction.allCases` and the pinned static labels are **unchanged**; `Button {` still absent; invoking every new surface spawns nothing | **D-f** |
| 9 | `cellarTests/PerPackageTrustCompositionTests · rowHeaderAndRowsReadOneProjection` (new file) | the tap row, the detail header and the detail package rows all call `TapProjection.grants(for:in:)`; none computes a count or a marker locally; `PackageDetailView` calls `grantsIndividually` | DD-6, DD-10 |
| 10 | `cellarUITests · theCountLineAndSectionAppearOnlyWhenReported` | count line present for `.granted`, absent for `.noGrants` and `.unreported`; the section's three renderings | the surfaces do not exist |

## Threat Matrix

Applicable: this design adds a **subprocess** and one new argv vector. Rows below are the canonical
matrix; the last is the project-relevant instantiation of *argument composition and ownership*.

| Boundary | Adversarial cases | Applicability | Design response | Planned RED test |
|---|---|---|---|---|
| Documentation-like paths | executable README/MDX, `requirements.txt` | **N/A** — this change classifies no files and executes nothing from disk; the only doc edit is prose in `README.md` | — | — |
| Git repository selection | `git -C`, relative/absolute paths | **N/A** — no VCS automation on any path in this change | — | — |
| Commit state | staged, `commit -a`, empty index | **N/A** — same | — | — |
| Push state | tracking branch, first push, refspec | **N/A** — same | — | — |
| Argument composition and ownership (`brew trust --json v1`) | a `/`-qualified token entering argv; a grant entry echoed back into a command; interpolation into the argv body; a "helpful" retry | **Applicable** | argv is a `static let` compile-time constant with three literal elements and no interpolation (DD-2). No value read from the ledger is ever used to build a command — attribution produces a `PackageID` for **display only** (DD-5). No control anywhere submits a trust command (D-f). `BrewCommand` hands argv to the process seam element-by-element and never routes through `/bin/sh -c` (shipped) | **2** (constant argv, no `/`), **7** (shipped C2, byte-identical), **8c** (no new control spawns anything), **6** (C1 ban list) |

**Failure behavior for the applicable row:** if the read fails for any reason the store lands in
`.unreported` and every surface claims nothing (Degradation table). There is no retry path, no
fallback command, and no second argv shape.

## Migration / Rollout

No migration. Nothing persists — no file format, no stored state, no schema. The store is additive and
read-only; deleting the three new files and reverting the projection returns the app to tap-only trust.
No feature flag: the degradation path (`.unreported`) is already the behaviour on a Homebrew that
cannot answer, so a partial rollout would be indistinguishable from a broken one.

## Open Questions

- [ ] **Blocks work unit 2's GREEN, not this design.** Capture a verbatim `brew trust --json v1`
      payload from the maintainer's Mac as the decode fixture. The exploration measured the *keys*
      (`taps`, `formulae`, `casks`, `commands`) but not the envelope's exact shape. PR #67's lesson is
      binding: the fixture must mirror the real object, not an invented one.
- [ ] **Probe before apply.** Confirm `brew trust --json v1` with **no package argument** is
      side-effect free: hash and stat `trust.json` before and after, twice. Naming a qualified token is
      the grant (`trust.rb#explicitly_allowed?`); a bare listing invocation should not write, but that
      is inferred, not measured. If it writes, this whole read is unshippable as designed and the
      change must stop rather than route around it.
- [ ] Does `brew trust --json v1` ever publish an **unqualified** entry? DD-5 refuses to attribute one
      (it would be ambiguous across taps) and surfaces it as unattributed. If the probe shows this is
      common rather than theoretical, the section's copy needs one more sentence — no code change.
