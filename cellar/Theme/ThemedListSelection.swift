//
//  ThemedListSelection.swift
//  cellar
//

import AppKit
import SwiftUI

/// The design's list selection — an accent tint in a rounded pill — on a
/// native `List(selection:)`.
///
/// AppKit paints list selection itself, in the system accent, over any row
/// background and beyond the reach of any SwiftUI tint. Rather than giving up
/// native selection (multi-select, arrow keys, accessibility), this modifier
/// switches the backing table's own painting off and draws the design's pill
/// as the row background. Selection *behaviour* is untouched: rows still
/// select, `selectedRowIndexes` still tracks, and XCUITest still reads
/// `isSelected`.
struct ThemedListSelection: ViewModifier {
    let isSelected: Bool
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        content
            .background(SelectionHighlightHider())
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.tint(0.16) : .clear)
                    .padding(.horizontal, 8)
            )
    }
}

extension View {
    /// Marks a list row as drawing the design's own selection. Pass the row's
    /// selected state; the native highlight is suppressed table-wide.
    func themedListSelection(isSelected: Bool) -> some View {
        modifier(ThemedListSelection(isSelected: isSelected))
    }
}

/// An invisible, non-interactive view that finds the enclosing table and turns
/// its selection painting off. Idempotent, so every row may carry one.
private struct SelectionHighlightHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class HiderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var candidate: NSView? = self
            while let view = candidate {
                if let table = view as? NSTableView {
                    table.selectionHighlightStyle = .none
                    return
                }
                candidate = view.superview
            }
        }
    }
}
