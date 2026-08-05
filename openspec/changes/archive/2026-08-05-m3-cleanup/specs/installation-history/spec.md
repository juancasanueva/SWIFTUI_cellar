# Delta for Installation History

## ADDED Requirements

### Requirement: Cleanup history has namespaced verbs and exact subjects

Every cleanup terminal MUST use exactly one stored verb: `cleanupGlobal`, `cleanupPackage`, `cleanupFull`, or `cleanupAutoremove`. Global, Full, and autoremove entries MUST store a null package identity and absent version fields. Package cleanup MUST store its validated formula-or-cask identity. Every entry MUST retain exact argv and outcome under the existing exactly-once, append-only rules.

#### Scenario: All cleanup scopes persist without invented identity

- GIVEN one terminal operation for every cleanup scope
- WHEN history is read
- THEN four entries carry their exact namespaced verbs, argv, and outcomes
- AND only `cleanupPackage` carries its exact package identity and kind

### Requirement: Cleanup labels and search preserve scope and rollback compatibility

Presentation MUST label the verbs respectively “Cleanup,” “Package cleanup,” “Full cleanup,” and “Autoremove.” Null identities MUST be presented as operation scopes, never as packages or inferred argv subjects. Case-insensitive search MUST match those labels/verbs, `cleanup`, `full`, `autoremove`, package names, and argv. The existing nullable schema MUST be used without migration; an older or unknown presentation MUST degrade to the stored verb, null/package subject, and raw argv without becoming executable.

#### Scenario: Labels and search distinguish cleanup operations

- GIVEN global, package, Full, and autoremove entries
- WHEN searches run for `cleanup`, `FULL`, `autoremove`, and the package name
- THEN each query returns only matching entries with the labels and subjects above
- AND reverting cleanup-specific presentation leaves every entry readable and non-replayable
