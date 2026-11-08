//
//  CaskInstalledAppTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// An installed cask's app is found through the link Homebrew wrote into
/// `Caskroom/<token>/<installed version>` — which works for a third-party
/// tap's cask exactly as for a `homebrew/cask` one, with no catalog record.
@Suite("Cask installed app")
struct CaskInstalledAppTests {
    @Test("The Caskroom link resolves to the installed app")
    func theCaskroomLinkResolvesToTheInstalledApp() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try Self.makeApp("Home-Cellar.app", in: root.appendingPathComponent("Applications"))
        let version = try Self.makeDirectory(root.appendingPathComponent("Caskroom/home-cellar/1.8.7"))
        try FileManager.default.createSymbolicLink(
            at: version.appendingPathComponent("Home-Cellar.app"),
            withDestinationURL: app
        )
        FileManager.default.createFile(atPath: version.appendingPathComponent("notes.txt").path, contents: nil)

        let url = CaskInstalledApp.url(
            token: "home-cellar",
            version: "1.8.7",
            caskroom: root.appendingPathComponent("Caskroom")
        )

        #expect(url?.standardizedFileURL.resolvingSymlinksInPath() == app.resolvingSymlinksInPath())
    }

    @Test("Another version's directory is not consulted")
    func anotherVersionsDirectoryIsNotConsulted() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.makeApp("Old.app", in: root.appendingPathComponent("Caskroom/zed/1.0"))

        let url = CaskInstalledApp.url(token: "zed", version: "2.0", caskroom: root.appendingPathComponent("Caskroom"))

        #expect(url == nil)
    }

    @Test("A link whose app was removed yields nothing")
    func aDanglingLinkYieldsNothing() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let version = try Self.makeDirectory(root.appendingPathComponent("Caskroom/gone/1.0"))
        try FileManager.default.createSymbolicLink(
            at: version.appendingPathComponent("Gone.app"),
            withDestinationURL: root.appendingPathComponent("Applications/Gone.app")
        )

        let url = CaskInstalledApp.url(token: "gone", version: "1.0", caskroom: root.appendingPathComponent("Caskroom"))

        #expect(url == nil)
    }

    // MARK: - Fixtures

    private static func scratch() throws -> URL {
        try makeDirectory(FileManager.default.temporaryDirectory
            .appendingPathComponent("CaskInstalledAppTests-\(UUID().uuidString)"))
    }

    private static func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeApp(_ name: String, in directory: URL) throws -> URL {
        try makeDirectory(directory.appendingPathComponent(name))
    }
}
