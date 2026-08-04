import DiskUsage

public extension InstalledPackage {
    var formulaLinkState: FormulaLinkState {
        guard kind == .formula else { return .notApplicable }
        return linkedKeg.map(FormulaLinkState.linked) ?? .unlinked
    }
}
