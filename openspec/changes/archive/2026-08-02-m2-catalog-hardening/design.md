# Design: M2 Prelude — Catalog Hardening

## Technical Approach

Six behaviour-preserving fixes inside `Packages/CellarCore`, no new product, no persisted-format
change. The unifying idea is **explicit identity for the two things M1 left implicit**: which snapshot
an index belongs to, and which work a single-flight slot actually holds. Everything else falls out of
those two.

Decisions below are numbered `D1…D6` for this change; M1's decisions are cited as `M1 D2`, `M1 D4`.

    engine.sync() ──┐                    ┌── revision guard ──▶ (drop duplicate)
                    ├── CatalogSnapshot ─┤
    events.snapshot ┘   (+ revision)     └── @concurrent build ──▶ ordinal guard ──▶ install + rerank
                                              (off-main)              (drop stale)      (MainActor)

## Architecture Decisions

### D1 — The index is built off-main by a `@concurrent` factory; adoption is ordered by an ordinal

`PackageSearchIndex` is already `Sendable` by composition (every stored property is a value type), so
the built value crosses back to `@MainActor` with no lock and no `@unchecked`. A `@concurrent` static
factory mirrors `CatalogDecoder.decode` (M1 D2) — the attribute must precede the modifier, per M1's
apply-time finding.

```swift
@concurrent
public static func build(from snapshot: CatalogSnapshot) async -> PackageSearchIndex {
    PackageSearchIndex(snapshot: snapshot)   // the existing init, unchanged
}
```

`adopt` becomes `async` and stamps a monotonic `adoptionSequence`. After the `await`, an install is
admitted only if its ordinal still exceeds `installedSequence`; a slower older build is **discarded,
not installed**. Two overlapping builds therefore always leave the newer snapshot resident.

| Option | Tradeoff |
|---|---|
| Keep the build on `@MainActor` (M1) | ~16k records normalized on the main actor; violates M1 D2, freezes typing |
| Actor-owned index | Turns every keystroke into an async hop; breaks M1 D4 and reintroduces out-of-order results |
| **`@concurrent` build + ordinal-guarded install (chosen)** | One `await` per adoption, zero change to query latency, out-of-order completion is a dropped build rather than a corrupted state |

**`rerank()` while a build is in flight**: unchanged, and deliberately unaware of the build. It runs
synchronously on `@MainActor` against the **installed** index — the last good catalog — so no
keystroke is dropped, delayed, or cancelled (M1 D4, p95 1.02 ms stands). `adopt` calls `rerank()` once
after installing, which re-answers the current query against the new index.

`isReady` is still set *after* `loadCache()`'s adoption completes, so a cold launch with a usable
cache shows results rather than flashing an empty state and repopulating. The wait is now a background
build instead of a frozen main thread.

### D2 — Snapshot identity is a process-local `revision`, pinned to the file on disk

Q4 settled: multi-ingress stays, deduplication is by snapshot identity. Identity is a value stamped
once per *materialization* of distinct catalog content, carried on the snapshot itself so it travels
through every existing signature untouched — `sync()`, `CatalogSyncEvent.snapshot`, `cachedSnapshot()`
keep their current types, and no test's pattern match changes shape.

```swift
public struct CatalogSnapshotRevision: Hashable, Sendable {   // Synchronization.Atomic counter
    static func next() -> Self
}
// on CatalogSnapshot: `public let revision: CatalogSnapshotRevision`, excluded from CodingKeys,
// assigned `.next()` in the explicit `init(from:)`. The persisted JSON is byte-identical.
```

The engine **pins** the revision of whatever is on disk (`diskRevision`), so `loadCache()` and every
later `performSync` see the same identity for the same file. Without the pin, the guard would only
catch a manual-refresh overlap while the ordinary 15-minute 304 poll re-emitted the same catalog under
a fresh identity and rebuilt a 16k index every quarter hour, forever. The pin is invalidated on a
successful persist (set to the new snapshot's revision) and on a failed persist (set to `nil`, so a
crash between `catalog.json` and its sidecar cannot leave a stale pin).

Rejected: a content triple `(generatedAt, packages.count, skippedRecordCount)`. O(1) and no model
change, but it *collides* — two different snapshots sharing a fixed `FakeTimeSource.now` and a record
count would silently drop a real update. A hardening change must not trade a stale-data bug for a
lost-update bug. Also rejected: `Equatable` on `CatalogSnapshot` (an O(16k) string comparison on the
main actor) and a separate `CatalogSnapshotDelivery` wrapper (mechanical churn across every existing
`.success(let snapshot)`).

### D3 — Single-flight recipe: the task vacates its own slot; a cancelled slot is drained, not joined

One shape, applied to `CatalogSyncEngine.sync()` and `BrewDetectionStore.refresh()`. This is the
exemplar `InstalledStore` will copy in `m2-installed-inventory`.

```swift
// 1. The slot is keyed by a token so a task can only ever vacate *its own* entry.
// 2. `defer` runs inside the task body, so the slot is empty before `task.value`
//    resumes any joiner — no caller can ever join settled work.
// 3. A cancelled slot is not joinable: a new caller drains it, then starts fresh work.
func sync() async -> Result<CatalogSnapshot, CatalogSyncError> {
    while let current = inFlight {
        guard current.isCancelled else { return await current.task.value }
        _ = await current.task.value            // let it unwind and vacate itself
    }
    let token = nextToken(); let task = Task { defer { vacate(token) }; return await performSync() }
    inFlight = (token, task, isCancelled: false)
    return await task.value
}
func cancel() { inFlight?.isCancelled = true; inFlight?.task.cancel() }
```

Creation and slot assignment are both actor-isolated with no suspension between them, so the body
cannot run before the slot is set.

**Why `cancel()` marks rather than vacates**, contrary to the proposal's first sketch: `performSync`
opens with `store.prepareStaging()`, which *purges* the staging directory, and closes with
`defer { store.purgeStaging() }`. If `cancel()` emptied the slot immediately, a fresh sync could start
while the cancelled one was still unwinding and have its in-flight download deleted by the old task's
`defer`. Marking the slot preserves the proposal's invariant — no caller is ever satisfied by
cancelled work — without opening a staging race.

`BrewDetectionStore.refresh()` takes the same shape minus the drain (it has no `cancel()` and no
staging), with `[weak self]` in the `defer` so the task keeps not retaining the store.

### D4 — Degenerate snapshots are refused on the write side and invisible on the read side

Q2/Q3 settled: threshold is **zero packages only**, and the write-side refusal is a visible
`failed(.malformedPayload)` that keeps the last good catalog. `CatalogSyncError.malformedPayload`
already exists — it is documented as *"unreadable as JSON, or held zero usable records"* — so no error
case is added and no `CatalogSyncStatus` case is added (Q1).

| Guard | Site | Effect |
|---|---|---|
| Write, semantic | `CatalogSyncEngine.performSync`, before `store.persist` | Throws `.malformedPayload` → `publish(.failed(...))`, `succeed()` is never reached, so no snapshot event, no adoption, and **neither** `catalog.json` nor its sidecar is written — the old validators survive and the last good catalog stays resident |
| Write, structural | `CatalogFileStore.persist`, **before** its `do` block | No code path in this package can write an empty `catalog.json`. Must sit outside the `do`, which rewrites every throw to `.persistence` |
| Read | `CatalogFileStore.loadSnapshot`, after decode | A zero-package snapshot returns `nil` — the same answer as missing, corrupt, or newer-schema (M1's CS6 contract) |

The read guard alone discharges #7 and Q1: `cachedSnapshot()` yields nothing, so the cold launch is
the ordinary silent empty state; `hasUsableCache` is false; and `performSync`'s
`revalidatable: previousSnapshot != nil` becomes `false`, which is the *existing* CS6 path forcing an
unconditional re-download. The poisoned 304 loop cannot form because no conditional request is ever
sent. The poisoned file is left in place rather than deleted — a read path should not mutate the
store, and the next successful sync overwrites it.

**Dead-code fallback (`CatalogSyncEngine.swift:145`)**: the unchanged branch is restructured from
`guard acquired.changed || previousSnapshot == nil` plus a `previousSnapshot ?? CatalogSnapshot(…,
packages: [])` fallback into `if !acquired.changed, let previousSnapshot { … }`. The unreachable
empty-snapshot construction disappears instead of being commented as unreachable.

### D5 — `CellarTestSupport` is a non-product target under `Tests/`, depending on nothing

```swift
.target(name: "CellarTestSupport", path: "Tests/CellarTestSupport",
        swiftSettings: [.swiftLanguageMode(.v6)]),   // no `dependencies:` — see CS1
```

SwiftPM has no test-only target kind, so the CS1 guarantee is enforced structurally instead: the
target declares **no** dependencies (only the stdlib and the `Synchronization` system module) and is
absent from `products:`, so it cannot introduce a `Catalog` → `BrewProcess` edge and cannot leak into
either shipped library. Both test targets add it to `dependencies`. Moved types (`TestClock`,
`TestPoll`, `FakeTimeSource`) become `public`; the `extension FakeTimeSource: CatalogTimeSource` stays
behind in `CatalogTests` as a retroactive conformance, because that is the only Catalog-shaped thing
about it.

**Cancellation fix.** Today `sleep(until:)` parks on a bare `CheckedContinuation`, so a cancelled
`runRefreshLoop` never returns, `CatalogStore.start()`'s task group never finishes, and the
`defer { loop.cancel() }` in `SchedulerTests` stops nothing. The replacement allocates the sleeper id
*before* suspending, wraps the continuation in `withTaskCancellationHandler`, and resolves the
handler-arrives-first race with a `cancelledIDs` set consulted under the same lock that parks the
sleeper:

```swift
try Task.checkCancellation()                     // already cancelled ⇒ throw, never park
let id = state.withLock { $0.allocateID() }
try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { c in
        switch state.withLock({ $0.park(id, deadline, c) }) {   // .due | .alreadyCancelled | .parked
        case .due: c.resume()
        case .alreadyCancelled: c.resume(throwing: CancellationError())
        case .parked: break
        }
    }
} onCancel: {
    state.withLock { $0.unpark(id) }?.continuation.resume(throwing: CancellationError())
}
```

Continuations are always resumed *outside* `withLock`, matching the existing `advance(by:)`.

### D6 — Test migration policy

An M1 assertion changes only when it encodes one of the six defects. Each such change lands in the
**same commit as its fix**, with the defect number in the commit body. No M1 assertion is deleted: one
that becomes meaningless is replaced by the assertion expressing the corrected semantics. A test that
merely used `packages: []` as a convenience fixture moves to a one-record fixture — that is a fixture
change, not a semantic one, and needs no rationale. Verified as *not* changing: `SchedulerTests
.manualRefreshIsSingleFlight` (a genuine in-flight join still joins) and `SyncEngineTests`' cancel
path (`sync()` → `cancel()` → `.cancelled`).

## File Changes

| File | Action | Description |
|---|---|---|
| `Sources/Catalog/CatalogModels.swift` | Modify | `CatalogSnapshotRevision`; `revision` on `CatalogSnapshot`, excluded from `CodingKeys`, explicit `init(from:)` |
| `Sources/Catalog/PackageSearchIndex.swift` | Modify | `@concurrent static func build(from:)` |
| `Sources/Catalog/CatalogStore.swift` | Modify | `async` adopt, revision guard, adoption ordinal, stale-build discard |
| `Sources/Catalog/CatalogSyncEngine.swift` | Modify | Token slot + drain (D3), disk-revision pin (D2), zero-package refusal, dead fallback removed |
| `Sources/Catalog/CatalogFileStore.swift` | Modify | Zero-package guard on `loadSnapshot` and on `persist` |
| `Sources/BrewProcess/BrewDetectionStore.swift` | Modify | Token slot (D3) |
| `Tests/CellarTestSupport/{TestClock,TestPoll,FakeTimeSource}.swift` | Create | Shared, cancellation-aware, `public` |
| `Tests/{CatalogTests,BrewProcessTests}/Fakes/TestClock.swift` | Delete | Replaced; `CatalogTimeSource` conformance re-homed in `CatalogTests` |
| `Packages/CellarCore/Package.swift` | Modify | `CellarTestSupport` target + both test-target dependencies |

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit — store | Main actor services at least one turn during a 16k-record adoption | Count `Task.yield()` turns completed on `@MainActor` across `adopt`; a synchronous build makes >0 impossible, so this is a regression test, not a timing test |
| Unit — store | Two overlapping adoptions: the newer snapshot is resident, the older build is discarded | Two `adopt` calls with distinct revisions; assert `packageCount`/`results` match the newer |
| Unit — store | One snapshot delivered through both ingresses builds one index | Instrumented build count; `refreshNow()` while `start()` is running |
| Unit — store | Queries answered from the last good index throughout an adoption | Assign `query` mid-adoption; assert non-empty results and no dropped keystroke |
| Unit — engine | A caller arriving after the previous sync settled starts new work | Sequential `sync()`; assert the source saw a second request |
| Unit — engine | A caller arriving after `cancel()` starts fresh work, not `.cancelled` | `sync()` → `cancel()` → `sync()`; assert a fresh result and a purge-free staging dir |
| Unit — engine | A zero-package payload fails as `.malformedPayload`, last good catalog intact, sidecar untouched | `FakeCatalogSource` scripted empty payload + `FakeCatalogFileSystem` write recorder |
| Unit — file store | Zero-package `catalog.json` reads as no cache; a zero-package persist throws | Real temp directory |
| Unit — engine | A poisoned snapshot on disk forces an **unconditional** fetch (no `If-None-Match`) | Assert the recorded request carried no validators |
| Unit — detection | A second `refresh()` after the first settled re-probes | `FakeBrewLocator.callCount == 2` (already asserted; must stay green) |
| Unit — test support | A cancelled `clock.sleep` throws `CancellationError` promptly, before and after parking | Cancel a task both before and after `waitForSleepers()` |
| Regression | Full suite green, both targets | `swift test`; `swift test -c release --filter SearchLatency` for M1 D4 |

Every fix is RED-first: one failing test per defect before its production change.

## Threat Matrix

N/A — no routing, shell command, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary is added or changed. `Catalog` still declares no dependency on
`BrewProcess`, and `CellarTestSupport` declares none at all (CS1). The change touches no network
policy, no payload cap, and no file location outside the existing app-owned catalog directory.

## Migration / Rollout

No migration. `CatalogSnapshot`'s persisted JSON is byte-identical (`revision` is outside
`CodingKeys`), so `schemaVersion` stays at 1 and no cache is invalidated by upgrading. A machine
holding a poisoned zero-package `catalog.json` re-downloads once on first launch under D4 and then
behaves normally. Rollback is `git revert` of the single merge commit; both duplicate `TestClock`
files return with it.

## Review Budget Forecast

**~800–950 authored lines (additions + deletions)** against the accepted 1,500-line `single-pr`
budget — above the proposal's 450–700 estimate. The gap is D5: moving two ~100-line `TestClock`
copies into one shared file counts roughly 380 add+delete lines while changing almost no behaviour.
Production changes are ~230 lines; new regression tests ~200. If a slice is wanted anyway, D5 is the
clean cut point (it is a pure test-infrastructure move with no production dependency), leaving
D1–D4 + D6 at ~550.

## Open Questions

- [ ] **Path-keyed single flight for `BrewDetectionStore`.** `configuredPath`'s `didSet` fires a
      refresh that can join an evaluation started under the *previous* path and adopt its answer.
      D3 does not fix this (that evaluation is genuinely in flight, just for a different question).
      The fix is to key the slot by the request — three lines — but it is a semantic change beyond the
      settled scope, so it is deferred to `m2-installed-inventory`, where the same recipe is copied.
- [ ] **Adoption on an unchanged (304) sync.** D2's disk pin removes the recurring rebuild for the
      poll path. If a future change makes the engine re-emit under a fresh identity, the 15-minute
      rebuild returns; the invariant to preserve is *identity is pinned to the bytes on disk, not to
      the load that produced them*.
