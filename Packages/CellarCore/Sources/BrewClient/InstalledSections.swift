import Catalog
import Foundation

/// How the installed list groups its packages, and therefore the order it shows
/// them in.
///
/// One projection, read twice: the sections that render and the order a bulk
/// selection enters. They were three private computeds in the view while the
/// selection appended in flat inventory order, so a select-all submitted its
/// operations in an order the user never saw. Rendering and selection order
/// cannot drift again because there is only one answer now — the `upgradableIDs`
/// precedent (installed-inventory II14, design D9).
///
/// The section *names* belong to the view. This owns the partition and the
/// order, which is what the requirement is about.
public struct InstalledSections: Sendable, Equatable {
    /// Behind their published version and worth acting on.
    public let outdated: [PackageEntry]
    /// Apps that update themselves. Separate on purpose: presenting them as
    /// outdated would ask the user to fix something that is not broken.
    public let selfUpdating: [PackageEntry]
    /// Everything else, in inventory order.
    public let rest: [PackageEntry]

    /// Partitions `entries`, preserving each section's relative inventory order.
    ///
    /// A chain rather than three independent filters, so every entry lands in
    /// exactly one section and `displayed` can never gain or lose a row against
    /// what is rendered. `outdatedIDs` is supplied because the eligible set is
    /// already narrowed by snoozes upstream, and this must not re-derive it.
    public init(entries: [PackageEntry], outdatedIDs: Set<PackageID>) {
        var outdated: [PackageEntry] = []
        var selfUpdating: [PackageEntry] = []
        var rest: [PackageEntry] = []
        for entry in entries {
            if outdatedIDs.contains(entry.id) {
                outdated.append(entry)
            } else if entry.installed?.hasNewerVersion == true {
                selfUpdating.append(entry)
            } else {
                rest.append(entry)
            }
        }
        self.outdated = outdated
        self.selfUpdating = selfUpdating
        self.rest = rest
    }

    /// Every entry in the order the list shows it: section by section from top
    /// to bottom, and within each section in that section's displayed order.
    public var displayed: [PackageEntry] { outdated + selfUpdating + rest }
}
