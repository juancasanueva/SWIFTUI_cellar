import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// `com.apple.quarantine`, decoded into typed components with the raw value kept
/// verbatim beside them — and **nothing guessed**.
///
/// Every value here came off a real brew-installed app during the U3 probe. The
/// flags field in particular is deliberately *not* interpreted: Apple documents
/// no public meaning for those bits, and inventing one would put a confident
/// sentence in front of the user with nothing behind it.
@Suite("Quarantine inspector")
struct QuarantineInspectorTests {
    private static func raw(_ fixture: String) throws -> String {
        try #require(String(bytes: try Fixture.data("Quarantine/\(fixture)"), encoding: .utf8))
    }

    // MARK: - 14.6 The four components

    /// VLC's real attribute: all four components present, agent named.
    @Test("The attribute decodes into flags, timestamp, agent and UUID")
    func theAttributeDecodesIntoFlagsTimestampAgentAndUuid() throws {
        let attribute = try #require(
            QuarantineAttribute(rawValue: try Self.raw("vlc-com.apple.quarantine.txt"))
        )

        #expect(attribute.flags == .decoded(0x01c3))
        #expect(attribute.timestamp == .decoded(Date(timeIntervalSince1970: 0x6a65_eb27)))
        #expect(attribute.agentName == .decoded("Safari"))
        #expect(
            attribute.identifier == .decoded(UUID(uuidString: "3E44AF78-B965-4994-8537-E5EEA922D6E5")!)
        )
        #expect(attribute.isWellFormed)
    }

    @Test("The raw value is preserved verbatim alongside the typed components")
    func theRawValueIsPreservedVerbatimAlongsideTheTypedComponents() throws {
        let raw = try Self.raw("vlc-com.apple.quarantine.txt")
        let attribute = try #require(QuarantineAttribute(rawValue: raw))

        #expect(attribute.rawValue == raw)
        #expect(attribute.rawValue == "01c3;6a65eb27;Safari;3E44AF78-B965-4994-8537-E5EEA922D6E5")
    }

    /// The real, common shape the probe found on two of three quarantined apps:
    /// the agent field is **empty**. Empty is not the same as unrecognised — the
    /// encoding was read perfectly and there was nothing in it — so it decodes to
    /// `.absent`, and the panel can say "no agent recorded" rather than inventing
    /// one or claiming the attribute is corrupt.
    @Test(
        "An empty agent field is absent rather than unknown",
        arguments: ["codexbar-com.apple.quarantine.txt", "applite-com.apple.quarantine.txt"]
    )
    func anEmptyAgentFieldIsAbsentRatherThanUnknown(fixture: String) throws {
        let attribute = try #require(QuarantineAttribute(rawValue: try Self.raw(fixture)))

        #expect(attribute.agentName == .absent)
        #expect(attribute.agentName != .unknown(""))
        #expect(attribute.flags == .decoded(0x03c1))
        #expect(attribute.isWellFormed, "an empty component is still a well-formed attribute")
        // The other three still decoded, so "absent" did not poison the record.
        #expect(attribute.timestamp.isDecoded)
        #expect(attribute.identifier.isDecoded)
    }

    @Test("An unrecognised component reports unknown and is never guessed")
    func anUnrecognisedComponentReportsUnknownAndIsNeverGuessed() throws {
        let attribute = try #require(
            QuarantineAttribute(rawValue: "zzzz;notatimestamp;Safari;not-a-uuid")
        )

        #expect(attribute.flags == .unknown("zzzz"))
        #expect(attribute.timestamp == .unknown("notatimestamp"))
        #expect(attribute.agentName == .decoded("Safari"))
        #expect(attribute.identifier == .unknown("not-a-uuid"))
        #expect(attribute.rawValue == "zzzz;notatimestamp;Safari;not-a-uuid")
        #expect(
            attribute.flags.decodedValue == nil,
            "an unknown component handed back a value anyway"
        )
    }

    /// Fewer or more than four components is a shape this build does not
    /// recognise. The raw value survives; nothing is invented to fill the gaps.
    @Test(
        "A component count other than four is not well formed and invents nothing",
        arguments: [
            "01c3;6a65eb27;Safari",
            "01c3;6a65eb27",
            "01c3",
            "",
            "01c3;6a65eb27;Safari;3E44AF78-B965-4994-8537-E5EEA922D6E5;extra"
        ]
    )
    func aComponentCountOtherThanFourIsNotWellFormed(raw: String) throws {
        let attribute = try #require(QuarantineAttribute(rawValue: raw))

        #expect(attribute.isWellFormed == false)
        #expect(attribute.rawValue == raw)
    }

    /// The flags field is decoded as a **number and nothing more**.
    ///
    /// Apple publishes no meaning for these bits. Decoding `0x01c3` into "opened
    /// by the user, assessment passed" would be a sentence with nothing behind
    /// it, and the spec forbids exactly that.
    @Test("Flags are decoded as a number and never interpreted into meaning")
    func flagsAreDecodedAsANumberAndNeverInterpreted() throws {
        let attribute = try #require(
            QuarantineAttribute(rawValue: try Self.raw("vlc-com.apple.quarantine.txt"))
        )

        #expect(attribute.flags.decodedValue == 451)
        #expect(attribute.flagsDescription == "0x01c3", "the flags read as anything but their value")
    }

    // MARK: - Provenance

    @Test("Provenance presence is reported when present, and its bytes are not guessed")
    func provenancePresenceIsReportedWhenPresent() throws {
        let present = ArtifactQuarantine(
            location: Self.location,
            attributeNames: ["com.apple.macl", "com.apple.provenance", "com.apple.quarantine"],
            quarantine: QuarantineAttribute(rawValue: try Self.raw("vlc-com.apple.quarantine.txt"))
        )
        let absent = ArtifactQuarantine(
            location: Self.location,
            attributeNames: ["com.apple.macl"],
            quarantine: nil
        )

        #expect(present.hasProvenance)
        #expect(present.isQuarantined)
        #expect(absent.hasProvenance == false)
        #expect(absent.isQuarantined == false)
    }

    /// Ghostty's real `com.apple.provenance` is 11 undocumented binary bytes.
    /// Presence is a fact; contents are not, and this build says so.
    @Test("Provenance is reported as present without any claim about its contents")
    func provenanceIsReportedAsPresentWithoutAnyClaimAboutItsContents() throws {
        let hex = try #require(
            String(bytes: try Fixture.data("Quarantine/ghostty-com.apple.provenance.hex"), encoding: .utf8)
        )

        #expect(hex.count == 22, "11 bytes, two hex digits each")
        #expect(
            ArtifactQuarantine.provenanceAttributeName == "com.apple.provenance",
            "the attribute this build looks for changed name"
        )
    }

    /// The attributes deliberately out of scope, recorded so the boundary is
    /// stated rather than accidental.
    @Test("Attributes outside the two this capability reads are enumerated but not decoded")
    func attributesOutsideTheTwoAreEnumeratedButNotDecoded() {
        let inspected = ArtifactQuarantine(
            location: Self.location,
            attributeNames: [
                "com.apple.FinderInfo", "com.apple.fileprovider.fpfs#P",
                "com.apple.macl", "com.apple.provenance"
            ],
            quarantine: nil
        )

        #expect(inspected.attributeNames.count == 4)
        #expect(inspected.hasProvenance)
        #expect(inspected.isQuarantined == false)
    }

    // MARK: - The real reader

    /// A real temporary file with a real attribute set on it, read back through
    /// `listxattr`/`getxattr`.
    ///
    /// The attribute is written with `setxattr` **in the test only** — the shipped
    /// target has no write call site at all, which `IntegrityProhibitionTests`
    /// asserts structurally.
    @Test("The real inspector reads a real attribute off disk")
    func theRealInspectorReadsARealAttributeOffDisk() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("binary")
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60)).write(to: file)
        let raw = try Self.raw("codexbar-com.apple.quarantine.txt")
        try Self.setAttribute("com.apple.quarantine", raw, on: file)

        let location = try #require(
            ArtifactLocation(packageID: PackageID(kind: .cask, name: "codexbar"), url: file)
        )
        let inspected = try await ExtendedAttributeQuarantineInspector().inspect(location)

        #expect(inspected.isQuarantined)
        #expect(inspected.quarantine?.rawValue == raw)
        #expect(inspected.quarantine?.agentName == .absent)
        #expect(inspected.attributeNames.contains("com.apple.quarantine"))
    }

    /// **Measured, not assumed.** macOS 26 attaches `com.apple.provenance` to a
    /// file this process writes, so provenance presence is *not* evidence that
    /// something was downloaded. The first version of this test asserted
    /// `hasProvenance == false` for a file it had just created, and the system
    /// disagreed. Recorded here because a panel that presented provenance as
    /// "this came from the internet" would be wrong about every file on the disk.
    @Test("Provenance is attached by the system to freshly written files, so presence is not origin")
    func provenanceIsAttachedBySystemToFreshlyWrittenFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("binary")
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60)).write(to: file)
        let location = try #require(
            ArtifactLocation(packageID: PackageID(kind: .formula, name: "x"), url: file)
        )

        let inspected = try await ExtendedAttributeQuarantineInspector().inspect(location)

        #expect(inspected.hasProvenance, "macOS 26 no longer attaches provenance on write")
        #expect(
            inspected.isQuarantined == false,
            "provenance is not quarantine, and presence of one must not imply the other"
        )
    }

    @Test("An artifact with no quarantine attribute reads as not quarantined rather than failing")
    func anArtifactWithNoQuarantineAttributeReadsAsNotQuarantined() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("binary")
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60)).write(to: file)
        let location = try #require(
            ArtifactLocation(packageID: PackageID(kind: .formula, name: "x"), url: file)
        )

        let inspected = try await ExtendedAttributeQuarantineInspector().inspect(location)

        #expect(inspected.isQuarantined == false)
        #expect(inspected.quarantine == nil)
        #expect(
            inspected.attributeNames.contains("com.apple.quarantine") == false,
            "an artifact nobody quarantined reported a quarantine attribute"
        )
    }

    // MARK: - Helpers

    private static let location = ArtifactLocation(
        packageID: PackageID(kind: .cask, name: "vlc"),
        url: URL(fileURLWithPath: "/Applications/VLC.app"),
        kind: .bundle
    )

    private static func setAttribute(_ name: String, _ value: String, on url: URL) throws {
        let bytes = Array(value.utf8)
        let status = bytes.withUnsafeBufferPointer { buffer in
            setxattr(url.path, name, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
        }
        try #require(status == 0, "setxattr failed with errno \(errno)")
    }
}
