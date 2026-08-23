import Catalog
import Foundation

/// Which tap Cellar may offer to trust after an untrusted-tap refusal — derived
/// from Cellar's **own** `tap-info` snapshot, never from brew's message.
///
/// `MutationOutcome.refusedUntrustedTap` carries no payload on purpose: PM10
/// :293-295 forbids parsing a tap name, package name, qualified token or
/// suggested command out of the refusal. That leaves the affordance PM10
/// :351-357 still requires, and this is how it is supplied honestly — the input
/// identity is one **Cellar typed itself** (`ActivityItem.command.packageID`),
/// and the candidate set is the taps Cellar already holds.
///
/// **Exactly one candidate, or nothing.** With two untrusted publishers of the
/// same `(kind, name)` Cellar genuinely does not know which tap brew meant, and
/// guessing would grant the wrong capability to the wrong third party. In that
/// case the typed message's own sentence — "Trust the tap in Taps, then try
/// again." — is the path, no button is shown, and brew's verbatim `brew trust …`
/// line is still on screen beside it (design DD-7, R16).
public enum UntrustedTapRecovery {
    public static func trustableTap(
        forRefused package: PackageID?,
        in inventory: TapInventory
    ) -> TapName? {
        // `upgradeAll` and every non-package command: nothing to attribute.
        guard let package else { return nil }
        let candidates = inventory.taps.filter { record in
            record.trust == .untrusted
                && !TapProjection.officialNames.contains(record.name.lowercased())
                && TapProjection.publishes(package, in: record)
        }
        guard candidates.count == 1, let only = candidates.first else { return nil }
        return TapName(only.name)
    }
}
