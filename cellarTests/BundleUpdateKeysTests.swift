//
//  BundleUpdateKeysTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads the partial property list off disk, anchored to this file.
///
/// Self-contained rather than shared, for the same reason `ReleasePipelineSources`
/// is: the update slice must roll back by deleting its own files. The `#filePath`
/// anchor is used because the test runner promises nothing about the working
/// directory.
nonisolated enum UpdateBundleSources {
    static let partialInfoPlist = "Resources/Cellar-Info.plist"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    /// The partial property list as a dictionary, parsed the way the build system
    /// parses it rather than by reading it as text. A file that looks right and
    /// does not parse is a build failure nobody sees until an archive.
    static func partialInfoPlistContents() throws -> [String: Any] {
        let data = try Data(contentsOf: url(partialInfoPlist))
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(parsed as? [String: Any])
    }
}

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
    static let feedURL = "https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml"

    /// The three keys the updater framework reads to decide, on its own, whether
    /// to check for updates and whether to ask the user to let it. None of them
    /// may exist anywhere in the bundle: Cellar's own persisted preference is the
    /// authority, written to the updater at launch.
    static let frameworkAutomaticCheckKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUScheduledCheckInterval"
    ]

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

    // MARK: - T10 — the feed and the verification key the running copy trusts

    /// Both build-time facts, read back out of the bundle that was actually built.
    ///
    /// The feed is asserted as the **exact** string and then again for its
    /// scheme, because "starts with the right host" would pass for an `http`
    /// downgrade and the whole point of compiling the key in is that the
    /// transport is not the thing being trusted.
    ///
    /// The key is asserted by **decoded length**, not by character count. A
    /// 44-character base64 string is what an Ed25519 public key looks like, but
    /// so is any 32 bytes of noise with the right padding, and `Data(base64Encoded:)`
    /// silently returns `nil` for a string that only looks right. Decoding to
    /// exactly 32 bytes is the narrowest claim that a placeholder cannot satisfy.
    @Test("The app bundle carries the exact feed URL and a 32-byte verification key")
    func bundleCarriesTheFeedAndVerificationKey() throws {
        let info = try #require(Bundle.main.infoDictionary)

        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(feed == Self.feedURL)
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")

        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(!key.isEmpty)
        let decoded = try #require(Data(base64Encoded: key))
        #expect(decoded.count == 32)
    }

    // MARK: - T22 (bundle half) — nothing bundled can enable automatic checking

    /// The partial property list carries **exactly two keys**, and the merged
    /// bundle carries none of the framework's own automatic-check keys.
    ///
    /// An exact key set rather than an absence list. An absence list only
    /// forbids the three keys someone thought of; the framework reads more than
    /// three, and the next one it learns to read would arrive unnoticed. Two
    /// keys, named, is the only form of this assertion that stays true as the
    /// framework grows.
    ///
    /// The bundle half matters separately from the file half: the generator
    /// merges this file into the generated `Info.plist`, and a key could in
    /// principle reach the bundle from the generator or the string catalog
    /// rather than from here.
    @Test("The partial property list carries exactly the feed and the key, and nothing enables checking")
    func partialPropertyListCarriesOnlyTheFeedAndTheKey() throws {
        let contents = try UpdateBundleSources.partialInfoPlistContents()

        #expect(contents.keys.sorted() == ["SUFeedURL", "SUPublicEDKey"])
        #expect(contents["SUFeedURL"] as? String == Self.feedURL)

        for key in Self.frameworkAutomaticCheckKeys {
            #expect(contents[key] == nil)
        }

        let info = try #require(Bundle.main.infoDictionary)
        for key in Self.frameworkAutomaticCheckKeys {
            #expect(info[key] == nil)
        }
        // The sweep over the bundle is only meaningful if it read a real bundle.
        #expect(info["CFBundleIdentifier"] as? String == "com.juancasanueva.cellar")
    }
}
