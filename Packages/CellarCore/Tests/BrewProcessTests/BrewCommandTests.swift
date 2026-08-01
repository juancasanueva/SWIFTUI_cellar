import Testing

@testable import BrewProcess

@Suite("BrewCommand value semantics")
struct BrewCommandTests {
    @Test("A read command keeps its argv vector intact")
    func readCommandPreservesArguments() {
        let command = BrewCommand.read(["outdated", "--json=v2"])

        #expect(command.arguments == ["outdated", "--json=v2"])
        #expect(command.kind == .read)
    }

    @Test("A mutate command is tagged as mutating")
    func mutateCommandIsMutating() {
        let command = BrewCommand.mutate(["upgrade", "ripgrep"])

        #expect(command.arguments == ["upgrade", "ripgrep"])
        #expect(command.kind == .mutate)
    }

    @Test("Arguments are argv elements, never a shell string")
    func argumentsAreNotJoinedIntoAShellString() {
        let hostile = "name with space; $(id)"
        let command = BrewCommand.read(["info", hostile])

        #expect(command.arguments.count == 2)
        #expect(command.arguments[1] == hostile)
    }

    @Test("Same arguments and kind compare equal, differing kind does not")
    func equalityCoversArgumentsAndKind() {
        #expect(BrewCommand.read(["list"]) == BrewCommand.read(["list"]))
        #expect(BrewCommand.read(["list"]) != BrewCommand.mutate(["list"]))
        #expect(BrewCommand.read(["list"]) != BrewCommand.read(["list", "--cask"]))
    }
}
