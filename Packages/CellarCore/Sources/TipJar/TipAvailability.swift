//
//  TipAvailability.swift
//  TipJar
//

/// Why there is nothing to tip with.
///
/// Two cases, kept apart on purpose. `emptyCatalog` is the ordinary answer in a
/// Developer ID build, in a build whose App Store Connect record does not exist
/// yet, and anywhere the storefront simply has nothing to sell; `loadFailed` is
/// a fetch that went wrong. They read identically to a user — no tip surface —
/// and completely differently to whoever has to diagnose it, which is why the
/// difference is a case rather than a sentence.
public enum TipUnavailableReason: Sendable, Equatable {
    case emptyCatalog
    case loadFailed(String)
}

/// Whether this build can be tipped, and with what.
///
/// Derived from **one runtime signal**: whether the loaded catalog produced a
/// product. Not from `AppStore.canMakePayments`, which is `true` on a machine
/// that can buy nothing at all; not from a compile-time flag, an `#if`, or an
/// `#available`, because a control that is present-but-inert is the thing this
/// app refuses to ship.
public enum TipAvailability: Sendable, Equatable {
    /// Nothing has been asked yet. Distinct from `loading`: not-yet-asked and
    /// asking are different facts, and collapsing them hides a load that never
    /// started.
    case unknown
    case loading
    case available(TipProduct)
    case unavailable(TipUnavailableReason)

    /// The one derivation, and the only place a catalog answer becomes a
    /// surface decision.
    public static func resolved(from load: TipCatalogLoad) -> TipAvailability {
        switch load {
        case .loaded(let products):
            guard let product = products.first else { return .unavailable(.emptyCatalog) }
            return .available(product)
        case .failed(let reason):
            return .unavailable(.loadFailed(reason))
        }
    }

    /// The product to offer, or nothing. The price a surface renders comes from
    /// here and from nowhere else.
    public var product: TipProduct? {
        guard case .available(let product) = self else { return nil }
        return product
    }

    /// Why not, when there is no product. `nil` while the answer is still open.
    public var unavailableReason: TipUnavailableReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }

    /// Whether the question has an answer. An empty catalog is settled; a
    /// spinner that never resolves is the failure mode this exists to name.
    public var isSettled: Bool {
        switch self {
        case .unknown, .loading: return false
        case .available, .unavailable: return true
        }
    }
}

/// One catalog load, published as the states it passes through.
///
/// Extracted from the store rather than written inside it so the sequence is
/// assertable on its own: "loading is observable while it is in progress" is a
/// claim about a state that exists only between the call and the answer, and a
/// store that published only the final state would satisfy every value-level
/// test while leaving the surface with a spinner it never removed.
public struct TipCatalogLoader: Sendable {
    private let catalog: any TipCatalogLoading

    public init(catalog: any TipCatalogLoading) {
        self.catalog = catalog
    }

    /// Emits `loading`, then exactly one settled state. Never emits twice for
    /// one call and never leaves the caller in `loading`.
    @MainActor
    public func load(emit: (TipAvailability) -> Void) async {
        emit(.loading)
        emit(.resolved(from: await catalog.loadTips()))
    }
}
