import { describe, expect, test } from "bun:test";
import {
  readJSONBody,
  validateCatalogReviews,
  validateCatalogSearch,
  validateCatalogTitle,
  validateCinemaShowings,
} from "../src/validation";

describe("request validation", () => {
  test("accepts bounded catalog inputs", () => {
    const search = validateCatalogSearch(
      new URL(
        "https://example.test/v1/catalog/search?q=Drama&kind=series&page=2&region=mt",
      ),
    );
    const title = validateCatalogTitle(
      "/v1/catalog/movie/42".match(/^\/v1\/catalog\/(movie|series)\/(\d+)$/)!,
      new URL("https://example.test/v1/catalog/movie/42?region=US"),
    );
    const reviews = validateCatalogReviews(
      "/v1/catalog/series/42/reviews".match(
        /^\/v1\/catalog\/(movie|series)\/(\d+)\/reviews$/,
      )!,
      new URL("https://example.test/v1/catalog/series/42/reviews?page=3"),
    );

    expect(search).toEqual({
      query: "Drama",
      kind: "series",
      page: 2,
      region: "MT",
    });
    expect(title).toEqual({ kind: "movie", id: 42, region: "US" });
    expect(reviews).toEqual({ kind: "series", id: 42, page: 3 });
  });

  test("rejects unknown, oversized, and out-of-range catalog inputs", () => {
    expect(() =>
      validateCatalogSearch(
        new URL("https://example.test/v1/catalog/search?debug=true"),
      ),
    ).toThrow("unknown_query_parameter");
    expect(() =>
      validateCatalogSearch(
        new URL("https://example.test/v1/catalog/search?page=1&page=2"),
      ),
    ).toThrow("duplicate_query_parameter");
    expect(() =>
      validateCatalogSearch(
        new URL(`https://example.test/v1/catalog/search?q=${"x".repeat(101)}`),
      ),
    ).toThrow("invalid_query");
    expect(() =>
      validateCatalogSearch(
        new URL("https://example.test/v1/catalog/search?page=21"),
      ),
    ).toThrow("invalid_page");
    expect(() =>
      validateCatalogSearch(
        new URL("https://example.test/v1/catalog/search?region=MALTA"),
      ),
    ).toThrow("invalid_region");
    expect(() =>
      validateCatalogReviews(
        "/v1/catalog/movie/42/reviews".match(
          /^\/v1\/catalog\/(movie|series)\/(\d+)\/reviews$/,
        )!,
        new URL("https://example.test/v1/catalog/movie/42/reviews?page=101"),
      ),
    ).toThrow("invalid_page");
  });

  test("bounds cinema dates and region", () => {
    const now = new Date("2026-07-15T12:00:00Z");
    expect(
      validateCinemaShowings(
        new URL(
          "https://example.test/v1/cinemas/showings?country=MT&date=2026-07-29",
        ),
        now,
      ).day,
    ).toBe("2026-07-29");
    expect(() =>
      validateCinemaShowings(
        new URL(
          "https://example.test/v1/cinemas/showings?country=US&date=2026-07-16",
        ),
        now,
      ),
    ).toThrow("unsupported_country");
    expect(() =>
      validateCinemaShowings(
        new URL("https://example.test/v1/cinemas/showings?date=2026-08-01"),
        now,
      ),
    ).toThrow("date_out_of_range");
  });

  test("rejects bodies above the endpoint limit before parsing", async () => {
    const request = new Request(
      "https://example.test/v1/app-attest/challenge",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": "5000",
        },
        body: "{}",
      },
    );

    await expect(readJSONBody(request, 1_024)).rejects.toThrow(
      "body_too_large",
    );
  });

  test("stops reading a streamed body when it crosses the endpoint limit", async () => {
    const request = new Request(
      "https://example.test/v1/app-attest/challenge",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ value: "x".repeat(2_000) }),
      },
    );

    await expect(readJSONBody(request, 1_024)).rejects.toThrow(
      "body_too_large",
    );
  });
});
