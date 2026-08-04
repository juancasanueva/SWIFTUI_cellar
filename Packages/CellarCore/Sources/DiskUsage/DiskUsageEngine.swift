import Catalog
import Foundation

public struct DiskUsageProgress: Codable, Sendable, Hashable {
    public let completedUnits: Int
    public let discoveredUnits: Int

    public init(completedUnits: Int, discoveredUnits: Int) {
        self.completedUnits = completedUnits
        self.discoveredUnits = discoveredUnits
    }
}

public enum DiskUsageEvent: Sendable, Hashable {
    case started(DiskRootsIdentity)
    case progress(DiskUsageProgress)
    case version(DiskVersionUsage)
    case package(DiskPackageUsage)
    case warning(DiskUsageWarning)
    case rootCompleted(DiskArea, DiskRootState)
    case completed(DiskUsageSnapshot)
}

public typealias DiskUsageEventStream = AsyncThrowingStream<DiskUsageEvent, any Error>

public protocol DiskUsageScanning: Sendable {
    func scan(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState]
    ) async -> DiskUsageEventStream
}

public struct DiskUsageEngine: Sendable {
    private let measurer: any DirectoryMeasuring

    public init(measurer: any DirectoryMeasuring = MetadataDirectoryMeasurer()) {
        self.measurer = measurer
    }

    @concurrent
    public func scan(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState] = [:]
    ) async -> DiskUsageEventStream {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    try produce(roots: roots, formulaLinks: formulaLinks, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    private func produce(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState],
        into continuation: DiskUsageEventStream.Continuation
    ) throws {
        continuation.yield(.started(roots.identity))
        var packages: [DiskPackageUsage] = []
        var states: [DiskArea: DiskRootState] = [:]
        var warnings: [DiskUsageWarning] = []
        var completedUnits = 0
        var discoveredUnits = 0

        for (area, kind) in [(DiskArea.cellar, PackageKind.formula), (.caskroom, .cask)] {
            try Task.checkCancellation()
            let root = roots.url(for: area)
            guard FileManager.default.fileExists(atPath: root.path) else {
                states[area] = .absent
                continuation.yield(.rootCompleted(area, .absent))
                continue
            }
            do {
                let packageDirectories = try children(of: root)
                discoveredUnits += packageDirectories.count
                for packageDirectory in packageDirectories {
                    let versionDirectories = try children(of: packageDirectory)
                    discoveredUnits += versionDirectories.count
                    var versions: [DiskVersionUsage] = []
                    let packageID = PackageID(kind: kind, name: packageDirectory.lastPathComponent)
                    for versionDirectory in versionDirectories {
                        try Task.checkCancellation()
                        let measured = try measurer.measure(versionDirectory, area: area)
                        let version = DiskVersionUsage(
                            id: DiskVersionID(package: packageID, rawVersion: versionDirectory.lastPathComponent),
                            observation: measured.observation,
                            linkState: kind == .formula ? (formulaLinks[packageID] ?? .unlinked) : .notApplicable
                        )
                        versions.append(version)
                        continuation.yield(.version(version))
                        if let warning = measured.warning {
                            warnings.append(warning)
                            continuation.yield(.warning(warning))
                        }
                        completedUnits += 1
                        continuation.yield(.progress(.init(
                            completedUnits: completedUnits,
                            discoveredUnits: discoveredUnits
                        )))
                    }
                    let package = DiskPackageUsage(id: packageID, versions: versions)
                    packages.append(package)
                    continuation.yield(.package(package))
                    completedUnits += 1
                    continuation.yield(.progress(.init(
                        completedUnits: completedUnits,
                        discoveredUnits: discoveredUnits
                    )))
                }
                states[area] = .present
                continuation.yield(.rootCompleted(area, .present))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let warning = DiskUsageWarning(area: area, path: root.path, message: error.localizedDescription)
                warnings.append(warning)
                states[area] = .failed(warning.message)
                continuation.yield(.warning(warning))
                continuation.yield(.rootCompleted(area, .failed(warning.message)))
            }
        }

        let cache: DiskObservation
        if FileManager.default.fileExists(atPath: roots.cache.path) {
            do {
                discoveredUnits += 1
                let measured = try measurer.measure(roots.cache, area: .cache)
                cache = measured.observation
                if let warning = measured.warning {
                    warnings.append(warning)
                    continuation.yield(.warning(warning))
                }
                states[.cache] = measured.warning == nil ? .present : .failed(measured.warning!.message)
                completedUnits += 1
                continuation.yield(.progress(.init(
                    completedUnits: completedUnits,
                    discoveredUnits: discoveredUnits
                )))
                continuation.yield(.rootCompleted(.cache, states[.cache]!))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let warning = DiskUsageWarning(area: .cache, path: roots.cache.path, message: error.localizedDescription)
                cache = .zero
                warnings.append(warning)
                states[.cache] = .failed(warning.message)
                continuation.yield(.warning(warning))
                continuation.yield(.rootCompleted(.cache, .failed(warning.message)))
            }
        } else {
            cache = .zero
            states[.cache] = .absent
            continuation.yield(.rootCompleted(.cache, .absent))
        }

        let snapshot = DiskUsageSnapshot(
            roots: roots.identity,
            generatedAt: Date(),
            rootStates: states,
            packages: packages,
            cache: cache,
            warnings: warnings
        )
        continuation.yield(.completed(snapshot))
    }

    private func children(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

extension DiskUsageEngine: DiskUsageScanning {}
