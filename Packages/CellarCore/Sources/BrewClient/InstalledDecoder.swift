import Catalog
import Foundation

/// Turns one snapshot payload into the inventory projection.
///
/// A pure function over `Data`, mirroring `CatalogDecoder`: no process, no file
/// system, no clock, so every shape the payload can take is reachable from a
/// test (design D3).
public enum InstalledDecoder {
    /// Decodes a payload off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `PackageSearchIndex.build` (M1 D2): projecting several hundred records is
    /// milliseconds of CPU and the caller is the main actor. The attribute goes
    /// **before** the modifier — the other order does not compile, which cost an
    /// apply cycle in M1. The result crosses back with no lock: an
    /// `InstalledInventory` is `Sendable` by composition (design D3, D6).
    @concurrent
    public static func decode(
        _ data: Data
    ) async throws(InstalledInventoryError) -> InstalledInventory {
        try inventory(from: data)
    }

    /// Projects the payload, tolerating individual bad records.
    ///
    /// Threat response — **untrusted subprocess payload**: an unreadable
    /// *envelope* is `.malformedPayload`, because nothing in it is recoverable;
    /// an unreadable *record* costs that record and is counted, because one
    /// formula whose shape drifted must not delete the user's whole inventory.
    static func inventory(from data: Data) throws(InstalledInventoryError) -> InstalledInventory {
        let envelope: InstalledEnvelopeWire
        do {
            envelope = try JSONDecoder().decode(InstalledEnvelopeWire.self, from: data)
        } catch {
            throw .malformedPayload
        }
        guard envelope.formulae != nil || envelope.casks != nil else {
            throw .malformedPayload
        }

        let formulae = envelope.formulae?.elements ?? []
        let casks = envelope.casks?.elements ?? []
        let packages = formulae.compactMap(project(formula:)) + casks.compactMap(project(cask:))

        // Ordering and the membership sets are the inventory's own invariants,
        // established once in its initialiser — this decoder is not the only
        // thing that builds one.
        return InstalledInventory(
            packages: packages,
            skippedRecordCount:
                (envelope.formulae?.skippedCount ?? 0) + (envelope.casks?.skippedCount ?? 0)
        )
    }

    // MARK: - Projection

    private static func project(formula: FormulaInstalledWire) -> InstalledPackage? {
        let kegs = (formula.installed ?? []).map {
            InstalledKeg(
                version: $0.version,
                installedAt: date($0.time),
                installedOnRequest: $0.installedOnRequest ?? true
            )
        }
        // No keg means the record is not installed, whatever else it says. That
        // is a shape the projection has no room for, not a corrupt record.
        guard let primary = primaryKeg(of: kegs, linked: formula.linkedKeg) else { return nil }

        return InstalledPackage(
            kind: .formula,
            name: formula.name,
            displayName: formula.name,
            desc: formula.desc,
            homepage: url(formula.homepage),
            tap: formula.tap ?? "",
            catalogVersion: formula.versions?.stable ?? primary.version,
            kegs: kegs,
            primaryKeg: primary,
            snapshotOutdated: formula.outdated ?? false,
            isPinned: formula.pinned ?? false,
            pinnedVersion: formula.pinnedVersion,
            // Formulae have no auto-update concept at all — not "declared
            // false", simply not a question that applies.
            declaresAutoUpdates: nil,
            linkedKeg: formula.linkedKeg
        )
    }

    private static func project(cask: CaskInstalledWire) -> InstalledPackage? {
        guard let installed = cask.installed else { return nil }

        // A cask's records carry no on-request marker, so nothing a user
        // deliberately installed may be hidden by the default view
        // (installed-inventory II3).
        let keg = InstalledKeg(
            version: installed,
            installedAt: date(cask.installedTime),
            installedOnRequest: true
        )

        return InstalledPackage(
            kind: .cask,
            name: cask.token,
            displayName: cask.name?.first ?? cask.token,
            desc: cask.desc,
            homepage: url(cask.homepage),
            tap: cask.tap ?? "",
            catalogVersion: cask.version ?? installed,
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: cask.outdated ?? false,
            isPinned: cask.pinned ?? false,
            pinnedVersion: cask.pinnedVersion,
            declaresAutoUpdates: cask.autoUpdates
        )
    }

    /// The linked keg, or the newest install when nothing is linked.
    ///
    /// `linked_keg` is authoritative even when an older keg: it names the
    /// version actually on `PATH`, which is the one the user is running.
    private static func primaryKeg(
        of kegs: [InstalledKeg],
        linked: String?
    ) -> InstalledKeg? {
        if let linked, let match = kegs.first(where: { $0.version == linked }) { return match }
        return kegs.max { $0.installedAt < $1.installedAt }
    }

    private static func date(_ epochSeconds: TimeInterval?) -> Date {
        Date(timeIntervalSince1970: epochSeconds ?? 0)
    }

    private static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }
}
