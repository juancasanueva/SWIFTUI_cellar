//
//  BrewfileExportSheet.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
import SwiftUI

/// The Brewfile this Mac would produce, before it is written anywhere.
///
/// The ordering is the security property, not a nicety: **dump, then preview,
/// then panel, then publish** (design DD3). The save panel is offered only once
/// `exportState` is `.preview`, so a failed dump can never reach the user's
/// disk, and the `--force` in the pinned argv can never point at a file the user
/// owns — it only ever points at the temporary path `BundleDumpSource` created
/// for this export and removes afterwards.
///
/// This sheet constructs no `brew` invocation. It cannot: the argv lives in
/// `BundleDumpCommand`, and the only thing reachable from here is the store.
struct BrewfileExportSheet: View {
    let store: BrewfileStore
    let source: any BundleDumpSourcing
    let detection: BrewDetectionState
    var destination: any BrewfileDestinationChoosing = BrewfileDestinationPanel()

    @Environment(\.dismiss) private var dismiss

    private var presentation: BrewfileExportPresentation {
        BrewfileExportPresentation(state: store.exportState)
    }

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
        .task {
            // Runs once, when the sheet appears. Nothing else starts a dump.
            guard case .idle = store.exportState else { return }
            await store.export(using: source, detection: detection)
        }
    }

    /// No identifier on the root container: one there **replaces** every
    /// descendant's own identifier outside a `List`, which would leave the Save
    /// button unaddressable. The headline carries the sheet's name instead.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.headline)
                .font(.title3.bold())
                .accessibilityIdentifier("brewfile-export-headline")
            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("brewfile-export-detail")
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentation.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking Homebrew what is installed…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let text = presentation.documentText {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("brewfile-export-document")
            }
        } else {
            ContentUnavailableView(
                presentation.headline,
                systemImage: presentation.isFailure ? "exclamationmark.triangle" : "doc.text",
                description: Text(presentation.detail)
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save…") {
                Task { await store.publish(to: destination) }
            }
            // The gate. No preview, no panel.
            .disabled(presentation.canPublish == false)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("brewfile-export-save-button")
        }
    }
}

/// One export state, as text and as two gates.
///
/// A value type rather than a `switch` inside `body`, so "the panel opens only
/// after a successful preview" is one assertion over a value instead of a claim
/// about pixels.
struct BrewfileExportPresentation: Equatable {
    let state: BrewfileStore.ExportState

    init(state: BrewfileStore.ExportState) {
        self.state = state
    }

    /// Whether there are bytes to write. This is the whole DD3 ordering rule.
    var canPublish: Bool {
        if case .preview = state { return true }
        return false
    }

    var isRunning: Bool {
        if case .dumping = state { return true }
        return false
    }

    var isPublished: Bool {
        if case .published = state { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    /// The document's bytes as text, and nothing else — no header, no footer, no
    /// provenance line. `nil` whenever there is no document.
    var documentText: String? {
        guard case .preview(let document) = state else { return nil }
        return String(decoding: document, as: UTF8.self)
    }

    var headline: String {
        switch state {
        case .idle: "Export a Brewfile"
        case .dumping: "Building your Brewfile"
        case .preview: "Ready to save"
        case .published: "Saved"
        case .failed: "Could not build a Brewfile"
        }
    }

    var detail: String {
        switch state {
        case .idle:
            "Cellar will ask Homebrew for a Brewfile and show it before anything is written."
        case .dumping:
            "Nothing has been written yet."
        case .preview(let document):
            "\(Self.lineCount(of: document)) lines, exactly as Homebrew wrote them. "
                + "Choose where to save them."
        case .published(let destination):
            "Written to \(destination.path)."
        case .failed(let error):
            Self.sentence(for: error)
        }
    }

    /// Counts the document's lines without re-encoding it: the preview must
    /// describe the bytes, never alter them.
    private static func lineCount(of document: Data) -> Int {
        String(decoding: document, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.isEmpty == false }
            .count
    }

    /// Both raw streams survive to here, so a user is told what brew actually
    /// said rather than "it failed".
    static func sentence(for error: BrewfileExportError) -> String {
        switch error {
        case .publicationFailed(let destination, let reason):
            "Cellar could not write to \(destination.path): \(reason). "
                + "Anything already there is unchanged."
        case .dumpFailed(let dump):
            sentence(for: dump)
        }
    }

    static func sentence(for error: BundleDumpError) -> String {
        switch error {
        case .unavailable:
            "Homebrew is not available."
        case .commandFailed(let status, _, let rawStderr):
            "Homebrew exited with status \(status). "
                + (Self.text(rawStderr) ?? "It reported nothing on its error stream.")
        case .launchFailed:
            "Cellar could not start Homebrew."
        case .cancelled:
            "The export was cancelled."
        case .documentUnreadable:
            "Homebrew reported success, but Cellar could not read the file it wrote."
        }
    }

    private static func text(_ raw: Data) -> String? {
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
