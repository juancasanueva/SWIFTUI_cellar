//
//  TipPurchaseOutcome.swift
//  TipJar
//

/// What one tip attempt actually did.
///
/// Six cases, and every one of them is distinguishable by switching rather than
/// by reading text. That is the whole design: a consumer that had to parse a
/// reason string to tell "waiting for a parent's approval" from "paid" would
/// eventually get it wrong, and both mistakes are ones a user notices — a
/// thank-you for money nobody spent, or an accusation aimed at someone whose
/// payment simply could not be verified.
public enum TipPurchaseOutcome: Sendable, Equatable {
    /// A verified transaction, finished. The only case that earns a thank-you.
    case completed
    /// The sheet was dismissed. Says nothing, shows nothing, records nothing.
    case cancelled
    /// Ask to Buy, or any other deferred approval. Explicitly **not** paid.
    case pending
    /// Verification failed. Finished anyway, thanked never, and never phrased as
    /// an accusation of fraud.
    case unverified
    /// The purchase threw. Carries a typed reason.
    case failed(reason: String)
    /// There was nothing to buy, so nothing was attempted.
    case unavailable(reason: String)

    /// The one mapping for an answer this app was compiled before StoreKit could
    /// give. A `@unknown default` that returned silence would leave a user
    /// looking at a button that did nothing at all.
    public static func unrecognized(_ description: String) -> TipPurchaseOutcome {
        .failed(reason: "unrecognized store answer: \(description)")
    }

    /// Whether this outcome writes the thank-you flag. Exactly one case does.
    public var recordsGratitude: Bool { self == .completed }

    /// Whether this outcome may be presented as "the tip went through".
    /// `pending` is the case this exists for.
    public var claimsTipComplete: Bool { self == .completed }

    /// Whether the user should be told nothing whatsoever. Cancelling is the
    /// only quiet outcome; every other one has something honest to say.
    public var isSilent: Bool { self == .cancelled }

    /// The typed reason a *failure* carries. `unavailable` deliberately does not
    /// answer here: nothing went wrong, there was simply nothing to buy.
    public var failureReason: String? {
        guard case .failed(let reason) = self else { return nil }
        return reason
    }
}

/// What must happen to a transaction the store handed back.
///
/// This exists because the rule requirement 3 argues hardest for — *"skipping
/// `finish()` on the unverified path MUST NOT be treated as a safety measure,
/// because an unfinished consumable replays forever"* — was, as a `switch`
/// inside the StoreKit conformer, the one rule in this capability that no test
/// could execute. `SKTestSession` cannot produce a transaction that fails
/// verification, so the unverified branch was reachable only by reading it.
///
/// Splitting the **decision** out from the call leaves exactly one millimetre
/// unproven — that `Transaction.finish()` is what actually gets invoked — and
/// makes everything else a value both branches of a test can drive.
///
/// `mustFinish` is a stored property rather than an implied constant on purpose.
/// The failure this guards against is precisely someone making finishing
/// conditional on verification at a later date, and a rule that is not
/// represented cannot be asserted.
public struct TipTransactionDisposition: Sendable, Equatable {
    /// Whether the transaction must be finished. **Always true.** Verification
    /// decides whether to say thank you; it never decides whether to finish.
    public let mustFinish: Bool

    /// What to report, and therefore whether the thank-you is recorded.
    public let outcome: TipPurchaseOutcome

    /// The one mapping from "did this verify" to "what happens to it now".
    public static func forTransaction(isVerified: Bool) -> TipTransactionDisposition {
        TipTransactionDisposition(
            mustFinish: true,
            outcome: isVerified ? .completed : .unverified
        )
    }
}

/// Where one purchase attempt stands.
public enum TipPurchaseState: Sendable, Equatable {
    case idle
    case inFlight
    case settled(TipPurchaseOutcome)
}

extension TipUnavailableReason {
    /// A short, stable diagnostic. Carried inside `TipPurchaseOutcome.unavailable`
    /// so a log says *which* kind of unavailable it was — never so that a caller
    /// has to read it to decide anything.
    public var diagnostic: String {
        switch self {
        case .emptyCatalog: return "emptyCatalog"
        case .loadFailed(let reason): return "loadFailed: \(reason)"
        }
    }
}

/// Whether a purchase may be attempted at all, and with what.
public enum TipPurchaseDecision: Sendable, Equatable {
    case buy(TipProduct)
    case refuse(TipPurchaseOutcome)
}

/// One tip attempt, from availability to outcome.
///
/// Extracted from the store for the same reason `TipCatalogLoader` is: the rule
/// that matters most here is an **absence** — a purchase requested with no
/// product must not reach the purchasing seam — and an absence is only provable
/// against a recorder, which needs the decision to live somewhere a test can
/// drive directly.
public struct TipPurchaseRunner: Sendable {
    private let purchases: any TipPurchasing

    public init(purchases: any TipPurchasing) {
        self.purchases = purchases
    }

    /// The decision, alone. Pure, and the only place "may this be bought" is
    /// answered.
    public static func decision(for availability: TipAvailability) -> TipPurchaseDecision {
        guard let product = availability.product else {
            let reason = availability.unavailableReason?.diagnostic ?? "catalogNotSettled"
            return .refuse(.unavailable(reason: reason))
        }
        return .buy(product)
    }

    public func run(for availability: TipAvailability) async -> TipPurchaseOutcome {
        switch Self.decision(for: availability) {
        case .refuse(let outcome): return outcome
        case .buy(let product): return await purchases.purchase(product)
        }
    }
}
