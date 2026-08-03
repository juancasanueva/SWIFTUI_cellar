@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// A `BrewMutating` conformer belonging to no capability at all.
///
/// Deliberately **not** `ServiceCommand`. The claim the spine makes is the
/// strong one — *anything* conforming may enter it — and testing that claim with
/// the one real second family would quietly weaken it to "services may enter".
/// It is also what lets Phases 8 and 9 be proven before Phase 11 exists.
///
/// Every projection is a stored property with a default, so a test states only
/// the one it is about.
struct ProbeMutation: BrewMutating, Equatable {
    var arguments: [String] = ["services", "start", "atuin"]
    var verb = "probeStart"
    var packageID: PackageID?
    var requiresConfirmation = false
    var invalidates: InvalidationScope = .services
}
