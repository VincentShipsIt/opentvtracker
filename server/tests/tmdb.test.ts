import { describe, expect, test } from "bun:test";
import { mapStreamingProvider } from "../src/tmdb";

describe("mapStreamingProvider", () => {
  test("maps TMDB's current Apple TV label to the Apple TV+ subscription", () => {
    expect(mapStreamingProvider("Apple TV")).toEqual([
      {
        id: "apple-tv",
        name: "Apple TV+",
        symbol: "apple.logo",
        brandHex: "1C1C1E",
      },
    ]);
  });

  test("keeps legacy Apple TV+ labels compatible", () => {
    expect(mapStreamingProvider("Apple TV+")[0]?.id).toBe("apple-tv");
    expect(mapStreamingProvider("Apple TV Plus")[0]?.id).toBe("apple-tv");
  });

  test("does not treat an add-on Amazon Channel as a direct subscription", () => {
    expect(mapStreamingProvider("Apple TV Amazon Channel")).toEqual([]);
  });

  test("keeps direct Prime Video subscriptions mapped", () => {
    expect(mapStreamingProvider("Amazon Prime Video")[0]?.id).toBe("prime-video");
    expect(mapStreamingProvider("Prime Video")[0]?.id).toBe("prime-video");
  });
});
