import Foundation

public protocol DiskUsageCaching: Sendable {
    func load() async throws -> DiskUsageSnapshot?
    func save(_ snapshot: DiskUsageSnapshot) async throws
}

public actor DiskUsageCache: DiskUsageCaching {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async throws -> DiskUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try JSONDecoder().decode(DiskUsageSnapshot.self, from: data)
        return snapshot.schemaVersion == 1 ? snapshot : nil
    }

    public func save(_ snapshot: DiskUsageSnapshot) async throws {
        guard snapshot.isComplete else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
