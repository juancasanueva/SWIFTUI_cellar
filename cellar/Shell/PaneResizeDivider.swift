//
//  PaneResizeDivider.swift
//  cellar
//

import AppKit
import SwiftUI

/// The hairline between the list pane and the detail pane, made draggable.
///
/// The visible line stays the design's half-point rule; the drag surface is a
/// wider invisible strip over it so the handle is grabbable without being seen.
struct PaneResizeDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    /// The pane width as it was when the drag began, so the translation is
    /// applied to one stable base rather than compounding per event.
    @State private var dragBase: Double?

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 0.5)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragBase ?? width
                                dragBase = base
                                width = (base + value.translation.width)
                                    .clamped(to: range)
                            }
                            .onEnded { _ in dragBase = nil }
                    )
            }
            .accessibilityIdentifier("pane-resize-divider")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
