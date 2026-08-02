import BrewProcess
import CoreServices
import Foundation
import Synchronization

// MARK: - Confinement invariant
//
// This file is the single **untested-by-design** surface in `BrewClient`
// (design D8, D12). It is a bridge to a C API that cannot be faked, so instead
// of a test it carries its safety argument in writing, and it is kept small
// enough — no branch beyond "yield" — that the argument is checkable by reading.
//
// The invariant, in full:
//
// 1. `FSEventStreamContext.info` carries `Unmanaged<SignalBox>.passRetained(_:)
//    .toOpaque()`. `SignalBox` is a `final class` conforming to `Sendable`
//    whose only stored property is a `let continuation`, itself `Sendable`.
//    There is no mutable state to race over, so no `@unchecked Sendable`
//    appears anywhere in this module.
// 2. The callback is a **file-scope** `@convention(c)` function. It captures
//    nothing — it cannot, being a C function pointer — recovers the box with
//    `Unmanaged.fromOpaque(_:).takeUnretainedValue()`, and does exactly one
//    thing: `continuation.yield()`. It never reads event paths, flags or ids,
//    which is what makes "the signal is never parsed" true by construction
//    rather than by discipline (installed-inventory II10).
// 3. Callbacks are delivered on a private `DispatchQueue` set with
//    `FSEventStreamSetDispatchQueue`, never on the main queue and never on a
//    run loop this module does not own.
// 4. The box is retained before `FSEventStreamStart` and released only after
//    `Stop` → `Invalidate` → `Release`, in that order, with the whole teardown
//    serialised by a `Mutex` holding the stream reference — the `SystemProcess`
//    D1 precedent. Teardown runs exactly once: the mutex clears the slot before
//    releasing, so a second call finds nothing.
// 5. Creation flags are the **deferred** default (no `NoDefer`), so the OS
//    coalesces a burst before our own debounce ever sees it.
//
// If this adapter never fires, the inventory is still correct: the coordinator's
// baseline refresh at launch and activation is the path that has to work, and
// the watcher is only latency (design D9).

/// Watches Homebrew's installation roots and reports that something changed.
public final class FSEventsInstalledObserver: InstalledChangeObserving {
    /// How long CoreServices coalesces before delivering. Our own quiet window
    /// sits on top of this, so bursts are absorbed twice.
    private static let latency: CFTimeInterval = 1.0

    private let roots: [String]
    private let queue = DispatchQueue(label: "com.juancasanueva.cellar.installed-watcher")
    private let watcher = Mutex<Watcher?>(nil)

    /// The running stream and its retained box.
    ///
    /// Held as bit patterns rather than pointers because pointers are not
    /// `Sendable` and `Mutex` hands its payload across an isolation boundary.
    /// Spelling them as `UInt` keeps the "no `@unchecked Sendable` anywhere"
    /// claim literally true; both are reconstructed in exactly one place,
    /// `stop()`, three lines from where they are used.
    private struct Watcher: Sendable {
        let stream: UInt
        let info: UInt
    }

    /// Watches `<prefix>/Cellar` and `<prefix>/Caskroom`.
    ///
    /// The prefix is derived from the executable — `<prefix>/bin/brew` — which
    /// is uniform across all three `BrewPrefix` cases, so no `BrewProcess` API
    /// has to be added to ask for it.
    public init(installation: BrewInstallation) {
        let prefix = installation.executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        roots = [
            prefix.appendingPathComponent("Cellar", isDirectory: true).path,
            prefix.appendingPathComponent("Caskroom", isDirectory: true).path
        ]
    }

    deinit { stop() }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { [self] _ in stop() }
        start(yielding: continuation)
        return stream
    }

    private func start(yielding continuation: AsyncStream<Void>.Continuation) {
        let info = Unmanaged.passRetained(SignalBox(continuation)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard
            let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                installedChangeCallback,
                &context,
                roots as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.latency,
                UInt32(kFSEventStreamCreateFlagNone)
            )
        else {
            Unmanaged<SignalBox>.fromOpaque(info).release()
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            Unmanaged<SignalBox>.fromOpaque(info).release()
            return
        }

        watcher.withLock {
            $0 = Watcher(
                stream: UInt(bitPattern: UnsafeMutableRawPointer(created)),
                info: UInt(bitPattern: info)
            )
        }
    }

    private func stop() {
        watcher.withLock { current in
            guard let running = current else { return }
            // Cleared before teardown, so a second call — `deinit` after the
            // stream already terminated — finds nothing and does nothing.
            current = nil
            guard
                let stream = OpaquePointer(bitPattern: running.stream),
                let info = UnsafeMutableRawPointer(bitPattern: running.info)
            else { return }

            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<SignalBox>.fromOpaque(info).release()
        }
    }
}

/// The only thing the C callback is allowed to reach: one `Sendable` handle to
/// the stream it feeds.
private final class SignalBox: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(_ continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }
}

/// File-scope so it captures nothing, and one statement long so there is
/// nothing to get wrong. Event paths, flags and ids are deliberately ignored.
private func installedChangeCallback(
    stream: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    count: Int,
    paths: UnsafeMutableRawPointer,
    flags: UnsafePointer<FSEventStreamEventFlags>,
    ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    Unmanaged<SignalBox>.fromOpaque(info).takeUnretainedValue().continuation.yield()
}
