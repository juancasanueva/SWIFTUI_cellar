//
//  CaskIconLoader.swift
//  cellar
//

import AppKit
import Catalog
import SwiftUI

/// The cask artwork pipeline, ported simplified from CaskHub: memory cache,
/// disk cache, negative-result markers, and the CaskFlow → App-Fair URL ladder.
///
/// The class lives on the main actor because views ask it questions, but every
/// byte of disk and network work runs in `@concurrent` functions — the main
/// actor never blocks on a file or a socket.
///
/// Constructed **once**, in `cellarApp`, and passed down — never built inside a
/// view. The session is injected there too, so a UI-test launch can hand this
/// loader a disabled configuration and prove zero network.
@MainActor
@Observable
final class CaskIconLoader {
    /// Decoded images by token. Capped, because a browse session can scroll
    /// past thousands of cards and each icon is a decoded bitmap.
    @ObservationIgnored
    private let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    /// One fetch per token at a time; a second card for the same cask joins
    /// the first request instead of issuing its own.
    @ObservationIgnored
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    @ObservationIgnored
    private let session: URLSession
    /// Set for UI-test launches: every lookup answers `nil` immediately, so a
    /// test run issues zero requests and touches no cache directory.
    @ObservationIgnored
    private let isDisabled: Bool

    init(session: URLSession = CaskIconLoader.defaultSession(), isDisabled: Bool = false) {
        self.session = session
        self.isDisabled = isDisabled
    }

    /// Ephemeral on purpose: the disk cache below is the persistence, and a
    /// second URL cache underneath it would double-store every icon.
    nonisolated static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }

    /// The icon for a token, from memory, disk, or the network — or `nil`,
    /// which the views answer with the letter tile.
    func icon(for token: String, isKnownToken: Bool) async -> NSImage? {
        guard !isDisabled else { return nil }
        if let cached = memory.object(forKey: token as NSString) { return cached }
        if let running = inFlight[token] { return await running.value }

        let session = self.session
        let task = Task {
            await Self.loadOffMain(token: token, isKnownToken: isKnownToken, session: session)
        }
        inFlight[token] = task
        let image = await task.value
        inFlight[token] = nil
        if let image { memory.setObject(image, forKey: token as NSString) }
        return image
    }

    // MARK: - Off the main actor

    /// Disk first, then the URL ladder. Runs on the concurrent pool.
    @concurrent
    private static func loadOffMain(
        token: String,
        isKnownToken: Bool,
        session: URLSession
    ) async -> NSImage? {
        let directory = cacheDirectory()
        let iconURL = directory.appendingPathComponent("\(token).png")
        if let image = NSImage(contentsOf: iconURL) { return image }

        // A recorded miss suppresses the retry — for a day ordinarily, but only
        // fifteen minutes when the manifest *promises* an icon exists, because
        // that miss was probably transient.
        let missURL = directory.appendingPathComponent("\(token).miss")
        let retryAfter: TimeInterval = isKnownToken ? 15 * 60 : 24 * 60 * 60
        if let attributes = try? FileManager.default.attributesOfItem(atPath: missURL.path),
           let missedAt = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(missedAt) < retryAfter {
            return nil
        }

        for url in CaskIconURL.candidateURLs(for: token, isKnownToken: isKnownToken) {
            guard
                let (data, response) = try? await session.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200,
                let image = NSImage(data: data)
            else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: iconURL)
            try? FileManager.default.removeItem(at: missURL)
            return image
        }

        // Every rung failed: stamp the miss so the next scroll past this card
        // costs nothing.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: missURL.path, contents: Data())
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: missURL.path
        )
        return nil
    }

    /// Beside `disk-usage-v1.json` and the advisory cache, under the app's own
    /// Caches folder.
    nonisolated private static func cacheDirectory() -> URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Cellar/cask-icons")
    }
}
