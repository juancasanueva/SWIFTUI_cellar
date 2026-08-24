import BrewProcess
import Foundation

public protocol TrustGrantSourcing: Sendable {
    func payload(using installation: BrewInstallation) async throws(TrustGrantError) -> Data
}

enum TrustGrantPayload {
    /// The same bounded stderr tail the tap read keeps: enough to name the
    /// failure, never enough to be a transcript.
    static let stderrTailLineCount = 12

    static func payload(from lines: [LogLine], exit: BrewExit) throws(TrustGrantError) -> Data {
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

/// The per-package trust report, asked of `brew` and of nothing else.
///
/// There is no fallback path. If the read fails the state stays `unreported`
/// and every surface claims nothing — Homebrew's own state files are never
/// opened, on this path or any other (package-trust PT1 :57-61, `rules.apply`).
public struct BrewTrustGrantPayloadSource: TrustGrantSourcing {
    /// Compile-time constant. **No element contains `/`**, so naming a package
    /// — which *is* the grant on Homebrew 6 (`trust.rb#explicitly_allowed?`) —
    /// is impossible here by construction, rather than merely avoided (D-f,
    /// DD-11). There is no parameter through which a token could arrive.
    static let command = BrewCommand.read(["trust", "--json", "v1"])

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func payload(using installation: BrewInstallation) async throws(TrustGrantError) -> Data {
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
        return try TrustGrantPayload.payload(from: lines, exit: await operation.exit())
    }
}
