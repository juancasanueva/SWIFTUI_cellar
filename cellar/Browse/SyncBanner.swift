//
//  SyncBanner.swift
//  cellar
//

import Catalog
import SwiftUI

/// The strip above the Browse list that explains why it looks the way it does.
///
/// Shows nothing when there is nothing to say. It never replaces the list: a
/// failed refresh with 16,000 cached records still shows the 16,000 records, and
/// says so above them (catalog-sync CS4, CS8).
struct SyncBanner: View {
    let status: CatalogSyncStatus
    let packageCount: Int
    let onRetry: () -> Void

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if status.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if case .failed = status {
                    Button("Retry", action: onRetry)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
        }
    }

    /// `nil` means "say nothing" — a quiet, up-to-date catalog needs no banner.
    private var message: String? {
        switch status {
        case .idle, .succeeded:
            packageCount == 0 ? "No catalog yet. It will download shortly." : nil
        case .downloading, .decoding:
            packageCount == 0
                ? "\(status.shortDescription) This is the first run, so it takes a moment."
                : status.shortDescription
        case .failed:
            packageCount == 0
                ? status.shortDescription
                : "\(status.shortDescription) Showing the last catalog that downloaded."
        }
    }
}

#Preview("First run") {
    SyncBanner(status: .downloading(fractionCompleted: nil), packageCount: 0) {}
}

#Preview("Failed with a cache") {
    SyncBanner(status: .failed(.offline), packageCount: 16_200) {}
}
