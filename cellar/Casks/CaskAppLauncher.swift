//
//  CaskAppLauncher.swift
//  cellar
//

import AppKit
import BrewClient
import Catalog

/// Resolves where a cask's declared app landed and opens it.
///
/// Read-only against the record: the resolution reads the published `app`
/// stanza — `CaskInstallPlan` — and only ever launches what already exists on
/// disk. Nothing here mutates an install or runs brew.
enum CaskAppLauncher {
    /// The on-disk URL of the cask's first declared app: an absolute published
    /// target verbatim, otherwise the declared name under the default
    /// Applications folder with the user-domain folder as the one fallback
    /// probe. `nil` when the record declares no app or nothing exists at any
    /// candidate — the Open affordance simply does not render then.
    static func installedAppURL(for package: CatalogPackage) -> URL? {
        guard let app = package.caskInspection?.installPlan?.apps.first else { return nil }
        let candidates: [String]
        if let target = app.target, target.hasPrefix("/") {
            candidates = [target]
        } else {
            let name = app.target ?? app.source
            candidates = [
                "\(CaskInstallDestination.applicationsFolderPath)/\(name)",
                NSHomeDirectory() + "/Applications/\(name)"
            ]
        }
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The entry-shaped overload the detail surfaces use: resolves only for an
    /// installed entry that carries its catalog record — a cold catalog has no
    /// `app` stanza to read, so there is nothing to offer.
    static func installedAppURL(for entry: PackageEntry) -> URL? {
        guard entry.isInstalled, let catalog = entry.catalog else { return nil }
        return installedAppURL(for: catalog)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
