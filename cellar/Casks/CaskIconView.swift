//
//  CaskIconView.swift
//  cellar
//

import AppKit
import Catalog
import SwiftUI

/// A cask's artwork in a rounded well — or Cellar's own letter tile while the
/// pipeline is looking and forever after when it finds nothing. The tile is a
/// designed answer, so there is no spinner and no empty square.
struct CaskIconView: View {
    let token: String
    let size: CGFloat
    let isKnownToken: Bool
    let iconLoader: CaskIconLoader
    /// `false` skips the remote pipeline entirely. The formula pages pass it:
    /// CaskFlow and App-Fair are cask-app registries, so a formula token
    /// would only buy a guaranteed miss per row — the letter tile *is* the
    /// designed answer there, not a fallback.
    var loadsRemote: Bool = true

    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.well)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                )
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.8, height: size * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            } else {
                PackageTile(
                    name: token,
                    size: size * 0.8,
                    fontSize: size * 0.34,
                    cornerRadius: size * 0.18
                )
            }
        }
        .frame(width: size, height: size)
        .task(id: token) {
            guard loadsRemote else { return }
            icon = await iconLoader.icon(for: token, isKnownToken: isKnownToken)
        }
    }
}

/// The front tile of a mixed formula-and-cask list: a cask gets the Discover
/// pages' artwork pipeline, a formula keeps the letter tile — CaskFlow and
/// App-Fair are cask-app registries, so a formula lookup can only miss.
///
/// The pipeline dependencies are optional so a preview, and any list that has
/// not been handed them, render the letter tile for everything — exactly what
/// those rows drew before artwork existed.
struct PackageIconTile: View {
    let id: PackageID
    var size: CGFloat = 36
    var fontSize: CGFloat = 14
    var cornerRadius: CGFloat = 7
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?

    var body: some View {
        if id.kind == .cask, let iconLoader {
            CaskIconView(
                token: id.name,
                size: size,
                isKnownToken: assets?.isKnownIconToken(id.name) ?? false,
                iconLoader: iconLoader
            )
        } else {
            PackageTile(
                name: id.name,
                size: size,
                fontSize: fontSize,
                cornerRadius: cornerRadius
            )
        }
    }
}
