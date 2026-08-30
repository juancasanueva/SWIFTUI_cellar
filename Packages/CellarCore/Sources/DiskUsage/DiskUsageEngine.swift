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
            guard let root = roots.url(for: area), FileManager.default.fileExists(atPath: root.path) else {
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

        // The npm globals directory is measured as one unit exactly like the
        // cache, and only when a prefix was configured: with npm off there is
        // no `.npm` state and no event, so the scan is indistinguishable from
        // one without the capability.
        var npmGlobals = DiskObservation.zero
        if let npmRoot = roots.npmGlobals {
            if FileManager.default.fileExists(atPath: npmRoot.path) {
                do {
                    // Per-package sizes first, then the root as one unit. The
                    // root total is what the storage bar shows because it also
                    // covers what no package owns (`.bin`, npm's lock file);
                    // the packages are what the list shows. That is two walks
                    // over the package trees, accepted for now: the globals
                    // directory is small next to the Cellar.
                    let packageDirectories = try npmPackageDirectories(in: npmRoot)
                    discoveredUnits += packageDirectories.count * 2
                    for (name, packageDirectory) in packageDirectories {
                        try Task.checkCancellation()
                        let packageID = PackageID(kind: .npm, name: name)
                        let measured = try measurer.measure(packageDirectory, area: .npm)
                        let version = DiskVersionUsage(
                            id: DiskVersionID(package: packageID, rawVersion: npmVersion(of: packageDirectory)),
                            observation: measured.observation,
                            linkState: .notApplicable
                        )
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
                        let package = DiskPackageUsage(id: packageID, versions: [version])
                        packages.append(package)
                        continuation.yield(.package(package))
                        completedUnits += 1
                        continuation.yield(.progress(.init(
                            completedUnits: completedUnits,
                            discoveredUnits: discoveredUnits
                        )))
                    }
                    discoveredUnits += 1
                    let measured = try measurer.measure(npmRoot, area: .npm)
                    npmGlobals = measured.observation
                    if let warning = measured.warning {
                        warnings.append(warning)
                        continuation.yield(.warning(warning))
                    }
                    states[.npm] = measured.warning.map { .failed($0.message) } ?? .present
                    completedUnits += 1
                    continuation.yield(.progress(.init(
                        completedUnits: completedUnits,
                        discoveredUnits: discoveredUnits
                    )))
                    continuation.yield(.rootCompleted(.npm, states[.npm]!))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let warning = DiskUsageWarning(area: .npm, path: npmRoot.path, message: error.localizedDescription)
                    warnings.append(warning)
                    states[.npm] = .failed(warning.message)
                    continuation.yield(.warning(warning))
                    continuation.yield(.rootCompleted(.npm, .failed(warning.message)))
                }
            } else {
                states[.npm] = .absent
                continuation.yield(.rootCompleted(.npm, .absent))
            }
        }

        let snapshot = DiskUsageSnapshot(
            roots: roots.identity,
            generatedAt: Date(),
            rootStates: states,
            packages: packages,
            cache: cache,
            npmGlobals: npmGlobals,
            warnings: warnings
        )
        continuation.yield(.completed(snapshot))
    }

    /// The packages under a globals directory, by their npm name.
    ///
    /// npm's layout has two shapes worth knowing: a top-level directory is a
    /// package, unless its name opens with `@`, in which case it is a scope
    /// whose children are the packages (`@angular/cli`). Dot entries — `.bin`,
    /// `.package-lock.json` — belong to npm, not to any package, and are
    /// skipped; `children(of:)` already keeps only directories.
    private func npmPackageDirectories(in root: URL) throws -> [(name: String, directory: URL)] {
        var packages: [(name: String, directory: URL)] = []
        for entry in try children(of: root) where !entry.lastPathComponent.hasPrefix(".") {
            let name = entry.lastPathComponent
            if name.hasPrefix("@") {
                for scoped in try children(of: entry) where !scoped.lastPathComponent.hasPrefix(".") {
                    packages.append((name: "\(name)/\(scoped.lastPathComponent)", directory: scoped))
                }
            } else {
                packages.append((name: name, directory: entry))
            }
        }
        return packages
    }

    /// The `"version"` from a package's `package.json`, or `"unknown"`.
    ///
    /// Only that one key is read, so any other shape the file takes is
    /// tolerated; and a missing or unreadable file is not a measurement
    /// failure — the bytes were still counted — so it raises no warning.
    private func npmVersion(of packageDirectory: URL) -> String {
        struct Manifest: Decodable { let version: String? }
        let manifest = packageDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
              let version = decoded.version, !version.isEmpty
        else { return "unknown" }
        return version
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
