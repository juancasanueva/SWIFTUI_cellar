//
//  SectionHeader.swift
//  cellar
//

import SwiftUI

/// The design's uppercase section label, shared by the detail panes.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.34))
            .padding(.top, 4)
    }
}
