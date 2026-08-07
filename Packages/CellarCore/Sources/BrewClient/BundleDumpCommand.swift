import BrewProcess
import Foundation

// MARK: - Threat response: subprocess file authority
//
// This file is the **entire** set of `brew bundle` invocations Cellar can
// construct, and it contains exactly one.
//
// Probe U8 established as fact that `brew bundle check --file <path>` evaluates
// the Brewfile's Ruby: a file whose only content was a `File.write` left its
// marker on disk after what a PRD would call a "read-only diff preview". Every
// `bundle` subcommand other than `dump` is therefore not merely unused here —
// it is **unrepresentable**, because `Subcommand` has no case for it and no
// source on this path spells the literal (`brewfile-management` BF1).
//
// `--file` takes a `URL` the caller constructed under a Cellar-owned temporary
// location. There is no string-taking initialiser, so a path obtained from a
// picker, a drag, a bookmark or an environment variable has no way in.

/// `brew bundle dump`, with the argv probe U6 pinned against the real binary.
public struct BundleDumpCommand: Sendable, Equatable {

    /// The only `bundle` subcommand this capability can name.
    ///
    /// `CaseIterable` with one case, so "there is no other subcommand" is a
    /// fact the compiler keeps rather than a list a reviewer has to re-check.
    /// The same technique `BulkSelection.Action` uses to make "no bulk pin,
    /// unpin, reinstall or zap exists" a property of the type.
    public enum Subcommand: String, Sendable, Equatable, CaseIterable {
        case dump
    }

    /// A path **this capability created** for this export.
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Pinned by probe U6 on Homebrew 6.0.15. The three positive type filters
    /// are what exclude `mas` and `vscode` entries from the exported file —
    /// they are load-bearing, not decoration.
    public var arguments: [String] {
        [
            "bundle", Subcommand.dump.rawValue,
            "--file", fileURL.path,
            "--force", "--formula", "--cask", "--tap"
        ]
    }

    /// A **read**. An export changes nothing installed, so it must not be
    /// serialised behind the mutation queue or counted as a mutation.
    public var brewCommand: BrewCommand { .read(arguments) }

    /// The command as a human reads it — and as they can paste it.
    public var displayCommand: String {
        "brew " + arguments.joined(separator: " ")
    }
}
