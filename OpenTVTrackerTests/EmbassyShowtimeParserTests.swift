import XCTest
@testable import OpenTVTracker

final class EmbassyShowtimeParserTests: XCTestCase {
    func testParsesOnlyRequestedDayWithOfficialBookingLinks() throws {
        let html = """
        <article class="film type-film availability-now-showing">
          <h3 class="elementor-heading-title elementor-size-default"><a href="/films/example/">Example &amp; Friends</a></h3>
          <ul><li>Cinema 2 Laser Projection</li></ul>
          <div class="schedule-row" data-schedule-day="Friday 17 Jul" data-schedule-ts="1784246400">
            <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=1" class="schedule-row-timeslot elementor-button">10:00</a>
            <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=2" class="schedule-row-timeslot elementor-button">20:30</a>
          </div>
          <div class="schedule-row" data-schedule-day="Saturday 18 Jul" data-schedule-ts="1784332800">
            <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=3" class="schedule-row-timeslot elementor-button">11:15</a>
          </div>
        </article>
        """
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Malta")!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17)))

        let showings = EmbassyShowtimeParser.showings(in: html, on: date)

        XCTAssertEqual(showings.count, 2)
        XCTAssertEqual(showings.map(\.title), ["Example & Friends", "Example & Friends"])
        XCTAssertEqual(showings.first?.venueID, "embassy")
        XCTAssertEqual(showings.first?.format, "Cinema 2 Laser Projection")
        XCTAssertEqual(showings.first?.bookingURL.host(), "embassy.admit-one.eu")
        XCTAssertTrue(showings.first?.bookingURL.absoluteString.contains("perfCode=1") == true)
    }
}
