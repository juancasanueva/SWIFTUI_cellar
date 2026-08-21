//
//  TipSeams.swift
//  TipJar
//

/// Where the tip catalog comes from.
///
/// It cannot throw. Every failure this seam can suffer is a state the surface has
/// to render anyway, so it is carried in the return value as
/// `TipCatalogLoad.failed` rather than as an error the caller may forget to
/// catch — and "an optional treated as failure" is exactly the shape the spec
/// forbids.
public protocol TipCatalogLoading: Sendable {
    func loadTips() async -> TipCatalogLoad
}

/// Buying the tip, and finishing every transaction that results.
///
/// `finish()` is the entire lifecycle of a consumable, so it is this seam's
/// promise on every path: the completed one, the unverified one, the approval
/// that arrives at a later launch, and anything found in the unfinished queue.
/// Skipping it on the unverified path is not caution — an unfinished consumable
/// replays forever.
public protocol TipPurchasing: Sendable {
    /// Buys `product` and finishes whatever transaction it produced.
    func purchase(_ product: TipProduct) async -> TipPurchaseOutcome

    /// Finishes everything already sitting in the unfinished queue at launch.
    func drainUnfinished() async

    /// Approvals and renewals arriving out of band. It never finishes on its
    /// own: a stream that ended would silently stop catching Ask-to-Buy
    /// approvals for the rest of the launch.
    func transactionOutcomes() -> AsyncStream<TipPurchaseOutcome>
}

/// The whole of what Cellar remembers about a tip: one boolean.
///
/// No date, no count, no transaction id, no price, no storefront. The
/// no-telemetry claim is what a payment feature is most likely to be suspected of
/// breaking, so the record is the smallest thing that works — enough not to
/// re-ask someone who has already given, and nothing more.
public protocol TipGratitudeRecording: Sendable {
    func hasTipped() async -> Bool
    func recordTip() async
}
