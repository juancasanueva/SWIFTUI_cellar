import Foundation

/// What one file's modification date turned out to be.
///
/// Three cases, and none of them is a `Date` nobody measured. "It is not there"
/// and "it is there and I could not read it" are different facts, and a consumer
/// that treats them the same is choosing not to say which one happened.
public enum FileModificationDate: Sendable, Hashable {
    case read(Date)
    /// No such file. On this capability's path that covers both "Homebrew has
    /// never fetched" and "this is not a git checkout at all" — the API-only
    /// future Homebrew has been moving toward.
    case absent
    /// The file exists and its metadata could not be read.
    case unreadable
}

/// The narrowest possible filesystem seam: one attribute, on one file.
///
/// It exists because neither shipped file seam can answer this question.
/// `CatalogFileSystem` reads and writes bytes; `ReleaseNotesFileAccess` reads
/// bytes. Neither exposes an attribute operation, and widening either of them
/// would give a bytes-shaped seam a metadata responsibility it has no other
/// caller for.
///
/// It is `ReleaseNotesFileAccess`-sized on purpose. A wider seam here would be a
/// filesystem, and a filesystem in this position is how "read how old Homebrew
/// is" quietly becomes "walk the Homebrew repository".
///
/// Synchronous rather than `async`: this is an `attributesOfItem` call on one
/// path, not I/O worth a suspension point.
///
/// It lives in `DiskUsage`, which already owns `HomebrewRoots` and the
/// filesystem domain, and which `Persistence` never needs to see.
public protocol FileMetadataAccess: Sendable {
    func modificationDate(at url: URL) -> FileModificationDate
}

/// The production seam.
///
/// Every failure is a typed case rather than a thrown error, because there is no
/// caller for whom "I could not stat this file" is exceptional: it is one of the
/// answers.
/// `manager` is computed rather than stored, matching `CatalogFileSystem`:
/// `FileManager` is not `Sendable`, and this type is, so holding one as a stored
/// property would need an `@unchecked` escape for no benefit at all.
public struct SystemFileMetadataAccess: FileMetadataAccess {
    private var manager: FileManager { FileManager.default }

    public init() {}

    public func modificationDate(at url: URL) -> FileModificationDate {
        guard manager.fileExists(atPath: url.path) else { return .absent }
        guard let attributes = try? manager.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date
        else { return .unreadable }
        return .read(date)
    }
}
