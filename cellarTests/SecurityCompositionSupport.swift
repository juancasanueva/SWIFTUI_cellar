//
//  SecurityCompositionSupport.swift
//  cellarTests
//

import Foundation

@testable import cellar

/// A filesystem that records every directory it was asked to enumerate.
///
/// The scope claim — "`/Applications` was never enumerated" — is an absence, and
/// an absence is only provable if something counted the presences. This records
/// them, so the assertion is over a real list rather than over a hope.
nonisolated final class RecordingFileSystem: ArtifactFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var enumerated: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func contentsOfDirectory(at url: URL) -> [URL] {
        lock.lock()
        recorded.append(url.path)
        lock.unlock()

        return (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

/// Reads `cellar/` off disk, the way `SecurityKitSources` reads the library.
///
/// Textual by necessity: a claim about what the app target does *not* contain
/// cannot be made by importing it.
nonisolated enum AppSecuritySources {
    struct Source: Sendable {
        let name: String
        let code: String
    }

    /// The app target's own directory, found relative to this file rather than to
    /// a working directory the test runner does not promise.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("cellar")
    }

    static func load() throws -> [Source] {
        var sources: [Source] = []
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            sources.append(Source(name: url.lastPathComponent, code: stripComments(from: text)))
        }
        return sources.sorted { $0.name < $1.name }
    }

    /// Comments are stripped so a prohibition *described* in a doc comment is
    /// never mistaken for one *violated* in code — the `SecurityKitSources`
    /// discipline, restated here because the app target has its own sources.
    static func stripComments(from source: String) -> String {
        var state = ScanState()
        var output = ""
        var index = source.startIndex

        while index < source.endIndex {
            let next = source.index(after: index)
            let following = next < source.endIndex ? source[next] : nil
            index = state.consume(source[index], following: following, into: &output, at: index, in: source)
            index = source.index(after: index)
        }
        return output
    }

    /// The stripper as a small state machine.
    ///
    /// Extracted from one long function that tripped the cyclomatic-complexity
    /// rule — the same shape `SecurityKitSources.stripComments` took for the same
    /// reason, and the same escape-pair rule: both characters of `\\x` survive,
    /// because swallowing them is how an interpolated host once slipped past a
    /// sibling scanner unnoticed.
    private struct ScanState {
        var inLine = false
        var inBlock = false
        var inString = false

        mutating func consume(
            _ character: Character,
            following: Character?,
            into output: inout String,
            at index: String.Index,
            in source: String
        ) -> String.Index {
            if inLine { return endLine(character, into: &output, at: index) }
            if inBlock { return endBlock(character, following: following, at: index, in: source) }
            if inString { return inside(character, following: following, into: &output, at: index, in: source) }
            return outside(character, following: following, into: &output, at: index, in: source)
        }

        private mutating func endLine(
            _ character: Character,
            into output: inout String,
            at index: String.Index
        ) -> String.Index {
            if character == "\n" {
                inLine = false
                output.append(character)
            }
            return index
        }

        private mutating func endBlock(
            _ character: Character,
            following: Character?,
            at index: String.Index,
            in source: String
        ) -> String.Index {
            guard character == "*", following == "/" else { return index }
            inBlock = false
            return source.index(after: index)
        }

        private mutating func inside(
            _ character: Character,
            following: Character?,
            into output: inout String,
            at index: String.Index,
            in source: String
        ) -> String.Index {
            if character == "\\", let following {
                output.append(character)
                output.append(following)
                return source.index(after: index)
            }
            if character == "\"" { inString = false }
            output.append(character)
            return index
        }

        private mutating func outside(
            _ character: Character,
            following: Character?,
            into output: inout String,
            at index: String.Index,
            in source: String
        ) -> String.Index {
            if character == "/", following == "/" {
                inLine = true
                return source.index(after: index)
            }
            if character == "/", following == "*" {
                inBlock = true
                return source.index(after: index)
            }
            if character == "\"" { inString = true }
            output.append(character)
            return index
        }
    }
}

/// A `URLProtocol` that fails every request loudly and counts it.
///
/// The `MigrationTests.RequestSpy` pattern: the only way a request could go
/// unnoticed is if nothing were watching.
nonisolated final class CompositionRequestSpy: @unchecked Sendable {
    private static let counter = NSLock()
    nonisolated(unsafe) private static var count = 0

    func install() {
        Self.counter.lock()
        Self.count = 0
        Self.counter.unlock()
        URLProtocol.registerClass(SpyProtocol.self)
    }

    func uninstall() {
        URLProtocol.unregisterClass(SpyProtocol.self)
    }

    var observedCount: Int {
        Self.counter.lock()
        defer { Self.counter.unlock() }
        return Self.count
    }

    static func record() {
        counter.lock()
        count += 1
        counter.unlock()
    }

    final class SpyProtocol: URLProtocol {
        // swiftlint:disable:next static_over_final_class
        override class func canInit(with request: URLRequest) -> Bool {
            CompositionRequestSpy.record()
            return false
        }

        // swiftlint:disable:next static_over_final_class
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    }
}

/// Counts scans, so "exactly one" is a number rather than an impression.
actor RecordingSecurityScanner {
    private(set) var count = 0

    func record() { count += 1 }
}

/// A consent answer that can change between triggers, which is the whole point:
/// revocation must take effect on the next trigger, not at the next launch.
actor MutableConsentFlag {
    private(set) var value: Bool

    init(_ value: Bool) { self.value = value }

    func set(_ newValue: Bool) { value = newValue }
}
