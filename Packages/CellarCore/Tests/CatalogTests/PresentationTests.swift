import Foundation
import Testing

@testable import Catalog

/// The wording the Browse UI renders lives here, not in the views: it is a
/// statement about what the data means, and it is the part of "render the count
/// honestly" that can actually be asserted (package-detail PD4, PD5).
@Suite("Presentation vocabulary")
struct PresentationTests {
    @Test("A formula count describes itself as installs on request over 365 days")
    func formulaCountDescription() throws {
        let count = try #require(
            CatalogPackage.stub(kind: .formula, name: "gh", installCount365d: 2_808_879).installCount
        )

        #expect(count.metricDescription == "installs on request")
        #expect(count.windowDescription == "last 365 days")
        #expect(count.lowerBoundNote.contains("opted out"))
        #expect(count.lowerBoundNote.contains("lower bound"))
    }

    @Test("A cask count describes itself as installs over 365 days")
    func caskCountDescription() throws {
        let count = try #require(
            CatalogPackage.stub(kind: .cask, name: "iterm2", installCount365d: 494_727).installCount
        )

        #expect(count.metricDescription == "installs")
        #expect(count.windowDescription == "last 365 days")
    }

    @Test("An absent count renders as 'not reported', never as zero")
    func absentCountRendersAsNotReported() {
        let unknown = CatalogPackage.stub(kind: .formula, name: "obscure", installCount365d: nil)
        let zero = CatalogPackage.stub(kind: .formula, name: "quiet", installCount365d: 0)

        #expect(unknown.installCountDescription == "not reported")
        #expect(zero.installCountDescription != "not reported")
        #expect(zero.installCountDescription.contains("0"))
    }

    @Test("A healthy package carries no status badge")
    func healthyPackageHasNoBadges() {
        #expect(CatalogPackage.stub(kind: .formula, name: "wget").badges.isEmpty)
    }

    @Test("Deprecated and disabled are independent badges")
    func badgesAreIndependent() {
        let deprecated = CatalogPackage.stub(
            kind: .formula, name: "old", deprecated: true, deprecationReason: "unmaintained"
        )
        let disabled = CatalogPackage.stub(
            kind: .formula, name: "gone", disabled: true, disableReason: "removed"
        )
        let both = CatalogPackage.stub(
            kind: .formula, name: "worst",
            deprecated: true, disabled: true
        )

        #expect(deprecated.badges == [.deprecated])
        #expect(disabled.badges == [.disabled])
        #expect(both.badges == [.deprecated, .disabled])
    }

    @Test("A badge exposes a label and a system image the view can render")
    func badgesCarryTheirPresentation() {
        #expect(PackageStatusBadge.deprecated.label == "Deprecated")
        #expect(PackageStatusBadge.disabled.label == "Disabled")
        #expect(PackageStatusBadge.deprecated.systemImage.isEmpty == false)
        #expect(PackageStatusBadge.disabled.systemImage != PackageStatusBadge.deprecated.systemImage)
    }

    @Test("A dependency that resolves is distinguishable from one that does not")
    func dependencyResolutionIsVisible() {
        let resolvable = PackageDependency(name: "pcre2", isResolvable: true)
        let dangling = PackageDependency(name: "ghost-lib", isResolvable: false)

        #expect(resolvable.resolutionNote == nil)
        #expect(dangling.resolutionNote == "not in catalog")
    }

    @Test("A sync status describes itself without exposing transport internals")
    func syncStatusDescriptions() {
        #expect(CatalogSyncStatus.idle.shortDescription == "Up to date")
        #expect(CatalogSyncStatus.downloading(fractionCompleted: nil).shortDescription
            == "Downloading catalog…")
        #expect(CatalogSyncStatus.decoding.shortDescription == "Reading catalog…")
        #expect(CatalogSyncStatus.failed(.offline).shortDescription
            == "Catalog update failed: no network connection")
        #expect(CatalogSyncStatus.failed(.httpStatus(503)).shortDescription.contains("503"))
        #expect(CatalogSyncStatus.succeeded(at: Date(timeIntervalSince1970: 0)).shortDescription
            == "Up to date")
    }

    @Test("Every sync error has a sentence, and none of them mention URLSession")
    func everyErrorHasASentence() {
        let errors: [CatalogSyncError] = [
            .offline, .httpStatus(404), .malformedPayload, .persistence, .cancelled
        ]

        for error in errors {
            #expect(error.shortDescription.isEmpty == false)
            #expect(error.shortDescription.lowercased().contains("urlsession") == false)
            #expect(error.shortDescription.lowercased().contains("nserror") == false)
        }
        #expect(Set(errors.map(\.shortDescription)).count == errors.count)
    }
}
