//
//  TipProduct.swift
//  TipJar
//

/// The one thing this capability sells.
///
/// Declared once, as a constant, and read from here everywhere else. A product
/// identifier repeated as a literal is a rename waiting to half-happen: the
/// catalog fetch would keep working while the transaction filter quietly stopped
/// matching, and an unfinished consumable replays forever.
public enum TipProductIDs {
    public static let tip = "com.juancasanueva.cellar.tip"

    /// Everything this capability owns. The conformer filters the transaction
    /// streams by this list, so the tip path can never finish a transaction
    /// belonging to something else (design D-H).
    public static let all = [tip]
}

/// A tip, as a plain value.
///
/// Every field is **read from the store**, none composed here — the display name,
/// the description and the localized price are the storefront's answers for this
/// user in this region, and inventing any of them locally is how an app ends up
/// showing a price it will not charge.
///
/// StoreKit's `Product` deliberately does not appear: it is a framework type with
/// a purchase method attached, and letting it cross into `CellarCore` would make
/// every rule in this target reachable only from a machine that can transact.
public struct TipProduct: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// The store's own description of the product.
    public let description: String
    /// The localized display price, verbatim. Never parsed, never reformatted,
    /// never compared against a literal.
    public let displayPrice: String

    public init(id: String, displayName: String, description: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
    }
}

/// What one catalog fetch produced.
///
/// Two cases, and the empty list lives **inside** `loaded` rather than beside it:
/// an empty answer is a successful fetch of nothing, which is a different fact
/// from a fetch that failed. Collapsing them would report "this build cannot
/// transact" as "something went wrong", and the reverse.
public enum TipCatalogLoad: Sendable, Equatable {
    case loaded([TipProduct])
    case failed(reason: String)
}
