export type AppAttestMode = "production" | "development" | "test";

export type ServerConfig = {
  port: number;
  tmdbToken?: string;
  appAttest: {
    mode: AppAttestMode;
    teamID: string;
    bundleID: string;
    tokenSecret: string;
    statePath: string;
    challengeTTLSeconds: number;
    tokenTTLSeconds: number;
    developmentBypassToken?: string;
  };
  controls: {
    proxyEnabled: boolean;
    catalogEnabled: boolean;
    cinemaEnabled: boolean;
    registrationEnabled: boolean;
  };
  corsAllowedOrigin?: string;
};

export function loadConfig(
  env: Record<string, string | undefined> = Bun.env,
): ServerConfig {
  const mode = appAttestMode(env.APP_ATTEST_MODE);
  const config: ServerConfig = {
    port: boundedInteger(env.PORT, 8787, 1, 65_535),
    tmdbToken: nonempty(
      env.TMDB_READ_ACCESS_TOKEN ?? env.TMDB_API_READ_ACCESS_TOKEN,
    ),
    appAttest: {
      mode,
      teamID: nonempty(env.APP_ATTEST_TEAM_ID) ?? "",
      bundleID: nonempty(env.APP_ATTEST_BUNDLE_ID) ?? "",
      tokenSecret: nonempty(env.APP_ATTEST_TOKEN_SECRET) ?? "",
      statePath:
        nonempty(env.APP_ATTEST_STATE_PATH) ?? "./data/app-attest-devices.json",
      challengeTTLSeconds: boundedInteger(
        env.APP_ATTEST_CHALLENGE_TTL_SECONDS,
        60,
        15,
        300,
      ),
      tokenTTLSeconds: boundedInteger(
        env.APP_ATTEST_TOKEN_TTL_SECONDS,
        600,
        60,
        3_600,
      ),
      developmentBypassToken: nonempty(env.APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN),
    },
    controls: {
      proxyEnabled: enabled(env.PROXY_ENABLED, true),
      catalogEnabled: enabled(env.CATALOG_ENABLED, true),
      cinemaEnabled: enabled(env.CINEMA_ENABLED, true),
      registrationEnabled: enabled(env.APP_ATTEST_REGISTRATION_ENABLED, true),
    },
    corsAllowedOrigin: nonempty(env.CORS_ALLOWED_ORIGIN),
  };

  if (mode === "production") {
    const missing = [
      ["APP_ATTEST_TEAM_ID", config.appAttest.teamID],
      ["APP_ATTEST_BUNDLE_ID", config.appAttest.bundleID],
      ["APP_ATTEST_TOKEN_SECRET", config.appAttest.tokenSecret],
      ["TMDB_READ_ACCESS_TOKEN", config.tmdbToken],
    ]
      .filter((entry) => !entry[1])
      .map((entry) => entry[0]);
    if (missing.length > 0)
      throw new Error(
        `Missing required production configuration: ${missing.join(", ")}`,
      );
    if (config.appAttest.tokenSecret.length < 32) {
      throw new Error(
        "APP_ATTEST_TOKEN_SECRET must contain at least 32 characters in production",
      );
    }
    if (config.appAttest.developmentBypassToken) {
      throw new Error(
        "APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN is forbidden in production",
      );
    }
  }

  if (mode === "development" && !config.appAttest.developmentBypassToken) {
    throw new Error(
      "Development mode requires APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN",
    );
  }
  return config;
}

function appAttestMode(value: string | undefined): AppAttestMode {
  if (value === "development" || value === "test") return value;
  return "production";
}

function nonempty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function enabled(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined) return fallback;
  return !["0", "false", "off", "no"].includes(value.trim().toLowerCase());
}

function boundedInteger(
  value: string | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return fallback;
  return Math.min(Math.max(parsed, minimum), maximum);
}
