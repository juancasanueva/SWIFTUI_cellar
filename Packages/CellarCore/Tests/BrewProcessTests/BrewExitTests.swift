import Testing

@testable import BrewProcess

@Suite("BrewExit value semantics")
struct BrewExitTests {
    @Test("A zero exit status is a success that exited normally")
    func successfulExit() {
        let exit = BrewExit(status: 0, reason: .exited)

        #expect(exit.status == 0)
        #expect(exit.reason == .exited)
        #expect(exit.isSuccess)
    }

    @Test("A non-zero exit status is carried, not treated as success")
    func nonZeroExitCarriesItsCode() {
        let exit = BrewExit(status: 1, reason: .exited)

        #expect(exit.status == 1)
        #expect(exit.isSuccess == false)
    }

    @Test("A cancelled exit records the delivered signal and is not a success")
    func cancelledExitCarriesSignal() {
        let exit = BrewExit(status: 130, reason: .cancelled(signal: 2))

        #expect(exit.reason == .cancelled(signal: 2))
        #expect(exit.isCancelled)
        #expect(exit.isSuccess == false)
    }

    @Test("A signalled exit is distinct from a cancelled one")
    func signalledIsNotCancelled() {
        let signalled = BrewExit(status: 139, reason: .signalled(11))

        #expect(signalled.isCancelled == false)
        #expect(signalled != BrewExit(status: 139, reason: .cancelled(signal: 11)))
    }
}
