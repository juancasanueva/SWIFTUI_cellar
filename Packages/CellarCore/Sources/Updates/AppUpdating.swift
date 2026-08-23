//
//  AppUpdating.swift
//  Updates
//

import Foundation
import Observation

/// Everything Cellar's own surfaces ask of an updater.
///
/// Four members and nothing else: the third-party updater framework is confined
/// to exactly one file in the app target, and this is the only vocabulary that
/// crosses out of it. A Settings card, a menu command and the launch wiring all
/// speak to this; none of them can name a framework type.
///
/// It is `@MainActor` because the app target compiles under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the concrete updater is
/// main-actor by construction, so a `nonisolated` requirement could not be
/// satisfied by the only conformer that matters.
///
/// It refines `Observable` so a view holding `any AppUpdating` still re-renders:
/// Observation registers at the **accessor**, so tracking survives the
/// existential. The existential is deliberate — dependency injection picks the
/// concrete type at runtime, real or in-memory, and a `Commands` body needs one
/// static type.
@MainActor
public protocol AppUpdating: AnyObject, Observable {
    /// Whether a check can run right now. In practice this is false only while a
    /// check is already in flight — never because automatic checking is off,
    /// never because the last check found nothing.
    var canCheckForUpdates: Bool { get }

    /// Whether the updater checks on its own. Cellar's persisted preference is
    /// the authority for this value and writes it at every launch.
    var automaticallyChecksForUpdates: Bool { get set }

    /// When the updater last completed a check, or `nil` if it never has.
    var lastUpdateCheckDate: Date? { get }

    /// Starts exactly one check.
    func checkForUpdates()
}
