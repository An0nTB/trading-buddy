import Testing
@testable import TradingCore

@Test func versionIstGesetzt() {
    #expect(!TradingCore.version.isEmpty)
}
