// BrewClient — the installed inventory.
//
// The only target in the package that sees both `BrewProcess` and `Catalog`.
// It turns a single `brew info --installed --json=v2` invocation into an
// immutable, `Sendable` snapshot of what this machine has installed, and joins
// that snapshot to the published catalog through the identity the catalog
// already uses, `PackageID`.
//
// The edge is one-directional by design (D1): `Catalog` depends on nothing, so
// catalog sync and search keep working with `brew` absent (catalog-sync CS1).
// `PackageGraphTests` asserts that from the manifest itself.
//
// This file declares no API. It exists so the module's role is written down
// once, next to the code, rather than only in `design.md`.
