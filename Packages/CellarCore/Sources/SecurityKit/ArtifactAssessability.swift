import Catalog
import Foundation

/// What kind of thing an assessable artifact turned out to be.
///
/// Two shapes, because the platform assesses two shapes: a code bundle, and a
/// Mach-O image on its own. Anything else is out of scope, and out of scope is
/// spelled `nil` rather than a third case — a `.notAssessable` case would be a
/// value that has to be filtered somewhere, and the somewhere is where it would
/// eventually be forgotten.
public enum AssessableArtifactKind: String, Sendable, Hashable, Codable, CaseIterable {
    case bundle
    case machO
}

/// Whether a path is worth asking Security.framework about.
///
/// A pure filesystem predicate, and deliberately a narrow one. A keg is dominated
/// by headers, man pages, completion scripts and symlinks into `libexec/`, none
/// of which carries a signature; a walk that asked about all of them would be
/// unbounded and would spend its time proving that a manual page is not signed.
public enum ArtifactAssessability {
    /// The bundle extensions the platform treats as code bundles.
    public static let bundleExtensions: Set<String> = ["app", "framework", "xpc", "bundle"]

    /// Mach-O magic **as the four bytes appear on disk**.
    ///
    /// Not as `UInt32` constants, and that distinction is load-bearing. A real
    /// brew-installed arm64 executable begins `cf fa ed fe`, which is
    /// `0xfeedfacf` read little-endian; a predicate comparing a host-order
    /// `UInt32` against `0xfeedfacf` matches nothing on this machine. Measured
    /// against `/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg` during the U3 probe
    /// and pinned by `MachO/ripgrep-header-64.bin`.
    ///
    /// Both byte orders of each thin magic are listed, and both of the fat magic,
    /// so the set is exhaustive over what can actually be on disk rather than
    /// over what this architecture happens to produce.
    static let machOMagics: Set<[UInt8]> = [
        [0xce, 0xfa, 0xed, 0xfe],  // MH_MAGIC     0xfeedface, little-endian
        [0xfe, 0xed, 0xfa, 0xce],  // MH_MAGIC     0xfeedface, big-endian
        [0xcf, 0xfa, 0xed, 0xfe],  // MH_MAGIC_64  0xfeedfacf, little-endian
        [0xfe, 0xed, 0xfa, 0xcf],  // MH_MAGIC_64  0xfeedfacf, big-endian
        [0xca, 0xfe, 0xba, 0xbe],  // FAT_MAGIC    0xcafebabe, big-endian
        [0xbe, 0xba, 0xfe, 0xca]   // FAT_CIGAM    0xbebafeca
    ]

    /// What this path is, or `nil` if it is nothing this capability assesses.
    ///
    /// **Symlinks are always `nil`**, whatever they point at. Following them
    /// would report one binary once per link that reaches it — a keg's `bin/` is
    /// full of links into `libexec/` — and, on the cask side, nine of the ten
    /// Caskroom `.app` entries measured during the U3 probe are links into
    /// `/Applications`. Resolution is the locator's job, done **once** against
    /// the path Homebrew itself recorded; doing it here would turn an explicit
    /// step into an implicit one and quietly widen the scope.
    public static func classify(_ url: URL) -> AssessableArtifactKind? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else { return nil }

        switch type {
        case .typeSymbolicLink:
            return nil
        case .typeDirectory:
            return isCodeBundle(url) ? .bundle : nil
        case .typeRegular:
            return hasMachOMagic(url) ? .machO : nil
        default:
            return nil
        }
    }

    /// A bundle-shaped name **and** something runnable inside it.
    ///
    /// The name alone is not enough: the U3 probe found a Caskroom
    /// `The Unarchiver.app` that is a directory with no `Contents/MacOS` at all,
    /// and `SecStaticCodeCreateWithPath` answers `-67028 bundle format
    /// unrecognized` for it. Refusing it here means the inspector is never handed
    /// something the platform will reject.
    private static func isCodeBundle(_ url: URL) -> Bool {
        guard bundleExtensions.contains(url.pathExtension) else { return false }
        let macOS = url.appendingPathComponent("Contents/MacOS")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: macOS.path) else {
            return false
        }
        return entries.isEmpty == false
    }

    /// Reads exactly four bytes, and only four.
    ///
    /// A keg holds multi-megabyte executables and the question is answered by the
    /// header, so the whole file is never mapped in to ask it.
    private static func hasMachOMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        return machOMagics.contains(Array(head))
    }
}

/// One artifact worth assessing, and the package it belongs to.
///
/// The initialiser is failable and classifies as it constructs, so "everything
/// the engine was handed had been classified" is true **by construction**. A
/// separate `classify`-then-build pair would let one call site skip the filter,
/// and that call site is how `/Applications` ends up in a sweep.
public struct ArtifactLocation: Sendable, Hashable, Identifiable {
    public let packageID: PackageID
    public let url: URL
    public let kind: AssessableArtifactKind

    public var id: URL { url }

    public init?(packageID: PackageID, url: URL) {
        guard let kind = ArtifactAssessability.classify(url) else { return nil }
        self.packageID = packageID
        self.url = url
        self.kind = kind
    }

    /// For values that were already classified — a decoded fixture, a test
    /// arrangement — where re-touching the filesystem would be the wrong thing to
    /// assert against.
    public init(packageID: PackageID, url: URL, kind: AssessableArtifactKind) {
        self.packageID = packageID
        self.url = url
        self.kind = kind
    }
}
