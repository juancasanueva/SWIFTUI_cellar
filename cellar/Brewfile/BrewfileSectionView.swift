//
//  BrewfileSectionView.swift
//  cellar
//

import AppKit
import BrewClient
import BrewProcess
import Catalog
import SwiftUI

/// The Brewfile as a place of its own, per the design document: the current
/// state as text, an export card, and an import card.
///
/// Everything mutating still flows through the same `BrewfileStore` the Taps
/// section uses — this section adds a surface, not a second pipeline. The dump
/// runs once on appearance so the well shows the real document; export and
/// import keep the sheet flows that already carry their guarantees (DD3, DD4).
struct BrewfileSectionView: View {
    let taps: TapStore
    let installed: InstalledStore
    let detection: BrewDetectionState
    let operations: OperationCenter
    var sourceChooser: any BrewfileSourceChoosing = BrewfileSourcePanel()
    var dumpSource: any BundleDumpSourcing = BundleDumpSource()

    @State private var brewfile = BrewfileStore()
    @State private var isImportPresented = false
    @State private var isExportPresented = false
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Brewfile")
                    .font(.system(size: 27, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    "A plain-text list of every tap, formula and cask you have. "
                        + "Keep it in a dotfiles repo and a new Mac is one command away."
                )
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.top, 7)

                HStack(spacing: 10) {
                    Text("Current state")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(currentState)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                .padding(.top, 22)

                document
                    .padding(.top, 11)

                HStack(alignment: .top, spacing: 12) {
                    exportCard
                    importCard
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.top, 20)
            }
            .padding(EdgeInsets(top: 28, leading: 34, bottom: 44, trailing: 34))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .sheet(isPresented: $isImportPresented) {
            BrewfileImportSheet(store: brewfile, operations: operations)
        }
        .sheet(isPresented: $isExportPresented) {
            BrewfileExportSheet(store: brewfile, source: dumpSource, detection: detection)
        }
        .task {
            // One dump per visit, so the well shows the document this Mac would
            // actually export. Nothing else starts one.
            guard case .idle = brewfile.exportState else { return }
            await brewfile.export(using: dumpSource, detection: detection)
        }
    }

    private var currentState: String {
        let tapCount = taps.inventory.taps.count
        let packages = installed.inventory.packages
        let formulae = packages.filter { $0.id.kind == .formula }.count
        let casks = packages.filter { $0.id.kind == .cask }.count
        return "\(tapCount) taps · \(formulae) formulae · \(casks) casks"
    }

    @ViewBuilder
    private var document: some View {
        let presentation = BrewfileExportPresentation(state: brewfile.exportState)
        ScrollView {
            Group {
                if let text = presentation.documentText {
                    Text(text)
                        .font(Theme.mono(12))
                        .foregroundStyle(Color(designHex: 0xC9CED4))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else if presentation.isRunning {
                    Text("Asking Homebrew what is installed…")
                        .font(Theme.mono(12))
                        .foregroundStyle(Color.white.opacity(0.4))
                } else {
                    Text(presentation.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        }
        .frame(height: 330)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .accessibilityIdentifier("brewfile-section-document")
    }

    private var exportCard: some View {
        card(
            title: "Export",
            body: "Write the list above to a file, or copy it to the clipboard."
        ) {
            HStack(spacing: 8) {
                cardButton("Save to file…", identifier: "brewfile-section-export") {
                    isExportPresented = true
                }
                .disabled(detection.installation == nil)
                cardButton("Copy", identifier: "brewfile-section-copy") {
                    guard
                        let text = BrewfileExportPresentation(state: brewfile.exportState)
                            .documentText
                    else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }

    private var importCard: some View {
        card(
            title: "Import",
            body: "You'll see a diff of what would be installed before anything runs. "
                + "Extras are never removed."
        ) {
            Button {
                Task { await beginImport() }
            } label: {
                Text("Open a Brewfile…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.windowBackground)
                    .padding(.horizontal, 13)
                    .frame(height: 29)
                    .background(theme.base, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(operations.isAvailable == false)
            .accessibilityIdentifier("brewfile-section-import")
        }
    }

    /// The panel first, then the sheet — `TapsListView.beginImport`'s ordering,
    /// for the same reason: cancelling presents nothing at all.
    private func beginImport() async {
        await brewfile.importFile(
            from: sourceChooser,
            installed: installed.inventory,
            taps: taps.inventory
        )
        guard brewfile.diff != nil || brewfile.importState != .idle else { return }
        isImportPresented = true
    }

    private func card(
        title: String,
        body: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(body)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Color.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .themeCard(radius: 10)
    }

    private func cardButton(
        _ label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: 29)
                .background(
                    Theme.controlFillLoud,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
