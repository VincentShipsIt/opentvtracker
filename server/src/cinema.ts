export type CinemaShowing = {
  id: string;
  catalogID: number | null;
  title: string;
  venueID: "embassy";
  startsAt: string;
  format: string | null;
  language: string | null;
  bookingURL: string;
};

const EMBASSY_SCHEDULE_URL = "https://www.embassycinemas.com/film-showtimes-tickets/";

export async function embassyShowings(day: string): Promise<CinemaShowing[]> {
  const response = await fetch(EMBASSY_SCHEDULE_URL, {
    headers: {
      Accept: "text/html",
      "User-Agent": "OpenTVTracker/0.1",
    },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`Embassy returned ${response.status}`);
  return parseEmbassyShowings(await response.text(), day);
}

export function parseEmbassyShowings(html: string, day: string): CinemaShowing[] {
  const showings: CinemaShowing[] = [];
  const articlePattern = /<article\b[^>]*\btype-film\b[^>]*>([\s\S]*?)<\/article>/gi;

  for (const articleMatch of html.matchAll(articlePattern)) {
    const article = articleMatch[1] ?? "";
    const title = decodeHTML(
      article.match(/<h3[^>]*elementor-size-default[^>]*>\s*<a[^>]*>(.*?)<\/a>\s*<\/h3>/is)?.[1] ?? "",
    ).replace(/<[^>]+>/g, "").trim();
    if (!title) continue;

    const format = decodeHTML(
      article.match(/<li[^>]*>\s*(Cinema[^<]+)\s*<\/li>/i)?.[1] ?? "",
    ).trim() || null;
    const rowPattern = /<div class="schedule-row"[^>]*data-schedule-ts="([0-9]+)"[^>]*>([\s\S]*?)(?=<div class="schedule-row"|$)/gi;

    for (const rowMatch of article.matchAll(rowPattern)) {
      const timestamp = Number(rowMatch[1]);
      if (!Number.isFinite(timestamp) || utcDay(timestamp) !== day) continue;
      const row = rowMatch[2] ?? "";
      const slotPattern = /<a[^>]*href="([^"]+)"[^>]*schedule-row-timeslot[^>]*>\s*([0-9]{1,2}:[0-9]{2})\s*<\/a>/gi;

      for (const slotMatch of row.matchAll(slotPattern)) {
        const time = slotMatch[2];
        if (!time) continue;
        const startsAt = maltaDate(day, time);
        if (!startsAt) continue;
        const bookingURL = decodeHTML(slotMatch[1] ?? "");
        showings.push({
          id: `embassy-${slug(title)}-${Math.floor(startsAt.getTime() / 1000)}`,
          catalogID: null,
          title,
          venueID: "embassy",
          startsAt: startsAt.toISOString(),
          format,
          language: null,
          bookingURL,
        });
      }
    }
  }

  return showings.sort((left, right) => left.startsAt.localeCompare(right.startsAt));
}

function utcDay(timestamp: number): string {
  return new Date(timestamp * 1000).toISOString().slice(0, 10);
}

function maltaDate(day: string, time: string): Date | null {
  const [year, month, date] = day.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  if ([year, month, date, hour, minute].some((value) => !Number.isFinite(value))) return null;
  const guess = Date.UTC(year!, month! - 1, date!, hour!, minute!);
  const offset = timeZoneOffsetMinutes(new Date(guess), "Europe/Malta");
  const candidate = new Date(guess - offset * 60_000);
  return Number.isNaN(candidate.getTime()) ? null : candidate;
}

function timeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const zoned = Date.UTC(
    Number(values.year),
    Number(values.month) - 1,
    Number(values.day),
    Number(values.hour),
    Number(values.minute),
    Number(values.second),
  );
  return (zoned - date.getTime()) / 60_000;
}

function decodeHTML(value: string): string {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&nbsp;", " ");
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}
