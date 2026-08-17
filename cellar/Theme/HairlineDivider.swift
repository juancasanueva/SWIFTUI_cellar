//
//  HairlineDivider.swift
//  cellar
//

import SwiftUI

/// The design's hairline, exactly one device pixel tall on any display.
///
/// A 0.5-point rectangle is half a pixel on a 1x display, so whether a given
/// line renders depends on where the layout happens to land it: on a pixel
/// boundary it draws, between two it antialiases away — which showed up as
/// row separators appearing only every second row. `1 / displayScale` is one
/// physical pixel everywhere: 1pt at 1x, the design's 0.5pt at 2x.
struct HairlineDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1 / max(displayScale, 1))
    }
}
