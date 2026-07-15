import { describe, expect, test } from "bun:test";
import type { ServerConfig } from "../src/config";
import {
  AppAttestHeaders,
  AppAttestSecurity,
  BoundedRateLimiter,
  canonicalRequestPayload,
  ChallengeStore,
  type AppAttestCryptography,
  MemoryDeviceStore,
} from "../src/security";

describe("AppAttestSecurity", () => {
  test("validates attestation against the configured app and persists the verified key", async () => {
    const devices = new MemoryDeviceStore();
    const cryptography = new FakeCryptography();
    const security = new AppAttestSecurity(
      appAttestConfig(),
      devices,
      cryptography,
    );
    const challenge = security.issueChallenge("attestation", undefined, null);

    const credentials = await security.register(
      challenge.id,
      "key-id",
      Buffer.from("attestation").toString("base64"),
    );

    expect(devices.get("key-id")).toMatchObject({
      publicKey: "verified-public-key",
      signCount: 0,
    });
    expect(cryptography.attestationInput).toMatchObject({
      challenge: challenge.challenge,
      keyID: "key-id",
      teamID: "C76R5DRH64",
      bundleID: "dev.shipshit.opentvtracker",
      allowDevelopmentEnvironment: false,
    });
    expect(typeof credentials.token).toBe("string");
  });

  test("binds assertions to the exact request and rejects replayed challenges", async () => {
    const devices = new MemoryDeviceStore();
    const cryptography = new FakeCryptography();
    const security = new AppAttestSecurity(
      appAttestConfig(),
      devices,
      cryptography,
    );
    const registration = security.issueChallenge(
      "attestation",
      undefined,
      null,
    );
    const credentials = await security.register(
      registration.id,
      "key-id",
      Buffer.from("attestation").toString("base64"),
    );
    const challenge = security.issueChallenge(
      "request",
      "key-id",
      `AppAttest ${credentials.token}`,
    );
    const request = authenticatedRequest(
      "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT",
      challenge.id,
      credentials.token,
    );

    await security.authorizeRequest(request, new Uint8Array());

    expect(cryptography.assertionInput?.payload).toBe(
      canonicalRequestPayload(request, new Uint8Array(), challenge.challenge),
    );
    expect(devices.get("key-id")?.signCount).toBe(1);
    await expect(
      security.authorizeRequest(request, new Uint8Array()),
    ).rejects.toThrow("invalid_challenge");
  });

  test("rejects a non-monotonic assertion counter", async () => {
    const devices = new MemoryDeviceStore();
    const cryptography = new FakeCryptography();
    cryptography.nextSignCount = 0;
    const security = new AppAttestSecurity(
      appAttestConfig(),
      devices,
      cryptography,
    );
    const registration = security.issueChallenge(
      "attestation",
      undefined,
      null,
    );
    const credentials = await security.register(
      registration.id,
      "key-id",
      Buffer.from("attestation").toString("base64"),
    );
    const challenge = security.issueChallenge(
      "request",
      "key-id",
      `AppAttest ${credentials.token}`,
    );

    await expect(
      security.authorizeRequest(
        authenticatedRequest(
          "https://example.test/v1/catalog/search",
          challenge.id,
          credentials.token,
        ),
        new Uint8Array(),
      ),
    ).rejects.toThrow("replayed_assertion");
  });
});

describe("bounded replay and quota state", () => {
  test("a challenge is one-time and expires", () => {
    let now = 1_000;
    const challenges = new ChallengeStore(100, 10, () => now);
    const issued = challenges.issue("attestation");

    expect(challenges.consume(issued.id, "attestation").challenge).toBe(
      issued.challenge,
    );
    expect(() => challenges.consume(issued.id, "attestation")).toThrow(
      "invalid_challenge",
    );

    const expiring = challenges.issue("attestation");
    now = 1_101;
    expect(() => challenges.consume(expiring.id, "attestation")).toThrow(
      "invalid_challenge",
    );
  });

  test("rate limits reset after the bounded window", () => {
    let now = 5_000;
    const limiter = new BoundedRateLimiter(10, () => now);
    expect(limiter.consume("device", 1, 1_000).allowed).toBe(true);
    expect(limiter.consume("device", 1, 1_000).allowed).toBe(false);
    now = 6_001;
    expect(limiter.consume("device", 1, 1_000).allowed).toBe(true);
  });
});

class FakeCryptography implements AppAttestCryptography {
  attestationInput?: Parameters<AppAttestCryptography["verifyAttestation"]>[0];
  assertionInput?: Parameters<AppAttestCryptography["verifyAssertion"]>[0];
  nextSignCount = 1;

  verifyAttestation(
    input: Parameters<AppAttestCryptography["verifyAttestation"]>[0],
  ) {
    this.attestationInput = input;
    return {
      publicKey: "verified-public-key",
      receipt: new Uint8Array([1, 2, 3]),
      environment: "production",
    };
  }

  verifyAssertion(
    input: Parameters<AppAttestCryptography["verifyAssertion"]>[0],
  ) {
    this.assertionInput = input;
    return { signCount: this.nextSignCount };
  }
}

function authenticatedRequest(
  url: string,
  challengeID: string,
  token: string,
): Request {
  return new Request(url, {
    headers: {
      [AppAttestHeaders.assertion]: Buffer.from("assertion").toString("base64"),
      [AppAttestHeaders.challengeID]: challengeID,
      [AppAttestHeaders.keyID]: "key-id",
      [AppAttestHeaders.token]: `AppAttest ${token}`,
    },
  });
}

function appAttestConfig(): ServerConfig["appAttest"] {
  return {
    mode: "production",
    teamID: "C76R5DRH64",
    bundleID: "dev.shipshit.opentvtracker",
    tokenSecret: "test-token-secret-that-is-at-least-thirty-two-characters",
    statePath: "unused",
    challengeTTLSeconds: 60,
    tokenTTLSeconds: 600,
  };
}
