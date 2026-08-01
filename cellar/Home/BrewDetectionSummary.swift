//
//  BrewDetectionSummary.swift
//  cellar
//
//  Extracted verbatim from the previous ContentView.
//

import BrewProcess
import SwiftUI

/// Renders the detection state as plain text.
///
/// Deliberately text only: M1 proves detection works end to end. Onboarding,
/// pickers, and remediation flows belong to a later milestone.
struct BrewDetectionSummary: View {
    let state: BrewDetectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .detected(let installation):
                Text("Homebrew detected")
                    .font(.headline)
                Text("Path: \(installation.executableURL.path)")
                Text("Prefix: \(Self.description(of: installation.prefix))")
                Text("Version: \(installation.version.major).\(installation.version.minor).\(installation.version.patch)")
                if installation.advisories.contains(.rosettaPrefix) {
                    Text("Advisory: installed under the Intel prefix. Fully supported; migration is optional.")
                }

            case .invalid(let url, let reason):
                Text("Configured Homebrew path is not usable")
                    .font(.headline)
                Text("Path: \(url.path)")
                Text("Reason: \(Self.description(of: reason))")

            case .configuredPathMissing(let url):
                Text("Configured Homebrew path no longer exists")
                    .font(.headline)
                Text("Path: \(url.path)")

            case .absent:
                Text("Homebrew not found")
                    .font(.headline)
                if let guidance = state.installGuidance {
                    Text("Install it from \(guidance.website.absoluteString)")
                    Text(guidance.installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private static func description(of prefix: BrewPrefix) -> String {
        switch prefix {
        case .appleSilicon: "/opt/homebrew (Apple Silicon)"
        case .intelCarryOver: "/usr/local (Intel carry-over)"
        case .custom(let url): "custom — \(url.path)"
        }
    }

    private static func description(of reason: BrewValidationError) -> String {
        switch reason {
        case .notExecutable:
            "the file is not an executable regular file"
        case .notHomebrew(_, let output):
            "--version did not report Homebrew: \(output)"
        case .versionTooOld(let found, let minimum):
            "Homebrew \(found.major).\(found.minor).\(found.patch) is older than the supported minimum \(minimum.major).\(minimum.minor).\(minimum.patch)"
        case .probeFailed(_, let message):
            "the binary could not be probed: \(message)"
        }
    }
}

#Preview {
    BrewDetectionSummary(state: .absent)
}
