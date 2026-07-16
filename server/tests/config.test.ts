import { describe, expect, test } from "bun:test";
import { loadConfig } from "../src/config";

describe("server configuration", () => {
  test("production fails closed without App Attest identity and secrets", () => {
    expect(() => loadConfig({ APP_ATTEST_MODE: "production" })).toThrow(
      "Missing required production configuration",
    );
  });

  test("production rejects a development bypass", () => {
    expect(() =>
      loadConfig({
        ...productionEnvironment(),
        APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN: "must-not-ship",
      }),
    ).toThrow("forbidden in production");
  });

  test("development is isolated behind an explicit bypass token", () => {
    expect(() => loadConfig({ APP_ATTEST_MODE: "development" })).toThrow(
      "Development mode requires",
    );
    expect(
      loadConfig({
        APP_ATTEST_MODE: "development",
        APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN: "local-only",
      }).appAttest.mode,
    ).toBe("development");
  });

  test("accepts only a syntactically valid trusted client IP header name", () => {
    expect(
      loadConfig({
        ...productionEnvironment(),
        CLIENT_IP_HEADER: "CF-Connecting-IP",
      }).clientIPHeader,
    ).toBe("cf-connecting-ip");
    expect(() =>
      loadConfig({
        ...productionEnvironment(),
        CLIENT_IP_HEADER: "X-Forwarded-For\r\nInjected",
      }),
    ).toThrow("valid HTTP header name");
  });
});

function productionEnvironment(): Record<string, string> {
  return {
    APP_ATTEST_MODE: "production",
    APP_ATTEST_TEAM_ID: "C76R5DRH64",
    APP_ATTEST_BUNDLE_ID: "dev.opentvtracker.app",
    APP_ATTEST_TOKEN_SECRET:
      "test-token-secret-that-is-at-least-thirty-two-characters",
    TMDB_READ_ACCESS_TOKEN: "dedicated-test-read-token",
  };
}
