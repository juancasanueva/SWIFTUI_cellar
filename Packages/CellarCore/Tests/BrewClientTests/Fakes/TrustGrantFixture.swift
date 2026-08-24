import Foundation

/// The **measured** `brew trust --json v1` payload, byte-for-byte as Homebrew 6
/// published it on the maintainer's Mac (2026-08-24, Engram `#7764`).
///
/// It is captured rather than invented on purpose. PR #67's lesson is binding:
/// an invented fixture proves the decoder agrees with the person who wrote it,
/// not with `brew`. Every edge case `package-trust` PT4 rests on is a property
/// of these exact bytes:
///
/// - a URL-shaped `formulae` entry with four slashes and no `owner/repo` shape;
/// - `@` inside a package name (`guria/tap/nehir@rc`);
/// - `commands` present and **empty**, which is not the same fact as absent;
/// - the **same** qualified identifier in *both* `formulae` and `casks`
///   (`gentleman-programming/tap/engram`), so the namespaces are not disjoint.
enum TrustGrantFixture {
    static let measuredTaps = ["juancasanueva/cellar"]

    static let measuredFormulae = [
        "gentleman-programming/tap/engram",
        "gentleman-programming/tap/gentle-ai",
        "gentleman-programming/tap/gentleman-dots",
        "gentleman-programming/tap/gga",
        "https://github.com/cloudmanic/spice-edit/spice-edit",
        "jnsahaj/lumen/lumen",
        "kitlangton/tap/ghui",
        "letstri/tap/druk",
        "modem-dev/tap/hunk"
    ]

    static let measuredCasks = [
        "gentleman-programming/tap/engram",
        "guria/tap/nehir",
        "guria/tap/nehir@rc",
        "nkzw-tech/tap/codiff"
    ]

    /// 1 tap + 9 formulae + 4 casks + 0 commands.
    static let measuredEntryCount = 14

    /// The captured document, verbatim.
    static let measuredPayload = Data("""
    {
      "taps": ["juancasanueva/cellar"],
      "formulae": ["gentleman-programming/tap/engram","gentleman-programming/tap/gentle-ai",\
    "gentleman-programming/tap/gentleman-dots","gentleman-programming/tap/gga",\
    "https://github.com/cloudmanic/spice-edit/spice-edit","jnsahaj/lumen/lumen",\
    "kitlangton/tap/ghui","letstri/tap/druk","modem-dev/tap/hunk"],
      "casks": ["gentleman-programming/tap/engram","guria/tap/nehir","guria/tap/nehir@rc",\
    "nkzw-tech/tap/codiff"],
      "commands": []
    }
    """.utf8)
}
