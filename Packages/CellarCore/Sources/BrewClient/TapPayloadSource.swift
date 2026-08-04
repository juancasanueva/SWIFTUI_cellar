import BrewProcess
import Foundation

public enum TapInventoryError: Error, Sendable, Equatable {
    case brewUnavailable
    case commandFailed(status: Int32, message: String)
    case blankOutput
    case malformedJSON
    case nonArrayEnvelope
    case cancelled
}

public protocol TapPayloadSourcing: Sendable {
    func payload(using installation: BrewInstallation) async throws(TapInventoryError) -> Data
}

enum TapPayload {
    static let stderrTailLineCount = 12

    static func payload(from lines: [LogLine], exit: BrewExit) throws(TapInventoryError) -> Data {
        if exit.isCancelled { throw .cancelled }
        guard exit.isSuccess else {
            let message = lines
                .filter { $0.stream == .stderr }
                .suffix(stderrTailLineCount)
                .map(\.text)
                .joined(separator: "\n")
            throw .commandFailed(status: exit.status, message: message)
        }

        let document = lines.lazy
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")
        guard document.contains(where: { !$0.isWhitespace }) else { throw .blankOutput }
        return Data(document.utf8)
    }
}

public struct BrewTapPayloadSource: TapPayloadSourcing {
    static let command = BrewCommand.read(["tap-info", "--installed", "--json"])

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func payload(using installation: BrewInstallation) async throws(TapInventoryError) -> Data {
        let runner = BrewRunner(installation: installation, launcher: launcher)
        let operation: BrewOperation
        do {
            operation = try await runner.start(Self.command)
        } catch {
            switch error {
            case .executableUnavailable: throw .brewUnavailable
            case .launchFailed(_, let code):
                throw .commandFailed(status: code, message: String(describing: error))
            case .cancelledUnresponsive: throw .cancelled
            }
        }

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        return try TapPayload.payload(from: lines, exit: await operation.exit())
    }
}
