import Catalog
import Foundation
import Testing

@testable import DiskUsage

/// Where a measured version lives on disk, derived from the roots the
/// snapshot was taken against — the same roots the engine walked, so the
/// answer is the directory it measured rather than a guess made later.
@Suite("Disk locations")
struct DiskLocationTests {
    private static let withNpm = DiskRootsIdentity(
        cellar: "/opt/homebrew/Cellar",
        caskroom: "/opt/homebrew/Caskroom",
        cache: "/Users/test/Library/Caches/Homebrew",
        npmGlobals: "/opt/homebrew/lib/node_modules"
    )
    private static let withoutNpm = DiskRootsIdentity(
        cellar: "/opt/homebrew/Cellar",
        caskroom: "/opt/homebrew/Caskroom",
        cache: "/Users/test/Library/Caches/Homebrew"
    )

    private static func version(_ kind: PackageKind, _ name: String, _ raw: String) -> DiskVersionUsage {
        let id = PackageID(kind: kind, name: name)
        return DiskVersionUsage(
            id: DiskVersionID(package: id, rawVersion: raw),
            observation: .zero,
            linkState: .notApplicable
        )
    }

    @Test("A formula version is its keg under the Cellar")
    func formulaIsAKeg() {
        let url = Self.withNpm.location(of: Self.version(.formula, "wget", "1.25.0"))
        #expect(url?.path == "/opt/homebrew/Cellar/wget/1.25.0")
    }

    @Test("A cask version is its directory under the Caskroom")
    func caskIsUnderTheCaskroom() {
        let url = Self.withNpm.location(of: Self.version(.cask, "ghostty", "1.0.1"))
        #expect(url?.path == "/opt/homebrew/Caskroom/ghostty/1.0.1")
    }

    @Test("An npm package is its directory under the globals, with no version component")
    func npmIsUnderTheGlobals() {
        let url = Self.withNpm.location(of: Self.version(.npm, "typescript", "5.9.2"))
        #expect(url?.path == "/opt/homebrew/lib/node_modules/typescript")
    }

    @Test("A scoped npm package is two path components under the globals")
    func scopedNpmIsTwoComponents() {
        let url = Self.withNpm.location(of: Self.version(.npm, "@angular/cli", "20.1.0"))
        #expect(url?.path == "/opt/homebrew/lib/node_modules/@angular/cli")
        #expect(url?.pathComponents.suffix(2) == ["@angular", "cli"])
    }

    @Test("Without configured globals an npm package has no location")
    func npmWithoutGlobalsIsNil() {
        #expect(Self.withoutNpm.location(of: Self.version(.npm, "typescript", "5.9.2")) == nil)
        // The brew kinds are unaffected by npm being off.
        #expect(Self.withoutNpm.location(of: Self.version(.formula, "wget", "1.25.0"))?.path == "/opt/homebrew/Cellar/wget/1.25.0")
    }
}
