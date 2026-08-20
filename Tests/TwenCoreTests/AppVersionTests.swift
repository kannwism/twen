import Testing
@testable import TwenCore

@Suite("AppVersion")
struct AppVersionTests {
    @Test func parsesPlainAndTaggedForms() {
        #expect(AppVersion("0.1.0")?.components == [0, 1, 0])
        #expect(AppVersion("v0.2.0")?.components == [0, 2, 0])
        #expect(AppVersion("10.20")?.components == [10, 20])
    }

    @Test func rejectsNonNumericVersions() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1.2.3-beta1") == nil)
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func ordersNumerically() {
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.9")!)
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!) // numeric, not lexicographic
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("v0.1.1")! > AppVersion("0.1.0")!)
    }

    @Test func missingComponentsCountAsZero() {
        #expect(AppVersion("1.2")! == AppVersion("1.2.0")!)
        #expect(!(AppVersion("1.2")! < AppVersion("1.2.0")!))
        #expect(AppVersion("1.2.1")! > AppVersion("1.2")!)
    }
}
