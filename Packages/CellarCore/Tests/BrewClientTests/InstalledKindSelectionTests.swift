import Testing

@testable import BrewClient
@testable import Catalog

/// The kind chips as toggles: every kind on by default, any combination
/// expressible, and never none.
@Suite("Installed kind selection")
struct InstalledKindSelectionTests {
    @Test("starts with every kind included")
    func startsWithEveryKind() {
        #expect(InstalledKindSelection().kinds == Set(PackageKind.allCases))
    }

    @Test("toggling removes and re-adds a kind")
    func togglesAKind() {
        var selection = InstalledKindSelection()
        selection.toggle(.cask, npmEnabled: true)
        #expect(selection.kinds == [.formula, .npm])
        selection.toggle(.cask, npmEnabled: true)
        #expect(selection.kinds == Set(PackageKind.allCases))
    }

    @Test("the last kind refuses to turn off")
    func refusesToEmpty() {
        var selection = InstalledKindSelection(kinds: [.formula])
        selection.toggle(.formula, npmEnabled: true)
        #expect(selection.kinds == [.formula])
    }

    @Test("with npm off, the last visible kind refuses to turn off even though npm is still selected")
    func refusesToEmptyTheVisibleChips() {
        var selection = InstalledKindSelection()
        selection.toggle(.cask, npmEnabled: false)
        #expect(selection.kinds == [.formula, .npm])
        selection.toggle(.formula, npmEnabled: false)
        #expect(selection.kinds == [.formula, .npm])
    }

    @Test("an npm-only selection collapses to every kind while npm is off")
    func npmOnlyCollapsesWhenNpmIsOff() {
        let selection = InstalledKindSelection(kinds: [.npm])
        #expect(selection.effective(npmEnabled: false) == Set(PackageKind.allCases))
        #expect(selection.effective(npmEnabled: true) == [.npm])
    }

    @Test("a mixed selection keeps its Homebrew kinds while npm is off")
    func mixedSelectionKeepsHomebrewKinds() {
        let selection = InstalledKindSelection(kinds: [.cask, .npm])
        #expect(selection.effective(npmEnabled: false) == [.cask])
    }

    @Test("names the single source in effect, or none")
    func sourceInEffect() {
        #expect(InstalledKindSelection(kinds: [.npm]).effectiveSource(npmEnabled: true) == .npm)
        #expect(InstalledKindSelection(kinds: [.formula, .cask]).effectiveSource(npmEnabled: true) == .homebrew)
        #expect(InstalledKindSelection(kinds: [.cask, .npm]).effectiveSource(npmEnabled: true) == nil)
        #expect(InstalledKindSelection(kinds: [.npm]).effectiveSource(npmEnabled: false) == nil)
    }
}
