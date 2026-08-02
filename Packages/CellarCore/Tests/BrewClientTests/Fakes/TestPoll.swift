/// Bounded cooperative polling shared by the fakes.
///
/// Yields until `condition` holds or a generous wall-clock deadline passes, so a
/// broken expectation fails on its assertion instead of hanging the suite.
///
/// A third copy of the `BrewProcessTests` / `CatalogTests` helper: separate test
/// targets cannot share code, and `CellarTestSupport` (M2-0 D5) was cut before
/// it landed.
enum TestPoll {
    static func until(
        timeout: Duration = .seconds(5),
        _ condition: @autoclosure () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
