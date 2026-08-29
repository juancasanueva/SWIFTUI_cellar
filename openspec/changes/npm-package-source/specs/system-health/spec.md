# Delta for system-health

Existing capability — `openspec/specs/system-health/spec.md` (**11 requirements / 51 scenarios**). This
delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is byte-identical. The
capability becomes **12 requirements / 54 scenarios**. Per the binding decision, Health changes copy
only: the score stays brew-only.

## ADDED Requirements

### Requirement: The outdated row names both sources in its copy, and the score counts Homebrew only

The outdated row MUST announce the merged count from the shared snooze-aware projection and MUST add
the per-source summary `installed-inventory` defines: when npm is `notChecked` or `failed` the row copy
MUST say npm was not checked, naming the reason when known, and MUST NOT describe the installation as up
to date. The score's outdated input MUST be computed over Homebrew identities only, and its breakdown
entry MUST say so, so an unchecked npm neither penalises nor flatters the number. The row's remediation
MUST remain the shipped upgrade-all, which acts on Homebrew only, and its copy MUST NOT claim it updates
npm packages. When the npm source is off or undetected, the row and the score MUST be byte-identical
to the shipped ones.

#### Scenario: The row says npm was not checked

- GIVEN one outdated brew package and npm `failed(network)`
- WHEN the outdated row is projected
- THEN it announces 1 outdated and its copy says npm was not checked, naming the network
- AND it does not describe the installation as up to date
- Verification: `unit`

#### Scenario: The score ignores npm in both directions

- GIVEN two input sets identical except that the second adds three fresh outdated npm packages
- WHEN both are scored
- THEN the numbers are equal and the outdated contribution names Homebrew only
- Verification: `unit`

#### Scenario: npm off leaves the row and score unchanged

- GIVEN the npm source off
- WHEN the row and the score are projected over brew-only inputs
- THEN both equal the shipped projections and no npm copy appears
- Verification: `unit`
