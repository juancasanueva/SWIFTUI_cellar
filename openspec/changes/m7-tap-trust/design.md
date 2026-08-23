# Design: Tap Trust as a First-Class, Honest Capability (`m7-tap-trust`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks`

**Inputs, and what changed since revision 1.** All four spec deltas are now on disk and were read in
full before this revision: `specs/{tap-management,package-mutation,brewfile-management,installed-inventory}/spec.md`
(**89 scenarios** after amendment #3 added the BF5 bare-token scenario (40/30/11/8), mapped one-by-one in *Scenario Coverage* below). Plus `proposal.md` (obs `#7726`),
`explore.md` (obs `#7723`), probes obs `#7721`, `#7722`, `#7724`, and the maintainer's binding
decisions **D1**, **D2** (proposal) and **D3** (obs `#7730`, 2026-08-23). Revision 1 was failed by the
design validator on two High findings; **DD-7** and **DD-8** below are rewritten, and DD-3, DD-6,
DD-11, DD-12 are corrected. Every validator finding is answered in *Validator Findings — Where Each Is
Resolved*.

> **Size note.** This document exceeds the 800-word default by explicit launch-brief instruction: a
> security-relevant capability grant needs exact Swift, `openspec/config.yaml` `rules.design` requires
> actor-isolation and protocol-boundary statements, and the brief requires an 89-scenario coverage map.
> The archived `m6-cask-tap` and `m6-release-pipeline` designs carry the same note. Density is
> preserved with tables; nothing is padded.

## Technical Approach

Four separable pieces, ordered by how much of the security surface each touches:

1. **Read** — one new optional key in an existing payload becomes a three-valued type. No new command,
   no new store, no new invalidation domain, no new protocol seam.
2. **Represent absence honestly** — `InstalledPackage.tap` becomes `String?` and `TapProjection` gains
   a third typed installed state, so a withheld tap stops being reported as "not installed".
3. **Two new argv vectors behind two explicit answers** — `brew trust` is confirmed, `brew untrust` is
   not, and every removal prepends the revocation.
4. **One new terminal outcome, and one prohibition** — brew's refusal is classified from **nothing but
   a structural phrase**, and no argv Cellar spawns ever carries a `/`-qualified package token, on any
   path, including a Brewfile import (**D3**).

`rules.design` compliance is structural: every new type lives in
`Packages/CellarCore/Sources/BrewClient`, the app target gains views and two `@MainActor` DI closures,
the external boundary stays the shipped `BrewMutating.brewCommand` → `BrewCommand.mutate` argv seam
(no new `Process`, `FileManager` or network dependency), and there is no `#available` branch — macOS 26
is the floor.

The engineering content is **not** the two new argv vectors. It is DD-3 (how a batch chooses its
disclosure), DD-7 (what may be read out of brew's refusal — nothing) and DD-8 (where the qualified
token is stripped), because those three are where this change could quietly become the bypass it
exists to forbid.

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-1** | `TapTrustState { trusted, untrusted, unreported }` on `TapRecord`, decoded from `TapWire.trusted` with `decodeIfPresent(Bool.self)` | `Bool` with `false` as the default | Proposal *Implied and binding*; TM12 :420-423. "Not reported" is not "reported false" — the identical rule `InstalledPackage.declaresAutoUpdates` already states. This one choice **is** the whole Homebrew < 6 mitigation |
| **DD-2** | `ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)`; new `.tapTrustGrant(TapName)` | Keeping a case named `tapTrust` on a command that grants nothing | **D2**, binding. The old name is the lie; the cross-spec churn is the change |
| **DD-3** *(rewritten)* | `BrewMutating.disclosure` **stays non-optional** with its shipped `.packageRemoval` protocol default. A **new** requirement `declaredDisclosure: ConfirmationDisclosure?` (protocol default `nil`) carries "what this command declares of its own", and `Collection.leadDisclosure` returns the first non-`nil` `declaredDisclosure`, else `.packageRemoval` | Revision 1's "make `disclosure` optional": it breaks `ConfirmationDisclosureTests.swift:161-178` (the protocol-default proof) and forces the `:203` ban on caller-side `?.disclosure ??` to be re-litigated. Also rejected: `declaresDisclosure: Bool` beside `disclosure` (two facts that can disagree); reordering the batch (revocation must precede removal); giving `.untrustTap` its own disclosure (a force sheet would lead with revoke copy); submitting the untrust outside the confirmed batch (runs a command the sheet never listed, breaking PM3) | PM1 :64-73 needs exactly two facts per command — *does it declare one*, and *what does a confirmation show*. Two members express them without either becoming derivable from the other: `disclosure` keeps meaning "what a confirmation over this command alone shows" (unchanged, still defaulted **in the protocol**, never by a caller), and `declaredDisclosure` is the skip predicate. `disclosure`'s default is redefined as `declaredDisclosure ?? .packageRemoval`, so one source of truth remains |
| **DD-4** | Untap = `[.untrustTap, .removeTap]`; Force Untap = `[.untrustTap, .forceRemoveTap]`, both through **one** `submitSequence` mirroring the shipped `submitBulk` shape | Two independent submissions from the view | `submitBulk` (`OperationCenterBulk.swift:113-124`) already encodes the required semantics: `request(commands)` covers the **whole** sequence, so declining submits none of it (PM3 :238-243) and confirming submits all of it in order. Plain untap needs no confirmation because neither member requires one, so `request` returns `nil` and both submit — TM7 :219-220 holds untouched |
| **DD-5** | The revocation is **unconditional** — including for an `unreported` tap — and its failure does not block the removal | Gate the untap on a successful untrust; skip the untrust when the state is not `trusted` | TM7 :221-231 states both halves as rules. `brew untrust` on a never-trusted tap exits 0 (obs `#7722`), so no precondition exists to check; blocking removal on a failed revoke would leave the user unable to remove the tap at all. **Homebrew < 6 consequence, stated rather than discovered:** a brew with no `untrust` verb makes *every* untap show a visibly failed `untrust` item in Activity beside a succeeding `untap`. That is the spec's own choice (TM7 :228-231: the failure "MUST appear as its own visible operation … rather than being swallowed"), not a defect — see R5 |
| **DD-6** *(corrected)* | `Signature.isUntrustedTap` matches the **single** structural phrase `"untrusted tap"`, case-sensitively, over the shipped **20-line** stderr tail (`MutationOutcome.tailLength`, unchanged) | The spec delta's current two-phrase OR (`"Refusing to load"` **or** `"from untrusted tap"`) | `"Refusing to load"` alone is not structural about trust — brew refuses to load things for reasons a grant would not fix, and a false positive offers a **Trust button** for one of them, which is a security-relevant misdirection rather than a wrong sentence. `"untrusted tap"` is the substring of the measured cask wording (obs `#7721`) and of any plausible formula wording, and cannot collide with the shipped lock or privilege phrases. Case-sensitive `line.contains(_:)` mirrors `Signature.isLock` / `isPrivilege` (`MutationOutcome.swift:128-134`) exactly. A miss degrades to `.failed` with the verbatim log; widening later needs no structural change. **This design owns the literal match strings by the spec's own division of labour (package-mutation :35-36), so the delta's two-phrase sentence is amended to match — see Spec Amendments #1** |
| **DD-7** *(rewritten — validator HIGH)* | `case refusedUntrustedTap` carries **no associated value**. Nothing whatsoever is parsed out of the payload. The recovery derives its tap from **Cellar's own `tap-info` snapshot**: `UntrustedTapRecovery.trustableTap(forRefused:in:)` returns the single `untrusted`, third-party tap whose published `formulaNames`/`caskTokens` contain the refused command's exact `(kind, name)`. Exactly one candidate ⇒ `Button("Trust")`; zero or two-or-more ⇒ **no button**, and the typed message's own sentence — "Trust the tap in Taps, then try again." — is the path | Revision 1's `refusedUntrustedTap(tap: TapName?)` parsed from stderr and validated through `TapName.init?` | PM10 :293-295 is literal: "**nothing extracted from the payload**. No tap name, package name, qualified token or suggested command MUST be parsed out of the message." Revision 1 argued a parsed-then-validated value was "strictly stronger"; it is not — it is an extraction, and PM10 :340-346 asserts the absence. The snapshot derivation needs no bytes from brew at all: the refused `PackageID` is one Cellar itself typed (`ActivityItem.command.packageID`), and the candidate set comes from the payload Cellar already holds. The one-candidate rule is what keeps it honest — with two publishers Cellar genuinely does not know which tap brew meant, and guessing would grant the wrong capability |
| **DD-8** *(rewritten — validator HIGH)* | **No `/` gate is added to `PackageTarget.init?` or `MutationName.isSafe`; both stay byte-identical.** Per **D3**, the *Brewfile plan* strips the qualifier: `BrewfileEntry.installTarget` projects the bare token brew installs by, and `BrewfilePlan.init(selecting:)` builds its installs from that projection. The prohibition itself is asserted as an **absence over the whole argv surface** by a test that walks every command the plan and the mutation surface can build | Revision 1's `MutationName.isUnqualified` gate on `PackageTarget.init?` | The gate breaks `FormulaID(name: "acme/tap/thing")`, which `BrewfileEntryTests.swift:80-87` pins as a name "a real dump actually contains", and it would turn every qualified Brewfile line into an unrepresentable entry — contradicting BF5 :95-101 ("one ordinary package entry with **no skip counted**"). Stripping instead satisfies both: the line still parses and is still counted, the *argv* carries `thing`, and if `acme/tap` is untrusted brew refuses and PM10's typed outcome offers Trust as an explicit answer. Rejected with D3: a carve-out for user-authored qualified names (the file's author is exactly the party BF5 refuses to delegate to), and refusing qualified lines as skips (silently drops packages the user asked for) |
| **DD-9** | The batch rule is a named `Collection.leadDisclosure` and the shipped textual guard `#expect(code.contains("?.disclosure ??") == false)` (`ConfirmationDisclosureTests.swift:203`) **stays green, untouched** | Writing `commands.first(where:)?.declaredDisclosure ?? .packageRemoval` at the gate | That guard caught a caller-side fallback. `leadDisclosure`'s body spells `declaredDisclosure ?? .packageRemoval` — capital `D`, so the banned substring `?.disclosure ??` does not appear — and the gate reads one named member. The guard keeps its intent instead of being traded away. Its *positive* half (`"disclosure: first.disclosure"`, `:216`) is updated deliberately, RED-first |
| **DD-10** | `TapPackage` exposes a typed `TapPackageInstallState`; `uninstalledExplanation` (`TapProjection.swift:25-27`) is renamed `statusExplanation` | Adding a second boolean beside `isInstalled` | The middle state **is** installed, so a property named "uninstalled explanation" answers the wrong question in the one case this change exists to fix (TM5 :56-63) |
| **DD-11** *(kept; wording tightened)* | The `InstalledPackage.tap: String?` migration is **not** compiler-driven at its readers, and nothing in this design or the specs may claim it is | Proposal R8's "a compile error at every site" | Verified: Swift promotes the non-optional operand of `==`, so `$0.tap == tap` (`TapProjection.swift:146`), `$0.tap == tap.rawValue` (`ContentView.swift:546`) and `package.tap == "homebrew/core"` (`HomebrewUpdateNeed.swift:85-86`) all keep compiling **and stay semantically correct** (`nil` equals nothing). Only two decoder sites and the declaration change. The three readers are pinned by **`InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch`** (unit 5b) and by nothing else. Proposal :211/R8 and the installed-inventory delta's archive note still assert the compile error — Spec Amendments #5, #6 |
| **DD-12** | Both app-side lookups reach CellarCore through injected `@MainActor` closures in the shipped `currentForceEvidence` idiom (`ContentView.forceEvidence(for:)`, `ContentView.swift:538-551`): `trustableTap(for:)` for the Activity recovery, and the tap controls' submission closures for the detail view | Passing `TapStore` into `ActivityDrawer` | The drawer stays ignorant of tap storage; the closure is the only thing that can turn a refused `PackageID` into a typed command, and it is the existing precedent for exactly this shape |
| **DD-13** | Controls are `Button("Trust")` / `Button("Untrust")` string-literal form; badge text is exactly `"Untrusted"`, beside the tap name in the list row and in the detail header, with Trust inline in the header | A menu, a toggle, or `Button { } label: { }` | Maintainer default (2026-08-23). `TapShippingProofTests.swift:197` bans `Button {` outright, and `:219-224`'s `staticButtonLabels` regex only sees `Button("…")`, so the literal form is the only shippable one |
| **DD-14** | Force Untap stays **hidden** (not disabled-with-guidance) while a tap is untrusted, and the tap detail's trust-aware footer explains why | Treating a withheld tap as "incomplete inventory" and showing the disabled-with-guidance form | TM7 :233-236 draws the line by *what the cross-reference is*: a complete, current snapshot with **zero exact matches** exposes no force action; only an unavailable/stale/failed/incomplete snapshot gets guidance. A withheld tap yields a complete, current snapshot that matches nothing, so it is the zero-match branch — and this is **unchanged from today**, because the `""` sentinel already matched nothing. Recommended footer copy (tap-scoped, per TM12 :428-430): *"Homebrew withholds which packages came from this tap while it is untrusted, so Force Untap is unavailable. Trust the tap to see them, or use Untap."* |

## Data Flow

    brew tap-info --installed --json
            │  trusted: true | false | null | (absent)
            ▼
    TapWire.trusted: Bool?  ──►  TapRecord.trust: TapTrustState
            │                          │
            │                          ├──► TapProjection.trust(for:) ──► badge · Trust · Untrust
            │                          │        (.unreported ⇒ none of the three)
            │                          ▼
            │                    TapProjection.packages(for:installed:)
            │                          │
    brew info --installed --json=v2    │   InstalledPackage.tap: String?
            │  tap: null ──────────────┘        exact match  ⇒ .installed(id)
            ▼                                   nil + untrusted + published here
      InstalledDecoder (no `?? ""`)                          ⇒ .installedTapWithheld(id)
                                                otherwise   ⇒ .notInstalled
                                                      │
                                                      └─► "Show in Installed" in BOTH installed states

    Trust      ──► TapCommand.trustTap    ──► request([·]) ──► sheet(.tapTrustGrant) ──► ["trust",   tap]
    Untrust    ──► TapCommand.untrustTap  ──► submitSequence ─────── no sheet ───────► ["untrust", tap]
    Untap      ──► [.untrustTap, .removeTap]      ──► submitSequence ─► no sheet (neither confirms)
    Force Untap──► [.untrustTap, .forceRemoveTap] ──► submitSequence ─► ONE sheet, leadDisclosure
                                                                        skips untrust ⇒ .forceUntap
            │
            ▼  every terminal
    invalidates ──► MutationGates ──► taps ×1; installed inventory ×1 for trust/untrust/force

    Brewfile line  brew "acme/tap/thing"
            │  parses as an ordinary entry, counted, qualified name retained for display
            ▼
    BrewfileEntry.installTarget ─► bare token `thing` ─► MutationCommand.install ─► ["install","--formula","thing"]
                                                                         (D3: no `/` ever reaches argv)

    brew stderr tail (20 lines, stderr only, non-zero exit only)
            │  "… from untrusted tap acme/tools."
            ▼
    Signature.isUntrustedTap ──► .refusedUntrustedTap        ← carries NOTHING
            │                          │
            │                          ├─► message: the fixed, tap-scoped sentence
            │                          ▼
            └─ item.command.packageID ─► UntrustedTapRecovery.trustableTap(forRefused:in: TapInventory)
                                              │ exactly one untrusted publisher ⇒ Button("Trust")
                                              │ zero or many                    ⇒ no button
                                              ▼
                                      operations.request(.trustTap(tap)) ──► confirmation sheet

## Interfaces / Contracts

### 1. Trust state — `TapWire.swift`

```swift
/// What Homebrew reports about a tap's trust grant.
///
/// Three-valued rather than `Bool`: an absent or null `trusted` key is a
/// Homebrew with no trust concept, which is not the same fact as a Homebrew
/// reporting `false` (tap-management TM12; the identical rule
/// `InstalledPackage.declaresAutoUpdates` states for `auto_updates`).
public enum TapTrustState: Sendable, Equatable {
    case trusted
    case untrusted
    case unreported
}

// TapRecord gains, after `lastCommit` (init default `.unreported`, so every
// shipped fixture and call site keeps compiling):
public let trust: TapTrustState

// TapWire (private) gains `case trusted` in CodingKeys and:
trusted = try container.decodeIfPresent(Bool.self, forKey: .trusted)

// TapDecoder.inventory(from:) maps it, and nothing else changes:
trust: wire.trusted.map { $0 ? .trusted : .untrusted } ?? .unreported
```

`decodeIfPresent` returns `nil` for **both** an absent key and an explicit JSON `null`, which is
exactly TM12 :432-438's four-way requirement.

### 2. Commands and disclosures — `TapCommand.swift`

```swift
public enum ConfirmationDisclosure: Sendable, Hashable {
    case packageRemoval
    case tapAdd(TapName)
    case tapTrustGrant(TapName)
    case forceUntap(tap: TapName, affected: Set<PackageID>)

    public var warningText: String {
        switch self {
        case .packageRemoval:
            "This removes installed software."
        case .tapAdd(let tap):
            """
            Adding \(tap.rawValue) clones a third-party repository. Homebrew \
            will not load its formulae or casks until you trust it, and Cellar \
            does not trust it for you.
            """
        case .tapTrustGrant(let tap):
            """
            Trusting \(tap.rawValue) lets Homebrew load and run its formulae \
            and casks. That is third-party code running as you, with your \
            permissions.
            """
        case .forceUntap(let tap, let affected):
            "Force-removing \(tap.rawValue) affects \(affected.count) installed packages."
        }
    }
}

public enum TapCommand: Sendable, Equatable, BrewMutating {
    case addTap(TapName)
    case trustTap(TapName)
    case untrustTap(TapName)
    case removeTap(TapName)
    case forceRemoveTap(ForceUntapEvidence)

    public static func trust(_ raw: String) -> TapCommand? { TapName(raw).map(TapCommand.trustTap) }
    public static func untrust(_ raw: String) -> TapCommand? { TapName(raw).map(TapCommand.untrustTap) }

    /// What the Untap action means, whole: revoke the grant, then remove the
    /// tap. Order is load-bearing — the untrust must run while the tap still
    /// resolves — and unconditional, because `brew untrust` on a never-trusted
    /// tap exits 0 (obs #7722) and because Cellar must not decide from a state
    /// it may be reading from a brew that reports none. Without this, untapping
    /// leaves a dormant, invisible grant in `trust.json` that a later Brewfile
    /// import re-arms with no new consent (tap-management TM7).
    public static func removal(of raw: String) -> [TapCommand]? {
        guard let tap = TapName(raw) else { return nil }
        return [.untrustTap(tap), .removeTap(tap)]
    }

    public static func forcedRemoval(evidence: ForceUntapEvidence) -> [TapCommand]? {
        guard let forced = forceUntap(evidence: evidence) else { return nil }
        return [.untrustTap(evidence.tap), forced]
    }

    public var arguments: [String] {
        switch self {
        case .addTap(let tap): ["tap", tap.rawValue]
        case .trustTap(let tap): ["trust", tap.rawValue]
        case .untrustTap(let tap): ["untrust", tap.rawValue]
        case .removeTap(let tap): ["untap", tap.rawValue]
        case .forceRemoveTap(let evidence): ["untap", "--force", evidence.tap.rawValue]
        }
    }

    public var verb: String {
        switch self {
        case .addTap: "tapAdd"
        case .trustTap: "tapTrust"
        case .untrustTap: "tapUntrust"
        case .removeTap: "tapUntap"
        case .forceRemoveTap: "tapForceUntap"
        }
    }

    public var packageID: PackageID? { nil }   // trust is a property of a tap (TM13 :475)

    public var requiresConfirmation: Bool {
        switch self {
        case .addTap, .trustTap, .forceRemoveTap: true
        case .removeTap, .untrustTap: false      // a revocation only reduces authority
        }
    }

    /// A grant and a revocation both change what `brew info --installed` reports
    /// as a package's `tap` (obs #7724), so both invalidate installed inventory
    /// as well as taps (TM9). Catalog is never invalidated by a tap command.
    public var invalidates: InvalidationScope {
        switch self {
        case .addTap, .removeTap: .taps
        case .trustTap, .untrustTap: [.taps, .installedInventory]
        case .forceRemoveTap: [.taps, .installedInventory, .diskUsage]
        }
    }

    /// What this command declares **of its own** (DD-3). `nil` for the two
    /// commands that have nothing to disclose.
    public var declaredDisclosure: ConfirmationDisclosure? {
        switch self {
        case .addTap(let tap): .tapAdd(tap)
        case .trustTap(let tap): .tapTrustGrant(tap)
        case .removeTap, .untrustTap: nil
        case .forceRemoveTap(let evidence):
            .forceUntap(tap: evidence.tap, affected: evidence.affected)
        }
    }
}
```

`TapCommand` no longer declares `disclosure` at all — it inherits the protocol default, which is now
`declaredDisclosure ?? .packageRemoval`. Every argv arm is a literal verb plus `tap.rawValue`, so
`MutationCommandTests.swift:289`'s "no `\(`, `joined(`, `split(` in an `arguments` body" scan stays
green with no exemption.

### 3. The batch-disclosure rule (DD-3, DD-9) — `BrewMutating.swift`

```swift
public protocol BrewMutating: Sendable {
    // … arguments, verb, packageID, requiresConfirmation, invalidates,
    //    diskAreas, environmentOverrides, classify — all unchanged …

    /// The warning **one confirmation over this command alone** must lead with.
    /// Unchanged: still a protocol requirement with a protocol-supplied default,
    /// never a caller's `??` (package-mutation PM1 :60-63).
    var disclosure: ConfirmationDisclosure { get }

    /// The warning this command declares **of its own**.
    ///
    /// `nil` means "this command has nothing of its own to disclose", which is a
    /// different fact from "it discloses the ordinary removal text" — and the
    /// batch rule below exists only because those two must be distinguishable.
    /// Prepending a revocation to a force untap makes the batch head a command
    /// with nothing to say; under the shipped rule that silently downgraded the
    /// force-untap disclosure to "This removes installed software.", which is
    /// the exact defect PM1 was written to fix.
    var declaredDisclosure: ConfirmationDisclosure? { get }
}

extension BrewMutating {
    public var declaredDisclosure: ConfirmationDisclosure? { nil }
    /// One source of truth: the default is *derived* from the declaration, so a
    /// conformer cannot declare one warning and present another.
    public var disclosure: ConfirmationDisclosure { declaredDisclosure ?? .packageRemoval }
}

extension Collection where Element: BrewMutating {
    /// The disclosure one confirmation over this whole batch must lead with: the
    /// first command that declares one of its own, skipping every command that
    /// relies on the protocol default. Submission order, never severity — the
    /// first *declaring* command wins (package-mutation PM1 :68-73).
    public var leadDisclosure: ConfirmationDisclosure {
        for command in self {
            if let declared = command.declaredDisclosure { return declared }
        }
        return .packageRemoval
    }
}

// AnyBrewMutation — the ninth projection, stored beside the eighth. Both are
// copied from the same command in its single initialiser, so they cannot
// disagree; there is no memberwise init that could let them.
public let disclosure: ConfirmationDisclosure
public let declaredDisclosure: ConfirmationDisclosure?

// OperationCenterBulk.request(_ commands:) — the one behavioural line:
disclosure: commands.leadDisclosure          // was: disclosure: first.disclosure

// ConfirmationRequest.tapIdentity gains the two new cases:
case .tapAdd(let tap), .tapTrustGrant(let tap), .forceUntap(let tap, _): tap
case .packageRemoval: nil
```

**Every conformer, and what it declares** (from the graph: eight conformances, two of them test
probes):

| Conformer | `declaredDisclosure` | `disclosure` | Change |
|---|---|---|---|
| `TapCommand` | `.tapAdd` / `.tapTrustGrant` / `.forceUntap` / `nil` ×2 | inherited | rewritten (was an overridden `disclosure`) |
| `MutationCommand` | `nil` (default) | `.packageRemoval` | none |
| `ServiceCommand` | `nil` (default) | `.packageRemoval` | none |
| `CleanupCommand` | `nil` (default) | `.packageRemoval` | none — cleanup carries its own typed `cleanupDisclosure` and never consults the batch head (`ConfirmationDisclosureTests.swift:140-154`) |
| `TerminalCleanupProbe` | `nil` (default) | `.packageRemoval` | none |
| `AnyBrewMutation` | stored, copied at init | stored, copied at init | +1 stored member |
| `ProbeMutation` (test) | `nil` (default) | `.packageRemoval` | none — it exists to prove the default is real |
| `DisclosingProbe` (test, `BrewMutatingTests.swift:257-264`) | stored `var declaredDisclosure` | inherited | `var disclosure` → `var declaredDisclosure`; the two use sites at `:279` and `:292` follow |

**Exact RED-first test updates for unit 8** (nothing else in these files moves):

| Site | Today | After | Why |
|---|---|---|---|
| `ConfirmationDisclosureTests.swift:161-178` | protocol-default proof; `:176-177` name `.tapTrust` | **unchanged except the D2 rename** at `:176-177` (`.tapTrust` → `.tapAdd`), owned by unit 3 | DD-3 keeps `disclosure` non-optional precisely so `:167`, `:169` and `:173` stay byte-identical |
| `ConfirmationDisclosureTests.swift:203` | bans `?.disclosure ??` | **unchanged, stays green** | `declaredDisclosure ?? .packageRemoval` does not contain that substring (capital `D`) |
| `ConfirmationDisclosureTests.swift:216` | `bulk.code.contains("disclosure: first.disclosure")` | `bulk.code.contains("disclosure: commands.leadDisclosure")` | the gate's positive half moves with the rule |
| `ConfirmationDisclosureTests.swift:223` | `spine.code.contains("var disclosure: ConfirmationDisclosure { get }")` | **unchanged**, plus a new sibling `#expect(spine.code.contains("var declaredDisclosure: ConfirmationDisclosure? { get }"))` | both facts are protocol requirements, not lucky concrete members |
| `ConfirmationDisclosureTests.swift:224-227` | `public let disclosure: ConfirmationDisclosure` on the erased value | **unchanged**, plus `public let declaredDisclosure: ConfirmationDisclosure?` | erasure must discard neither |
| `BrewMutatingTests.swift:257-264, :279, :292` | `DisclosingProbe.disclosure` varied directly | varies `declaredDisclosure`; `.tapTrust(tap)` → `.tapAdd(tap)` | the probe must declare, not merely present |
| `BrewMutatingTests.swift:231-240` | `divergent.count == 7` | **unchanged** | that list never contained `disclosure`; the disclosure/declaration pair is covered by `:274-293` |

### 4. Ordered submission — `OperationCenterBulk.swift`

```swift
/// Submits an ordered sequence of commands as **one** user action, asking once
/// when any member requires it.
///
/// The same shape as `submitBulk`, and for the same reason: one request covers
/// the whole sequence, so confirming submits every command it listed and
/// declining submits none of them — never a partial subset (package-mutation
/// PM3 :180-182). Each member still gets its own queue item, log, copy-command,
/// cancel and terminal outcome, which is what makes a failed revocation visible
/// instead of swallowed (TM7 :228-231).
@discardableResult
public func submitSequence(_ commands: [some BrewMutating]) -> ConfirmationRequest? {
    if let request = request(commands) { return request }
    for command in commands { submit(command) }
    return nil
}
```

### 5. Installed inventory, the withheld state, and one publication rule

```swift
// InstalledModels.swift:39,65,80 — `tap: String` becomes `tap: String?`
/// The tap the record came from. `nil` when Homebrew withheld it, which it does
/// for every package published by an untrusted tap (obs #7721). Absence is
/// preserved rather than collapsed, on exactly the terms II2 already states for
/// tri-state `auto_updates`, and it compares equal to no tap name at all.
public let tap: String?

// InstalledDecoder.swift:76,108 — the sentinel goes
tap: formula.tap        // was `formula.tap ?? ""`
tap: cask.tap           // was `cask.tap ?? ""`

// TapProjection.swift — one normalization, used by three callers, so they
// cannot drift (TM5 :44-51).
static func bareToken(_ published: String, publishedBy tap: String) -> String {
    let prefix = tap + "/"
    return published.hasPrefix(prefix) ? String(published.dropFirst(prefix.count)) : published
}

/// Whether this tap's own published set contains that exact `(kind, name)`.
/// The tap's published names are the only source; nothing else may claim a
/// package (TM5 :122-128).
static func publishes(_ id: PackageID, in tap: TapRecord) -> Bool {
    let published = id.kind == .formula ? tap.formulaNames : tap.caskTokens
    return published.contains { bareToken($0, publishedBy: tap.name) == id.name }
}

public enum TapPackageInstallState: Sendable, Equatable {
    case installed(PackageID)
    /// Installed, and Homebrew is withholding the tap that published it.
    case installedTapWithheld(PackageID)
    case notInstalled
}

private static func installState(
    _ id: PackageID,
    tap: TapRecord,
    inventory: InstalledInventory
) -> TapPackageInstallState {
    if inventory.packages.contains(where: { $0.id == id && $0.tap == tap.name }) {
        return .installed(id)
    }
    // Only while *this* tap is the one being withheld, and only for a package
    // this tap publishes. A record with no tap under a trusted or unreported tap
    // is not this tap's package, and claiming it would be the same false
    // statement in the other direction (TM5 :113-137).
    if tap.trust == .untrusted,
       inventory.packages.contains(where: { $0.id == id && $0.tap == nil }) {
        return .installedTapWithheld(id)
    }
    return .notInstalled
}

// TapPackage
public let state: TapPackageInstallState
public var isInstalled: Bool { state != .notInstalled }
public var installedHandoff: PackageID? {
    switch state {
    case .installed(let id), .installedTapWithheld(let id): id   // Show in Installed, both states
    case .notInstalled: nil
    }
}
public var statusExplanation: String? {          // was `uninstalledExplanation`
    switch state {
    case .installed: nil
    case .installedTapWithheld: "Installed. Homebrew withholds its tap while this tap is untrusted."
    case .notInstalled: "Not installed."
    }
}
```

`packages(for:installed:)` iterates this tap's own `formulaNames` / `caskTokens`, so the
"this tap publishes this exact `(kind, name)`" clause is satisfied by construction for the inventory
path; `publishes(_:in:)` is the same rule made callable for the recovery path (DD-7). PD6 is
untouched — no tap package enters the catalog.

### 6. Trust presentation — `TapProjection.swift`

```swift
/// Badge and controls as **one** value, so the three facts cannot disagree and
/// the list row, the detail header and the tests read one projection
/// (TM12 :425-427, :456-461).
public struct TapTrustPresentation: Sendable, Equatable {
    public let badge: String?     // nil ⇒ nothing may be claimed
    public let canGrant: Bool     // show "Trust"
    public let canRevoke: Bool    // show "Untrust"
}

public static func trust(for tap: TapRecord) -> TapTrustPresentation {
    switch tap.trust {
    case .untrusted:  TapTrustPresentation(badge: "Untrusted", canGrant: true,  canRevoke: false)
    case .trusted:    TapTrustPresentation(badge: nil,         canGrant: false, canRevoke: true)
    // A Homebrew that reports nothing gets no badge and neither control, and
    // neither control ever builds or spawns a process.
    case .unreported: TapTrustPresentation(badge: nil,         canGrant: false, canRevoke: false)
    }
}
```

Official taps never reach this surface: `TapProjection.officialNames` filters them (`:62`) and TM4
keeps them non-mutable, so "do official taps report `trusted`?" cannot affect any control.

### 7. Refusal classification — `MutationOutcome.swift` (DD-7)

```swift
/// Homebrew refused to load the package because the tap publishing it is not
/// trusted. Nothing ran.
///
/// **No associated value, deliberately.** Not one byte of the refusal is parsed,
/// captured or echoed — no tap name, package name, qualified token or suggested
/// command (package-mutation PM10 :293-295). The recovery finds its tap in
/// Cellar's own snapshot instead (`UntrustedTapRecovery`), so the only thing
/// brew's message does is answer "was this a trust refusal?".
case refusedUntrustedTap

// classify(…), after the lock and privilege checks and before `.failed`.
// Reached only on a non-zero exit, and reading only the stderr tail — so
// stdout never classifies and a success never classifies, unchanged.
if tail.contains(where: Signature.isUntrustedTap) { return .refusedUntrustedTap }

// Signature (private, inside MutationOutcome — the shipped idiom, case-sensitive
// `contains`, exactly as `isLock` and `isPrivilege`):
/// One phrase, not two (design DD-6). `"untrusted tap"` is the substring of the
/// measured cask refusal (obs #7721) and of any plausible formula wording, and it
/// cannot collide with the lock or privilege phrases. `"Refusing to load"` alone
/// was rejected: brew refuses to load things for reasons trust would not fix, and
/// a false positive here offers a Trust button for one of them.
static let untrustedTap = "untrusted tap"

static func isUntrustedTap(_ line: String) -> Bool { line.contains(untrustedTap) }

// message(for:) — the spec's sentence verbatim, tap-scoped and tap-agnostic
// (PM10 :308-310):
case .refusedUntrustedTap:
    """
    Homebrew refused to load this package because its tap is not trusted. \
    Trust the tap in Taps, then try again.
    """

// summaryLabel
case .refusedUntrustedTap: "Tap not trusted"
// isFailure — true: the command did not run.
```

**The recovery, as a pure projection** — new file
`Packages/CellarCore/Sources/BrewClient/UntrustedTapRecovery.swift`:

```swift
/// Which tap Cellar may offer to trust after a refusal — derived from Cellar's
/// own `tap-info` snapshot, never from brew's message.
///
/// The input identity is one **Cellar typed itself** (`ActivityItem.command.packageID`),
/// and the candidate set is the taps Cellar already holds. That is what makes
/// PM10's "nothing extracted" absolute while still offering the affordance
/// PM10 :348-354 requires.
///
/// Exactly one candidate or nothing: with two untrusted publishers of the same
/// `(kind, name)` Cellar genuinely does not know which tap brew meant, and
/// guessing would grant the wrong capability. In that case the typed message's
/// own sentence — "Trust the tap in Taps, then try again." — is the path, and
/// no button is shown.
public enum UntrustedTapRecovery {
    public static func trustableTap(
        forRefused package: PackageID?,
        in inventory: TapInventory
    ) -> TapName? {
        guard let package else { return nil }          // upgradeAll and every non-package command
        let candidates = inventory.taps.filter { record in
            record.trust == .untrusted
                && !TapProjection.officialNames.contains(record.name.lowercased())
                && TapProjection.publishes(package, in: record)
        }
        guard candidates.count == 1, let only = candidates.first else { return nil }
        return TapName(only.name)
    }
}
```

`ActivityDrawer` renders `Button("Trust")` only when the injected `@MainActor` closure returns a
`TapName`, and submits `operations.request(.trustTap(tap))` — the ordinary confirmed grant, never a
retry of the refused command (TM13 :513-519).

### 8. The argv prohibition and the Brewfile bare token (D1, D3, PM10) — DD-8

**No source gate changes.** `MutationName.isSafe` (`MutationCommand.swift:130-133`) and
`PackageTarget.init?` (`:44-47`) are byte-identical after this change; `TapName.init?` keeps using
`isSafe` and a tap name stays `owner/repo`.

```swift
// BrewfileEntry.swift — the strip, as a projection on the entry, so the plan
// composes no strings and the rule is unit-testable on the entry alone.
extension BrewfileEntry {
    /// The identity that will actually be installed: the bare token brew
    /// installs by, with any `owner/tap/` qualifier removed (**D3**).
    ///
    /// Homebrew 6 treats *naming* a qualified package on the command line as a
    /// per-package trust grant (`trust.rb#explicitly_allowed?`), so a file's
    /// `brew "acme/tap/thing"` must not be forwarded as argv: that would let the
    /// file's author grant trust on the importing user's Mac — exactly the party
    /// BF5 refuses to delegate a trust decision to. The line still parses as an
    /// ordinary entry and is still counted; what runs is
    /// `install --formula thing`, and if `acme/tap` is untrusted brew refuses and
    /// PM10's typed outcome offers Trust as an explicit answer.
    ///
    /// `nil` for a tap entry, which installs nothing, and for a degenerate
    /// qualified name whose last component is empty — `PackageTarget` refuses it
    /// rather than silently installing the component before it.
    public var installTarget: PackageTarget? {
        guard let id = packageID else { return nil }
        return PackageTarget(PackageID(kind: id.kind, name: Self.bareToken(id.name)))
    }

    /// The token that will appear in argv, for the import row to show.
    public var installName: String? { installTarget?.name }

    /// Empty components included on purpose: `acme/tap/` yields `""`, which does
    /// not construct, instead of yielding `tap`, which would install the wrong
    /// package.
    static func bareToken(_ name: String) -> String {
        guard let last = name.split(separator: "/", omittingEmptySubsequences: false).last
        else { return name }
        return String(last)
    }
}

// BrewfilePlan.swift:34-43 — the only behavioural change in this file.
for entry in entries {
    switch entry.kind {
    case .tap(let name, _):
        taps.append(.addTap(name))
    case .formula, .cask:
        // The entry's own projection, not a string this type composed. An entry
        // whose bare token cannot construct produces no command, and the import
        // must not present it as applied (BF7, amended — see Spec Amendments #3).
        if let target = entry.installTarget { installs.append(.install(target)) }
    }
}
```

**Import row presentation.** The row's title is the token that will be installed (`installName`), and
when the file's own token differs it is shown verbatim as the row's secondary detail. No sentence
claims anything about trust; `BrewfileEntry.displayName`'s doc comment ("the same token the file
contained … as it will appear in argv") becomes false and is corrected in the same commit.

**The prohibition is an absence, asserted over the whole surface** (unit 7): a test walks every argv
every command family on the spine can produce — every `MutationCommand` factory and `naming(_:)`
build, every `TapCommand` case, and every command a `BrewfilePlan` built from a qualified-name
fixture emits — and asserts that **no `MutationCommand` argv element contains `/`** and that no argv
element of any family contains two or more `/`. It is positively anchored: the fixture set is
non-empty, `TapCommand.addTap` really does produce exactly one `/`, and the qualified Brewfile entry
really does produce `install --formula thing`.

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapWire.swift` | Modify | `TapTrustState`; `TapWire.trusted`; `TapRecord.trust`; decoder mapping |
| `.../BrewClient/TapCommand.swift` | Modify | `.trustTap` / `.untrustTap`; `.tapAdd` / `.tapTrustGrant`; `removal(of:)` / `forcedRemoval(evidence:)`; argv, verb, confirmation, invalidation and `declaredDisclosure` arms |
| `.../BrewClient/BrewMutating.swift` | Modify | `declaredDisclosure` requirement + `nil` default; `disclosure` default derived; `Collection.leadDisclosure`; `AnyBrewMutation` stores both |
| `.../BrewClient/OperationCenterBulk.swift` | Modify | `disclosure: commands.leadDisclosure`; `submitSequence`; `tapIdentity` arms |
| `.../BrewClient/TapProjection.swift` | Modify | `TapTrustPresentation`, `trust(for:)`, `bareToken`, `publishes(_:in:)`, `TapPackageInstallState`, `installState`, `TapPackage.state` / `statusExplanation` |
| `.../BrewClient/UntrustedTapRecovery.swift` | **New** | The one-candidate recovery projection (DD-7) |
| `.../BrewClient/InstalledModels.swift` :39, :65, :80 | Modify | `tap: String?` |
| `.../BrewClient/InstalledDecoder.swift` :76, :108 | Modify | `?? ""` removed |
| `.../BrewClient/MutationOutcome.swift` | Modify | `.refusedUntrustedTap` (no payload); `Signature.untrustedTap` + `isUntrustedTap`; `message` / `summaryLabel` / `isFailure` arms |
| `.../BrewClient/BrewfileEntry.swift` | Modify | `installTarget`, `installName`, `bareToken`; `displayName` doc corrected (**D3**) |
| `.../BrewClient/BrewfilePlan.swift` :34-43 | Modify | installs are built from `entry.installTarget` (**D3**) — this file is **no longer a 0-line binding** |
| `.../BrewClient/MutationCommand.swift` | **Untouched — binding** | `isSafe` and `PackageTarget.init?` are byte-identical (DD-8) |
| `cellar/Taps/TapsListView.swift` | Modify | `Untrusted` badge beside the tap name in the row. **No button** |
| `cellar/Taps/TapDetailView.swift` | Modify | Badge in the header; `Button("Trust")` / `Button("Untrust")` inline; untap and force untap submit sequences; trust-aware footer (:183) incl. the DD-14 sentence |
| `cellar/Activity/MutationConfirmation.swift` :153, :168 | Modify | `.tapAdd` → "Add this tap?" / "Add Tap"; `.tapTrustGrant` → "Trust this tap?" / "Trust" |
| `cellar/Activity/ActivityDrawer.swift` | Modify | The `.refusedUntrustedTap` recovery `Button("Trust")`, shown only for a unique publisher |
| `cellar/ContentView.swift` | Modify | `trustableTap(for:)` closure in the `forceEvidence(for:)` idiom (:538-551); wiring for the two detail controls |
| `cellar/Brewfile/…` import row | Modify | Title shows `installName`; the file's qualified token becomes secondary detail |
| `PRD.md` §3.7 :108 | Modify | Honest tap-versus-trust line |
| `Packages/CellarCore/Tests/BrewClientTests/*` (10 files) + `cellarTests` (2) + `cellarUITests` | Modify/New | See *Testing Strategy* |

### Readers of `InstalledPackage.tap` — the complete list (DD-11, R8)

| Site | Change | Why |
|---|---|---|
| `TapProjection.swift:146` | none | `String? == String` promotes; `nil` matches nothing, which is now the correct answer |
| `cellar/ContentView.swift:546` (`forceEvidence`) | none | Same promotion. A withheld package is excluded from the affected set, so Force Untap stays hidden for an untrusted tap — DD-14, fail-closed, and unchanged from today's `""` collapse |
| `cellar/Home/HomebrewUpdateNeed.swift:85-86` | none | Same promotion; a withheld package is not comparable against `homebrew/core` |
| `cellar/Casks/CaskInfoPopover.swift:77-78`, `cellar/Browse/PackageDetailView.swift:557` | **none — different type** | These read `CatalogPackage.tap`, which stays `String`. Both declare `let package: CatalogPackage` |
| `InstalledDecoder.swift:76,108` · `InstalledModels.swift:39,65,80` | Modify | The two sentinels and the declaration |
| Fixtures (`Fakes/InstalledFixture.swift`, `TapProjectionTests`, `InstalledDeriveTests`, `SecurityKitTests/NVDSourceTests`, `cellarTests/{HomeCompositionTests,BrewfileCompositionTests,HealthCompositionSupport,SecurityScopeArrangement,SecurityCompositionTests}`, `cellar/Installed/InstalledRow.swift`) | none | `String` literals promote to `String?` at the initialiser |

**Nine sites, three of them readers, and not one of them a compile error.** The migration is pinned by
`InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` (unit 5b), not by the compiler.

## Concurrency, Isolation and Sendable (`rules.design`)

| Element | Isolation | Note |
|---|---|---|
| `TapTrustState`, `TapTrustPresentation`, `TapPackageInstallState` | `nonisolated` value types, `Sendable` | CellarCore uses SwiftPM `nonisolated` defaults; all three are enums/structs of `Sendable` members |
| `TapRecord`, `TapInventory` | unchanged `Sendable, Equatable` | `trust` adds a `Sendable` member; synthesis unchanged |
| `TapDecoder.decode` | `@concurrent`, unchanged | One extra `decodeIfPresent` inside the existing off-main hop |
| `TapCommand`, `ConfirmationDisclosure`, `AnyBrewMutation` | `Sendable, Hashable` | `ConfirmationDisclosure?` is `Hashable`, so `AnyBrewMutation`'s synthesis is unchanged; equality widens by one member, stated in `BrewMutatingTests` rather than discovered downstream |
| `Collection.leadDisclosure`, `TapProjection.publishes`, `UntrustedTapRecovery.trustableTap` | `nonisolated`, pure, total | No storage, no isolation, no I/O — each is a function of values a test can synthesise |
| `MutationOutcome` + `Signature` | `nonisolated`, pure, total | `.refusedUntrustedTap` has no payload, so `MutationOutcome: Sendable, Equatable` is preserved trivially |
| `OperationCenter.submitSequence` | `@MainActor` | Same isolation as `submitBulk`; no new hop, no `Task`, no detached work |
| `trustableTap(for:)` closure | `@MainActor` | Reads `TapStore` on the main actor, exactly as `currentForceEvidence` does |
| Views | app-target `@MainActor` default | No new isolation |

**Protocol boundaries.** No new external dependency and therefore no new seam: process access still
goes through `BrewMutating.brewCommand` → `BrewCommand.mutate(_:)` → the shipped runner; the tap
payload still arrives through the existing `TapPayloadSourcing` protocol, whose production conformer
`BrewTapPayloadSource` (`TapPayloadSource.swift:13` and `:40`) is a **binding 0-line diff**. No
`FileManager`, no network, and **no `#available` branch**.

## Testing Strategy

| Layer | What | Approach | Runner |
|---|---|---|---|
| Unit (core) | decode, argv, disclosure text, projection, classification, the recovery selection, the argv prohibition, the batch rule | Swift Testing over pure values and source scans | `swift test --package-path Packages/CellarCore` |
| Unit (app) | disclosures raised per action; the refusal recovery; Brewfile import grants nothing | Swift Testing against composed stores | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` |
| E2E | control visibility per trust state; badge text | XCUITest | `cellarUITests` |
| Manual evidence | the real grant round trip, the real refusal, the formula wording | maintainer transcript, captured **into the verify report** | maintainer's Mac, Homebrew 6.0.18 |

### Strict TDD — RED units, files and names

| # | RED test (file · name) | Asserts | RED because |
|---|---|---|---|
| 1 | `TapDecodeTests · tapTrustIsThreeValuedAndAbsenceIsNotFalse` | `trusted` `true`/`false`/**`null`**/absent → `.trusted`/`.untrusted`/`.unreported`/`.unreported`; fixture mirrors the real `tap-info` object shape (PR #67 lesson) | `TapWire` names no `trusted` key |
| 2a | `TapCommandTests · trustAndUntrustLowerToLiteralArgv` | `["trust","acme/tools"]` / `["untrust","acme/tools"]`; verbs `tapTrust`/`tapUntrust`; `packageID == nil`; no kind flag, no extra token | the cases do not exist |
| 2b | `TapCommandTests · onlyTheGrantIsConfirmedAndBothInvalidateInstalledInventory` | `requiresConfirmation` true/false; `invalidates == [.taps,.installedInventory]` for both | — |
| 2c | `TapCommandTests · everyRemovalRevokesBeforeItRemoves` | `removal(of:)` == `[.untrustTap,.removeTap]` and `forcedRemoval` == `[.untrustTap,.forceRemoveTap]` for **all three** trust states; argvs character-for-character as TM7/TM8 pin them; no third command | the factories do not exist |
| 2d | `TapCommandTests · noRecoveryOrRetryPathSubmitsATrustCommand` | the refusal recovery and a retry of a failed mutation each submit no `trust` argv | the paths do not exist |
| 3 | `ConfirmationDisclosureTests · theAddDisclosureClaimsNoGrantAndTheGrantDisclosureClaimsOne` | exact `warningText` for `.tapAdd` and `.tapTrustGrant`; `.packageRemoval` / `.forceUntap` unchanged | `.tapTrust` still asserts a grant (`TapCommand.swift:57-58`, asserted at `ConfirmationDisclosureTests.swift:176-177`) |
| 4a | `TapProjectionTests · unreportedTrustShowsNoBadgeAndNoControl` | `trust(for:)` over the three states; badge text exactly `"Untrusted"` | no trust projection exists |
| 4b | `TapProjectionTests · aWithheldTapIsInstalledNotMissing` | withheld → `.installedTapWithheld`, exact copy, `installedHandoff` non-nil; exact-match and not-installed unchanged | `exactInstalled` has two states |
| 4c | `TapProjectionTests · aWithheldTapIsNotClaimedByATapThatDoesNotPublishIt` | a `tap: nil` record the selected tap does not publish is absent from its inventory and makes no middle-state claim | nothing enforces the publication clause for the withheld path |
| 4d | `TapProjectionTests · aWithheldTapUnderATrustedOrUnreportedTapIsStillNotInstalled` | parameterized over `.trusted` and `.unreported`: exact copy `"Not installed."`, no withheld copy | the state does not exist |
| 4e | `TapProjectionTests · everyTrustStringIsScopedToTheTap` | every string the trust surface presents is tap-scoped; none states or implies a package is untrusted | no trust strings exist |
| 5a | `InstalledDecodeTests · aNullTapIsAbsentNotEmpty` | `tap: null` → `nil`; `"acme/tools"` → that value; key absent → `nil`; the record still decodes with version/kind intact | `?? ""` collapses null |
| 5b | `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` | the three readers: projection no-match, `forceEvidence` excludes it, `HomebrewUpdateNeed` reports it incomparable; and absence matches neither a tap name nor `""` | **DD-11** — nothing else pins them |
| 6a | `ClassificationTests · anUntrustedTapRefusalIsItsOwnOutcome` | refusal prose on **stderr** + non-zero → `.refusedUntrustedTap`; same prose on **stdout** → `.failed`; exit 0 → `.succeeded`; `"Refusing to load"` **without** `"untrusted tap"` → `.failed` (DD-6) | the case does not exist |
| 6b | `ClassificationTests · nothingIsExtractedFromTheRefusal` | the outcome value carries no tap, package, token or command (it has no payload, asserted by value equality across two refusals naming different taps); the message is the exact spec sentence; classification read no more than `tailLength` lines | revision 1 carried a parsed `TapName?` |
| 6c | `TapProjectionTests · theRecoveryPicksOnlyAUniquePublisherFromCellarsOwnSnapshot` | `UntrustedTapRecovery.trustableTap`: one untrusted publisher → that tap; two publishers → `nil`; a trusted or unreported publisher → `nil`; an official tap → `nil`; `packageID == nil` → `nil` | the projection does not exist |
| 7 | `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken` | over every `MutationCommand` factory and `naming(_:)` build, every `TapCommand` case, and every command a `BrewfilePlan` built from a qualified fixture emits: no `MutationCommand` argv element contains `/`, and no argv element of any family contains two or more `/`. Positively anchored (non-empty fixture set; `addTap` produces exactly one `/`) | nothing asserts the absence today |
| 7b | `BrewfilePlanTests · aQualifiedEntryInstallsTheBareToken` | `brew "acme/tap/thing"` → `["install","--formula","thing"]`; `cask "acme/tap/app"` → `["install","--cask","app"]`; the entry still parses with **no skip counted**; a degenerate `acme/tap/` produces no command | the strip does not exist |
| 7c | `BrewfileEntryTests · qualifiedNamesStillConstructAndProjectABareTarget` | `FormulaID(name: "acme/tap/thing")` **still** succeeds (`:80-87` stays green) while `installTarget?.name == "thing"` | `installTarget` does not exist |
| 8 | `ConfirmationDisclosureTests · aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap` | `[.untrustTap,.forceRemoveTap]` → `.forceUntap`; `[.untrustTap,.removeTap]` raises **no** request; erased install-only batch → `.packageRemoval`; erased mixed tap+install batch → `.tapAdd`; plus the six guard updates tabulated in §3 | the gate reads `first.disclosure` (`OperationCenterBulk.swift:169`) |
| 8b | `ConfirmationDisclosureTests · skippingPicksTheFirstDeclaringCommandNotTheStrongest` | `[untrust, addTap, forceRemoveTap]` → `.tapAdd`, **not** `.forceUntap` — submission order, never severity | the rule does not exist |
| 9 | `TapShippingProofTests` (`:90`, `:194`) · existing cases, updated | `TapManagementAction.allCases` == 8 (`…, "trust", "untrust"`, in TM11's order); the flattened argv expectation grows to the revoke-first sequences; pinned labels == `["Add Tap","Untap","Force Untap","Show in Installed","Trust","Untrust"]`; `Button {` still absent; excluded-capability scan still clean. The helper's return type becomes `[TapCommand]` | the pinned sets are **6 actions and 4 labels**, and untap is one command |
| 9b | `TapShippingProofTests · anUnreportedTapOffersNoControlAndSpawnsNothing` | invoking both controls for an `unreported` tap builds and spawns nothing (`launcher.specs.isEmpty`), while an untap of the same tap still submits its revocation | TM12's control clause is unasserted |
| 9c | `TapShippingProofTests · listRowAndDetailHeaderReadOneTrustProjection` | both views call `TapProjection.trust(for:)` and neither computes a badge or a control condition locally | nothing prevents the two drifting |
| 9d | `TapShippingProofTests · trustIsAReportedStateAndAGrantNeverAVerdict` | everything the surface presents is either the reported state or a control submitting brew's own grant/revocation; no scoring, ranking or recommendation vocabulary appears | TM11's new clause is unasserted |
| 10 | `cellarTests/TapCompositionTests · noPathGrantsTrustWithoutAnExplicitAnswer` (new file) + `cellarTests/BrewfileCompositionTests` | Add Tap raises exactly one `.tapAdd`; Trust exactly one `.tapTrustGrant`; **Untrust none**; Untap none; Force Untap exactly one `.forceUntap`; a Brewfile import with `trusted:` on tap, brew and cask lines raises exactly one `.tapAdd` and submits no `trust` argv | the cases do not exist |
| 10b | `cellarTests/TapCompositionTests · theRefusalRecoveryOffersTrustOnlyForAUniquePublisher` | the recovery button appears for one publisher and not for zero or two; pressing it opens the ordinary confirmed Trust sheet and retries nothing | the recovery does not exist |
| 10c | `MutationCommandTests · anUntrustedTapNeverPreBlocksAMutation` | a mutation for a package whose tap is withheld and untrusted is built and submitted normally; no build path consults a trust state | nothing forbids a future pre-launch gate |
| 11 | `cellarUITests · theTrustControlAppearsOnlyForAnUntrustedTap` | Trust present only for `.untrusted`; Untrust only for `.trusted`; neither for `.unreported`; badge text | no control exists |
| 12 | `MutationCommandTests:289` (shipped) | `TapCommand.swift`'s `arguments` body stays free of `\(`, `joined(`, `split(` | **regression guard — must never go red** |
| 13 | `MutationRefreshReceiptTests · everyTapTerminalRefreshesItsDeclaredDomainsExactlyOnce` | **5 commands × 4 terminals** (success, failure, launch failure, cancellation before spawn): taps ×1 each; installed inventory ×1 for trust, untrust and force untap and ×0 for add and plain untap; catalog ×0 everywhere | TM9's enumeration is three commands today |
| 13b | `MutationRefreshReceiptTests · anUntapActionsInventoryRefreshComesFromItsRevocation` | an untap action refreshes installed inventory exactly once, attributable to the revocation, while `removeTap.invalidates` still excludes it | the sequence does not exist |
| 14 | `TapIntegrationTests · aFailedRevocationDoesNotBlockTheRemoval` | the revocation reaches a failed terminal outcome, the removal is still submitted and reaches its own, and the failure is its own visible `ActivityItem` | the sequence does not exist |
| 14b | `TapIntegrationTests · anIdempotentGrantOrRevocationIsAnOrdinarySuccess` | exit 0 for a re-grant and for a never-trusted revocation → `.succeeded`, not a failure and not a defect | the commands do not exist |

## Scenario Coverage — all 89 delta scenarios (the BF5 scenario "A qualified package entry installs the bare token", added by amendment #3, maps to unit 7c)

Convention: **new / updated** rows name the exact test function; rows marked *shipped* are already
covered by a case in the named file that this change re-runs unchanged (the D2 rename aside).

**`tap-management` — 40**

| Scenario | Test / evidence |
|---|---|
| TM5 :83 selected-tap prefix only | `TapProjectionTests` *shipped* |
| TM5 :90 qualified cask token matches | `TapProjectionTests` *shipped* |
| TM5 :98 equal formula/cask tokens distinct | `TapProjectionTests` *shipped* |
| TM5 :105 exact installed tap controls handoff | `TapProjectionTests` *shipped* |
| TM5 :113 withheld + untrusted reads installed | 4b |
| TM5 :122 withheld not claimed by a non-publisher | **4c** |
| TM5 :130 withheld under trusted/unreported still "Not installed." | **4d** |
| TM5 :139 tap names never become catalog records | `TapIntegrationTests` *shipped* |
| TM5 :146 large inventory narrows without eager presentation | `TapProjectionTests` *shipped* |
| TM6 :177 canonical target → exact argv | `TapCommandTests` *shipped* |
| TM6 :184 hostile targets rejected, nothing spawned | `TapCommandTests` *shipped* |
| TM6 :191 every add discloses what add does/does not do | 3 |
| TM6 :199 adding a tap grants no trust | 10 |
| TM6 :207 presentation cannot rewrite execution | `TapCommandTests` *shipped* |
| TM7 :240 plain untap grows no hidden force flag | 2c |
| TM7 :249 untap revokes before it removes (3 states) | 2c |
| TM7 :257 failed revocation does not block removal | **14** |
| TM7 :265 empty cross-reference hides force | `TapShippingProofTests` *shipped* + DD-14 |
| TM7 :272 untrustworthy inventory cannot enable force | `TapShippingProofTests` *shipped* |
| TM8 :300 disclosure names every kind-qualified package | `ConfirmationDisclosureTests` *shipped* |
| TM8 :308 revoke-first force batch still shows force disclosure | 8 |
| TM8 :316 additions/removals invalidate stale confirmation | `ForceDenialRecoveryTests` *shipped* |
| TM8 :323 kind change invalidates stale confirmation | `ForceDenialRecoveryTests` *shipped* |
| TM8 :330 ordering alone does not invalidate | `ForceDenialRecoveryTests` *shipped* |
| TM9 :357 tap mutations serialize with other mutations | `TapIntegrationTests` *shipped* |
| TM9 :364 five commands × four terminals | **13** |
| TM9 :373 untap's inventory refresh comes from its revocation | **13b** |
| TM11 :392 enumerated actions stay within scope (8) | 9 |
| TM11 :400 reported state and grant, never a verdict | **9d** |
| TM12 :432 three states incl. `null` | **1** |
| TM12 :440 unreported shows nothing, controls spawn nothing | **9b** |
| TM12 :448 badge and controls follow the state | 4a |
| TM12 :456 list row and detail header read one projection | **9c** |
| TM12 :463 trust copy is about the tap | **4e** |
| TM13 :496 trust/untrust exact argv | 2a |
| TM13 :504 grant confirmed, revocation not | 2b + 10 |
| TM13 :513 no path grants trust implicitly | **10 + 2d** |
| TM13 :521 idempotent grant/revocation is ordinary success | **14b** |
| TM13 :529 real grant round trip flips the badge | manual evidence 1 |
| TM13 :537 untapping a trusted tap leaves no grant | manual evidence 3 |

**`package-mutation` — 30**

| Scenario | Test / evidence |
|---|---|
| PM1 :83, :90, :97, :104, :112 kind flags | `MutationCommandTests` *shipped* ×5 |
| PM1 :120 another family enters the spine | `BrewMutatingTests` *shipped* |
| PM1 :128 erased mixed batch discloses the tap add | 8 |
| PM1 :137 erased install-only batch discloses package removal | 8 |
| PM1 :145 batch led by a non-declaring command | 8 |
| PM1 :154 skipping picks the first declaring, not the strongest | **8b** |
| PM1 :163 no disclosure recovered by a type test | `ConfirmationDisclosureTests:190-228` *shipped, guards updated per §3* |
| PM3 :199, :207, :214, :222, :230, :238 uninstall/zap/bulk gate | `ConfirmationDisclosureTests` *shipped* ×6 |
| PM3 :245 every tap add carries its typed add disclosure | 3 + 10 |
| PM3 :253 every trust grant confirmed with its disclosure | 3 + 10 |
| PM3 :262 untrust passes the gate without confirmation | 2b + 10 |
| PM3 :270 force untap carries complete package disclosure | `ConfirmationDisclosureTests` *shipped* |
| PM3 :278 stale disclosure/display text cannot become argv | `ForceDenialRecoveryTests` *shipped* |
| PM10 :325 stderr refusal is the typed outcome | 6a |
| PM10 :332 stdout prose / success does not classify | 6a |
| PM10 :340 nothing is extracted | **6b** |
| PM10 :348 offers Trust, worded about the tap | **6b + 6c + 10b** |
| PM10 :356 no argv anywhere carries a qualified token | **7 + 7b** |
| PM10 :364 an untrusted tap never pre-blocks a mutation | **10c** |
| PM10 :372 formula refusal wording captured first | manual evidence 5 |
| PM10 :380 a real refusal renders the typed outcome | manual evidence 2 |

**`brewfile-management` — 11**

| Scenario | Test / evidence |
|---|---|
| BF5 :61 a trusted tap still raises the tap-add disclosure | 10 |
| BF5 :115 A qualified package entry installs the bare token | **7b + 7c** |
| BF5 :70 `trusted:` never becomes argv | `BrewfileArgvStructureTests` *shipped* |
| BF5 :78 an import submits no trust command | 10 |
| BF5 :87 the claim is surfaced, attributed to the file | `BrewfileParserTests` *shipped* |
| BF5 :95 `trusted:` on a brew/cask line parses, confers nothing | `BrewfileParserTests` *shipped* + **7b** (bare-token argv) |
| BF7 :130 mixed selection fans out, taps first | `BrewfilePlanTests` *shipped* |
| BF7 :140 only selected entries are submitted | `BrewfilePlanTests` *shipped* |
| BF7 :148 one confirmation covers the batch, tap selected last | 8 + `BrewfilePlanTests` *shipped* |
| BF7 :158 an empty selection submits nothing | `BrewfilePlanTests` *shipped* |
| BF7 :165 a mid-batch failure attributes to one entry | `BrewfileStoreTests` *shipped* |

**`installed-inventory` — 8**

| Scenario | Test / evidence |
|---|---|
| II2 :62, :69, :76, :84, :92 keg/cask/auto-update/linked shapes | `InstalledDecodeTests` *shipped* ×5 |
| II2 :100 a withheld tap decodes as absent, not empty | 5a |
| II2 :108 a record with a withheld tap still enters the inventory | 5a |
| II2 :116 an absent tap never matches a selected tap | 5b |

### Manual evidence (maintainer's Mac, Homebrew 6.0.18 — cannot be automated)

1. `brew tap juancasanueva/cellar` → Cellar shows **Untrusted** → in-app **Trust** → the sheet shows
   `.tapTrustGrant`'s exact text → `brew trust --json v1` lists the tap → the badge flips with no
   manual reload. *(TM13 :529)*
2. A bare-token upgrade of a package from an untrusted tap, launched **from inside Cellar**, renders
   `.refusedUntrustedTap` with brew's own `brew trust …` line visible in the untruncated log, and the
   recovery **Trust** button opens the ordinary confirmation. *(PM10 :380)*
   > **BINDING — never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (obs `#7724`).
   > Use `brew upgrade --cask --dry-run <token>`, or the installed Home-Cellar, which declares
   > `auto_updates`. This applies to every step of this evidence, including a retry.
3. **Untap** a trusted tap from Cellar → `brew trust --json v1` no longer lists it → re-tap it → it
   comes back untrusted. *(TM13 :537)*
4. Confirm the withheld state end-to-end: with the tap untrusted, an installed package from it reads
   *"Installed. Homebrew withholds its tap while this tap is untrusted."* and **Show in Installed**
   still lands on the right record.
5. The **formula** refusal stderr, verbatim (R6). *(PM10 :372)*
6. Homebrew < 6 degradation is **not reproducible** here; covered by unit 1 plus a documented
   limitation (R5).

All six transcripts are captured **in the verify report**, which is the artifact that carries
evidence in this repository; a design written before execution cannot contain them. The spec deltas
currently say "in `design.md` and the verify report" — Spec Amendments #7.

## Threat Matrix

**Applicable** — this design adds two subprocess argv vectors and reads untrusted subprocess output
as classification input.

| Boundary | Adversarial case | Applicability | Design response | Planned RED test |
|---|---|---|---|---|
| Documentation-like paths | a tap publishing a token shaped like a flag or a path | **Applicable** | Package tokens still pass `MutationName.isSafe`; tap names pass `TapName.init?` (two canonical ASCII components). Both are argv-only — `BrewCommand` never builds a command line and never routes through `/bin/sh -c` | 7, 7b |
| Git repository selection | `brew tap` clones a repository the user named | **N/A** | The add argv is unchanged (`["tap", name]`) and no new git operation exists. Trust and untrust touch `~/.homebrew/trust.json` only | covered by the shipped TM6 argv scenario |
| Commit state / Push state / VCS automation | — | **N/A** | This change performs no VCS operation | — |
| Executable-file classification | — | **N/A** | No file is written, marked executable, or classified | — |
| Argument composition — **the qualified-argv bypass** | `trust.rb#explicitly_allowed?` treats naming `owner/tap/token` on the command line **as the grant**, so a "helpful" retry — or a Brewfile line the user never wrote — would silently execute code nobody consented to run | **Applicable — the central threat** | Prohibited by D1 and D3. The refusal recovery re-runs nothing; it opens a **confirmed** Trust sheet. The Brewfile plan strips the qualifier (DD-8). The prohibition is asserted as an **absence over the whole argv surface**, non-vacuously, rather than by a gate that would break the qualified names a file legitimately contains | 7 (absence over the surface), 7b (Brewfile path), 2d (recovery/retry), 10 (no path grants implicitly) |
| Untrusted payload as classification input | brew's stderr steering the UI: a package echoing refusal prose; a refusal naming a tap that is not the user's | **Applicable** | stderr-only, non-zero-exit-only, 20-line tail (all unchanged). One specific phrase (DD-6). **Nothing is read out of the payload at all** (DD-7): the recovery's tap comes from Cellar's own snapshot and is offered only when exactly one untrusted tap publishes that exact `(kind, name)`. A miss degrades to `.failed` with the verbatim log | 6a, 6b, 6c |
| Confirmation integrity | a prepended command silently downgrading another command's disclosure | **Applicable** | DD-3 / DD-9: `leadDisclosure` skips only commands that declare nothing, never re-ranks by severity, and the shipped ban on caller-side `?.disclosure ??` stays green | 8, 8b |
| Capability grant without consent | any path granting trust implicitly — add, import, refusal recovery, retry | **Applicable** | Every grant is `requiresConfirmation: true` carrying `.tapTrustGrant`; the revocation is the only trust command submitted without its own answer, and it grants nothing | 10, 2d |

## Migration / Rollout

**No migration.** No cache file, no schema version, no Keychain item, no preference key, no
dependency, no on-disk format. `TapRecord.trust` defaults to `.unreported` in its initialiser, so
every fixture keeps compiling; `InstalledPackage.tap` is decoded fresh on every launch. A user on
Homebrew < 6 sees the app as it is today, minus the false Add Tap sentence — and, per DD-5, with a
visibly failed `untrust` item beside every untap.

## Work Units, Commits and Delivery

`single-pr` on `feat/m7-tap-trust` (branch pattern
`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓). RED → GREEN inside
each unit; tests travel with the behaviour they verify. Conventional commits, **no `Co-Authored-By`
and no AI attribution**.

| WU | Content | RED units | Commit | Rollback boundary |
|---|---|---|---|---|
| **WU1** | `trusted` decode + `TapTrustState` + `TapTrustPresentation` + list/detail badge | 1, 4a, 4e, 9c | `feat(taps): read and show the trust state Homebrew already reports` | drop the decode; the badge disappears, nothing else changes |
| **WU2** | `.tapAdd` / `.tapTrustGrant` + `MutationConfirmation` copy + the four spec renames + `PRD.md` §3.7 | 3 | `fix(taps): stop claiming that adding a tap trusts it` | revert the rename — a single-commit revert |
| **WU3** | `InstalledPackage.tap: String?` + `bareToken`/`publishes` + the withheld state + `statusExplanation` | 5a, 5b, 4b, 4c, 4d | `fix(installed): a withheld tap is absent, not empty` | independent of every trust surface; keeps on its own |
| **WU4** | `.trustTap` / `.untrustTap`, detail controls, shipping proof, composition tests, refresh receipts | 2a, 2b, 9, 9b, 9d, 10, 11, 13 | `feat(taps): grant and revoke tap trust as explicit answers` | drop the two cases, their controls and their pinned entries |
| **WU5** | `removal(of:)` / `forcedRemoval`, `submitSequence`, `declaredDisclosure` + `leadDisclosure` | 2c, 8, 8b, 13b, 14, 14b | `fix(taps): revoke the grant before removing the tap` | drop the prepend and the second protocol member; `removeTap` returns to one command |
| **WU6** | `.refusedUntrustedTap` + `UntrustedTapRecovery` + the Activity recovery | 6a, 6b, 6c, 10b, 10c, 2d | `feat(activity): explain an untrusted-tap refusal and offer the only safe recovery` | drop the case; refusals return to `.failed` with the log |
| **WU7** | **D3**: `BrewfileEntry.installTarget` + plan strip + import-row detail + the absence assertion | 7, 7b, 7c | `fix(brewfile): install the bare token a qualified entry names` | drop the projection; the plan returns to `entry.*.target` |

**Reverse order is the rollback order**: WU7 → WU6 → WU5 → WU4 → WU1. WU2 and WU3 stand
independently.

### Review Workload Forecast (restated for `sdd-tasks`, which must reuse it)

| Bucket | Lines |
|---|---|
| Core (`TapWire`, `TapCommand`, `TapProjection`, `UntrustedTapRecovery`, `BrewMutating`, `OperationCenterBulk`, `InstalledModels`/`InstalledDecoder`, `MutationOutcome`, `BrewfileEntry`/`BrewfilePlan`) | ~285 |
| App (`TapsListView`, `TapDetailView`, `MutationConfirmation`, `ActivityDrawer`, `ContentView`, Brewfile row, `PRD.md`) | ~150 |
| Tests (12 files) | ~520 |
| Specs (4 deltas, 11 MODIFIED + 3 ADDED, plus the eight amendments) | ~470 |
| **Bottom-up subtotal** | **~1,425** |

The house's measured **1.9–2.3×** discovery correction applies to the code + test buckets only
(955 → **1,815–2,197**); the spec buckets are enumerated requirement-by-requirement. With SDD
artifacts at ~600-900, the **PR total is roughly 2,885–3,567 authored lines**.

```
Decision needed before apply: No
Chained PRs recommended: No
400-line budget risk: High
```

`400-line budget risk: High` against the **default** reviewer guard; **Low** against the governing
`review_budget_lines=5000` (≤71 % at the ceiling). `single-pr` holds with **no `size:exception`**. If
the maintainer prefers slices, the natural cut is **WU1–WU3** (read, badge, honesty) then **WU4–WU7**
(grant, revoke, refusal, Brewfile).

## Bindings — files that MUST show a 0-line diff, and this is asserted

`scripts/*` (every file), `.github/workflows/release.yml` and every other workflow,
`Packages/CellarCore/Sources/Catalog/**` (`CatalogPackage.tap` stays `String`),
`Packages/CellarCore/Sources/BrewClient/TapPayloadSource.swift`,
`Packages/CellarCore/Sources/BrewClient/MutationCommand.swift` (**new binding** — DD-8 adds no gate),
`Packages/CellarCore/Sources/BrewProcess/**`, and `cellar.xcodeproj/project.pbxproj`.

**`BrewfilePlan.swift` is no longer a binding 0-line diff** — D3 changes its install arm. The
proposal's *Out of scope*, *Affected Areas* and *Success Criteria* still bind it to zero; Spec
Amendments #6.

`project.pbxproj` needs no edit even for new test files: `cellarTests/` and the CellarCore test
targets are `PBXFileSystemSynchronizedRootGroup`s, so a new file joins its target by existing.

## Rollback

One `git revert` of the PR restores every behaviour. The change adds no cache file, no schema version,
no Keychain item, no migration and no dependency, so a revert orphans nothing. Post-revert checks:
`swift build --package-path Packages/CellarCore` and
`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

**What rollback does NOT do:** reverting Cellar does not revoke a grant already written to
`~/.homebrew/trust.json`. `brew untrust <tap>` in Terminal remains the exit, and the PR body must say
so.

## Risk Register

| # | Risk | L | Design-level mitigation |
|---|---|---|---|
| **R1** | Trust is a capability grant; an implicit grant on any path hands arbitrary code execution to a third party without consent | **High** | Every grant is `requiresConfirmation: true` with `.tapTrustGrant`; unit 10 asserts it positively for add, trust, untrust, untap, force untap **and** Brewfile import; unit 2d covers recovery and retry |
| **R2** | The qualified-argv bypass looks like a bug fix | **High** | D1 + D3; the recovery re-runs nothing; the Brewfile strips; unit 7 asserts the absence over the whole surface non-vacuously; the code comments record *why*, so a future reader does not "fix" the refusal |
| **R3** | Stale grants — untap leaves the entry in `trust.json`, and a Brewfile import silently re-arms it | **High** | DD-4's unconditional revoke-first sequence; units 2c, 13b; manual evidence 3 |
| **R4** | The batch-disclosure downgrade the prepend introduces would defeat the force-untap disclosure — the exact defect PM1 was written to fix | **High** | DD-3 + DD-9; units 8 and 8b; the shipped `?.disclosure ??` ban stays green |
| **R5** | Homebrew version drift — a brew with no trust concept | Med | `.unreported` shows no badge and neither control, and neither control spawns anything (unit 9b). **Consequence, accepted:** because DD-5's revocation is unconditional, every untap on such a brew shows a *failed* `untrust` item beside a succeeding `untap`. That is TM7's own choice — a visible failed operation beats a silently retained grant — and it is documented in the PR body rather than discovered |
| **R6** | Refusal-prose drift; the **formula** wording is unmeasured | Med | DD-6's single specific phrase; a miss degrades to `.failed` with the verbatim log. Widening needs no structural change. **Obligation before release: capture the formula wording (manual evidence 5)** |
| **R7** | Per-package grants — a package individually trusted under an untrusted tap must never be described as untrusted, nor blocked | Med | No pre-launch gate anywhere (unit 10c); every string is tap-scoped (unit 4e); the withheld state requires an actual `tap: nil` record, and a per-package grant restores `tap` (obs `#7724`), so such a package projects as plainly `.installed` |
| **R8** | The `tap` optional migration is **not** compiler-enforced at its readers, contrary to the proposal's and the installed-inventory delta's framing | Med | DD-11; the three readers are enumerated and pinned by unit 5b; Spec Amendments #5 and #6 correct both documents |
| **R9** | Shipping-proof drift — the pinned action enum and button set fail loudly | Low | Desired behaviour; unit 9 updates 6→8 actions and 4→6 labels deliberately, and the helper's return type with them |
| **R10** | Cross-spec rename churn — `tapTrust` is named in four requirements across two other capabilities | Low | Enumerated in the proposal's Capabilities table; compiler-checked in Swift, prose-only in specs; `rg 'tapTrust'` must return zero hits after promotion |
| **R11** | Invalidation cost — trust/untrust now refresh installed inventory as well as taps | Low | Required (obs `#7724`); one refresh per terminal, asserted by unit 13 |
| **R12** | **Force Untap is unavailable while a tap is untrusted**, because brew withholds the `tap` field and the affected set collapses to empty | Med | **DD-14**: this is the zero-match branch of TM7 :233-236, so force is *hidden* rather than disabled-with-guidance, and it is **unchanged from today** (the `""` sentinel already matched nothing). The recommended footer sentence explains it; the exits are Trust → Force Untap, or plain Untap |
| **R13** | Adding a second disclosure member touches the spine and three shipped source-scanning guards | Med | DD-3 keeps `disclosure` non-optional precisely to bound this: only `TapCommand` changes its declaration, `:161-178` and `:203` stay green, and exactly three assertions move (`:216`, plus new siblings at `:223`/`:225`) with `BrewMutatingTests:257-292`. All tabulated in §3 and driven RED-first by unit 8 |
| **R14** *(closed)* | Revision 1 was written before the spec deltas existed | — | Closed: all four deltas were read in full for this revision, and every divergence found is listed in *Spec Amendments Required* rather than silently resolved |
| **R15** *(new)* | A qualified Brewfile entry keeps its **qualified identity** for diffing, so it always projects as "missing" even when the bare package is installed, and installing it is then a near no-op | Low | Accepted and scoped: D3 governs argv, not the diff. Changing the entry's identity would move the strip into the parser and alter `BrewfileEntry.packageID`, `displayName` and the diff in one step — larger, and outside this change's spec deltas. Recorded as a deferred follow-up; unit 7b pins the argv, which is the security-relevant half |
| **R16** *(new)* | The refusal recovery shows **no** Trust button when two untrusted taps publish the same `(kind, name)`, or when the publisher is not in the snapshot | Low | Deliberate (DD-7): Cellar will not guess which capability to grant. The typed message already names the path — "Trust the tap in Taps, then try again." — and the verbatim log still carries brew's own `brew trust …` line. Unit 6c pins both branches |

## Validator Findings — Where Each Is Resolved

| # | Finding | Resolved at |
|---|---|---|
| 1 (HIGH) | DD-7 must not extract the tap from stderr | **DD-7** (rewritten); §7 `UntrustedTapRecovery` + `TapProjection.publishes`; units 6b, 6c; Threat Matrix row "Untrusted payload"; R16 |
| 2 (HIGH) | No `/` gate on `PackageTarget.init?`; strip at the plan per D3 | **DD-8** (rewritten); §8 `BrewfileEntry.installTarget` + `BrewfilePlan` arm; units 7, 7b, 7c; Bindings (`MutationCommand.swift` now binding); R15 |
| 3 (MED) | Keep `disclosure` non-optional; add `declaredDisclosure` | **DD-3** (rewritten) + DD-9; §3 conformer table and the six exact test updates; R13 |
| 4 (MED) | Single-phrase classifier, window stated | **DD-6**; §7; Spec Amendments #1 |
| 5 (MED) | TM7 vs TM12; Homebrew < 6 consequence | **DD-5**; R5; unit 9b; Spec Amendments #2 |
| 6 (MED) | No compile-error migration claim; name the pinning test | **DD-11**; readers table; unit 5b (`InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch`); Spec Amendments #5, #6 |
| 7 (LOW) | R12: zero matches vs incomplete, plus guidance copy | **DD-14**; R12 |
| 8 (LOW) | `BrewTapPayloadSource` struct vs `TapPayloadSourcing` protocol | *Concurrency — Protocol boundaries* (`TapPayloadSource.swift:13`, `:40`) |
| 9 (LOW) | Open-question count | *Open Questions* — five |
| 10 (LOW) | Evidence transcripts live in the verify report | *Manual evidence* closing paragraph; *Evidence to Capture*; Spec Amendments #7 |
| 11 (COV) | Map all 89 scenarios | *Scenario Coverage*; every previously-unmapped scenario now names a **bold** new test |

## Spec Amendments Required — **all eight applied on disk 2026-08-23 (sdd-spec amendment run + orchestrator); kept as the record of why**

The orchestrator applies these; the design does not edit spec deltas.

| # | File · location | Replace | With |
|---|---|---|---|
| **1** (MED) | `specs/package-mutation/spec.md` :298-299 | "Matching MUST rest on two independent structural phrases, either of which suffices, so a reworded suffix cannot silently disable classification." | "Matching MUST rest on **one** structural phrase about the tap, read from the shipped stderr tail window, so a reworded prefix or suffix cannot silently disable classification and no phrase broad enough to catch an unrelated refusal can offer a trust affordance for it. The literal string is design-owned (:35-36)." |
| **2** (MED) | `specs/tap-management/spec.md` :425-426 and scenario :440-446 | ":425 '…and no `brew trust` or `brew untrust` process MUST be built or spawned for it.' / :445 '- AND no process is built or spawned for either'" | ":425 '…and neither the **Trust nor the Untrust control** MUST build or spawn a process for it. TM7's revocation before removal is unconditional and still submits `untrust` when such a tap is untapped, where it may fail and MUST remain visible as its own operation.' / :445 '- AND neither control builds or spawns a process, and no trust command is submitted except the revocation TM7 pins ahead of a removal'" |
| **3** (HIGH) | `specs/brewfile-management/spec.md` — BF5 (after :49-51), BF7 :104-107, header :15 and :22, notes :186 | header "This delta changes no rule."; ":22 `BrewfilePlan` still emits a tap add and nothing else."; :186 "the proposal binds `BrewfilePlan.swift` to a zero-line diff beyond the rename" | header "This delta carries **D3** and the D2 rename."; BF5 gains: "A package entry whose name is `/`-qualified MUST still parse as an ordinary entry with no skip counted, and the command applied for it MUST name the **bare token** brew installs by, with the qualifier removed. Homebrew 6 treats naming a qualified package on the command line as a per-package grant, so forwarding the file's qualified token as argv would let the file's author grant trust on the importing user's Mac — the delegation this requirement already refuses. When that tap is untrusted, brew refuses and `package-mutation` PM10's typed outcome offers the grant as an explicit answer." + a scenario "A qualified package entry installs the bare token"; BF7 :107 gains "The install MUST name the entry's bare token; a selected package entry whose qualified name has no constructible bare token MUST produce no command and MUST NOT be presented as applied."; :186 note replaced with the D3 record. **Counts move: BF5 5→6 scenarios, capability 39→40** |
| **4** (LOW) | `specs/package-mutation/spec.md` :411-413 | "Narrowing it would break the qualified names a Brewfile legitimately carries; the prohibition is therefore an absence assertion over the argv surface." | "Narrowing it would make every `TapName` unconstructible, because `TapName.init?` is expressed over the same gate and a tap name *is* `owner/repo`. The prohibition is therefore an absence assertion over the argv surface, together with **D3**'s bare-token strip on the Brewfile path." |
| **5** (MED) | `specs/installed-inventory/spec.md` :136-139 | "Record in provenance that the optional tap is a **compile-error migration by design**… a compile error at each beats a `\"\"` anyone can forget." | "Record in provenance that the optional tap is **not** a compile-error migration: Swift promotes the non-optional operand of `==`, so all three shipped readers keep compiling and stay semantically correct (`nil` equals nothing). Only the declaration and the two decoder sites change, and the readers are pinned by `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch`." |
| **6** (MED) | `proposal.md` :95, :211, :219, :307, :355 | ":95 '`BrewfilePlan.swift:36-37` needs **no** change'; :211 '**≈6-9 sites**, each a compile error'; :219 binding-untouched row listing `BrewfilePlan.swift`; :307 'A compile error at every site'; :355 success criterion binding `BrewfilePlan.swift` to a 0-line diff" | D3: `BrewfilePlan.swift` **does** change (install arm) and leaves the binding list; `MutationCommand.swift` joins it. DD-11: "≈6-9 sites, **none of them a compile error** — three readers pinned by test" and R8 restated accordingly |
| **7** (MED) | `specs/tap-management/spec.md` :36, `specs/package-mutation/spec.md` :33, PM10 scenario :376 | "transcript captured in `design.md` and the verify report" / ":376 'THEN those bytes are captured verbatim in `design.md` and the verify report'" | "transcript captured in the verify report" / ":376 'THEN those bytes are captured verbatim in the verify report'" — a design written before execution cannot contain evidence produced by it |
| **8** (LOW) | `specs/tap-management/spec.md` :20 | "All five of the proposal's open questions resolve to their stated defaults." | Reconcile with `proposal.md`'s *Open Questions*, which numbers six items covering the same five decisions plus the untap-confirmation default TM7 already pins. Either renumber the proposal to five or restate the delta as "all of the proposal's open questions"; the binding count in this design is **five** |

## Open Questions

**None block `sdd-tasks`.** The maintainer's **five** resolved defaults (2026-08-23) are folded in:
silent untrust on untap as its own Activity operation (**DD-4**, **DD-5**); a failed untrust does not
block the untap (**DD-5**); the withheld-state copy plus **Show in Installed** (**DD-10**, §5); the
"Trust"/"Untrust" labels, the "Untrusted" badge in list and header, and Trust inline (**DD-13**);
and PM1's lead disclosure = the first command's **own declared** disclosure (**DD-3**).

Two items are obligations rather than questions:

- [ ] **Formula refusal wording** — unmeasured (R6). Capture as manual evidence 5 before release; it
      needs no design change either way.
- [x] **Spec amendments** — the eight above were applied on 2026-08-23 before `sdd-tasks`
      writes tasks against these deltas.

## Evidence to Capture at Apply / Verify

| Evidence | Class | Owner | Destination |
|---|---|---|---|
| `swift test --package-path Packages/CellarCore` — exact counts, RED before GREEN per work unit | `unit` | apply | verify report |
| `xcodebuild test … -only-testing:cellarTests` — exact result | `unit` | apply | verify report |
| `cellarUITests` unit 11 — exact result | `e2e` | apply | verify report |
| `git diff --stat` proving the binding 0-line diffs (incl. `MutationCommand.swift`, `TapPayloadSource.swift`) | `binding` | apply | verify report |
| Manual evidence 1–4, verbatim, including `brew trust --json v1` before/after | `manual-evidence` | maintainer | verify report |
| The formula refusal stderr, verbatim (R6, manual evidence 5) | `manual-evidence` | maintainer | verify report |
