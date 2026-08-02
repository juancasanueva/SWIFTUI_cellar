//
//  ActivityLogView.swift
//  cellar
//

import BrewClient
import BrewProcess
import SwiftUI

/// One operation's output, as it arrives.
///
/// Lines are rendered exactly as `BrewProcess` read them: no trimming, no
/// re-encoding, no reordering, no deduplication and no prefixing
/// (operation-activity OA3). The only thing this view adds is a colour for
/// stderr and — when the ring has evicted something — an honest note saying so.
struct ActivityLogView: View {
    let item: ActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isLogTruncated {
                Label(
                    "Earlier output was dropped; showing the most recent "
                        + "\(ActivityItem.logCapacity) lines.",
                    systemImage: "scissors"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if item.log.isEmpty {
                Text("No output yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                logLines
            }
        }
        .padding(.leading, 24)
    }

    private var logLines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(item.log, id: \.sequence) { line in
                        Text(line.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(line.stream == .stderr ? Color.orange : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.sequence)
                    }
                }
                .padding(6)
            }
            .frame(height: 140)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: item.log.count) {
                guard let last = item.log.last else { return }
                proxy.scrollTo(last.sequence, anchor: .bottom)
            }
        }
    }
}
