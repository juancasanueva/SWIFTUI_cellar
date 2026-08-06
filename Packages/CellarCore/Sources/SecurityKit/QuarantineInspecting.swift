import Foundation

// MARK: - Components

/// One decoded field of an extended attribute, or an honest account of why it is
/// not decoded.
///
/// Three cases, and the distinction between the last two is the point. `absent`
/// means the encoding was read perfectly and there was nothing in it — the real,
/// common shape of the agent field, measured on two of the three quarantined apps
/// the U3 probe found. `unknown` means there *was* something and this build could
/// not read it. Collapsing them would report a perfectly ordinary attribute as
/// damaged.
public enum QuarantineComponent<Value: Sendable & Hashable>: Sendable, Hashable {
    case decoded(Value)
    /// Present in the encoding and empty.
    case absent
    /// Present, non-empty, and not interpretable. Carries the raw text so the
    /// surface can show exactly what it could not read.
    case unknown(String)

    public var decodedValue: Value? {
        guard case .decoded(let value) = self else { return nil }
        return value
    }

    public var isDecoded: Bool { decodedValue != nil }
}

/// `com.apple.quarantine`, decoded — with the raw value kept verbatim beside it.
///
/// The shape is `flags;hexTimestamp;agentName;UUID`, confirmed against real
/// captures from three brew-installed casks during the U3 probe.
public struct QuarantineAttribute: Sendable, Hashable {
    public static let attributeName = "com.apple.quarantine"

    /// Exactly the bytes `getxattr` returned, unmodified.
    ///
    /// Kept because the decode is best-effort by design: a reader who disagrees
    /// with how this build read a component can see the original, and a component
    /// this build calls `unknown` is still fully available to them.
    public let rawValue: String
    public let flags: QuarantineComponent<UInt32>
    public let timestamp: QuarantineComponent<Date>
    /// What put this file here — `Safari`, `Chrome`, or nothing at all.
    public let agentName: QuarantineComponent<String>
    public let identifier: QuarantineComponent<UUID>
    /// Whether the value had the four components this build knows the shape of.
    public let isWellFormed: Bool

    public init(rawValue: String) {
        self.rawValue = rawValue
        let components = rawValue.components(separatedBy: ";")
        isWellFormed = components.count == 4

        func component(_ index: Int) -> String? {
            components.indices.contains(index) ? components[index] : nil
        }

        flags = Self.decode(component(0)) { UInt32($0, radix: 16) }
        timestamp = Self.decode(component(1)) { hex in
            UInt32(hex, radix: 16).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        agentName = Self.decode(component(2)) { $0 }
        identifier = Self.decode(component(3)) { UUID(uuidString: $0) }
    }

    /// The flags as a number, and **only** as a number.
    ///
    /// Apple publishes no meaning for these bits. Rendering `0x01c3` as "opened by
    /// the user, assessment passed" would be a confident sentence with nothing
    /// behind it, and the spec's "never guessed" is aimed squarely at this field.
    /// So the description is the value, in the base it was written in.
    public var flagsDescription: String {
        switch flags {
        case .decoded(let value): "0x" + String(format: "%04x", value)
        case .absent: "(empty)"
        case .unknown(let raw): raw
        }
    }

    private static func decode<Value: Sendable & Hashable>(
        _ text: String?,
        _ transform: (String) -> Value?
    ) -> QuarantineComponent<Value> {
        guard let text else { return .unknown("") }
        guard text.isEmpty == false else { return .absent }
        guard let value = transform(text) else { return .unknown(text) }
        return .decoded(value)
    }
}

/// What one artifact's extended attributes say.
public struct ArtifactQuarantine: Sendable, Hashable {
    public static let provenanceAttributeName = "com.apple.provenance"

    public let location: ArtifactLocation
    /// Every attribute name found, including the ones this build does not read —
    /// `com.apple.macl`, `com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P`.
    /// Enumerated so "we read the two we understand" is a stated boundary rather
    /// than an oversight.
    public let attributeNames: [String]
    public let quarantine: QuarantineAttribute?

    public init(
        location: ArtifactLocation,
        attributeNames: [String],
        quarantine: QuarantineAttribute?
    ) {
        self.location = location
        self.attributeNames = attributeNames
        self.quarantine = quarantine
    }

    public var isQuarantined: Bool { quarantine != nil }

    /// Presence only.
    ///
    /// `com.apple.provenance` is undocumented binary — eleven bytes on the
    /// artifact the probe read. That it is there is a fact; what it says is not,
    /// and this build makes no claim about it.
    public var hasProvenance: Bool { attributeNames.contains(Self.provenanceAttributeName) }
}

// MARK: - The seam

public protocol QuarantineInspecting: Sendable {
    func inspect(_ location: ArtifactLocation) async throws -> ArtifactQuarantine
}

// MARK: - The real one

/// `listxattr` and `getxattr` directly.
///
/// ## Read-only, and structurally so
///
/// This file contains **no `setxattr` and no `removexattr` call site**, and
/// neither does anything else in this target — `EgressStructureTests` scans for
/// both target-wide and `IntegrityProhibitionTests` enumerates the public surface
/// for mutating verbs. The C API's read and write halves are siblings one letter
/// apart, which is exactly why the prohibition is asserted rather than intended.
///
/// There is also no `xattr` **subprocess**: the tool's textual output would have
/// to be parsed, and parsing a command's output is what the spec forbids.
///
/// `XATTR_NOFOLLOW` throughout: an artifact's own attributes are asked for, never
/// its symlink target's.
public struct ExtendedAttributeQuarantineInspector: QuarantineInspecting {
    public init() {}

    public func inspect(_ location: ArtifactLocation) async throws -> ArtifactQuarantine {
        try Task.checkCancellation()
        let path = location.url.path
        let names = Self.attributeNames(at: path)

        let quarantine = names.contains(QuarantineAttribute.attributeName)
            ? Self.value(of: QuarantineAttribute.attributeName, at: path)
                .map { QuarantineAttribute(rawValue: $0) }
            : nil

        return ArtifactQuarantine(
            location: location,
            attributeNames: names,
            quarantine: quarantine
        )
    }

    /// Every attribute name on the artifact, in the order the filesystem listed
    /// them.
    ///
    /// An artifact with no attributes is the ordinary case and answers `[]` — not
    /// an error. A file being unremarkable is not a failure to report.
    static func attributeNames(at path: String) -> [String] {
        let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: size)
        guard listxattr(path, &buffer, size, XATTR_NOFOLLOW) > 0 else { return [] }

        // The kernel returns a run of NUL-terminated names.
        return buffer
            .split(separator: 0)
            .compactMap { String(bytes: $0.map { UInt8(bitPattern: $0) }, encoding: .utf8) }
    }

    static func value(of name: String, at path: String) -> String? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW) > 0 else { return nil }
        // Failable rather than lossy: an attribute whose bytes are not UTF-8 is one
        // this build cannot read, and replacing the undecodable bytes with U+FFFD
        // would present a mangled value as if it had been decoded.
        return String(bytes: buffer, encoding: .utf8)
    }
}
