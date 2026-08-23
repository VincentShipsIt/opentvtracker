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

  test("NODE_ENV production requires production App Attest", () => {
    for (const mode of ["development", "test"] as const) {
      expect(() =>
        loadConfig({
          NODE_ENV: "production",
          APP_ATTEST_MODE: mode,
        }),
      ).toThrow("APP_ATTEST_MODE must be production when NODE_ENV=production");
    }
  });

  test("production runtime rejects a bypass independently of App Attest mode", () => {
    expect(() =>
      loadConfig({
        NODE_ENV: "production",
        APP_ATTEST_MODE: "test",
        APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN: "must-not-ship",
      }),
    ).toThrow("APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN is forbidden in production");
  });

  test("rejects unknown App Attest modes instead of silently coercing them", () => {
    expect(() =>
      loadConfig({
        ...productionEnvironment(),
        APP_ATTEST_MODE: "prodution",
      }),
    ).toThrow("APP_ATTEST_MODE must be one of production, development, or test");
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

  test("security controls reject invalid boolean values with the key name", () => {
    for (const key of [
      "PROXY_ENABLED",
      "CATALOG_ENABLED",
      "CINEMA_ENABLED",
      "APP_ATTEST_REGISTRATION_ENABLED",
    ]) {
      expect(() =>
        loadConfig({
          APP_ATTEST_MODE: "test",
          [key]: "flase",
        }),
      ).toThrow(`${key} must be one of`);
      expect(() =>
        loadConfig({
          APP_ATTEST_MODE: "test",
          [key]: " ",
        }),
      ).toThrow(`${key} must be one of`);
    }
  });

  test("security controls preserve explicit boolean aliases", () => {
    const disabled = loadConfig({
      APP_ATTEST_MODE: "test",
      PROXY_ENABLED: "0",
      CATALOG_ENABLED: "false",
      CINEMA_ENABLED: "OFF",
      APP_ATTEST_REGISTRATION_ENABLED: " no ",
    });
    expect(disabled.controls).toEqual({
      proxyEnabled: false,
      catalogEnabled: false,
      cinemaEnabled: false,
      registrationEnabled: false,
    });

    const enabled = loadConfig({
      APP_ATTEST_MODE: "test",
      PROXY_ENABLED: "1",
      CATALOG_ENABLED: "true",
      CINEMA_ENABLED: "ON",
      APP_ATTEST_REGISTRATION_ENABLED: " yes ",
    });
    expect(enabled.controls).toEqual({
      proxyEnabled: true,
      catalogEnabled: true,
      cinemaEnabled: true,
      registrationEnabled: true,
    });
  });

  test("valid NODE_ENV production configuration still loads", () => {
    const config = loadConfig({
      ...productionEnvironment(),
      NODE_ENV: "production",
    });

    expect(config.appAttest.mode).toBe("production");
    expect(config.controls).toEqual({
      proxyEnabled: true,
      catalogEnabled: true,
      cinemaEnabled: true,
      registrationEnabled: true,
    });
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
    for (const header of ["X-Forwarded-For", "Forwarded"]) {
      expect(() =>
        loadConfig({ ...productionEnvironment(), CLIENT_IP_HEADER: header }),
      ).toThrow("header your edge overwrites");
    }
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
    DATABASE_URL: "postgresql://opentv:test@database.test:5432/opentv",
  };
}
