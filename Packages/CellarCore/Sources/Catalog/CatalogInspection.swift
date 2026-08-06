import Foundation

// The typed shape probe U4 accepted for pre-install cask inspection.
//
// Three rules govern every type in this file, and all three are measurements
// rather than taste:
//
// 1. **Nothing untyped is persisted.** No JSON value tree, no `[String: Any]`,
//    no raw stanza payload. Keeping the stanza tree cost +28.3 MB resident over
//    16,214 records and was rejected.
// 2. **Nothing unmodelled is materialised.** What the projection cannot
//    represent it counts, and only counts.
// 3. **URLs are `String`.** Foundation `URL` costs ~2.2x the resident bytes of
//    the same text at catalog scale. A `URL` is reconstructed at the view
//    boundary, for one package at a time.
//
// The groups below also write themselves compactly: a cask that publishes an
// `artifacts` list with no representable stanza would otherwise persist
// `{"apps":[],"binaries":[],"packageInstallers":[],"unrepresentedStanzaCount":0}`
// — about 75 bytes of literal emptiness, 7,684 times over. The public types
// still expose arrays and never optionals, so "absent" stays a property of the
// *group*, per field, exactly as it is everywhere else in this projection.

/// What a cask's published record says about the thing it downloads and what it
/// puts on the machine.
///
/// `nil` on a formula, and on a cask that published none of the widened keys.
///
/// Deliberately absent, and structurally unable to acquire: any signature,
/// notarization, signing identity, team identifier or trust value. Catalog data
/// supports no such claim, so no field here can carry one (package-detail N1).
public struct CaskInspection: Codable, Hashable, Sendable {
    /// The download location as published — text, not a resolved `URL`.
    public let downloadURL: String?
    /// The checksum the *record declares* for that download. Nothing has been
    /// fetched, hashed or verified (package-detail N2).
    public let declaredChecksum: CaskDownloadChecksum?
    /// `nil` when the record published no `artifacts` list at all.
    public let installPlan: CaskInstallPlan?
    public let requirements: CaskRequirements?
    public let conflicts: CaskConflicts?

    public init(
        downloadURL: String?,
        declaredChecksum: CaskDownloadChecksum?,
        installPlan: CaskInstallPlan?,
        requirements: CaskRequirements?,
        conflicts: CaskConflicts?
    ) {
        self.downloadURL = downloadURL
        self.declaredChecksum = declaredChecksum
        self.installPlan = installPlan
        self.requirements = requirements
        self.conflicts = conflicts
    }

    /// Whether this inspection carries anything at all.
    public var isEmpty: Bool {
        downloadURL == nil && declaredChecksum == nil && installPlan == nil
            && requirements == nil && conflicts == nil
    }

    /// The download URL, and only when handing it to a link opener is safe.
    ///
    /// `downloadURL` is attacker-influenceable catalog text, and a `Link` hands
    /// its destination to the workspace opener — so `javascript:`, `file:`,
    /// `data:` and every other scheme must never reach one. This predicate lives
    /// in CellarCore precisely so that no SwiftUI view is the thing deciding
    /// what is safe to open, and so it can be tested without a view.
    ///
    /// A refused value is not dropped: `downloadURL` still carries the published
    /// text, and the caller renders it as selectable text instead of a link.
    public var browsableDownloadURL: URL? {
        guard let downloadURL,
              let url = URL(string: downloadURL),
              let scheme = url.scheme?.lowercased(),
              Self.browsableSchemes.contains(scheme),
              url.host()?.isEmpty == false
        else { return nil }
        return url
    }

    /// Exhaustive on purpose: a scheme is browsable only by being on this list,
    /// so one nobody thought about is refused rather than allowed.
    private static let browsableSchemes: Set<String> = ["http", "https"]
}

/// The checksum a cask declares for its download.
///
/// A two-case enum and not `String?` because casks really do publish
/// `"sha256": "no_check"`. A plain string forces every consumer to choose
/// between printing that literal as though it were a digest and silently
/// dropping a published fact; this type makes the wrong render unrepresentable
/// and costs nothing, since it encodes as the same string it decoded from.
public enum CaskDownloadChecksum: Codable, Hashable, Sendable {
    case declared(String)
    /// The record published `no_check`: it declares *no* checksum.
    case notChecked

    /// The digest, and only when one was actually declared.
    public var declaredDigest: String? {
        switch self {
        case .declared(let digest): digest
        case .notChecked: nil
        }
    }

    static let noCheckLiteral = "no_check"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = value == Self.noCheckLiteral ? .notChecked : .declared(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .declared(let digest): try container.encode(digest)
        case .notChecked: try container.encode(Self.noCheckLiteral)
        }
    }
}

/// One thing a cask declares it will place on the machine.
///
/// Data describing an installer's declaration — never an instruction this system
/// carries out (package-detail R10).
public struct CaskInstallArtifact: Codable, Hashable, Sendable {
    /// What the cask ships, as published — `iTerm.app`.
    public let source: String
    /// Where the record declares it goes, when it published a destination.
    public let target: String?

    public init(source: String, target: String?) {
        self.source = source
        self.target = target
    }
}

/// Where an `app` artifact lands.
public enum CaskInstallDestination: Hashable, Sendable {
    case explicit(String)
    /// No destination was published, so Homebrew's default applies.
    case defaultApplicationsFolder

    public static let applicationsFolderPath = "/Applications"

    /// The destination an `app` stanza resolves to. Only apps default to the
    /// Applications folder, which is why this is spelled `appTarget` rather than
    /// offered as a property of every artifact.
    public init(appTarget: String?) {
        self = appTarget.map(Self.explicit) ?? .defaultApplicationsFolder
    }

    public var path: String {
        switch self {
        case .explicit(let path): path
        case .defaultApplicationsFolder: Self.applicationsFolderPath
        }
    }
}

/// What a cask declares it installs, for the three stanza kinds this projection
/// represents, plus an honest count of everything else it published.
///
/// The remainder deliberately carries no content: `zap` and `uninstall` stanzas
/// are directive maps (`trash`, `rmdir`, `launchctl`, `pkgutil`, `script`, …),
/// and projecting them would both re-introduce the heterogeneous tree U4
/// rejected and put removable paths and commands into a read-only surface.
public struct CaskInstallPlan: Codable, Hashable, Sendable {
    public let apps: [CaskInstallArtifact]
    public let binaries: [CaskInstallArtifact]
    public let packageInstallers: [CaskInstallArtifact]
    /// Published stanzas this build does not represent. `0`, never absent, when
    /// every published stanza was represented, and distinct from the snapshot's
    /// `skippedRecordCount`.
    public let unrepresentedStanzaCount: Int

    public init(
        apps: [CaskInstallArtifact],
        binaries: [CaskInstallArtifact],
        packageInstallers: [CaskInstallArtifact],
        unrepresentedStanzaCount: Int
    ) {
        self.apps = apps
        self.binaries = binaries
        self.packageInstallers = packageInstallers
        self.unrepresentedStanzaCount = unrepresentedStanzaCount
    }

    public var isEmpty: Bool {
        apps.isEmpty && binaries.isEmpty && packageInstallers.isEmpty
            && unrepresentedStanzaCount == 0
    }

    private enum CodingKeys: String, CodingKey {
        case apps, binaries, packageInstallers, unrepresentedStanzaCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([CaskInstallArtifact].self, forKey: .apps) ?? []
        binaries = try container.decodeIfPresent([CaskInstallArtifact].self, forKey: .binaries) ?? []
        packageInstallers = try container.decodeIfPresent(
            [CaskInstallArtifact].self, forKey: .packageInstallers
        ) ?? []
        unrepresentedStanzaCount = try container.decodeIfPresent(
            Int.self, forKey: .unrepresentedStanzaCount
        ) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !apps.isEmpty { try container.encode(apps, forKey: .apps) }
        if !binaries.isEmpty { try container.encode(binaries, forKey: .binaries) }
        if !packageInstallers.isEmpty {
            try container.encode(packageInstallers, forKey: .packageInstallers)
        }
        if unrepresentedStanzaCount != 0 {
            try container.encode(unrepresentedStanzaCount, forKey: .unrepresentedStanzaCount)
        }
    }
}

/// What a cask declares it needs.
public struct CaskRequirements: Codable, Hashable, Sendable {
    public let formulae: [String]
    public let casks: [String]
    /// The macOS bound as published, rendered for display — `">= 13"`.
    public let macOSRequirement: String?
    /// Relation kinds this build does not model.
    public let unrepresentedCount: Int

    public init(
        formulae: [String],
        casks: [String],
        macOSRequirement: String?,
        unrepresentedCount: Int
    ) {
        self.formulae = formulae
        self.casks = casks
        self.macOSRequirement = macOSRequirement
        self.unrepresentedCount = unrepresentedCount
    }

    public var isEmpty: Bool {
        formulae.isEmpty && casks.isEmpty && macOSRequirement == nil && unrepresentedCount == 0
    }

    private enum CodingKeys: String, CodingKey {
        case formulae, casks, macOSRequirement, unrepresentedCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = try container.decodeIfPresent([String].self, forKey: .formulae) ?? []
        casks = try container.decodeIfPresent([String].self, forKey: .casks) ?? []
        macOSRequirement = try container.decodeIfPresent(String.self, forKey: .macOSRequirement)
        unrepresentedCount = try container.decodeIfPresent(
            Int.self, forKey: .unrepresentedCount
        ) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !formulae.isEmpty { try container.encode(formulae, forKey: .formulae) }
        if !casks.isEmpty { try container.encode(casks, forKey: .casks) }
        try container.encodeIfPresent(macOSRequirement, forKey: .macOSRequirement)
        if unrepresentedCount != 0 {
            try container.encode(unrepresentedCount, forKey: .unrepresentedCount)
        }
    }
}

/// What a cask declares it cannot live beside.
public struct CaskConflicts: Codable, Hashable, Sendable {
    public let casks: [String]
    public let formulae: [String]
    /// Relation kinds this build does not model.
    public let unrepresentedCount: Int

    public init(casks: [String], formulae: [String], unrepresentedCount: Int) {
        self.casks = casks
        self.formulae = formulae
        self.unrepresentedCount = unrepresentedCount
    }

    public var isEmpty: Bool {
        casks.isEmpty && formulae.isEmpty && unrepresentedCount == 0
    }

    private enum CodingKeys: String, CodingKey {
        case casks, formulae, unrepresentedCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        casks = try container.decodeIfPresent([String].self, forKey: .casks) ?? []
        formulae = try container.decodeIfPresent([String].self, forKey: .formulae) ?? []
        unrepresentedCount = try container.decodeIfPresent(
            Int.self, forKey: .unrepresentedCount
        ) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !casks.isEmpty { try container.encode(casks, forKey: .casks) }
        if !formulae.isEmpty { try container.encode(formulae, forKey: .formulae) }
        if unrepresentedCount != 0 {
            try container.encode(unrepresentedCount, forKey: .unrepresentedCount)
        }
    }
}

/// Where a formula's source comes from.
///
/// Carried for the release-notes slice: nothing renders these yet.
public struct FormulaSources: Codable, Hashable, Sendable {
    public let stableURL: String?
    public let headURL: String?

    public init(stableURL: String?, headURL: String?) {
        self.stableURL = stableURL
        self.headURL = headURL
    }

    public var isEmpty: Bool { stableURL == nil && headURL == nil }
}
