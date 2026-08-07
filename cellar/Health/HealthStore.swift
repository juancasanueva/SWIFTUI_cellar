//
//  HealthStore.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation
import Observation

/// The **two** things Health acquires, and nothing else.
///
/// Read the property list: a doctor outcome and a last-update reading. Every
/// other signal on the dashboard is resident state some other store already owns,
/// and this type deliberately holds no reference to any of them — no inventory,
/// no catalog, no security scan, no disk measurement. A "health store" that
/// gathered all eight would be a background job with a window attached, and the
/// requirement it would break is the first one this capability has
/// (`system-health`, "Health is a projection over resident state and acquires
/// nothing to render").
///
/// It also has **no cadence**. No timer, no polling loop, no `Task.sleep`, and no
/// view in `cellar/Health/` carries a `.task` — asserted structurally by
/// `HealthCompositionTests`, because "nothing schedules this" is an absence and an
/// absence needs something counting.
///
/// The doctor run is user-initiated and only user-initiated: nothing in
/// `cellarApp` calls `runDoctor`, which is also asserted. The last-update reading
/// is invocation-free — one `attributesOfItem` behind a seam, zero processes — so
/// it joins the app's existing launch-and-activation refresh rather than waiting
/// for a click that would tell the user nothing they asked for.
@MainActor
@Observable
final class HealthStore {
    /// The last doctor answer, or `nil` because nobody has asked yet — which is
    /// not the same fact as a doctor that found nothing.
    private(set) var doctor: DoctorOutcome?
    /// The last reading of Homebrew's own age. `nil` before the first read;
    /// after it, one of four typed answers and never an invented date.
    private(set) var lastUpdate: HomebrewLastUpdate?
    /// Drives the run control's disabled state, so a second click cannot stack a
    /// second `brew doctor`.
    private(set) var isRunningDoctor = false

    /// The last projection, held so the list column and the detail column render
    /// the same one rather than building it twice from two copies of the inputs.
    ///
    /// Not an acquisition. `HealthProjection.build` is pure over the value it is
    /// handed and reaches no seam at all — which is exactly why the store can hold
    /// its result without becoming the polling thing this capability forbids.
    private(set) var content: HealthContent?

    @ObservationIgnored private let doctorSource: any DoctorSourcing
    @ObservationIgnored private let metadataAccess: any FileMetadataAccess

    init(
        doctorSource: any DoctorSourcing = BrewDoctorSource(),
        metadataAccess: any FileMetadataAccess = SystemFileMetadataAccess()
    ) {
        self.doctorSource = doctorSource
        self.metadataAccess = metadataAccess
    }

    /// Acquisition one. Spawns exactly one `brew doctor`, classified `.read`.
    ///
    /// Cannot throw, by design: `brew doctor` reports warnings by exiting `1`, so
    /// a non-zero run is the ordinary informative answer rather than a failure
    /// (design HD1). Every outcome — including `unavailable` — is assigned, so a
    /// failed run replaces a stale one instead of leaving the old answer on screen.
    func runDoctor(using installation: BrewInstallation) async {
        guard !isRunningDoctor else { return }
        isRunningDoctor = true
        defer { isRunningDoctor = false }
        doctor = await doctorSource.run(using: installation)
    }

    /// Acquisition two. Reads one file's modification date through the seam.
    ///
    /// Synchronous because it is an `attributesOfItem` call and not I/O worth
    /// suspending, and because making it `async` would invite a `.task` to drive
    /// it — which is the one thing this section may not have.
    func readLastUpdate(roots: HomebrewRoots, now: Date) {
        lastUpdate = HomebrewUpdateReader.lastUpdate(roots: roots, now: now, access: metadataAccess)
    }

    /// Rebuilds the projection. Acquires nothing — the inputs are already in hand.
    func project(_ inputs: HealthInputs, now: Date) async {
        content = await HealthProjection.build(inputs: inputs, now: now)
    }
}
