//
//  CaskIconView.swift
//  cellar
//

import AppKit
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
