import XCTest
@testable import TokenPeek

final class TokenPeekTests: XCTestCase {
    func testRemainingPercentIsClamped() {
        XCTAssertEqual(QuotaWindow(usedPercent: 4, windowDurationMins: 300, resetsAt: nil).remainingPercent, 96)
        XCTAssertEqual(QuotaWindow(usedPercent: 120, windowDurationMins: nil, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(QuotaWindow(usedPercent: -5, windowDurationMins: nil, resetsAt: nil).remainingPercent, 100)
    }

    func testTightestQuotaWins() {
        let usage = CodexUsage(
            primary: QuotaWindow(usedPercent: 4, windowDurationMins: 300, resetsAt: nil),
            secondary: QuotaWindow(usedPercent: 18, windowDurationMins: 10_080, resetsAt: nil)
        )
        XCTAssertEqual(usage.tightestRemaining, 82)
    }

    func testCompactPoints() {
        XCTAssertEqual(AppModel.compactPoints(860), "860")
        XCTAssertEqual(AppModel.compactPoints(4_087), "4.1k")
    }
}
