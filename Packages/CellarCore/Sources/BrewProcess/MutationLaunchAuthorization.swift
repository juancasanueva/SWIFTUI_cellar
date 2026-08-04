/// A state-changing brew invocation that can be authorized at the FIFO front.
///
/// Unlike `BrewCommand`, this type has no kind discriminator. A read operation
/// is therefore unrepresentable through the authorization API.
public struct BrewMutation: Sendable, Equatable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public struct MutationLaunchDenial: Error, Sendable, Equatable {
    public enum Code: Sendable, Equatable {
        case evidenceChanged
        case evidenceUnavailable
    }

    public let code: Code

    public init(code: Code) {
        self.code = code
    }
}

public enum MutationLaunchDecision: Sendable, Equatable {
    case allow
    case deny(MutationLaunchDenial)
}

public protocol MutationLaunchAuthorizing: Sendable {
    func authorizeLaunch() async -> MutationLaunchDecision
}

public struct AllowMutationLaunch: MutationLaunchAuthorizing {
    public init() {}

    public func authorizeLaunch() async -> MutationLaunchDecision { .allow }
}

public enum AuthorizedMutationTerminal: Sendable, Equatable {
    case process(BrewExit, fault: BrewProcessError?)
    case authorizationDenied(MutationLaunchDenial)
}
