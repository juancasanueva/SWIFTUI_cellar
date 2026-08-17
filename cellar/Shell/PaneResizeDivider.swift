//
//  PaneResizeDivider.swift
//  cellar
//

import AppKit
import SwiftUI

/// The line between the list pane and the detail pane, made draggable.
///
/// A full point at the border tone rather than the half-point hairline: the
/// panes it separates share one dark ground, and a divider nobody can see is a
/// handle nobody can find. Hovering the grab strip brightens it, so the line
/// answers "where do I drag?" the moment the cursor asks.
struct PaneResizeDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    /// The pane width as it was when the drag began, so the translation is
    /// applied to one stable base rather than compounding per event.
    @State private var dragBase: Double?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.white.opacity(0.22) : Theme.border)
            .frame(width: 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        isHovering = inside
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
