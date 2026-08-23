# Exploration: m7-tap-trust — tap trust as a first-class, honest capability

> ARTIFACT BODY. The executor had no Write tool; the orchestrator persists this verbatim to
> `openspec/changes/m7-tap-trust/explore.md`.

## Executive answer

Keep Homebrew's split: **`brew tap` fetches, `brew trust` grants.** Cellar stops claiming a grant it
never made, reads the trust state it already receives, and offers Trust / Untrust as their own
explicitly answered commands. Revocation is bundled into Untap (stale grants are the real defect).
Untrusted-tap mutation refusals are classified into a typed outcome, never worked around with a
fully-qualified name.

## Current state (verified in source)

| Fact | Evidence |
|---|---|
| Add Tap argv is `["tap", name]` only; no `brew trust` anywhere in the app | `Packages/CellarCore/Sources/BrewClient/TapCommand.swift:85` |
| The Add Tap disclosure asserts a grant that does not happen | `TapCommand.swift:57-58` — "Adding \(tap) trusts third-party formulae and casks that can distribute code." |
| Tap payload read is a single `tap-info --installed --json` | `Packages/CellarCore/Sources/BrewClient/TapPayloadSource.swift:41` |
| The decoder ignores every key it does not name, including `trusted` | `Packages/CellarCore/Sources/BrewClient/TapWire.swift:44-74` |
| A withheld tap collapses into `""` — indistinguishable from an empty one | `Packages/CellarCore/Sources/BrewClient/InstalledDecoder.swift:76` (`tap: formula.tap ?? ""`), `:108` (`tap: cask.tap ?? ""`) |
| The record is **not** skipped when `tap` is null (only a missing keg skips it) | `InstalledDecoder.swift:68`, `:91` |
| Installed match requires exact tap equality, so `""` never matches | `Packages/CellarCore/Sources/BrewClient/TapProjection.swift:141-147` |
| Package argv is always the bare token plus a kind flag | `Packages/CellarCore/Sources/BrewClient/MutationCommand.swift:329-335` |
| `MutationName.isSafe` would *permit* a `/` in a name — nothing structural blocks a qualified token today | `MutationCommand.swift:130-133` |
| Confirmation is one yes over a typed batch; partial confirmation is impossible by design | `Packages/CellarCore/Sources/BrewClient/OperationCenterBulk.swift:160-188` |
| Outcome classification reads only the last 20 stderr lines and extracts nothing | `Packages/CellarCore/Sources/BrewClient/MutationOutcome.swift:11-23`, `:96-105` |
| Brewfile `trusted:` is parsed, displayed, and confers nothing | `Packages/CellarCore/Sources/BrewClient/BrewfileEntry.swift:162-194`; `BrewfilePlan.swift:36-37` emits `.addTap` only |
| The tap UI's static button set and action enum are pinned | `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift:90-93`, `:194-196`, `:287-294` |
| Every `*Command.swift` argv body is scanned for interpolation/joining | `Packages/CellarCore/Tests/BrewClientTests/MutationCommandTests.swift:289-312` |

Measured brew behaviour (obs #7721, #7722, #7711 — treated as given):
`brew tap` never trusts and has no trust hook in `cmd/tap.rb`; `brew trust` / `brew untrust` are the
grant and its reverse; **`brew tap-info --json --installed` already carries a per-tap `trusted`
boolean on Homebrew 6**; `brew trust --json v1` has `taps`/`formulae`/`casks`/`commands` and records
**per-package** grants independently of tap grants; `brew untrust` on a never-trusted tap exits 0;
with the tap untrusted `brew info --installed --json=v2` returns `tap: null` and bare-token
`brew upgrade --cask <token>` is refused.

### The four defects, named

1. **Dishonest copy.** The one sentence a user reads before granting says a grant happens. It does not.
2. **Invisible half-state.** A tap added in Cellar is fetched but inert: nothing loads from it, and
   its installed packages read "Not installed." in the Taps view (`tap: null` → `""` → no match).
3. **No recovery.** `brew upgrade --cask <token>` is refused; Cellar reports `.failed(status:)` with a
   log and no action.
4. **Stale grants.** Untap leaves the entry in `trust.json`. A later re-tap — including one a Brewfile
   import performs — is silently trusted again with no new consent, and Cellar cannot see the grant
   at all once the tap is gone.

---

## Q1 — Consent model

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **A. Add Tap = tap + trust as one confirmed batch** (two argv vectors, existing `request([commands])` path; sheet lists both exact commands) | One step for the common intent; uses the shipped batch mechanism verbatim (`BrewfilePlan` already does taps-then-installs under one yes); never produces the inert half-state | The batch cannot be partially confirmed (`package-mutation` PM3 sc5–6 forbids a subset), so a user who wants the fetch without the capability has no path; couples a repo clone to arbitrary-code execution authority — the exact coupling Homebrew separated | Low |
| **B. Keep them separate; explicit Trust control** (recommended) | Matches `brew` semantics exactly, so Cellar never diverges from the tool it fronts; each capability grant is its own explicit answer; serves both users; Add Tap argv stays `tap user/repo` character-for-character, so TM6's argv scenario and `TapShippingProofTests` argv assertions are untouched | Two steps for the common intent; needs the untrusted state to be *visible* or it is the same silent half-state | Medium (badge + 2 commands + 2 buttons) |
| C. Two-outcome confirmation ("Add and Trust" / "Add Only") | Best UX on paper | Requires a partial-confirm path through `ConfirmationRequest`, directly contradicting "confirming submits every command it listed; declining submits none, never a partial subset" | High + spec conflict |

**Recommendation: B.** The deciding argument is not ergonomics but *representability*: A makes
"fetch without granting execution authority" unrepresentable in Cellar, and C buys it back only by
weakening the one confirmation invariant the whole mutation spine rests on. B's single weakness — the
invisible half-state — is exactly what probe 1 removes for free: `tap-info` already publishes
`trusted`, so Cellar can show an Untrusted badge with an inline Trust button, and the half-state
becomes visible and one click from resolved. Homebrew's own reason for the split (fetching a git repo
is not consenting to load Ruby from it) then survives intact in the GUI.

**D1 — confirm with the user.** If the user prefers A, everything below still holds except the Add
Tap copy (§Q6) and the addition of a batch at the Add Tap call site; the Trust/Untrust controls are
still required for taps added outside Cellar and for revocation.

## Q2 — Trust state surface (revised by probe 1)

**No new read command, no new store, no new invalidation domain.**

- `TapWire` decodes `trusted` with `decodeIfPresent(Bool.self)`; `TapRecord` publishes
  `trust: TapTrustState`.
- `TapTrustState` is **three-valued**, not a `Bool`: `.trusted`, `.untrusted`, `.unreported`.
  `.unreported` is the absent key — a Homebrew that has no trust concept. This is the same rule
  `InstalledPackage.declaresAutoUpdates` already applies (`InstalledModels.swift:55-57`): "not
  declared" is not "declared false". It is also the whole of the version-drift mitigation: on
  Homebrew < 6 the badge and both buttons are absent and `brew trust` is never spawned, instead of
  every tap being labelled untrusted.
- Badge copy lives in `TapProjection` beside `packageSummary`, so the list row, the detail header and
  the tests read one projection.
- **Invalidation**: `TapCommand.trustTap` / `.untrustTap` declare `invalidates: .taps`
  (`BrewMutating.swift:48`). The shipped terminal-refresh machinery re-runs `tap-info` once per
  terminal outcome and the badge flips with no new plumbing. TM9's "each terminal refreshes taps
  exactly once, and none refreshes catalog or installed inventory" extends to the two new commands
  unchanged.
- `brew trust --json v1` and a `TrustInventory` type are **deferred**. They buy only per-package
  grants, which no surface in this change needs (see Q4), and they would add a second read path and a
  second source of truth for the same question.

## Q3 — Untap semantics

Homebrew leaves the grant in `trust.json` after `untap`, and once the tap is gone Cellar cannot even
see it without the deferred `brew trust --json v1` read. A dormant, invisible capability grant for a
tap the user just removed is the worst available outcome, and it silently re-arms on the next tap —
including a tap performed by a Brewfile import.

**Recommendation: Untap revokes first.** `Untap` submits two commands under one action —
`["untrust", name]` then `["untap", name]`. `brew untrust` on a never-trusted tap exits 0 (probe 3),
so no trust-state precondition is needed and the vector is unconditional. Order is load-bearing:
untrust must run while the tap still resolves (**probe P2** confirms). Force Untap gets the same
prepend.

TM7 keeps "ordinary removal MUST NOT require confirmation" and the untap argv stays exactly
`untap user/repo`; what changes is that the action submits two operations. That is a MODIFIED
requirement, not a new confirmation.

## Q4 — Mutations on packages from an untrusted tap

| Option | Verdict |
|---|---|
| (a) Pre-launch gate: detect and block, offering "Trust <tap> first" | **Rejected as a gate, kept as a hint.** Cellar cannot prove the origin tap: with the tap untrusted the inventory reports `tap: null`, so the only available inference is "some untrusted tap publishes this exact token", which two taps can satisfy. Worse, probe 2 shows **per-package grants exist independently of tap grants** — a package can be trusted while its tap is not, so a tap-state gate would block an operation brew would have allowed. |
| (b) Build the fully-qualified argv when the tap is known and untrusted | **Rejected outright.** `trust.rb#explicitly_allowed?` treats naming the qualified package as the grant, so this converts a refusal into silent execution of code the user did not consent to run — it *is* the bypass, dressed as a fix. It also requires synthesising a name that is not the package's identity (`PackageID.name` is the bare token), and `MutationName.isSafe` would not stop it (`MutationCommand.swift:130-133`) — which is precisely why the prohibition must be a rule with a test, not an accident of validation. |
| (c) Let brew refuse; classify the refusal; offer the recovery | **Recommended.** brew is the only authority that knows whether a given invocation is allowed, because it alone sees both grant kinds. |

Implementation of (c): a new `MutationOutcome` case (`refusedUntrustedTap`) and a
`Signature.isUntrustedTap` matching brew's refusal prose, added beside `isLock`/`isPrivilege`
(`MutationOutcome.swift:110-135`) under the same discipline — stderr-only, tail-bounded, structural
facts first, and **nothing parsed out of the payload**. The message is therefore tap-agnostic:

> "Homebrew refused to load this package because its tap is not trusted. Trust the tap in Taps, then
> try again."

...shown beside the full verbatim log, which already contains brew's own exact `brew trust …` line.
A miss degrades to `.failed` with the log visible — the accepted degradation the type already
documents.

The non-blocking hint: because `tap-info` gives untrusted taps *and* their published tokens, the tap
detail can mark an installed package whose tap is withheld (§Q5), and the Installed detail can carry
the same note. Presented as an explanation, never as a gate, and worded about the **tap** only —
never "this package is untrusted", which a per-package grant would make false.

## Q5 — Installed inventory with `tap: null`

Confirmed at `InstalledDecoder.swift:76` and `:108`: `tap: formula.tap ?? ""` / `tap: cask.tap ?? ""`.
The record survives; the field becomes `""`. `TapProjection.exactInstalled` (`TapProjection.swift:146`)
demands `$0.tap == tap`, so every installed package from an untrusted tap reads **"Not installed."** —
a false statement about this Mac, and the same defect class as PR #67 with a new cause.

The trust work makes it moot only for taps the user chooses to trust. A deliberately untrusted tap
keeps lying. Fix it honestly:

- Make absence representable: `InstalledPackage.tap` becomes `String?` and the decoder stops
  collapsing null into `""`. This is the in-house rule already stated for `declaresAutoUpdates`
  (`InstalledModels.swift:55-57`) and is a compile-error migration (~8 call sites) rather than a
  sentinel anyone can forget.
- `TapProjection` gains a third, typed state between installed and not: tap matches exactly →
  handoff (unchanged); tap is **withheld** *and* the selected tap is untrusted *and* publishes this
  exact `(kind, name)` → "Installed. Homebrew withholds its tap while this tap is untrusted."; else
  "Not installed." The **Show in Installed** handoff is still offered in the middle state, because
  the handoff selects by exact `PackageID` and that identity is exact.
- TM5's "installed status MUST come only from a snapshot whose exact `InstalledPackage.tap` equals
  the selected tap" is MODIFIED to admit this second typed case. Under the current wording the spec
  *mandates* the wrong answer.

Cheaper alternative if the optional migration is unwanted: treat `""` as the sentinel for withheld.
Rejected — brew never emits `tap: ""`, so it works, but it re-creates exactly the "two facts, one
value" collapse this codebase spends paragraphs avoiding.

## Q6 — Disclosure copy and the spec lines that move

Under the recommended split, the case named `tapTrust` would carry text saying trust does *not*
happen. Rename it. **D2**: `ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)`, plus a new
`.tapTrustGrant(TapName)`. The rename touches `package-mutation` and `brewfile-management`, which name
the case in spec prose — that churn *is* the change: the old name is the lie.

Proposed exact text (English, neutral):

- `.tapAdd(tap)` — "Adding \(tap) clones a third-party repository. Homebrew will not load its
  formulae or casks until you trust it, and Cellar does not trust it for you."
- `.tapTrustGrant(tap)` — "Trusting \(tap) lets Homebrew load and run its formulae and casks. That is
  third-party code running as you, with your permissions."
- Under D1=A instead, one text replaces both: "Adding \(tap) and trusting it lets Homebrew load and
  run its formulae and casks. That is third-party code running as you, with your permissions."
- `TapDetailView.swift:183` footer — "Add ones you trust." becomes trust-state aware; it currently
  describes a decision the Add action does not make.
- `MutationConfirmation.swift:153`/`:168` need the new cases (title "Trust this tap?", confirm label
  "Trust").

Spec deltas:

| Spec | Change |
|---|---|
| `tap-management` TM5 | MODIFIED — third installed state for a withheld tap |
| `tap-management` TM6 | MODIFIED — truthful add copy; add grants no trust |
| `tap-management` TM7 | MODIFIED — untap revokes first |
| `tap-management` TM8 | MODIFIED — force untap revokes first |
| `tap-management` TM11 | MODIFIED — action surface gains trust and untrust |
| `tap-management` **TM12** | ADDED — "Tap trust is read from the snapshot, shown, and granted only by an explicit answer" (three-valued state, `.unreported` hides the surface, no silent grant on any path) |
| `package-mutation` (gate, spec.md:173-182) | MODIFIED — the shared gate's disclosure inventory |
| `installed-inventory` | MODIFIED — a withheld tap is not an empty tap |
| `brewfile-management` BF5 | MODIFIED only for the case rename; the rule is unchanged |

## Q7 — Brewfile

**`trusted:` stays informational. No `brew trust` during import.**

`brewfile-management` spec.md:218-231 already requires it, and its provenance (spec.md:508-510) gives
the reason: the claim is made by *the file's author*, who is exactly the party a trust decision must
not be delegated to. Homebrew 6 turning trust into a real grantable capability makes that argument
stronger — honouring the option would turn Brewfile import into a way for a file author to get
arbitrary code trusted on someone else's Mac.

Consequence for scope: `BrewfilePlan` (`BrewfilePlan.swift:36-37`) emits `TapCommand.addTap` only and
**needs no change at all**. Under the recommended split its imports tap without trusting, which is
the correct and now-honest behaviour. The only edit is the disclosure case rename.

## Q8 — Strict TDD plan

RED-able units, with exact files:

| # | Unit | File |
|---|---|---|
| 1 | `trusted: true` / `false` / absent → `.trusted` / `.untrusted` / `.unreported`; fixture mirrors real `tap-info` shape (PR #67 lesson) | `Packages/CellarCore/Tests/BrewClientTests/TapDecodeTests.swift` |
| 2 | argv `["trust", "acme/tools"]`, `["untrust", "acme/tools"]`; Untap submits untrust-then-untap in that order; `requiresConfirmation` true for trust and false for untrust; `invalidates == .taps`; `packageID == nil`; namespaced `verb` | `TapCommandTests.swift` |
| 3 | exact `warningText` for `.tapAdd` and `.tapTrustGrant`; `.packageRemoval` / `.forceUntap` / protocol default unchanged | `ConfirmationDisclosureTests.swift` |
| 4 | badge projection per trust state; `.unreported` yields no control; the withheld-tap third state; exact-match behaviour preserved | `TapProjectionTests.swift` |
| 5 | `tap: null` → `nil`, `tap: "acme/tools"` → that value, key absent → `nil`, record still projected | installed decode suite (`InstalledDeriveTests.swift` / the decoder's own suite) |
| 6 | refusal prose on stderr + non-zero exit → `.refusedUntrustedTap`; same prose on stdout → `.failed`; exit 0 → `.succeeded` | `ClassificationTests.swift` |
| 7 | `TapManagementAction.allCases` grows to 8; static button set becomes `["Add Tap","Untap","Force Untap","Show in Installed","Trust","Untrust"]`; excluded-capability scan still clean | `TapShippingProofTests.swift:90`, `:194`, `:287` |
| 8 | `TapCommand.swift`'s `arguments` body stays free of `\(`, `joined(`, `split(` — satisfied by literal verbs plus `tap.rawValue` | `MutationCommandTests.swift:289` (already shipped; must stay green) |
| 9 | Add Tap raises exactly one `.tapAdd`; Trust raises exactly one `.tapTrustGrant`; Untrust raises none; Brewfile import still raises exactly one and grants nothing | `cellarTests/BrewfileCompositionTests.swift` + a tap composition test |
| 10 | Trust button present only for `.untrusted`; absent for `.trusted` and `.unreported`; badge text | `cellarUITests` |

**manual-evidence** (maintainer's Mac, cannot be automated):

- Round trip: `brew tap juancasanueva/cellar` → app shows Untrusted → app **Trust** → `brew trust
  --json v1` lists `juancasanueva/cellar` → badge flips with no manual reload.
- Bare-token `brew upgrade --cask home-cellar` from inside Cellar renders `.refusedUntrustedTap` with
  brew's own `brew trust …` line visible in the log.
- **Untap** on a trusted tap → `brew trust --json v1` no longer lists it (the stale-grant fix).
- Homebrew < 6 degradation is not reproducible on the maintainer's Mac; it is covered by the
  `.unreported` decode test plus a documented limitation.

## Q9 — Sizing, risks, rollback

**Sizing** (authored additions + deletions, estimate):

| Area | Lines |
|---|---|
| Core (`TapWire`, `TapCommand`, `TapProjection`, `InstalledDecoder`/`InstalledModels` + ~8 call sites, `MutationOutcome`) | ~220 |
| App (`TapsListView`, `TapDetailView`, `MutationConfirmation`) | ~110 |
| Tests (7 files) | ~400 |
| Specs (5 MODIFIED + 1 ADDED across 4 spec files) | ~300 |
| **Total** | **~1000–1300** |

Against the cached `review_budget_lines=5000`: **Low risk**. Against the default 400-line reviewer
guard it is High, so `single-pr` is a deliberate, budgeted exception rather than an oversight — worth
restating in the proposal. If the user later wants slices, the natural cut is
(1) read + badge + honesty (decode, projection, copy, specs) and (2) grant + revoke + refusal
classification.

**Risks**

- *Trust is a capability grant.* No path may grant it implicitly: not Add Tap (under the recommended
  split), not Brewfile import, not the refusal recovery, not a retry. Assert it as an absence test
  over the argv surface, not by review.
- *Stale grants* — mitigated by untrust-before-untap; depends on probe P2.
- *Homebrew version drift* — `.unreported` hides the whole surface and spawns no `brew trust`.
- *Per-package grants* — a package individually trusted under an untrusted tap must not be described
  as untrusted; all copy is tap-scoped.
- *`tap` optional migration* — 8 call sites; made a compile error rather than a runtime sentinel.
- *Refusal-prose drift* — degrades to `.failed` with the verbatim log, the already-accepted fallback.
- *Shipping-proof drift* — the pinned button set and action enum fail loudly, which is the desired
  behaviour.

**Rollback** — additive except two pieces, reversible in order: (1) drop the untrust prepend
(`removeTap` returns to one command); (2) drop the trust/untrust cases, UI and shipping-proof
entries; (3) drop the `trusted` decode (badge disappears, no behaviour change). The
`InstalledPackage.tap` optionality can stay independently — it is a strict honesty improvement with
no dependency on the trust surface.

## Q10 — Orchestrator probes still needed

| # | Command | Decides |
|---|---|---|
| P1 | `brew tap-info --json --installed` full object for one trusted and one untrusted tap, plus `homebrew/core` | exact `trusted` key name/type; whether official taps report it |
| P2 | `brew untap acme/tools && brew untrust acme/tools; echo $?` (and stderr) | whether untrust must precede untap (Q3 ordering) |
| P3 | With tap untrusted and a **per-package** grant (`brew trust --cask owner/tap/token`): `brew info --installed --json=v2 \| jq '.casks[].tap'` and `brew upgrade --cask <token>` | whether a per-package grant restores the `tap` field and unblocks bare-token argv (Q4/Q5 hint accuracy) |
| P4 | Exact stderr bytes of the refusal for a **formula** and a **cask**, on `upgrade` and `uninstall`, bare token | pins `Signature.isUntrustedTap` (wording differs formula vs cask for locks today — confirm it does not here) |
| P5 | `brew trust acme/tools` on an already-trusted tap: exit code + stdout | whether `.noChange` classification is needed |
| P6 | `brew trust --help` full flag list on 6.0.18 | whether argv should be explicit `trust --tap acme/tools` rather than a bare positional |
| P7 | `brew untap` a trusted tap, then `brew tap` it again; `brew trust --json v1` before/after | empirical confirmation of the stale-grant risk |
| P8 | Homebrew changelog/source: which release added `trusted` to `tap-info --json` | wording of the `.unreported` degradation note |

## Ready for proposal

**Yes**, once D1 (consent model) and D2 (disclosure case rename) are answered and probes P1–P4 land.
P5–P8 refine copy and argv but do not block the proposal.
