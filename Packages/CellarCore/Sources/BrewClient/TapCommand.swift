import BrewProcess
import Catalog
import DiskUsage
import Foundation

public struct TapName: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init?(_ rawValue: String) {
        guard MutationName.isSafe(rawValue) else { return nil }
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy(Self.isCanonicalComponent)
        else { return nil }
        self.rawValue = rawValue
    }

    private static func isCanonicalComponent(_ component: Substring) -> Bool {
        guard let first = component.first,
              first.isASCII,
              first.isLetter || first.isNumber
        else { return false }
        return component.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }
}

public struct ForceUntapEvidence: Sendable, Equatable {
    public let tap: TapName
    public let affected: Set<PackageID>
    public let isComplete: Bool

    public init(tap: TapName, affected: Set<PackageID>, isComplete: Bool) {
        self.tap = tap
        self.affected = affected
        self.isComplete = isComplete
    }
}

public enum ConfirmationDisclosure: Sendable, Equatable {
    case packageRemoval
    case tapTrust(TapName)
    case forceUntap(tap: TapName, affected: Set<PackageID>)

    public var warningText: String {
        switch self {
        case .packageRemoval:
            "This removes installed software."
        case .tapTrust(let tap):
            "Adding \(tap.rawValue) trusts third-party formulae and casks that can distribute code."
        case .forceUntap(let tap, let affected):
            "Force-removing \(tap.rawValue) affects \(affected.count) installed packages."
        }
    }
}

public enum TapCommand: Sendable, Equatable, BrewMutating {
    case addTap(TapName)
    case removeTap(TapName)
    case forceRemoveTap(ForceUntapEvidence)

    public static func add(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.addTap)
    }

    public static func untap(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.removeTap)
    }

    public static func forceUntap(evidence: ForceUntapEvidence) -> TapCommand? {
        guard evidence.isComplete, !evidence.affected.isEmpty else { return nil }
        return .forceRemoveTap(evidence)
    }

    public var arguments: [String] {
        switch self {
        case .addTap(let tap): ["tap", tap.rawValue]
        case .removeTap(let tap): ["untap", tap.rawValue]
        case .forceRemoveTap(let evidence): ["untap", "--force", evidence.tap.rawValue]
        }
    }

    public var verb: String {
        switch self {
        case .addTap: "tapAdd"
        case .removeTap: "tapUntap"
        case .forceRemoveTap: "tapForceUntap"
        }
    }

    public var packageID: PackageID? { nil }

    public var requiresConfirmation: Bool {
        switch self {
        case .addTap, .forceRemoveTap: true
        case .removeTap: false
        }
    }

    public var invalidates: InvalidationScope {
        switch self {
        case .addTap, .removeTap: .taps
        case .forceRemoveTap: [.taps, .installedInventory, .diskUsage]
        }
    }

    public var diskAreas: Set<DiskArea> {
        guard case .forceRemoveTap(let evidence) = self else { return [] }
        return Set(evidence.affected.map { $0.kind == .formula ? .cellar : .caskroom })
    }

    public var disclosure: ConfirmationDisclosure {
        switch self {
        case .addTap(let tap): .tapTrust(tap)
        case .removeTap: .packageRemoval
        case .forceRemoveTap(let evidence):
            .forceUntap(tap: evidence.tap, affected: evidence.affected)
        }
    }
}

public struct ForceUntapLaunchAuthorizer: MutationLaunchAuthorizing {
    private let tap: TapName
    private let expected: Set<PackageID>
    private let currentEvidence: @Sendable () async -> ForceUntapEvidence?

    public init(
        tap: TapName,
        expected: Set<PackageID>,
        currentEvidence: @escaping @Sendable () async -> ForceUntapEvidence?
    ) {
        self.tap = tap
        self.expected = expected
        self.currentEvidence = currentEvidence
    }

    public func authorizeLaunch() async -> MutationLaunchDecision {
        guard let evidence = await currentEvidence(),
              evidence.isComplete,
              evidence.tap == tap
        else {
            return .deny(MutationLaunchDenial(code: .evidenceUnavailable))
        }
        guard evidence.affected == expected else {
            return .deny(MutationLaunchDenial(code: .evidenceChanged))
        }
        return .allow
    }
}
