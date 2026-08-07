import BrewProcess

/// The only `brew` invocation the system-health capability makes.
///
/// Threat response — **argument composition**: a compile-time constant argv
/// vector with exactly one element. There is no parameter, no interpolation and
/// no string joining, so no package name, selection, catalog record or Brewfile
/// token can reach it. There is nothing here to reach it *through*: this
/// enumeration declares one `let` and nothing else, which is why
/// `DoctorCommandTests` asserts the absence of `func` and `var` in the file
/// rather than merely asserting the vector's contents.
///
/// Threat response — **subprocess integration**: `.read`, and not as a
/// convenience. Probe U14 measured `<prefix>/.git/FETCH_HEAD`'s modification
/// date identical before and after two `brew doctor` runs under
/// `HOMEBREW_NO_AUTO_UPDATE=1` — the same pin every Cellar read runs under — so
/// doctor changes nothing that this capability, or any other, reads. Classifying
/// it as a mutation would serialise a harmless measurement behind every queued
/// install and write a history entry for a command that did nothing.
///
/// `brew doctor` has no fix mode. There is no `--fix` to omit and no repair to
/// offer; the surface that runs this says it **re-measures** (`system-health`,
/// "Doctor is a read, and running it fixes nothing").
enum DoctorCommand {
    /// The argv vector, spelled under the name every other `*Command.swift` in
    /// this module spells it.
    ///
    /// Named `arguments` deliberately rather than inlined into `command`: the
    /// shipped `MutationCommandTests` guard scans every `*Command.swift` for a
    /// `var arguments: [String]` and holds its body to "literal tokens plus
    /// validated wrappers only". Hiding this vector behind a differently named
    /// constant would have exempted the newest command family from the oldest
    /// structural rule about argv, which is precisely backwards.
    static var arguments: [String] { ["doctor"] }

    static let command = BrewCommand.read(arguments)
}
