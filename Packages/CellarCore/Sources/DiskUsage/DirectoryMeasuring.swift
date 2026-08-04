import Darwin
import Foundation

public struct DirectoryMeasurement: Sendable, Hashable {
    public let observation: DiskObservation
    public let warning: DiskUsageWarning?

    public init(observation: DiskObservation, warning: DiskUsageWarning? = nil) {
        self.observation = observation
        self.warning = warning
    }
}

public protocol DirectoryMeasuring: Sendable {
    func measure(_ root: URL, area: DiskArea) throws -> DirectoryMeasurement
}

public struct MetadataDirectoryMeasurer: DirectoryMeasuring {
    public init() {}

    public func measure(_ root: URL, area: DiskArea) throws -> DirectoryMeasurement {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .fileResourceIdentifierKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var observation = DiskObservation.zero
        var seen: Set<FileIdentity> = []
        var warning: DiskUsageWarning?
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true || values.isAliasFile == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true else { continue }
                var metadata = stat()
                if stat(url.path, &metadata) == 0 {
                    let identifier = FileIdentity(device: metadata.st_dev, inode: metadata.st_ino)
                    if !seen.insert(identifier).inserted { continue }
                }
                observation = observation + DiskObservation(
                    allocatedBytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0),
                    logicalBytes: Int64(values.fileSize ?? 0)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warning = DiskUsageWarning(area: area, path: url.path, message: error.localizedDescription)
            }
        }
        return DirectoryMeasurement(observation: observation, warning: warning)
    }
}

private struct FileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}
