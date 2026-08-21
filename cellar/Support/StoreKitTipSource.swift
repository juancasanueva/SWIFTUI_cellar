//
//  StoreKitTipSource.swift
//  cellar
//

import StoreKit
import TipJar

/// The **only** file in this app that imports StoreKit.
///
/// Everything on the far side of these three seams is a plain `Sendable` value:
/// `Product` and `Transaction` are created here, consumed here, and finished
/// here, and neither type appears in `TipJar`, in a view, or anywhere else in the
/// app target. `TipCompositionTests` asserts that structurally rather than
/// leaving it to discipline, because a single `import StoreKit` in a view file
/// would quietly undo the whole arrangement.
///
/// A `struct` with immutable storage, like every other conformer here, so its
/// `async` bodies run off the main actor and only values cross back. The stream
/// and its continuation are built once at construction on purpose: the launch
/// drain happens **before** anyone starts observing, and an outcome it produces
/// has to survive that gap. `AsyncStream` buffers it; a stream created lazily
/// inside `transactionOutcomes()` would have thrown it away.
struct StoreKitTipSource: TipCatalogLoading, TipPurchasing, Sendable {
    private let stream: AsyncStream<TipPurchaseOutcome>
    private let continuation: AsyncStream<TipPurchaseOutcome>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    // MARK: - The catalog

    /// Every field of the returned value is read from the storefront's answer —
    /// the id, the display name, the description and the localized price. None
    /// of them is composed here, because a price this app invented is a price it
    /// will not charge, and a name this app invented is one App Review has never
    /// seen.
    ///
    /// An empty array is returned as `loaded([])`, not as a failure: a build that
    /// simply has nothing to sell is a successful fetch of nothing, and the
    /// difference is what keeps "this build cannot transact" from reaching a user
    /// as "something went wrong".
    func loadTips() async -> TipCatalogLoad {
        do {
            let products = try await Product.products(for: TipProductIDs.all)
            return .loaded(products.map(Self.value(of:)))
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    private static func value(of product: Product) -> TipProduct {
        TipProduct(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice
        )
    }

    // MARK: - Buying

    /// Re-resolves the `Product` by id rather than holding one (design D-G).
    ///
    /// It keeps `TipProduct` a plain value with no framework object hiding behind
    /// it, and one extra fetch is free next to a payment sheet the user is about
    /// to be shown anyway.
    func purchase(_ product: TipProduct) async -> TipPurchaseOutcome {
        do {
            let resolved = try await Product.products(for: [product.id])
            guard let storeProduct = resolved.first(where: { $0.id == product.id }) else {
                return .unavailable(reason: "productNotFound")
            }
            return await Self.outcome(of: try await storeProduct.purchase())
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    /// No purchase options are supplied, and that is deliberate: `appAccountToken`
    /// would attach an identifier to a payment made by an app that has no
    /// accounts, and `quantity` has no meaning for a single thank-you.
    private static func outcome(of result: Product.PurchaseResult) async -> TipPurchaseOutcome {
        switch result {
        case .success(let verification):
            return await finish(verification)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            // Never silence. A case StoreKit adds after this shipped leaves the
            // user looking at a button that did nothing, unless it says so.
            return .unrecognized("Product.PurchaseResult")
        }
    }

    /// Finishes the transaction on **both** branches.
    ///
    /// Leaving an unverified consumable unfinished is not caution: it replays at
    /// every launch, forever, and the user is the one who notices. Verification
    /// decides whether to say thank you — never whether to finish.
    private static func finish(
        _ verification: VerificationResult<Transaction>
    ) async -> TipPurchaseOutcome {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
            return .completed
        case .unverified(let transaction, _):
            await transaction.finish()
            return .unverified
        }
    }

    // MARK: - Transactions this app owns

    /// Finishes everything left over from an earlier launch, and publishes what
    /// each one was so a verified leftover still earns its thank-you.
    ///
    /// Filtered by `TipProductIDs.all` (design D-H): the tip path must never
    /// finish a transaction belonging to something else.
    func drainUnfinished() async {
        for await verification in Transaction.unfinished where Self.isTip(verification) {
            continuation.yield(await Self.finish(verification))
        }
    }

    /// Approvals arriving out of band — an Ask-to-Buy the parent granted after
    /// the app was quit, most of all. Filtered by the same list, and it never
    /// finishes: a stream that ended would stop catching approvals for the rest
    /// of the launch.
    func transactionOutcomes() -> AsyncStream<TipPurchaseOutcome> {
        Task { [continuation] in
            for await verification in Transaction.updates where Self.isTip(verification) {
                continuation.yield(await Self.finish(verification))
            }
        }
        return stream
    }

    private static func isTip(_ verification: VerificationResult<Transaction>) -> Bool {
        TipProductIDs.all.contains(verification.unsafePayloadValue.productID)
    }

    /// The unfinished tip transactions, by product id. Test-facing: it is how a
    /// suite states "nothing was left behind" over a list rather than over a
    /// hope.
    static func unfinishedTipIDs() async -> [String] {
        var ids: [String] = []
        for await verification in Transaction.unfinished where isTip(verification) {
            ids.append(verification.unsafePayloadValue.productID)
        }
        return ids
    }
}
