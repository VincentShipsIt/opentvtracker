export type AppAttestMode = "production" | "development" | "test";

export type ServerConfig = {
  port: number;
  tmdbToken?: string;
  databaseURL?: string;
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
  clientIPHeader?: string;
};

export function loadConfig(
  env: Record<string, string | undefined> = Bun.env,
): ServerConfig {
  const mode = appAttestMode(env.APP_ATTEST_MODE);
  const productionRuntime =
    env.NODE_ENV?.trim().toLowerCase() === "production";
  const config: ServerConfig = {
    port: boundedInteger(env.PORT, 8787, 1, 65_535),
    databaseURL: nonempty(env.DATABASE_URL),
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
      proxyEnabled: securityBoolean(env.PROXY_ENABLED, true, "PROXY_ENABLED"),
      catalogEnabled: securityBoolean(
        env.CATALOG_ENABLED,
        true,
        "CATALOG_ENABLED",
      ),
      cinemaEnabled: securityBoolean(
        env.CINEMA_ENABLED,
        true,
        "CINEMA_ENABLED",
      ),
      registrationEnabled: securityBoolean(
        env.APP_ATTEST_REGISTRATION_ENABLED,
        true,
        "APP_ATTEST_REGISTRATION_ENABLED",
      ),
    },
    corsAllowedOrigin: nonempty(env.CORS_ALLOWED_ORIGIN),
    clientIPHeader: headerName(env.CLIENT_IP_HEADER),
  };

  if (
    (productionRuntime || mode === "production") &&
    config.appAttest.developmentBypassToken
  ) {
    throw new Error(
      "APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN is forbidden in production",
    );
  }
  if (productionRuntime && mode !== "production") {
    throw new Error(
      "APP_ATTEST_MODE must be production when NODE_ENV=production",
    );
  }

  if (mode === "production") {
    const missing = [
      ["APP_ATTEST_TEAM_ID", config.appAttest.teamID],
      ["APP_ATTEST_BUNDLE_ID", config.appAttest.bundleID],
      ["APP_ATTEST_TOKEN_SECRET", config.appAttest.tokenSecret],
      ["TMDB_READ_ACCESS_TOKEN", config.tmdbToken],
      ["DATABASE_URL", config.databaseURL],
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
  }

  if (mode === "development" && !config.appAttest.developmentBypassToken) {
    throw new Error(
      "Development mode requires APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN",
    );
  }
  return config;
}

// Proxies append to these instead of overwriting them, so the first entry is
// whatever the client sent. Rate limits keyed on it would be trivially bypassed.
const APPEND_STYLE_CLIENT_IP_HEADERS = new Set(["x-forwarded-for", "forwarded"]);

function headerName(value: string | undefined): string | undefined {
  const name = nonempty(value)?.toLowerCase();
  if (name && !/^[a-z0-9!#$%&'*+.^_`|~-]+$/.test(name)) {
    throw new Error("CLIENT_IP_HEADER must be a valid HTTP header name");
  }
  if (name && APPEND_STYLE_CLIENT_IP_HEADERS.has(name)) {
    throw new Error(
      `CLIENT_IP_HEADER must be a header your edge overwrites (for example CF-Connecting-IP), not ${name}`,
    );
  }
  return name;
}

function appAttestMode(value: string | undefined): AppAttestMode {
  if (value === undefined) return "production";
  if (value === "production" || value === "development" || value === "test") {
    return value;
  }
  throw new Error(
    "APP_ATTEST_MODE must be one of production, development, or test",
  );
}

function nonempty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function securityBoolean(
  value: string | undefined,
  fallback: boolean,
  key: string,
): boolean {
  if (value === undefined) return fallback;
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "on", "yes"].includes(normalized)) return true;
  if (["0", "false", "off", "no"].includes(normalized)) return false;
  throw new Error(
    `${key} must be one of true, false, 1, 0, on, off, yes, or no`,
  );
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
