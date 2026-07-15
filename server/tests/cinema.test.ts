import { describe, expect, test } from "bun:test";
import { parseEmbassyShowings } from "../src/cinema";

describe("parseEmbassyShowings", () => {
  test("returns official booking slots for only the requested day", () => {
    const html = `
      <article class="film type-film availability-now-showing">
        <h3 class="elementor-heading-title elementor-size-default"><a>Example &amp; Friends</a></h3>
        <ul><li>Cinema 2 Laser Projection</li></ul>
        <div class="schedule-row" data-schedule-ts="1784246400">
          <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=1" class="schedule-row-timeslot">10:00</a>
          <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=2" class="schedule-row-timeslot">20:30</a>
        </div>
        <div class="schedule-row" data-schedule-ts="1784332800">
          <a href="https://embassy.admit-one.eu/?p=tickets&amp;perfCode=3" class="schedule-row-timeslot">11:15</a>
        </div>
      </article>`;

    const showings = parseEmbassyShowings(html, "2026-07-17");

    expect(showings).toHaveLength(2);
    expect(showings[0]?.title).toBe("Example & Friends");
    expect(showings[0]?.format).toBe("Cinema 2 Laser Projection");
    expect(showings[0]?.bookingURL).toContain("perfCode=1");
    expect(showings.every((showing) => showing.startsAt.startsWith("2026-07-17"))).toBe(true);
  });
});
