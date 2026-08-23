//
//  BundleUpdateKeysTests.swift
//  cellarTests
//

import Foundation
import Testing

/// What the **running bundle** says about updates.
///
/// Everything here reads `Bundle.main`, not the repository, because the claims
/// are about the values a delivered copy of Cellar actually carries. A test that
/// read the partial property list off disk would pass for a build that never
/// merged it, which is the exact failure this suite exists to catch.
///
/// `infoDictionary` is pinned deliberately and must **not** be swapped for
/// `localizedInfoDictionary`. The copyright precedent in
/// `ReleasePipelineCompositionTests` is the opposite case — that key is
/// catalog-sourced and lands in the compiled `InfoPlist.strings` — whereas U24
/// measured both update keys and the application category in the raw generated
/// dictionary.
@Suite("Bundle update keys")
struct BundleUpdateKeysTests {
    static let applicationCategory = "public.app-category.developer-tools"

    // MARK: - T11 — the delivered bundle reports its application category

    /// The category the Finder inspector and the App Store category field read.
    ///
    /// `RELEASING.md` §7 recorded its absence as a known follow-up; this is what
    /// discharges it. Asserting the exact value rather than mere presence is the
    /// point: a category of the wrong kind is as wrong as no category at all,
    /// and only the exact string is a claim the pbxproj edit can be checked
    /// against.
    @Test("The app bundle reports the developer-tools application category")
    func bundleReportsApplicationCategory() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let value = try #require(info["LSApplicationCategoryType"] as? String)

        #expect(value == Self.applicationCategory)
    }
}
