> **Post-archive follow-up (2026-08-22).** This report postdates the archive it sits in. It is the
> U22 Mac App Store feasibility spike that `archive-report.md` names as the change's most
> consequential open follow-up. Its verdict — **MAS infeasible**: the App Sandbox denies
> `file-read-data` on `/opt/homebrew` before brew can even exec, Guidelines 2.5.2/2.4.5 forbid the
> category, and no Homebrew GUI exists on MAS — is what triggered the removal of the tip jar in the
> very next change: the maintainer chose a free app with no tip jar and no external links. The
> capability this archive built was merged in PR #55 and reverted immediately after this measurement.

# U22 — Mac App Store Feasibility Spike (Cellar)

Date: 2026-08-22 · macOS 26 (arm64) · Xcode 26.6 (17F113) · brew at /opt/homebrew/bin/brew
Signing identity used: `Apple Development: Juan Casanueva (A8EB4839B9)`, team Z3S5JK8E38.
Repo untouched: `git status --short` before and after shows the identical pre-existing state
(`M cellar-storekit.xcscheme` unstaged + the two staged formula.imageset files).

Question: can a sandboxed (MAS-eligible) Cellar exist at all, and does the tip jar's StoreKit
path work under sandboxing? Documented reasoning said no; this spike turns reasoning into measurement.

---

## E1 — Sandbox child-process inheritance, minimal case

Scratch app: `u22/e1/SandboxProbe.app` — Swift CLI-style bundle, signed with the dev identity,
hardened runtime + `com.apple.security.app-sandbox` (verified via `codesign -d --entitlements -`).
It spawns children via `Process` and writes results to `$HOME/e1-output.txt`.

Sandbox confirmed active at launch:

```
HOME=/Users/juancasanueva/Library/Containers/com.u22.sandboxprobe/Data
APP_SANDBOX_CONTAINER_ID=com.u22.sandboxprobe
secinitd: AppSandbox request successful
```

Measurements (raw excerpts):

```
stat(/opt/homebrew/bin/brew) exists per FileManager: true

=== /bin/echo sandbox-spawn-works ===        exit=0, stdout "sandbox-spawn-works"
=== /bin/ls /opt/homebrew/bin ===            exit=1, stderr "ls: /opt/homebrew/bin: Operation not permitted"
=== /opt/homebrew/bin/brew --version ===     LAUNCH FAILED: NSCocoaErrorDomain Code=4
    "The file "brew" doesn't exist." (NSFilePath=/opt/homebrew/bin/brew)
=== /opt/homebrew/bin/brew list --formula == same LAUNCH FAILED
```

Kernel sandbox log (`/usr/bin/log show --predicate 'eventMessage CONTAINS "deny" ...'`):

```
Sandbox: ls(32888) deny(1) file-read-data /opt/homebrew/bin
```

Mechanism: `Process` spawning itself works fine inside the sandbox and children fully inherit it
(`/bin/echo` succeeds; inherited `ls` is denied file-read-data on /opt/homebrew). brew never even
executes: `posix_spawn`'s read of the executable is denied and Foundation surfaces it as
NSCocoaErrorDomain 4 "file doesn't exist" — despite `FileManager.fileExists` returning true
(metadata stat is allowed, content read is not). This is one step worse than the documented
reasoning: it is not that brew breaks inside the inherited sandbox — brew cannot be exec'd at all.

**VERDICT (E1): No brew invocation survives — not even `brew --version`. Launch fails before the
first instruction of brew runs; the deny is `file-read-data /opt/homebrew/*`.**

## E2 — The real Cellar, sandbox forced on

Command (repo untouched, scratch derived data):

```
xcodebuild -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath <scratch>/u22/dd ENABLE_APP_SANDBOX=YES build
→ ** BUILD SUCCEEDED **
```

No entitlements conflict: the built product's entitlements are `app-sandbox=true`,
`files.user-selected.read-only=true`, `get-task-allow=true`. Launched via `open`, observed ~60s.

- Container `~/Library/Containers/com.juancasanueva.cellar/` already existed (Aug 1, from an
  earlier sandboxed run); its `Data/` was freshly touched at launch (`tmp/`, `default.profraw`,
  metadata rewritten). **Maintainer note: this container plus
  `com.juancasanueva.cellarUITests.xctrunner` exist and were reused/updated — candidates for
  manual cleanup; nothing was deleted by the spike.**
- Screenshot (`u22/e2-cellar-sandboxed.png`): app launches and renders fine, but Home shows
  **"Homebrew not found — Install it from https://brew.sh"**. The inventory never populates;
  brew detection cannot see `/opt/homebrew/bin/brew` from inside the sandbox — exactly the E1
  failure surfacing through Cellar's own UI.
- Kernel log denials from the `cellar` process: `file-read-data /Library/Preferences/com.apple.networkd.plist`,
  `mach-lookup com.apple.dnssd.service`, `network-outbound /private/var/run/mDNSResponder` —
  i.e. with sandbox on, Cellar also lacks `com.apple.security.network.client`, so even the
  formulae.brew.sh API calls would be blocked. No brew-path denials appear because brew is
  never successfully exec'd (fails pre-spawn, as in E1).

**VERDICT (E2): The sandboxed Cellar builds and launches, but is functionally dead — brew is
invisible, inventory never populates, and networking is additionally blocked. Sandbox-on Cellar
is an empty shell.**

## E3 — Is sandboxing the gate for Run-time StoreKit config delivery?

Scratch project `u22/e3/SKProbe` (generated with xcodegen): two app targets sharing one SwiftUI
source — `SKProbeSandboxed` (app-sandbox entitlement) and `SKProbeUnsandboxed` (hardened runtime
only, like today's Cellar) — and two shared schemes, each with
`<StoreKitConfigurationFileReference identifier="../../../Tip.storekit">` (same relative-path shape
as the repo's `cellar-storekit` scheme), pointing at a copy of the real `cellarTests/Tip.storekit`
(one consumable, `com.juancasanueva.cellar.tip`). The app calls
`Product.products(for:)` at launch and writes the count to `$HOME/skprobe-result.txt`.
Both runs were launched through Xcode via AppleScript (`open` project → `set active scheme` → `run`),
the pattern that worked yesterday; a third control run launched the binary directly with `open`.

```
XCODE-RUN SANDBOXED    sandboxed=true   products.count=0
XCODE-RUN UNSANDBOXED  sandboxed=false  products.count=0
DIRECT-LAUNCH control  sandboxed=false  products.count=0   (expected 0 — no Xcode injection)
```

No error was thrown in any run — `Product.products(for:)` returned an empty array. Xcode's
Run-time StoreKit configuration delivered zero products in **both** sandbox states, on a fresh
minimal project, reproducing yesterday's unsandboxed-Cellar result exactly.

Honest scope note: this measurement cannot distinguish "StoreKit-config-at-Run is broken in this
Xcode 26.6/macOS 26 environment" from "the AppleScript-run path skips injection" — but both
sandbox states went through the identical launch path, so the specific hypothesis under test is
answered cleanly.

**VERDICT (E3): Sandbox state does NOT change StoreKit config delivery — 0 products either way.
The Run-time delivery failure is orthogonal to sandboxing; enabling the sandbox would not fix the
tip jar's Xcode-run testing path.**

## E4 — Desk research

### (a) Guidelines 2.5.2 / 2.4.5 vs "a GUI that instructs Homebrew"

Current wording (fetched 2026-08-22 from https://developer.apple.com/app-store/review/guidelines/):

- **2.5.2**: "Apps should be self-contained in their bundles, and may not read or write data
  outside the designated container area, nor may they download, install, or execute code which
  introduces or changes features or functionality of the app, including other apps." (Educational
  exception exists but requires source viewable/editable — not applicable.)
- **2.4.5(i)**: Mac App Store apps "must be appropriately sandboxed".
- **2.4.5(ii)**: "self-contained, single app installation bundles and cannot install code or
  resources in shared locations."
- **2.4.5(iv)**: "They may not download or install standalone apps, kexts, additional code, or
  resources to add functionality or significantly change the app…"

A Homebrew GUI violates 2.5.2 ("execute code… including other apps"), 2.4.5(ii) (/opt/homebrew is
a shared location), and 2.4.5(iv) (installing standalone apps/casks) — and 2.4.5(i) is the
technical wall E1/E2 measured. Precedent: **no known Homebrew GUI is on the Mac App Store** —
Cakebrew, Applite, Cork, WailBrew, Cakebrewjs all distribute outside MAS (Applite's own site
notes it is not sandboxed); MacRumors/AppAddict coverage of the category lists no MAS entry.
Searches found zero MAS apps that drive Homebrew or install CLI tools.

Sources: https://developer.apple.com/app-store/review/guidelines/ ·
https://github.com/beeware/briefcase/issues/1655 (MAS rejection: "your app installed or launched
executable code, which is not permitted") · https://milanvarady.github.io/Applite/ ·
https://appaddict.app/post/a-few-gui-tools-for-the-homebrew-curious ·
https://saagarjha.com/blog/2020/11/08/fixing-section-2-5-2/

### (b) PrivacyInfo.xcprivacy required-reason enforcement on macOS

Since May 1 2024 Apple rejects submissions missing required-reason declarations (ITMS-91053), but
current reporting and community consensus is that **the required-reason API declaration is not
(yet) enforced for macOS submissions** — enforcement targets iOS/iPadOS/tvOS/watchOS/visionOS;
Apple's enforcement announcement does not name macOS. If Cellar ever submits to MAS it should
ship a PrivacyInfo.xcprivacy anyway (UserDefaults, file-timestamp, disk-space APIs are all in
Cellar's dependency surface) — cheap insurance against Apple extending enforcement.

Sources: https://developer.apple.com/news/?id=3d8a9yyh (enforcement dates; no macOS platform list) ·
https://www.avanderlee.com/xcode/missing-api-declaration-required-reason-itms-91053/ ("an API
declaration is not required for macOS" as of its last update) ·
https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest

## E5 — Escape-hatch survey (research only)

**Privileged helper via SMAppService.** Verified: from a *sandboxed* app, SMAppService can only
register helpers that are themselves sandboxed (enforced since macOS 14.2), and 2.4.5(v) forbids
root escalation on MAS anyway. A sandboxed helper inherits the same /opt/homebrew wall E1
measured, so this buys nothing for Cellar. Sources:
https://developer.apple.com/forums/thread/739940 · https://developer.apple.com/forums/thread/708765

**Shipping an unsandboxed helper inside the MAS app.** Verified false path: App Review requires
every executable in a MAS bundle to be sandboxed (2.4.5(i)); DTS explicitly warns off installing a
non-sandboxed helper from a sandboxed app, citing 2.4.5. A MAS Cellar cannot ship or install its
own unsandboxed brew-runner. Sources: https://developer.apple.com/forums/thread/763977 ·
https://developer.apple.com/forums/thread/112628

**XPC to a user-installed companion.** Technically possible: the user separately downloads a
Developer ID companion (from the website), and the sandboxed MAS app talks to its mach service via
an app-group-prefixed name or a temporary-exception mach-lookup entitlement. But temporary
exceptions are "tricky" to get past App Review, the app must degrade gracefully when the companion
is absent (a MAS Cellar that says "now go download the real engine from our website" invites
rejection as a shell app, 4.2 minimum functionality), and the companion executing brew still walks
into 2.5.2's "execute code… including other apps" as the app's advertised purpose. Realistic for a
2.x experiment with a big compliance gamble; not realistic for Cellar 1.x. Sources:
https://developer.apple.com/forums/thread/112628 · https://developer.apple.com/forums/thread/99602

**Verdict (E5): none of the three patterns is realistic for Cellar 1.x.** The only honest MAS
shape would be a read-only "catalog browser" with no brew execution at all — a different product.

---

## Overall VERDICT: **MAS infeasible** for Cellar as designed.

Strongest single piece of evidence: E1's kernel-level measurement — a signed, sandboxed app
cannot even *exec* `/opt/homebrew/bin/brew` (`Sandbox: deny(1) file-read-data /opt/homebrew/bin`;
`posix_spawn` fails pre-launch). This is not a guideline interpretation that review might waive;
it is the OS mechanically refusing, confirmed end-to-end by E2's sandboxed Cellar rendering
"Homebrew not found" over a permanently empty inventory.

## RECOMMENDATION (tip jar): **pivot to external links** (Developer ID distribution, tip via
Stripe/GitHub Sponsors/Ko-fi link), keeping the existing StoreKit code dormant behind a flag
rather than deleting it.

Strongest single piece of evidence: E3 — StoreKit's Xcode-run test path delivers 0 products in
*both* sandbox states on a fresh minimal project, so the tip jar's one blocked dependency is not
waiting on a sandbox decision; meanwhile MAS (the only distribution channel where StoreKit IAP is
*required*) is infeasible per the overall verdict, and outside MAS Apple imposes no IAP
requirement, making a plain payment link the zero-dependency path. Dual strategy is not worth
carrying: there is no realistic MAS Cellar 1.x for the StoreKit half to serve.

---

## Artifacts (scratch)

- `u22/e1/` — SandboxProbe source, entitlements, app bundle; output also at
  `~/Library/Containers/com.u22.sandboxprobe/Data/e1-output.txt`
- `u22/dd/` — sandboxed Cellar derived data (`Build/Products/Debug/cellar.app`)
- `u22/e2-cellar-sandboxed.png`, `u22/e2-denials.txt`, `u22/e2-cellar-log.txt`
- `u22/e3/` — SKProbe project, `run_e3.sh`, results in task output
- Containers touched (report only, NOT deleted): `com.u22.sandboxprobe`,
  `com.u22.skprobe.sandboxed`, `com.juancasanueva.cellar` (pre-existing, refreshed),
  `com.juancasanueva.cellarUITests.xctrunner` (pre-existing)

## Key Learnings

1. A sandboxed macOS app cannot exec `/opt/homebrew/bin/brew` at all: the sandbox denies
   `file-read-data` on /opt/homebrew, so `Process.run` fails with NSCocoaErrorDomain 4 ("file
   doesn't exist") before brew ever starts, even though `FileManager.fileExists` returns true.
2. Child processes fully inherit the App Sandbox: `/bin/echo` spawns and succeeds, while an
   inherited `/bin/ls /opt/homebrew/bin` dies with "Operation not permitted"
   (`Sandbox: deny(1) file-read-data /opt/homebrew/bin` in the kernel log).
3. Cellar built with `ENABLE_APP_SANDBOX=YES` compiles and launches cleanly but shows "Homebrew
   not found" with a permanently empty inventory, and its current entitlements lack
   `network.client`, so sandboxed networking is also denied.
4. Xcode 26.6's Run-time StoreKitConfigurationFileReference delivered 0 products to a minimal
   fresh project in both sandboxed and unsandboxed runs — the delivery failure is orthogonal to
   sandboxing.
5. No Homebrew GUI exists on the Mac App Store (Cakebrew, Applite, Cork, WailBrew all distribute
   outside it), and Guidelines 2.4.5(i)/(ii)/(iv) plus 2.5.2 each independently forbid the
   category; required-reason privacy-manifest enforcement currently does not apply to macOS
   submissions.
