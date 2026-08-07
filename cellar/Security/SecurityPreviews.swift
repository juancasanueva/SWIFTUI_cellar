//
//  SecurityPreviews.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Persistence
import SecurityKit
import SwiftUI

// MARK: - The one documented exemption from the consent-gate guard
//
// `SecurityCompositionTests.theTwoAdvisorySourcesAreConstructibleFromTheCompositionRootOnly`
// asserts that `OSVSource` and `NVDSource` — which carry no internal consent
// check, because the gate lives in `SecurityScanEngine` — are named by the
// composition root and by nothing else in the app.
//
// A shell preview has to build a whole `ContentView`, which means building a
// `SecurityStore`, which means naming both sources. That is a real construction
// and the guard is right to see it. Rather than exempt `ContentView.swift`
// wholesale — which would have left the guard blind to every future line in the
// app's largest view — the preview lives here, alone, in a file whose entire
// contents are previews.
//
// What makes the exemption safe is asserted, not assumed: this file declares
// **no type and no function**, so nothing in it is reachable from the running
// app, and every source it constructs is handed straight to a
// `SecurityScanEngine` with `FixedScanConsent(.notGranted)` — so even under
// SwiftUI's preview host, the gate refuses before any request is built. Both
// facts are checked by `thePreviewExemptionIsNarrowAndConsentDenied`.

#Preview("Shell") {
    let services = ServicesStore()
    return ContentView(
        brewDetection: BrewDetectionStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        installed: InstalledStore(),
        operations: OperationCenter(),
        metadata: MetadataStore(container: nil),
        history: HistoryStore(container: nil),
        services: services,
        servicesRefresher: ServicesRefreshCoordinator(store: services),
        taps: TapStore(),
        diskUsage: DiskUsageStore(
            cache: DiskUsageCache(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview-disk.json")
            )
        ),
        cleanup: CleanupStore(),
        cleanupPreviewSource: CleanupPreviewSource(),
        brewfileSourceChooser: BrewfileSourcePanel(),
        security: SecurityStore(
            engine: SecurityScanEngine(
                discovery: OSVSource(),
                enrichment: NVDSource(),
                cache: AdvisoryCache(
                    fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("preview-advisories.json")
                ),
                consent: FixedScanConsent(.notGranted),
                queries: { [] }
            )
        ),
        securityConsent: SecurityConsentPreference(),
        advisoryCredentials: KeychainAdvisoryCredentialStore(),
        dismissals: DismissalStore(container: nil),
        integrity: ArtifactIntegrityStore(),
        artifactLocations: []
    )
}
