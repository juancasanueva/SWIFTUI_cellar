import Catalog
import CryptoKit
import Foundation
import Testing

@testable import SecurityKit

/// Visibility does not become remediation, and inspection changes nothing.
///
/// Every claim here is an **absence**, and an absence passes for free when the
/// thing it forbids has not been written yet. So each one is paired with either a
/// positive anchor (the scanner really did read real code) or a control (the
/// scanner really would fire if the forbidden thing appeared).
@Suite("Integrity prohibitions")
struct IntegrityProhibitionTests {
    /// The five files that make up the integrity half.
    private static let integrityFiles: Set<String> = [
        "ArtifactAssessability.swift",
        "ArtifactIntegrityEngine.swift",
        "ArtifactSignatureModels.swift",
        "CodeSignatureInspecting.swift",
        "QuarantineInspecting.swift"
    ]

    private static func integritySources() throws -> [SecurityKitSource] {
        let sources = try SecurityKitSources.load().filter { integrityFiles.contains($0.name) }
        #expect(
            Set(sources.map(\.name)) == integrityFiles,
            "an integrity source was renamed or removed, and this guard stopped covering it"
        )
        return sources
    }

    // MARK: - 14.10 Nothing is written, launched or escalated

    /// A real temporary tree, hashed and stat'ed before and after a real sweep.
    ///
    /// Content digest, modification date **and** the extended-attribute set are
    /// all compared, because "read-only" fails in three different ways: rewriting
    /// bytes, touching mtime by opening for write, and — the one this capability
    /// is most at risk of — clearing a quarantine attribute it just read.
    @Test("No byte of an inspected artifact changes")
    func noByteOfAnInspectedArtifactChanges() async throws {
        try await withTemporaryTree { root, locations in
            let before = try Self.fingerprints(of: locations)
            #expect(before.count == locations.count, "the fingerprint pass read nothing")
            #expect(
                before.values.contains { $0.attributeNames.contains(QuarantineAttribute.attributeName) },
                "no artifact carried a quarantine attribute, so clearing one could not be detected"
            )

            var assessed = 0
            for try await event in await ArtifactIntegrityEngine().inspect(locations) {
                if case .assessed = event { assessed += 1 }
            }
            #expect(assessed == locations.count, "the sweep did not actually run")

            let after = try Self.fingerprints(of: locations)
            #expect(after == before, "an inspected artifact changed")
            _ = root
        }
    }

    /// The control: the comparison above would notice. Without this, `after ==
    /// before` proves only that both sides were computed the same wrong way.
    @Test("The fingerprint comparison detects a byte, a timestamp and an attribute change")
    func theFingerprintComparisonDetectsEveryKindOfChange() async throws {
        try await withTemporaryTree { _, locations in
            let baseline = try Self.fingerprints(of: locations)
            let target = try #require(locations.first)

            try Data([0xcf, 0xfa, 0xed, 0xfe, 0x99]).write(to: target.url)
            #expect(try Self.fingerprints(of: locations) != baseline, "a content change went unnoticed")

            try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: target.url)
            let restoredContent = try Self.fingerprints(of: locations)

            try Self.setQuarantine("01c3;6a65eb27;Control;\(UUID().uuidString)", on: target.url)
            #expect(
                try Self.fingerprints(of: locations) != restoredContent,
                "an attribute change went unnoticed"
            )
            // And specifically that it is the *attribute* half that noticed —
            // rewriting the bytes left the attribute set in place, which is how
            // the first version of this fingerprint managed to miss it.
            #expect(
                try Self.fingerprints(of: locations)[target.url]?.attributeValues
                    != restoredContent[target.url]?.attributeValues
            )
        }
    }

    /// `Process`, `posix_spawn` and `NSTask` are already forbidden target-wide by
    /// task 1.5. This restates it over the four integrity files specifically,
    /// because they are the ones with an obvious `codesign`/`spctl`/`xattr`
    /// shortcut a future edit might reach for.
    @Test("No process is launched during a full sweep")
    func noProcessIsLaunchedDuringAFullSweep() throws {
        let sources = try Self.integritySources()

        for source in sources {
            for token in ["Process", "posix_spawn", "NSTask", "execve", "system", "popen"] {
                #expect(
                    source.code.containsIdentifier(token) == false,
                    "\(source.name) names \(token)"
                )
            }
            for tool in ["/usr/bin/", "/bin/", "codesign", "spctl", "stapler"] {
                #expect(source.code.contains(tool) == false, "\(source.name) names \(tool)")
            }
        }

        // The positive anchor: the scanner read real code, and the code really
        // does reach the platform API the subprocess would have replaced.
        #expect(
            sources.contains { $0.code.containsIdentifier("SecStaticCodeCreateWithPath") },
            "the scan read files that do not contain the API it is meant to be protecting"
        )
    }

    /// No elevation, and no path towards one. The U3 probe ran the whole sequence
    /// at euid 501 with no prompt of any kind, so a request for authorization here
    /// would be asking for something the feature has been measured not to need.
    @Test("No elevation is requested")
    func noElevationIsRequested() throws {
        for source in try Self.integritySources() {
            for token in [
                "AuthorizationCreate", "AuthorizationExecuteWithPrivileges",
                "SMJobBless", "SMJobSubmit", "setuid", "seteuid", "sudo"
            ] {
                #expect(
                    source.code.containsIdentifier(token) == false,
                    "\(source.name) names \(token)"
                )
            }
        }
    }

    /// The single most dangerous neighbour: `getxattr` is mandated and
    /// `removexattr`/`setxattr` are forbidden, and they are one word apart in the
    /// same header. Asserted over the **whole target**, not just the integrity
    /// files, because a write helper could be put anywhere.
    @Test("No write to an extended attribute exists anywhere in the target")
    func noWriteToAnExtendedAttributeExistsAnywhereInTheTarget() throws {
        let sources = try SecurityKitSources.load()
        SecurityKitSources.assertAnchored(sources)

        for source in sources {
            for token in ["removexattr", "setxattr", "fremovexattr", "fsetxattr"] {
                #expect(
                    source.code.containsIdentifier(token) == false,
                    "\(source.name) names \(token)"
                )
            }
        }

        // The positive anchor: the mandated read half **is** present, so this is a
        // scan over code that genuinely works with extended attributes.
        #expect(
            sources.contains {
                $0.code.containsIdentifier("getxattr") && $0.code.containsIdentifier("listxattr")
            },
            "neither getxattr nor listxattr is present, so the write ban guards nothing"
        )
    }

    // MARK: - 14.11 No public surface accepts a write

    /// Every public declaration in the integrity half, checked against the verbs
    /// that would make it remediation rather than visibility.
    @Test("No public surface of the capability accepts a write")
    func noPublicSurfaceOfTheCapabilityAcceptsAWrite() throws {
        let declarations = try Self.integritySources().flatMap { source in
            Self.publicDeclarations(in: source.code).map { (source.name, $0) }
        }

        #expect(declarations.count > 20, "the declaration scanner found almost nothing")
        #expect(
            declarations.contains { $0.1.contains("func assess") },
            "the scanner did not find the capability's own entry point"
        )

        for (file, declaration) in declarations {
            for verb in Self.mutatingVerbs {
                #expect(
                    Self.names(verb, in: declaration) == false,
                    "\(file) publishes a mutating surface: \(declaration)"
                )
            }
        }
    }

    /// The control. Without it, the scan above passes for a declaration list that
    /// is empty, malformed, or matched against verbs that can never appear.
    @Test("The public-surface scanner fires on a mutating declaration")
    func thePublicSurfaceScannerFiresOnAMutatingDeclaration() {
        let sample = """
            public func clearQuarantine(_ url: URL) {}
            public func assess(_ location: ArtifactLocation) async throws -> Assessment {}
            public var stripAttributes: Bool { false }
            func removeQuarantine() {}
            """
        let declarations = Self.publicDeclarations(in: sample)

        #expect(declarations.count == 3, "a non-public declaration was picked up, or a public one missed")

        let offenders = declarations.filter { declaration in
            Self.mutatingVerbs.contains { Self.names($0, in: declaration) }
        }
        #expect(offenders.count == 2, "the scanner missed a mutating declaration")
        #expect(offenders.contains { $0.contains("clearQuarantine") })
        #expect(offenders.contains { $0.contains("stripAttributes") })
    }

    private static let mutatingVerbs = [
        "clear", "remove", "strip", "delete", "write", "sign", "resign",
        "staple", "unstaple", "quarantine", "unquarantine", "approve", "trust", "set"
    ]

    /// Whether a declaration names a verb, case-insensitively at a word boundary.
    ///
    /// `clearQuarantine` and `clear_quarantine` both match `clear`;
    /// `nuclearOption` does not, and neither does `assessment` for `set`.
    private static func names(_ verb: String, in declaration: String) -> Bool {
        guard let range = declaration.range(of: "func ") ?? declaration.range(of: "var ") else {
            return false
        }
        let name = declaration[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard name.isEmpty == false else { return false }

        // Split the identifier into camel-case words and compare whole words, so
        // a verb has to *be* a word of the name rather than appear inside one.
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase || character == "_" {
                if current.isEmpty == false { words.append(current.lowercased()) }
                current = character == "_" ? "" : String(character)
            } else {
                current.append(character)
            }
        }
        if current.isEmpty == false { words.append(current.lowercased()) }
        return words.contains(verb.lowercased())
    }

    private static func publicDeclarations(in code: String) -> [String] {
        code.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public ") }
    }

    // MARK: - The temporary tree

    private struct Fingerprint: Hashable {
        let digest: String
        let modified: Date?
        let attributeNames: [String]
        /// Attribute **values**, not only their names.
        ///
        /// The control test caught this: rewriting a file's bytes left its
        /// extended attributes in place, so a fingerprint over names alone was
        /// blind to an attribute whose *value* changed. Clearing a quarantine and
        /// rewriting one are both things this capability must be shown not to do,
        /// and only one of them changes the name set.
        let attributeValues: [String]
    }

    private static func fingerprints(
        of locations: [ArtifactLocation]
    ) throws -> [URL: Fingerprint] {
        var fingerprints: [URL: Fingerprint] = [:]
        for location in locations {
            let data = try Data(contentsOf: location.url)
            let attributes = try FileManager.default.attributesOfItem(atPath: location.url.path)
            let names = ExtendedAttributeQuarantineInspector
                .attributeNames(at: location.url.path)
                .sorted()
            fingerprints[location.url] = Fingerprint(
                digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                modified: attributes[.modificationDate] as? Date,
                attributeNames: names,
                attributeValues: names.map {
                    ExtendedAttributeQuarantineInspector.value(of: $0, at: location.url.path) ?? "(binary)"
                }
            )
        }
        return fingerprints
    }

    private static func setQuarantine(_ value: String, on url: URL) throws {
        let bytes = Array(value.utf8)
        let status = bytes.withUnsafeBufferPointer { buffer in
            setxattr(url.path, QuarantineAttribute.attributeName, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
        }
        try #require(status == 0, "setxattr failed with errno \(errno)")
    }

    private func withTemporaryTree(
        _ body: (URL, [ArtifactLocation]) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var locations: [ArtifactLocation] = []
        for index in 0..<3 {
            let file = root.appendingPathComponent("binary\(index)")
            try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: file)
            if index == 0 {
                try Self.setQuarantine(
                    "01c3;6a65eb27;Safari;3E44AF78-B965-4994-8537-E5EEA922D6E5",
                    on: file
                )
            }
            locations.append(
                ArtifactLocation(
                    packageID: PackageID(kind: .formula, name: "pkg\(index)"),
                    url: file,
                    kind: .machO
                )
            )
        }

        try await body(root, locations)
    }
}
