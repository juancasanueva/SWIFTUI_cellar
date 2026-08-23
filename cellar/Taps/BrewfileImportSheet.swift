//
//  BrewfileImportSheet.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// What a Brewfile means for this machine, and what Cellar would do about it.
///
/// Presentation only. Every decision this sheet appears to make was made in
/// `CellarCore`: which rows exist and which of the three states each is in
/// (`BrewfileDiff`), which of them can be selected (`BrewfileDiff.Row`
/// `isSelectable`), and what a selection expands to (`BrewfilePlan`). The sheet
/// cannot construct a `brew` invocation, cannot move a present or skipped row
/// into the selection, and never reads the file again.
///
/// The two sentences it must not invent are `BrewfileDiff.attribution` — this is
/// Cellar's reading, not Homebrew's verdict — and `BrewfileTrustClaim.attribution`,
/// which is what keeps a `trusted:` option a claim by the file's author rather
/// than a grant.
struct BrewfileImportSheet: View {
    let store: BrewfileStore
    let operations: OperationCenter

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
    }

    // MARK: - Header

    /// The sheet's identifier lives on the title rather than on the root
    /// container, and that is not a style choice. An identifier applied to a
    /// container **replaces** its descendants' own identifiers everywhere the
    /// hierarchy is not broken by a `List` — so a root-level one left the
    /// footer's Import button unaddressable and every header line reporting the
    /// sheet's name. Recorded as an apply-time amendment.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Import a Brewfile")
                .font(.title3.bold())
                .accessibilityIdentifier("brewfile-import-sheet")
            // Never "Homebrew says". Nothing here asked Homebrew anything.
            Text(BrewfileDiff.attribution)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("brewfile-import-attribution")
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch store.importState {
        case .idle:
            ContentUnavailableView(
                "No file chosen",
                systemImage: "doc.text",
                description: Text("Choose a Brewfile to see what it would install.")
            )
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the file…").foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("brewfile-import-reading")
        case .failed(let error):
            ContentUnavailableView(
                "Could not read that file",
                systemImage: "exclamationmark.triangle",
                description: Text(BrewfileImportSummaryCopy.sentence(for: error))
            )
            .accessibilityIdentifier("brewfile-import-failed")
        case .parsed(let diff):
            parsed(diff)
        }
    }

    @ViewBuilder
    private func parsed(_ diff: BrewfileDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BrewfileImportSummaryCopy.sentence(for: diff.summary))
                .font(.subheadline)
                .accessibilityIdentifier("brewfile-import-summary")

            List {
                Section("Entries") {
                    ForEach(BrewfileImportRow.rows(for: diff)) { row in
                        entry(row, diff: diff)
                    }
                }

                let groups = BrewfileSkipGroup.groups(for: diff)
                if groups.isEmpty == false {
                    Section("Skipped") {
                        ForEach(groups) { group in
                            skip(group)
                        }
                    }
                }
            }
            .accessibilityIdentifier("brewfile-import-list")
        }
    }

    /// A missing row is a toggle; a present or skipped row is text. The
    /// difference is `row.isSelectable`, which is the diff's rule and not this
    /// view's.
    @ViewBuilder
    private func entry(_ row: BrewfileImportRow, diff: BrewfileDiff) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { diff.selection.contains(row.id) },
                    set: { _ in store.toggle(row.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let fileToken = row.fileToken {
                        Text("In the file as \(fileToken)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("brewfile-import-file-token")
                    }
                    if let claim = row.trustClaim {
                        Text(claim)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("brewfile-import-trust-claim")
                    }
                }
            }
            .disabled(row.isSelectable == false)
        }
        .accessibilityIdentifier("brewfile-import-row-\(row.id)")
    }

    @ViewBuilder
    private func skip(_ group: BrewfileSkipGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.headline)
                .accessibilityIdentifier("brewfile-skip-headline-\(group.id)")
            Text(group.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("brewfile-skip-reason-\(group.id)")
            if let detail = group.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(group.lines)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let diff = store.diff {
                Button("Select all") { store.selectAllMissing() }
                    .disabled(diff.missing.isEmpty)
                Button("Select none") { store.deselectAll() }
                    .disabled(diff.selection.isEmpty)
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Import") {
                BrewfileImportAction.apply(store, through: operations)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            // Driven by the selection, never by the skip count: a file that
            // produced skips imports on exactly the same terms as one that did
            // not.
            .disabled(store.canImport == false || operations.isAvailable == false)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("brewfile-import-button")
        }
    }
}

/// Submitting an import, as one function over the two stores.
///
/// Extracted from `body` so the composition guard can assert it without
/// rendering anything — and so "exactly one confirmation, carrying the tapAdd
/// disclosure" is provable against a real `OperationCenter`.
///
/// It mirrors `submitBulk`'s shape exactly: ask first, and treat "no request" as
/// "submit directly", so no caller restates which verbs are destructive.
enum BrewfileImportAction {
    @MainActor
    @discardableResult
    static func apply(
        _ store: BrewfileStore,
        through center: OperationCenter
    ) -> OperationCenter.ConfirmationRequest? {
        guard let plan = store.plan, plan.isEmpty == false else { return nil }
        let commands = plan.commands
        if let request = center.request(commands) { return request }
        for command in commands { center.submit(command) }
        return nil
    }
}

/// One row of the diff, as text.
struct BrewfileImportRow: Identifiable, Equatable {
    let id: Int
    let state: BrewfileDiff.State
    /// The token that will actually be installed, or a skipped line exactly as
    /// it was read.
    let title: String
    let detail: String
    /// The file's own token, shown only when it differs from what will run —
    /// which happens when a `/`-qualified entry is installed by its bare token
    /// (**D3**). Nothing here claims anything about trust.
    let fileToken: String?
    let isSelectable: Bool
    /// The attribution sentence, when the line carried a `trusted:` option.
    let trustClaim: String?

    static func rows(for diff: BrewfileDiff) -> [BrewfileImportRow] {
        diff.rows.map(BrewfileImportRow.init)
    }

    init(_ row: BrewfileDiff.Row) {
        id = row.id
        state = row.state
        isSelectable = row.isSelectable

        switch row {
        case .missing(let entry), .present(let entry):
            // The row's title is the token that will appear in argv, so what the
            // user reads before applying is what will run.
            title = entry.installName ?? entry.displayName
            fileToken = title == entry.displayName ? nil : entry.displayName
            detail = "\(Self.kind(of: entry)) · \(Self.status(of: entry, state: row.state))"
            trustClaim = entry.trustedClaim == nil ? nil : BrewfileTrustClaim.attribution
        case .skipped(let skip):
            title = skip.rawLine
            fileToken = nil
            detail = "Line \(skip.lineNumber) · \(BrewfileSkipCopy.reason(for: skip.reason.category))"
            trustClaim = nil
        }
    }

    private static func kind(of entry: BrewfileEntry) -> String {
        switch entry.kind {
        case .tap: "Tap"
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }

    /// A tap is "added", a package is "installed". Saying "installed" about a
    /// tap would be wrong in the one place a user is deciding whether to trust
    /// one.
    private static func status(of entry: BrewfileEntry, state: BrewfileDiff.State) -> String {
        switch (entry.kind, state) {
        case (.tap, .present): "already added"
        case (.tap, _): "not added"
        case (_, .present): "already installed"
        default: "not installed"
        }
    }
}

/// Skips, grouped by category, counted, and named.
///
/// Grouping switches on `BrewfileSkipReason.Category` and never on free text,
/// which is what `brewfile-management` BF4 requires of a consumer. The detail is
/// read only to render.
struct BrewfileSkipGroup: Identifiable, Equatable {
    let category: BrewfileSkipReason.Category
    let count: Int
    /// What each skip in this group named, unique and sorted. `nil` for the
    /// categories that name nothing.
    let detail: String?
    let lines: String

    var id: String { category.rawValue }
    var headline: String { "\(count) \(count == 1 ? "line" : "lines") skipped" }
    var reason: String { BrewfileSkipCopy.reason(for: category) }

    static func groups(for diff: BrewfileDiff) -> [BrewfileSkipGroup] {
        let grouped = Dictionary(grouping: diff.skips, by: { $0.reason.category })
        return BrewfileSkipReason.Category.allCases.compactMap { category in
            guard let skips = grouped[category], skips.isEmpty == false else { return nil }
            let details = Set(skips.compactMap(\.reason.detail)).sorted()
            let numbers = skips.map(\.lineNumber).sorted()
            return BrewfileSkipGroup(
                category: category,
                count: skips.count,
                detail: details.isEmpty ? nil : details.joined(separator: ", "),
                lines: (numbers.count == 1 ? "Line " : "Lines ")
                    + numbers.map(String.init).joined(separator: ", ")
            )
        }
    }
}

/// Why a line was skipped, in words.
///
/// Named constants rather than view copy, so the wording is assertable in the
/// test suite and reviewable in one place. Every sentence answers the question a
/// user actually has when they read "3 lines skipped": *why*, without opening
/// the file.
enum BrewfileSkipCopy {
    static func reason(for category: BrewfileSkipReason.Category) -> String {
        switch category {
        case .unsupportedEntryKind:
            "Cellar installs Homebrew formulae, casks and taps only."
        case .unsupportedOption:
            "Carried an option Cellar does not apply. Installing without it would not be what the file asked for."
        case .rubyConditional:
            "Carried a Ruby condition. Cellar reads a Brewfile as text and never runs it."
        case .unrepresentableName:
            "Named something Cellar will not pass to Homebrew."
        case .unrecognisedLine:
            "Cellar has no reading for this line."
        case .undecodableBytes:
            "Was not valid text."
        }
    }
}

/// What kind of nothing, when there is nothing to do — and what kind of failure,
/// when reading failed.
enum BrewfileImportSummaryCopy {
    static func sentence(for summary: BrewfileDiff.Summary) -> String {
        switch summary {
        case .nothingInTheFile:
            "This file lists nothing at all."
        case .everythingAlreadyPresent:
            "Everything in this file is already on this Mac."
        case .everythingSkipped:
            "Nothing in this file is something Cellar installs."
        case .actionable:
            "Choose what to install. Everything missing is selected."
        }
    }

    static func sentence(for error: BrewfileImportError) -> String {
        switch error {
        case .unreadable(let url):
            "Cellar could not read \(url.lastPathComponent)."
        case .tooLarge(let bytes, let limit):
            "That file is \(bytes) bytes. Cellar reads a Brewfile up to \(limit) bytes."
        }
    }
}
