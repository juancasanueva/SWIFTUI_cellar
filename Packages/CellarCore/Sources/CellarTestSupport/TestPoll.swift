/// Bounded cooperative polling shared by the fakes.
///
/// Yields until `condition` holds or a generous wall-clock deadline passes, so a
/// broken expectation fails on its assertion instead of hanging the suite.
///
/// The single copy (design D9); it imports nothing at all, which is what keeps
/// `CellarTestSupport` dependency-free.
public enum TestPoll {
    /// The condition is `@Sendable` because the helper is also called from
    /// main-actor-isolated suites, where a plain closure would be sending
    /// non-`Sendable` state across the yield.
    public static func until(
        timeout: Duration = .seconds(5),
        _ condition: @autoclosure @Sendable () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
