// MarketHoursTests.swift — session open/closed logic in ET.
import XCTest
@testable import DayTrader

final class MarketHoursTests: XCTestCase {

    // Build a Date at a specific ET wall-clock time.
    private func etDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    // 2026-09-28 is a Monday.
    func testOpenDuringSession() {
        let d = etDate(year: 2026, month: 9, day: 28, hour: 10, minute: 30)
        XCTAssertTrue(MarketHours.isOpen(at: d))
    }

    func testClosedAtOpenBoundaryExclusive() {
        // 09:29 → closed (pre-market); 09:30 → open
        XCTAssertFalse(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 28, hour: 9, minute: 29)))
        XCTAssertTrue(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 28, hour: 9, minute: 30)))
    }

    func testClosedAtCloseBoundary() {
        // 15:59 → open; 16:00 → closed
        XCTAssertTrue(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 28, hour: 15, minute: 59)))
        XCTAssertFalse(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 28, hour: 16, minute: 0)))
    }

    func testWeekendClosed() {
        // 2026-09-26 is a Saturday, 27 Sunday
        XCTAssertFalse(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 26, hour: 11, minute: 0)))
        XCTAssertFalse(MarketHours.isOpen(at: etDate(year: 2026, month: 9, day: 27, hour: 11, minute: 0)))
    }

    func testStatusLabels() {
        XCTAssertEqual(MarketHours.statusLabel(at: etDate(year: 2026, month: 9, day: 26, hour: 11, minute: 0)), "Market Closed · Weekend")
        XCTAssertEqual(MarketHours.statusLabel(at: etDate(year: 2026, month: 9, day: 28, hour: 8, minute: 0)), "Pre-Market")
        XCTAssertEqual(MarketHours.statusLabel(at: etDate(year: 2026, month: 9, day: 28, hour: 17, minute: 0)), "After-Hours")
    }
}
