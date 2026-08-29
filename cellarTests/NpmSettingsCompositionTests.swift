//
//  NpmSettingsCompositionTests.swift
//  cellarTests
//

import BrewProcess
import Foundation
import Testing

@testable import cellar

/// The npm Settings group holds no state logic of its own.
///
/// Every sentence it renders — the path, the version, the prefix, where the npm
/// came from and the note when there is none — is a projection off
/// `NpmDetectionState`, so each of them is assertable without rendering
/// anything. The view's whole job is to lay the projection out.
@Suite("npm settings composition")
struct NpmSettingsCompositionTests {
    private static let environment = NpmEnvironment(
        executableURL: URL(fileURLWithPath: "/Users/tester/.volta/bin/npm"),
        version: "10.9.2",
        prefix: URL(fileURLWithPath: "/Users/tester/.volta"),
        origin: .volta
    )

    // MARK: - The preference

    @Test("The preference is off with nothing stored, and survives a write")
    func preferenceDefaultsOffAndPersists() throws {
        let suite = try #require(UserDefaults(suiteName: "npm-settings-\(UUID().uuidString)"))
        defer { suite.removeSuite(named: suite.description) }
        let preference = NpmSourcePreference(defaults: suite)

        #expect(preference.isEnabled == false)
        #expect(preference.configuredPath == nil)

        preference.isEnabled = true
        preference.configuredPath = URL(fileURLWithPath: "/opt/tools/npm")

        // Read back through a second value over the same suite: the storage is
        // the defaults domain, not the value.
        let reread = NpmSourcePreference(defaults: suite)
        #expect(reread.isEnabled)
        #expect(reread.configuredPath?.path == "/opt/tools/npm")
    }

    @Test("A blank configured path reads as no configured path")
    func blankConfiguredPathIsAbsent() throws {
        let suite = try #require(UserDefaults(suiteName: "npm-settings-\(UUID().uuidString)"))
        defer { suite.removeSuite(named: suite.description) }
        let preference = NpmSourcePreference(defaults: suite)

        preference.configuredPath = URL(fileURLWithPath: "/opt/tools/npm")
        suite.set("   ", forKey: NpmSourcePreference.pathKey)

        // A field the user emptied means "go back to discovering it", not "look
        // for a binary called nothing".
        #expect(NpmSourcePreference(defaults: suite).configuredPath == nil)
    }

    // MARK: - The disclosure

    @Test("A detected npm discloses its path, version, prefix and origin")
    func detectedDisclosesTheTriple() throws {
        let disclosure = NpmSettingsDisclosure(state: .detected(Self.environment))

        #expect(disclosure.path == "/Users/tester/.volta/bin/npm")
        #expect(disclosure.version == "npm 10.9.2")
        #expect(disclosure.prefix == "/Users/tester/.volta")
        #expect(disclosure.origin == "Volta")
        #expect(disclosure.note == nil)
    }

    @Test("Each undetected state has its own note and no facts to show")
    func undetectedStatesHaveTheirOwnNote() {
        let cases: [(NpmDetectionState, String)] = [
            (.disabled, "Turn the npm source on to detect it"),
            (.absent, "npm not detected"),
            (
                .invalid(URL(fileURLWithPath: "/opt/tools/npm"), .notNpm(output: "git version 2.4.0")),
                "/opt/tools/npm is not npm"
            ),
            (
                .invalid(URL(fileURLWithPath: "/opt/tools/npm"), .notExecutable),
                "/opt/tools/npm is not executable"
            ),
            (
                .configuredPathMissing(URL(fileURLWithPath: "/opt/tools/npm")),
                "/opt/tools/npm no longer exists"
            ),
        ]

        for (state, note) in cases {
            let disclosure = NpmSettingsDisclosure(state: state)

            #expect(disclosure.note == note)
            #expect(disclosure.path == nil)
            #expect(disclosure.version == nil)
            #expect(disclosure.prefix == nil)
            #expect(disclosure.origin == nil)
        }
    }

    @Test("Every origin has a name of its own")
    func everyOriginIsNamed() {
        let names = NpmOrigin.allCases.map(\.displayName)

        #expect(Set(names).count == NpmOrigin.allCases.count)
        #expect(names.contains { $0.isEmpty } == false)
    }

    @Test("The path field shows what is configured, not what was detected")
    func configuredPathFieldIsIndependentOfDetection() {
        // Detected under Volta, configured nowhere: the field must stay empty
        // rather than filling itself with the discovered path, which would turn
        // a discovery into a configuration the user never made.
        let disclosure = NpmSettingsDisclosure(
            state: .detected(Self.environment), configuredPath: nil
        )
        let configured = NpmSettingsDisclosure(
            state: .detected(Self.environment),
            configuredPath: URL(fileURLWithPath: "/opt/tools/npm")
        )

        #expect(disclosure.configuredPathText.isEmpty)
        #expect(configured.configuredPathText == "/opt/tools/npm")
    }

    // MARK: - The switch drives the store

    @MainActor
    @Test("Toggling the preference drives the detection store, off by default")
    func toggleDrivesTheStore() async {
        let store = NpmDetectionStore(locator: FakeAppNpmLocator(result: .detected(Self.environment)))

        #expect(store.isEnabled == false)
        #expect(store.state == .disabled)

        store.isEnabled = true
        for _ in 0..<100 { await Task.yield() }

        #expect(store.state == .detected(Self.environment))
    }
}

/// A locator that answers one scripted state, so the app-target composition test
/// needs no npm and no process.
private final class FakeAppNpmLocator: NpmLocating, Sendable {
    private let result: NpmDetectionState

    init(result: NpmDetectionState) {
        self.result = result
    }

    func detect(configuredPath: URL?) async -> NpmDetectionState { result }
}
