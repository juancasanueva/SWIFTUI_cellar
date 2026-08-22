# m6-tip-jar — Measurement Probes

Run 2026-08-21 on macOS 26.5.2 (Mac mini, arm64), Xcode 26.6 (17F113), clean `main`.
All probe artifacts (scratch scheme, throwaway test file, `.storekit` files, scratch
DerivedData) were deleted after measurement. Probe method: a throwaway Swift Testing
file `cellarTests/StoreKitProbeTests.swift` that wrote measurements to a scratch file
(hosted-test `print()` output is not recoverable from `xcodebuild` logs or `.xcresult`).

The `.storekit` file used everywhere was a minimal hand-written JSON (version 4.0
schema) with one consumable, `productID = com.juancasanueva.cellar.tip`,
`displayPrice = "0.99"`. StoreKit accepted it as-is.

---

## U16 (GATE) — local StoreKit testing viability

**What was run**

- `Tip.storekit` at repo root (untracked); scratch scheme
  `cellar.xcodeproj/xcshareddata/xcschemes/cellar-storekit-probe.xcscheme` = copy of
  `cellar.xcscheme` + `<StoreKitConfigurationFileReference identifier = …>` inside
  `LaunchAction` (TestAction keeps `shouldUseLaunchSchemeArgsEnv="YES"`).
- Test: `Product.products(for: ["com.juancasanueva.cellar.tip"])`, expect count 1.
- `xcodebuild test -project cellar.xcodeproj -scheme cellar-storekit-probe -destination 'platform=macOS,arch=arm64' -only-testing:'cellarTests/StoreKitProbeTests/u16ProductResolves()'`
- Identifier variants tried, each with the persistent StoreKit test environment
  cleared first: `../../../Tip.storekit`, `../../Tip.storekit`, and the absolute path.

**Observed**

- All three scheme-reference variants: `U16-PROBE products.count=0 ids=[] prices=[]`
  → `** TEST FAILED **`.
- An earlier suite-level run appeared to pass (`products.count=1 … prices=["$0.99"]`),
  but that was contamination: `SKTestSession` (running in the same suite) installs a
  persistent per-app test environment at
  `~/Library/Caches/com.apple.storekitagent/Octane/com.juancasanieva.cellar/`
  (sic: `com.juancasanueva.cellar`) that survives across processes AND across
  `xcodebuild` invocations. After `rm -rf` of that directory, the pass reverted to 0
  products.
- With `SKTestSession(contentsOf: URL)` created inside the test (no scheme reference
  at all, plain `cellar` scheme): `products.count=1`, price `$0.99`. See U19.

**VERDICT: GATE PASSES — but via StoreKitTest, not the scheme.** `xcodebuild test`
does not apply a scheme `StoreKitConfigurationFileReference` to hosted unit tests
(verified with relative and absolute identifiers on Xcode 26.6). `SKTestSession`
makes `Product.products(for:)` resolve the synthetic product with zero scheme
changes. The scheme reference remains useful only for interactive Run in Xcode
(manual purchase-flow testing).

---

## U17 — .storekit placement

**What was run**

- (a) `Tip.storekit` copied into `cellar/` (PBXFileSystemSynchronizedRootGroup), then
  `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -derivedDataPath <scratch>` and bundle inspection.
- (b) `Tip.storekit` at repo root — exercised by every U16/U19 run.
- (c) Bonus: `Tip.storekit` copied into `cellarTests/` (also a synchronized group).

**Observed**

- (a) Build log: `CpResource … cellar.app/Contents/Resources/Tip.storekit …` and the
  file is present in `cellar.app/Contents/Resources/` — the synchronized group treats
  `.storekit` as a bundle resource of the app target. It would ship in release builds.
- (b) Repo root: never copied anywhere; scheme identifier resolution is moot since the
  scheme route does not work for tests anyway (U16).
- (c) `cellarTests/` placement: file lands in
  `cellar.app/Contents/PlugIns/cellarTests.xctest/Contents/Resources/Tip.storekit` —
  test-bundle resource only, NOT in the app's own `Resources/`. This is what makes
  `SKTestSession(configurationFileNamed: "Tip")` work (U19).

**VERDICT: safe location is `cellarTests/`** — it keeps the config out of the shipping
app's resources, gets bundled into the test bundle automatically by the synchronized
group, and enables path-free `SKTestSession(configurationFileNamed:)`. Do NOT place it
in `cellar/` (ships inside the app). Repo root is fine for an Xcode-Run-only config
but contributes nothing to automated tests.

---

## U18 — shared-scheme perturbation

**What was run**

With `cellar-storekit-probe.xcscheme` (carrying the StoreKitConfigurationFileReference)
present next to the shared scheme:

```
xcodebuild test -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:cellarTests -skip-testing:cellarTests/StoreKitProbeTests
```

**Observed**

- `** TEST SUCCEEDED **`, 171 passed / 0 failed — identical to baseline (U21).
- The unmodified `cellar` scheme is completely unaffected by a sibling scheme carrying
  the StoreKit reference.

**VERDICT: no scheme change needed at all for tests.** Since `xcodebuild test` ignores
the scheme StoreKit reference (U16), automated tests rely solely on `SKTestSession` +
a test-bundle `.storekit` — zero schemes touched. A second scheme (or adding the
reference to the shared scheme's LaunchAction) is only for interactive Run in Xcode;
if wanted, the second scheme is the safer choice, and it provably does not perturb
`cellar` scheme test runs.

---

## U19 — SKTestSession headless

**What was run**

Throwaway Swift Testing tests via `xcodebuild test` (headless, no dialogs):

1. `SKTestSession(contentsOf: <absolute file URL>)`; `resetToDefaultState()`;
   `disableDialogs = true`; `clearTransactions()`; `Product.products(for:)`;
   `product.purchase()`; assert `.success(.verified)`.
2. `SKTestSession(configurationFileNamed: "Tip")` with and without the `.storekit`
   in the test bundle.

**Observed**

- URL-based session, plain `cellar` scheme, headless:
  `U19-PROBE post-session products.count=1` then
  `U19-PROBE VERIFIED transaction id=0 product=com.juancasanueva.cellar.tip` —
  purchase succeeded, transaction verified and finished. `** TEST … passed **`
  (1.4 s).
- `configurationFileNamed:` with no bundled config:
  `Error Domain=SKTestErrorDomain Code=4 "File not found"`.
- `configurationFileNamed: "Tip"` with `Tip.storekit` in `cellarTests/`: passed
  (0.007 s).
- Side effect: the session installs the persistent Octane test environment (see U16);
  tests that assert "no products without config" must clean it or will flake.

**VERDICT: fully works headless on this machine.** The StoreKit conformer gets real
automated tests: create `SKTestSession(configurationFileNamed: "Tip")` (config in
`cellarTests/`), `disableDialogs = true`, buy the consumable, assert a verified
transaction. No scheme edits, no absolute paths, no UI.

---

## U20 — transact-capability signal in a Dev-ID/local build

**What was run**

Plain `cellar` scheme, NO StoreKit config, persistent Octane environment deleted
first (`rm -rf ~/Library/Caches/com.apple.storekitagent/Octane/com.juancasanueva.cellar`):

```
xcodebuild test … -only-testing:'cellarTests/StoreKitProbeTests/u20TransactSignals()'
```

**Observed (clean environment)**

- `U20-PROBE canMakePayments=true`
- `U20-PROBE AppTransaction.shared threw: unknown`  (StoreKitError.unknown)
- `U20-PROBE no-config products.count=0`

**Observed (with leftover SKTestSession environment — for contrast)**

- `canMakePayments=true`
- `AppTransaction VERIFIED bundleID=com.juancasanueva.cellar originalVersion=1.0.0`
- `products.count=1`

**VERDICT: `canMakePayments` is NOT a usable seam** (always true locally).
The clean signals for "this build cannot transact" are:
`Product.products(for:)` returning an empty array for known IDs, and
`AppTransaction.shared` throwing (`StoreKitError.unknown` here). Product-fetch
emptiness is the cheaper, purchase-adjacent seam: the tip UI should degrade
(hide/disable) when the product list comes back empty, which covers Dev-ID builds,
no-App-Store-Connect setups, and network failure with one code path. Note the
signals are environment-sensitive: a StoreKit test environment makes both succeed.

---

## U21 — baseline

**What was run**

At clean `main`, before any probe artifact existed:

```
xcodebuild test -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
swiftlint --version && swiftlint --quiet   # from repo root
```

**Observed**

- cellarTests: **171 passed, 0 failed**, `** TEST SUCCEEDED **`.
- SwiftLint 0.65.0, no `.swiftlint.yml` in repo (matches openspec/config.yaml):
  default rules report **246 warnings, 20 errors** pre-existing (e.g.
  `type_body_length` on `cellar/Browse/PackageDetailView.swift`). Lint is not
  currently a green gate; do not treat lint-clean as an m6 acceptance criterion.
- cellarUITests baseline: not run (time); unit baseline was the required gate.

**VERDICT: baseline green — 171/171 unit tests pass; lint has 266 pre-existing
findings under default rules and is not a usable pass/fail gate.**

---

## Plan-changing conclusions

1. Drop any task that edits schemes for testing: the StoreKitConfigurationFileReference
   route does not reach `xcodebuild test` at all. Tests use `SKTestSession` only.
2. Check `Tip.storekit` into `cellarTests/` (test-bundle resource, path-free lookup,
   never ships in the app). Optionally keep a scheme copy with the reference for
   manual Run-in-Xcode purchase testing — it provably does not disturb CI.
3. The runtime "can transact" seam = empty `Product.products(for:)` result (plus
   `AppTransaction.shared` throwing as a secondary signal); `canMakePayments` is
   useless. Design the tip UI to degrade on an empty product list.
4. Swift Testing + `xcodebuild -only-testing` needs the trailing `()` on function-level
   identifiers (`…/u20TransactSignals()`); without it, zero tests run and xcodebuild
   still reports `TEST SUCCEEDED` — a silent false-green to watch for in CI recipes.
5. SKTestSession leaves a persistent per-app StoreKit test environment under
   `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/`; any test asserting
   the no-config behavior must not run after session-based tests without cleanup.
