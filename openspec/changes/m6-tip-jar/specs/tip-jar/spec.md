# Delta for tip-jar

New capability — there is no `openspec/specs/tip-jar/spec.md` yet, so this delta is **ADDED-only**:
**9 requirements / 40 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED, so `rules.archive`'s
destructive-delta warning does not fire.

This capability owns what Cellar may ask for, may claim, and may remember when a user chooses to
thank the developer: how the tip catalog is loaded and what an empty catalog means, the six typed
purchase outcomes and what each is allowed to tell the user, the finish-always rule, why the tip may
be given again, what the app is allowed to remember afterwards, how the surface behaves in a build
that cannot transact, and the copy rules that keep gratitude from becoming a nag.

Behaviour is specified as behaviour of `CellarCore` values (`rules.specs`). Two requirements —
"One purchase call site, and no new section" and "StoreKit lives behind exactly one seam" — are
**structural** rather than view specifications: they constrain which files may reference which
symbols, in the shipped `AppSecuritySources` / `OSVSource` composition-test idiom, and are
assertable without rendering any SwiftUI view.

Traceability: **D1** → the availability requirement and the openly-unproven ship path it protects;
**D2** → "One purchase call site, and no new section"; **D3** → "The tip surface exists only when
the build can transact"; **D4** → the single product id in "The tip catalog has three states";
**D5** → "The thank-you is one local boolean"; **D6** is a PRD-text amendment carried by `tasks`,
not by a requirement here. D2's literal "opens Settings" wording is **amended by D-E** (Engram obs
7642): the About row is static and availability-gated, because navigation would require diffing the
root content view.

Measured constraints this spec is written against (`probes.md`): `AppStore.canMakePayments` is
always `true` locally and is therefore **not** a usable seam (U20); the clean "cannot transact"
signal is `Product.products(for:)` returning an empty array (U20); `Tip.storekit` lives in
`cellarTests/` and never ships in the app (U17); `SKTestSession` drives the conformer headlessly
with no scheme change (U18/U19).

## ADDED Requirements

### Requirement: The tip catalog has three states, and empty is one of them

The tip catalog MUST be loaded through a `TipCatalogLoading` seam for exactly one consumable
product id, **`com.juancasanueva.cellar.tip`**, declared once as a constant rather than repeated as
a literal. Loading MUST settle into exactly one typed state: **not yet loaded**, **loading**,
**loaded** carrying at least one `TipProduct`, **unavailable** because the returned product list was
empty, or **failed** carrying a typed reason.

An empty product list MUST be treated as a real, reachable, terminal state — it MUST NOT be
represented as a still-loading state, an error, an optional treated as failure, or a spinner that
never resolves. A failure MUST remain distinguishable from an empty catalog, so "this build cannot
transact" is never reported as "something went wrong" and the reverse is never reported either.

`TipProduct` MUST be a plain `Sendable` value carrying the product id, the display name, the
description and the localized display price. StoreKit's `Product` and `Transaction` types MUST NOT
appear in it, and MUST NOT cross into `CellarCore`.

#### Scenario: A catalog with one product loads

- GIVEN a catalog seam returning one product for `com.juancasanueva.cellar.tip`
- WHEN the catalog is loaded
- THEN the state is loaded, carrying exactly one `TipProduct` with that id and a non-empty display
  price
- AND that value carries no StoreKit type

#### Scenario: An empty product list is a settled state, not a spinner

- GIVEN a catalog seam returning an empty array
- WHEN the catalog is loaded
- THEN the state settles as unavailable
- AND it is neither the loading state, the failed state, nor a loaded state with zero products

#### Scenario: Loading is observable while it is in progress

- GIVEN a catalog seam that has not yet answered
- WHEN loading has been started but has not returned
- THEN the state is loading
- AND once the seam answers, the state settles exactly once and is no longer loading

#### Scenario: A failure is not an empty catalog

- GIVEN a catalog seam that throws
- WHEN the catalog is loaded
- THEN the state is failed, carrying a typed reason
- AND that state is distinguishable from the unavailable state without inspecting free text

#### Scenario: The product id has one home

- GIVEN the `TipJar` target's sources and tests
- WHEN they are inspected structurally
- THEN `com.juancasanueva.cellar.tip` appears as a single declared constant
- AND no second literal of that id exists in shipped source

### Requirement: Six outcomes, and each one claims exactly what happened

A tip purchase MUST settle into exactly one of six typed `TipPurchaseOutcome` cases, and each MUST
be distinguishable by a consumer without parsing free text:

| Outcome | Means | The user is told |
|---|---|---|
| **completed** | a verified transaction, finished | thank you |
| **cancelled** | the user dismissed the sheet | nothing at all |
| **pending** | Ask to Buy / deferred approval | the tip is **not** complete yet |
| **unverified** | the transaction failed verification | **no thank-you**, and no accusation |
| **failed** | the purchase threw | a typed reason |
| **unavailable** | no product to buy | no purchase was attempted |

`cancelled` MUST be quiet: no error, no alert, no thank-you, and no state change of any kind.
`pending` MUST NOT be reported as success and MUST NOT record the thank-you. `unverified` MUST NOT
record the thank-you, MUST NOT be collapsed into `failed`, and MUST NOT be presented as an
accusation of fraud. `failed` MUST carry a typed reason distinct from every other case. A purchase
requested while the catalog is unavailable MUST answer `unavailable` without calling the purchasing
seam. `@unknown default` handling MUST map to `failed`, never to silence.

#### Scenario: A verified purchase completes and thanks the user

- GIVEN a loaded catalog and a purchasing seam returning a verified transaction
- WHEN the tip is purchased
- THEN the outcome is `completed`
- AND the thank-you state is recorded

#### Scenario: Cancelling says nothing

- GIVEN a loaded catalog and a purchasing seam reporting user cancellation
- WHEN the tip is purchased
- THEN the outcome is `cancelled`
- AND no thank-you is recorded, no failure reason is produced, and no message is surfaced

#### Scenario: Ask to Buy is honest that nothing has been paid

- GIVEN a purchasing seam reporting a deferred approval
- WHEN the tip is purchased
- THEN the outcome is `pending`
- AND no thank-you is recorded
- AND the outcome is distinguishable from `completed` and from `failed`

#### Scenario: An unverified transaction is finished but never thanked

- GIVEN a purchasing seam returning a transaction that fails verification
- WHEN the tip is purchased
- THEN the outcome is `unverified`
- AND no thank-you is recorded
- AND the outcome is not reported as `failed`

#### Scenario: A thrown purchase is a typed failure

- GIVEN a purchasing seam that throws
- WHEN the tip is purchased
- THEN the outcome is `failed`, carrying a typed reason
- AND no thank-you is recorded

#### Scenario: Purchasing without a product attempts nothing

- GIVEN a catalog that settled as unavailable and a recording purchasing seam
- WHEN a purchase is requested
- THEN the outcome is `unavailable`
- AND the recorder saw no purchase attempt

### Requirement: Every transaction is finished, including the unverified one

Every transaction reaching the app MUST be finished, on every path: `completed`, `unverified`, an
Ask-to-Buy approval arriving later, and any transaction found in the unfinished queue. `finish()` is
the entire lifecycle of this consumable; skipping it on the unverified path MUST NOT be treated as a
safety measure, because an unfinished consumable replays forever.

A `Transaction.updates` observation MUST be started **at launch**, before any tip surface is shown,
through the app's existing idempotent per-id loop mechanism under the `"tips"` slot, so a second
window joins the existing observation rather than starting a second listener. The observation MUST
NOT terminate on its own. The unfinished-transaction queue MUST additionally be **drained at
launch**, and each drained transaction MUST be finished.

An approval arriving through the update stream for a verified tip transaction MUST record the
thank-you; an unverified one MUST be finished without recording it.

#### Scenario: A completed purchase finishes its transaction

- GIVEN a recording purchasing seam returning a verified transaction
- WHEN the tip is purchased
- THEN the recorder shows that transaction finished exactly once

#### Scenario: An unverified transaction is still finished

- GIVEN a purchasing seam returning a transaction that fails verification
- WHEN the tip is purchased
- THEN the outcome is `unverified` and the recorder shows that transaction finished
- AND it does not remain in the unfinished set

#### Scenario: The unfinished queue is drained at launch

- GIVEN two unfinished tip transactions, one verified and one unverified
- WHEN launch-time observation starts
- THEN both are finished
- AND the thank-you is recorded for the verified one only

#### Scenario: A later Ask-to-Buy approval is caught after the app was quit

- GIVEN a `pending` outcome recorded in an earlier session and a verified approval delivered through
  the update stream at the next launch
- WHEN the update is observed
- THEN the thank-you is recorded and the transaction is finished

#### Scenario: A second window joins the one observation

- GIVEN observation already started under the `"tips"` slot
- WHEN observation is started again
- THEN exactly one observation exists
- AND the first one was not cancelled or restarted

### Requirement: A tip may be given again, and nothing is entitled by it

The tip product is a **consumable**: a user who has already tipped MUST be able to tip again, with
the same surface, the same copy, and a second `completed` outcome. A recorded thank-you MUST NOT
disable, hide, or gate the tip surface.

A tip MUST grant nothing. `Transaction.currentEntitlements` MUST NOT be consulted anywhere in this
capability, because a finished consumable never appears there. There MUST be no restore-purchases
affordance and no call to `AppStore.sync()`: consumables are not restorable, and such a control
would be misleading UI rather than compliance. No content, feature, or setting anywhere in Cellar
MUST be gated on having tipped.

#### Scenario: Tipping twice works

- GIVEN a recorded thank-you from an earlier tip and a purchasing seam returning verified
  transactions
- WHEN the tip is purchased again
- THEN the outcome is `completed` and the transaction is finished
- AND the purchase was not refused, disabled, or short-circuited by the earlier thank-you

#### Scenario: The thank-you does not remove the tip surface

- GIVEN a recorded thank-you and a loaded catalog
- WHEN availability is evaluated
- THEN the tip surface is still available
- AND its price still comes from the loaded product

#### Scenario: Nothing is entitled or restorable

- GIVEN the change's shipped sources
- WHEN they are inspected structurally
- THEN no source references `currentEntitlements`, `AppStore.sync`, or a restore-purchases control
- AND no feature elsewhere in the app is conditioned on the thank-you flag

### Requirement: The tip surface exists only when the build can transact

Availability MUST be derived from **one runtime signal**: whether the loaded catalog produced a
product. An empty product list means the tip surface MUST be **absent** — not disabled, not greyed,
not replaced by a placeholder row or an explanatory "unavailable" card. This upholds the shipped
refusal to ship present-but-inert controls, and it covers Developer ID builds, missing App Store
Connect records, and a failed fetch through one code path.

`AppStore.canMakePayments` MUST NOT be used as this signal (it is `true` even where no purchase can
occur). Availability MUST NOT be decided by a compile-time flag, an `#if` branch, or an `#available`
check. Both the available and unavailable states MUST be reachable in tests from a fake catalog
seam, with no StoreKit linkage.

While the catalog is still loading, the surface MUST NOT render a purchase control that would
resolve into a permanently inert one.

#### Scenario: An empty catalog renders no tip surface

- GIVEN a catalog seam returning an empty array
- WHEN availability is evaluated
- THEN the tip surface is unavailable
- AND no disabled control, placeholder row, or explanatory unavailable card is offered in its place

#### Scenario: A loaded catalog makes the surface available

- GIVEN a catalog seam returning one product
- WHEN availability is evaluated
- THEN the tip surface is available and carries that product's display price

#### Scenario: Availability ignores the payments-capability flag

- GIVEN the change's shipped sources
- WHEN they are inspected structurally
- THEN no source references `canMakePayments`
- AND no `#if` or `#available` branch decides availability

#### Scenario: A failed load is also no surface

- GIVEN a catalog seam that throws
- WHEN availability is evaluated
- THEN the tip surface is unavailable
- AND the failed state remains distinguishable from the empty-catalog state for diagnostics

### Requirement: The thank-you is one local boolean, and that is the whole record

Cellar's no-telemetry claim is what a payment feature is most likely to be suspected of breaking, so
the tip's memory MUST be the smallest thing that works: **one local boolean**. It MUST NOT record a
date, a count, a transaction id, an original transaction id, a product id, a price, a storefront, a
purchase history, or any identifier. It MUST NOT be synchronised to iCloud or any server, and
`.appAccountToken` MUST NOT be supplied to any purchase, because Cellar has no accounts.

The flag MUST persist across relaunch — a session-only flag would re-ask someone who has already
given. It MUST be stored in local preferences under a namespaced key in the shipped
`SecurityConsentPreference` / `ReleaseNotesConsentPreference` style, so it stays greppable and a
revert leaves one inert key.

No part of the tip path MUST issue a network request of Cellar's own or spawn a `brew` process. The
payment itself is Apple's request, not Cellar's.

#### Scenario: The thank-you survives a relaunch

- GIVEN a `completed` outcome recorded and the preference store re-read from scratch
- WHEN the flag is read back
- THEN it is set
- AND the stored record is a single boolean under a namespaced key

#### Scenario: Nothing else is remembered

- GIVEN a completed tip and the preference store's contents
- WHEN they are inspected
- THEN no date, count, transaction id, product id, price, or storefront was written
- AND the change's sources reference no `appAccountToken` and no iCloud synchronisation

#### Scenario: The tip path costs no egress and no brew process

- GIVEN a recording network seam and a recording process seam
- WHEN the catalog is loaded, a tip is purchased, finished and recorded
- THEN the network recorder saw no request of Cellar's own
- AND the process recorder saw no process spawned

#### Scenario: A non-completing outcome writes nothing

- GIVEN, in turn, `cancelled`, `pending`, `unverified`, `failed` and `unavailable` outcomes
- WHEN the preference store is read back after each
- THEN the flag is unset in every case

### Requirement: The copy is gratitude, never a nag, and the price is never a string

Tip copy MUST be gratitude-based. It MUST NOT beg, guilt, count down, claim the app is at risk, or
imply that any feature depends on tipping. Cellar MUST NOT show a launch-time tip prompt, modal,
sheet, banner, toast, or badge, and MUST NOT re-ask after any outcome — the surface is entered by
the user, never pushed. There MUST be exactly one moment where a tip is offered, and it is the one
the user navigated to.

Every price shown anywhere MUST come from the loaded product's localized display price. A literal
price string MUST NOT appear in shipped source, in copy, or in any test assertion; `$0.99` is a
price tier recorded in the PRD, not a string this app may render.

Guideline 3.1.1's exclusivity is a requirement, not a note: this capability MUST NOT add an external
payment link, button, or language directing the user to pay outside the app (Ko-fi, GitHub Sponsors,
Stripe, or any other), because a binary that transacts StoreKit may not also carry one.

#### Scenario: No price literal exists anywhere

- GIVEN the change's shipped sources and its tests
- WHEN they are inspected structurally
- THEN no literal price string appears in any of them
- AND every rendered price is read from the loaded product's display price

#### Scenario: Nothing is shown at launch

- GIVEN a launched app with an available tip surface and no recorded thank-you
- WHEN launch completes
- THEN no tip prompt, modal, sheet, banner, toast, or badge was presented
- AND the tip is reachable only by the user navigating to it

#### Scenario: A dismissed tip is never re-asked

- GIVEN a `cancelled` outcome
- WHEN the app continues running and is relaunched
- THEN no follow-up prompt, reminder, or escalated copy is presented

#### Scenario: No external payment link ships

- GIVEN the change's shipped sources and its user-facing copy
- WHEN they are inspected
- THEN no external payment or donation URL and no language directing purchase outside the app is
  present

### Requirement: One purchase call site, and no new section

The tip MUST be offered from exactly **one** purchase call site: a card in Settings beside the
existing "Cellar is free" card. That card MUST be additive — the existing free-app copy MUST remain
unchanged. About MUST carry **one static informational row** that names Settings as
where tipping lives. That row MUST be present only when the tip surface is available, MUST NOT
navigate, and MUST NOT purchase — it is a signpost, not a control, so there is a single place where
a purchase can be initiated and a single place to prove correct. (An About row that actually opened
Settings would require changing the root content view, which owns the selected section as private
state and is a not-touched binding of this change.)

This capability MUST NOT introduce a new `AppSection` case. `AppSection`, the root content view and
the placement test suite are a **not-touched binding**: a whole navigable page for one button
exceeds the PRD's "single subtle" instruction and would cost a new case across six exhaustive
switches.

#### Scenario: Exactly one purchase call site exists

- GIVEN the app target's sources
- WHEN they are inspected structurally
- THEN exactly one file invokes the purchasing seam
- AND the About surface invokes neither the purchasing seam nor any navigation

#### Scenario: The About row is a signpost, and only when there is something to point at

- GIVEN an available tip surface, and separately an unavailable one
- WHEN the About surface is inspected in each case
- THEN the informational row is present in the first case and absent in the second
- AND in the first case it names Settings as the location and carries no action of any kind

#### Scenario: The section enumeration is untouched

- GIVEN the shipped `AppSection` enumeration and its placement suite
- WHEN the suite runs with this change present
- THEN the case count and ordering assertions pass unchanged
- AND no case named for support, tips, or donations exists

#### Scenario: The existing free-app card is unchanged

- GIVEN the Settings surface before and after this change
- WHEN the free-app card's copy is compared
- THEN it is identical
- AND the tip card is an addition beside it

### Requirement: StoreKit lives behind exactly one seam

`CellarCore`'s `TipJar` target MUST have **zero dependencies**, making "the tip jar cannot reach
brew, the catalog, the network client, or SwiftData" a build-graph fact rather than a convention. It
MUST declare `TipCatalogLoading` and `TipPurchasing` as protocols and MUST NOT import StoreKit.

`import StoreKit` MUST appear in **exactly one** file under the app target, the conformer that
adapts StoreKit to those two seams. No view file MUST reference `Product`, `Transaction`, or
`AppStore`. Every outcome named in this spec MUST be reachable from fake seams in the core package's
test suite without StoreKit linkage, and the conformer itself MUST additionally be exercised against
a real local StoreKit test session that loads the product, completes a purchase, and verifies the
transaction — with no Xcode scheme modified.

The StoreKit configuration used by tests MUST live with the tests and MUST NOT be a resource of the
shipping app bundle. UI tests MUST continue to run with zero egress and zero StoreKit, through the
app's existing test-fixture seam.

#### Scenario: The tip target depends on nothing

- GIVEN the core package manifest
- WHEN the `TipJar` target is inspected
- THEN its dependency list is empty
- AND its sources contain no `import StoreKit`

#### Scenario: StoreKit is imported exactly once

- GIVEN every source file in the app target
- WHEN their imports are inspected
- THEN exactly one file imports StoreKit
- AND no view file references `Product`, `Transaction`, or `AppStore`

#### Scenario: The conformer is proven against a real local store

- GIVEN a local StoreKit test session configured with the tip product
- WHEN the conformer loads the catalog and purchases the tip
- THEN one product is returned and the purchase yields a verified, finished transaction
- AND no Xcode scheme was modified to make this run

#### Scenario: The test store configuration never ships

- GIVEN a release build of the app
- WHEN its bundled resources are inspected
- THEN the StoreKit configuration file is absent from the app's own resources
- AND it is present only in the test bundle

#### Scenario: UI tests stay at zero egress and zero StoreKit

- GIVEN the app launched under its UI-test fixture configuration
- WHEN the tip surface is exercised
- THEN the seams in use are fakes
- AND no StoreKit request and no network request was issued
