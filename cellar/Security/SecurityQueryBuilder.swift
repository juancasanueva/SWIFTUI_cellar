//
//  SecurityQueryBuilder.swift
//  cellar
//

import BrewClient
import Catalog
import SecurityKit

/// What one inventory turns into: the packages to ask about, and the typed
/// reasons for every package nobody will be asked about.
///
/// Both halves, always. A builder that returned only the queries would leave the
/// caller to infer that everything else is fine, which is the exact collapse this
/// whole capability exists to prevent — the packages that produced no query are
/// the *majority*, and each one carries its own reason.
nonisolated struct SecurityQueryPlan {
    let queries: [AdvisoryQuery]
    let outcomes: [PackageID: CVEScanOutcome]
}

/// The composition point between `BrewClient`'s inventory and `SecurityKit`'s
/// query vocabulary.
///
/// It lives in the app target because no CellarCore target may import both, and
/// it is deliberately thin: `AdvisoryQueryPlanner` in `SecurityKit` owns every
/// rule about mapping, version interpretation and coverage, and this is the
/// projection that hands it `InstalledPackage` shaped input. All this file
/// decides is *which version string to read*, and it does not decide that either
/// — `InstalledDecoder.primaryKeg` already owns "linked wins, else newest", and
/// `InstalledPackage.primaryKeg` publishes its answer.
nonisolated enum SecurityQueryBuilder {
    static func plan(for inventory: [InstalledPackage]) -> SecurityQueryPlan {
        var queries: [AdvisoryQuery] = []
        var outcomes: [PackageID: CVEScanOutcome] = [:]

        for package in inventory {
            // Read, never rederived. A second implementation of primary-keg
            // selection would be a second owner of a rule that has one, and the
            // two would disagree the first time an unlinked keg appeared.
            let plan = AdvisoryQueryPlanner.plan(
                for: package.id,
                installedVersion: package.primaryKeg.version
            )

            switch plan {
            case .query(let query):
                queries.append(query)
            case .notCovered(let reason):
                outcomes[package.id] = .notCovered(reason)
            }
        }

        return SecurityQueryPlan(queries: queries, outcomes: outcomes)
    }
}
