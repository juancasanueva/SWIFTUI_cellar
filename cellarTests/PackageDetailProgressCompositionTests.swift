//
//  PackageDetailProgressCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing

/// The detail pane's Upgrade and Install buttons give way to progress feedback
/// while the package has an unsettled mutation. The rule itself is proven on
/// `OperationCenter.activeMutation(naming:)`; what only the composition can
/// claim is that each button actually reads it, in the shipped structural idiom.
@Suite("Package detail mutation progress")
struct PackageDetailProgressCompositionTests {
    @Test("Every Install button in the detail pane is replaced by progress while busy")
    func everyInstallButtonIsReplacedByProgressWhileBusy() throws {
        let detail = try ReceiptDetailSources.source(at: "cellar/Browse/PackageDetailView.swift")
        let lines = detail.code.components(separatedBy: "\n")

        let buttons = lines.indices.filter { index in
            lines[index].contains("identifier: \"detail-primary-install\"")
                || lines[index].contains("identifier: \"detail-action-install\"")
        }
        // Header primary, Actions row.
        #expect(buttons.count == 2)

        for button in buttons {
            let guardLine = lines[max(0, button - 3)..<button].joined(separator: "\n")
            #expect(
                guardLine.contains("operations.activeMutation(naming:"),
                "line \(button + 1) offers Install without checking for an in-flight mutation"
            )
        }
    }

    @Test("Every Upgrade button in the detail pane is replaced by progress while busy")
    func everyUpgradeButtonIsReplacedByProgressWhileBusy() throws {
        let detail = try ReceiptDetailSources.source(at: "cellar/Browse/PackageDetailView.swift")
        let lines = detail.code.components(separatedBy: "\n")

        let buttons = lines.indices.filter { index in
            lines[index].contains("identifier: \"detail-primary-upgrade\"")
                || lines[index].contains("identifier: \"detail-action-upgrade\"")
        }
        // Header primary, brew Actions row, npm Actions row.
        #expect(buttons.count == 3)

        for button in buttons {
            let guardLine = lines[max(0, button - 3)..<button].joined(separator: "\n")
            #expect(
                guardLine.contains("operations.activeMutation(naming:"),
                "line \(button + 1) offers Upgrade without checking for an in-flight mutation"
            )
        }

        #expect(detail.code.contains("ProgressView()"))
        #expect(detail.code.contains(".progressLabel"))
    }
}
