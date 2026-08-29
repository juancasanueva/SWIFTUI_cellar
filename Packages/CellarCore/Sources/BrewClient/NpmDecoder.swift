import Foundation

/// Reads npm's two JSON documents.
///
/// Pure functions over `Data`, decoded off the main actor by their callers, with
/// exactly one failure: `.malformedPayload`. Every rule about *exit codes* lives
/// in `NpmPayload`; by the time bytes arrive here they have already been
/// accepted as a document, and the only remaining question is whether they say
/// what they must.
///
/// Threat response — **untrusted subprocess payload**. Two rules, and the
/// tension between them is deliberate:
///
/// - keys npm adds that Cellar does not read are **ignored**. `overridden`,
///   `resolved`, `dependent`, `location` and a per-entry `problems` array all
///   appear in real captures, and refusing on an unrecognised key would let the
///   next npm release blank the list;
/// - the keys Cellar *does* read are **required**. An entry with no `version`,
///   or a report row with no `latest`, is malformed rather than skipped: a
///   silently dropped package is a package the user is not told about.
public enum NpmDecoder {
    /// The globals from `npm ls -g --json --depth=0`, ordered by name.
    ///
    /// The top-level `name`/`version` is the prefix's own record — `lib`, in
    /// every real capture — and never becomes an entry. An absent `dependencies`
    /// key is an empty inventory, not a malformed one: that is exactly what a
    /// prefix with nothing installed produces.
    public static func globals(from data: Data) throws(NpmInventoryError) -> [NpmGlobalPackage] {
        let document: ListingDocument
        do {
            document = try JSONDecoder().decode(ListingDocument.self, from: data)
        } catch {
            throw .malformedPayload
        }

        return document.dependencies
            .map { NpmGlobalPackage(name: $0.key, version: $0.value.version) }
            .sorted { $0.name < $1.name }
    }

    /// The report from `npm outdated -g --json`, keyed by package name.
    public static func outdated(
        from data: Data
    ) throws(NpmInventoryError) -> [String: NpmOutdatedRecord] {
        do {
            let rows = try JSONDecoder().decode([String: ReportRow].self, from: data)
            return rows.mapValues {
                NpmOutdatedRecord(current: $0.current, wanted: $0.wanted, latest: $0.latest)
            }
        } catch {
            throw .malformedPayload
        }
    }

    // MARK: - Wire shapes

    /// Only the two members that matter. Every other key npm writes decodes to
    /// nothing at all, which is what makes tolerance the default here without
    /// making it the default for `version`.
    private struct ListingDocument: Decodable {
        let dependencies: [String: Entry]

        private enum CodingKeys: String, CodingKey { case dependencies }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dependencies = try container.decodeIfPresent(
                [String: Entry].self, forKey: .dependencies
            ) ?? [:]
        }

        struct Entry: Decodable {
            let version: String
        }
    }

    private struct ReportRow: Decodable {
        let current: String
        let wanted: String?
        let latest: String
    }
}
