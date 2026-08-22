//
//  TipJarCard.swift
//  cellar
//

import SwiftUI
import TipJar

/// The one place in Cellar where a tip can be given.
///
/// **Copy status: placeholder awaiting the maintainer's wording.** Every line
/// below is written to the spec's rules rather than to a voice — gratitude, no
/// begging, no countdown, no claim that the app is at risk, and no suggestion
/// that any feature depends on tipping — but the final phrasing is the
/// maintainer's to author. It is flagged in the PR body rather than quietly
/// shipped as if it were settled.
///
/// The card renders **only** when the catalog produced a product. An empty
/// catalog, a failed load and a catalog still loading all render nothing at all:
/// not a disabled button, not a greyed row, not an "unavailable" explanation.
/// Cellar does not ship present-but-inert controls, and a purchase control in a
/// build that cannot transact is the most inert one there is.
///
/// The price is `product.displayPrice`, verbatim, and is interpolated rather
/// than composed. No price string exists in this file, in this app, or in any of
/// its tests — the storefront is the only thing that knows what this costs where
/// the user is standing.
struct TipJarCard: View {
    @Environment(TipStore.self) private var tips
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        if let product = tips.availability.product {
            card(for: product)
        }
    }

    private func card(for product: TipProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(explanation)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                purchaseButton(for: product)
            }
            if let note = outcomeNote {
                Text(note)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .themeCard(fill: Color.white.opacity(0.02))
        .accessibilityIdentifier("tip-jar-card")
    }

    private func purchaseButton(for product: TipProduct) -> some View {
        Button {
            Task { await tips.tip() }
        } label: {
            if tips.purchase == .inFlight {
                ProgressView().controlSize(.small)
            } else {
                // The only thing this app knows about the price is what the
                // storefront said it was.
                Text("\(buttonVerb) \(product.displayPrice)")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(tips.purchase == .inFlight)
        .accessibilityIdentifier("tip-jar-purchase")
    }

    // MARK: - Copy (placeholder — see the note on the type)

    /// Unchanged after a tip. A consumable may be given again, and copy that
    /// escalated or softened on the second visit would be a nag in slow motion.
    private var headline: String { "Say thanks" }

    private var explanation: String {
        tips.hasTipped
            ? "Thank you — it made a difference. Cellar stays exactly as it is, and so does everything in it."
            : "Cellar is free, and every feature stays free whether you do this or not. It is a thank-you, nothing more."
    }

    private var buttonVerb: String { tips.hasTipped ? "Again ·" : "Tip ·" }

    /// What the last attempt actually did.
    ///
    /// `cancelled` is deliberately absent: dismissing the sheet says nothing, so
    /// nothing is said back. `pending` says out loud that nothing has been paid,
    /// and `unverified` states the fact without accusing anyone of anything.
    private var outcomeNote: String? {
        guard case .settled(let outcome) = tips.purchase else { return nil }
        switch outcome {
        case .completed, .cancelled:
            return nil
        case .pending:
            return "Waiting for approval. Nothing has been paid yet."
        case .unverified:
            return "That purchase could not be verified, so it has not been recorded."
        case .failed:
            return "That did not go through. Nothing was charged."
        case .unavailable:
            return nil
        }
    }
}
