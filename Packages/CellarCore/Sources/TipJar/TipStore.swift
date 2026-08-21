//
//  TipStore.swift
//  TipJar
//

import Observation

/// Everything the tip surfaces read, and the only place a tip is decided.
///
/// `@MainActor` because every property here is read straight out of a view body,
/// and `@Observable` for the same reason every other store in this app is. The
/// three seams are `Sendable` protocols with `async` requirements, so their
/// conformers run off the main actor and only plain values — a `TipProduct`, a
/// `TipCatalogLoad`, a `TipPurchaseOutcome`, a `Bool` — ever cross back.
///
/// What it deliberately does not have: any notion of an entitlement. A finished
/// consumable never appears in `currentEntitlements`, there is nothing to
/// restore, and nothing anywhere in Cellar is gated on having tipped — so this
/// store answers "may a tip be offered" from the catalog alone, and "was one
/// ever given" from one boolean it never consults for permission.
@MainActor
@Observable
public final class TipStore {
    /// Whether this build can be tipped, and with what. Starts at `unknown`:
    /// nothing has been asked yet, which is a different fact from asking.
    public private(set) var availability: TipAvailability = .unknown

    /// Where the current attempt stands, if there is one.
    public private(set) var purchase: TipPurchaseState = .idle

    /// Whether a tip was ever completed. Read to say thank you, never to decide
    /// what a user may see or do.
    public private(set) var hasTipped = false

    @ObservationIgnored private let catalog: any TipCatalogLoading
    @ObservationIgnored private let purchases: any TipPurchasing
    @ObservationIgnored private let gratitude: any TipGratitudeRecording

    /// Guards the one observation. A second window joining the app calls
    /// `start()` again through the same idempotent loop slot, and a second
    /// listener would mean a second thank-you for one approval.
    @ObservationIgnored private var hasStarted = false

    public init(
        catalog: any TipCatalogLoading,
        purchases: any TipPurchasing,
        gratitude: any TipGratitudeRecording
    ) {
        self.catalog = catalog
        self.purchases = purchases
        self.gratitude = gratitude
    }

    /// Whether to render the tip surface at all.
    ///
    /// Absent, not disabled: an empty catalog, a failed load and a catalog still
    /// being fetched all render nothing, because a control that resolves into a
    /// permanently inert one is worse than no control.
    public var showsTipSurface: Bool { availability.product != nil }

    // MARK: - Launch

    /// Hydrate, load, drain, then observe forever.
    ///
    /// The order is the whole contract. Hydration first, so a user who already
    /// gave is never asked as if they had not. The catalog next, because the
    /// card cannot fetch its own — it does not render until the answer exists.
    /// The unfinished queue **before** observation, so a consumable left over
    /// from a previous launch is finished rather than replayed forever. Then the
    /// update stream, which never ends: an Ask-to-Buy approval can arrive at any
    /// later moment of this launch, and a listener that returned would miss it.
    ///
    /// It never returns, which is why the caller owns it through an idempotent
    /// per-id loop slot rather than a scene `.task`.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        hasTipped = await gratitude.hasTipped()
        await TipCatalogLoader(catalog: catalog).load { availability = $0 }
        await purchases.drainUnfinished()

        for await outcome in purchases.transactionOutcomes() {
            await record(outcome)
        }
    }

    // MARK: - Tipping

    /// Buys the tip, if there is one to buy.
    ///
    /// A tap while one attempt is already in flight is a no-op, because a
    /// double-click on a button must not become two payments. An unavailable
    /// catalog settles as `unavailable` **without touching the purchasing
    /// seam**: there is no product, so there is nothing to attempt.
    public func tip() async {
        guard purchase != .inFlight else { return }

        if case .refuse(let outcome) = TipPurchaseRunner.decision(for: availability) {
            purchase = .settled(outcome)
            return
        }

        purchase = .inFlight
        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: availability)
        await record(outcome)
        purchase = .settled(outcome)
    }

    /// The one write. Five of the six outcomes fall out on the first line.
    private func record(_ outcome: TipPurchaseOutcome) async {
        guard outcome.recordsGratitude else { return }
        await gratitude.recordTip()
        hasTipped = true
    }
}
