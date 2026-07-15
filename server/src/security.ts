import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
import { mkdir, rename } from "node:fs/promises";
import { isIP } from "node:net";
import { dirname } from "node:path";
import { verifyAssertion, verifyAttestation } from "node-app-attest";
import type { AppAttestMode, ServerConfig } from "./config";

export const AppAttestHeaders = {
  assertion: "x-app-attest-assertion",
  challengeID: "x-app-attest-challenge-id",
  keyID: "x-app-attest-key-id",
  token: "authorization",
  developmentBypass: "x-opentv-development-token",
} as const;

export type ChallengePurpose = "attestation" | "token" | "request";

export type Challenge = {
  id: string;
  challenge: string;
  expiresAt: string;
};

type StoredChallenge = Challenge & {
  purpose: ChallengePurpose;
  keyID?: string;
  expiresAtMilliseconds: number;
};

export class ChallengeStore {
  private readonly challenges = new Map<string, StoredChallenge>();

  constructor(
    private readonly ttlMilliseconds: number,
    private readonly maximumEntries = 5_000,
    private readonly now: () => number = Date.now,
  ) {}

  issue(purpose: ChallengePurpose, keyID?: string): Challenge {
    this.prune();
    if (this.challenges.size >= this.maximumEntries) {
      const oldest = this.challenges.keys().next().value as string | undefined;
      if (oldest) this.challenges.delete(oldest);
    }
    const expiresAtMilliseconds = this.now() + this.ttlMilliseconds;
    const challenge: StoredChallenge = {
      id: base64URL(randomBytes(18)),
      challenge: base64URL(randomBytes(32)),
      expiresAt: new Date(expiresAtMilliseconds).toISOString(),
      expiresAtMilliseconds,
      purpose,
      keyID,
    };
    this.challenges.set(challenge.id, challenge);
    return {
      id: challenge.id,
      challenge: challenge.challenge,
      expiresAt: challenge.expiresAt,
    };
  }

  consume(
    id: string,
    purpose: ChallengePurpose,
    keyID?: string,
  ): StoredChallenge {
    this.prune();
    const challenge = this.challenges.get(id);
    this.challenges.delete(id);
    if (
      !challenge ||
      challenge.purpose !== purpose ||
      challenge.keyID !== keyID
    ) {
      throw new SecurityError("invalid_challenge");
    }
    if (challenge.expiresAtMilliseconds <= this.now())
      throw new SecurityError("expired_challenge");
    return challenge;
  }

  private prune(): void {
    const now = this.now();
    for (const [id, challenge] of this.challenges) {
      if (challenge.expiresAtMilliseconds <= now) this.challenges.delete(id);
    }
  }
}

export type VerifiedDevice = {
  keyID: string;
  publicKey: string;
  signCount: number;
  environment: string;
  receipt: string;
  registeredAt: string;
  lastSeenAt: string;
};

export interface DeviceStore {
  get(keyID: string): VerifiedDevice | undefined;
  register(device: VerifiedDevice): Promise<void>;
  updateCounter(keyID: string, previous: number, next: number): Promise<void>;
}

export class MemoryDeviceStore implements DeviceStore {
  protected readonly devices = new Map<string, VerifiedDevice>();

  get(keyID: string): VerifiedDevice | undefined {
    const device = this.devices.get(keyID);
    return device ? { ...device } : undefined;
  }

  async register(device: VerifiedDevice): Promise<void> {
    const existing = this.devices.get(device.keyID);
    if (existing && existing.publicKey !== device.publicKey)
      throw new SecurityError("duplicate_key");
    this.devices.set(device.keyID, { ...device });
    await this.persist();
  }

  async updateCounter(
    keyID: string,
    previous: number,
    next: number,
  ): Promise<void> {
    const device = this.devices.get(keyID);
    if (!device || device.signCount !== previous || next <= previous)
      throw new SecurityError("replayed_assertion");
    device.signCount = next;
    device.lastSeenAt = new Date().toISOString();
    await this.persist();
  }

  protected async persist(): Promise<void> {}
}

export class FileDeviceStore extends MemoryDeviceStore {
  private constructor(private readonly path: string) {
    super();
  }

  static async open(path: string): Promise<FileDeviceStore> {
    const store = new FileDeviceStore(path);
    const file = Bun.file(path);
    if (await file.exists()) {
      const parsed = (await file.json()) as {
        version?: unknown;
        devices?: unknown;
      };
      if (parsed.version !== 1 || !Array.isArray(parsed.devices))
        throw new Error("Invalid App Attest state file");
      for (const value of parsed.devices) {
        const device = parseStoredDevice(value);
        store.devices.set(device.keyID, device);
      }
    }
    return store;
  }

  protected override async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const temporaryPath = `${this.path}.${process.pid}.${base64URL(randomBytes(8))}.tmp`;
    await Bun.write(
      temporaryPath,
      `${JSON.stringify({ version: 1, devices: [...this.devices.values()] })}\n`,
    );
    await rename(temporaryPath, this.path);
  }
}

export interface AppAttestCryptography {
  verifyAttestation(input: {
    attestation: Uint8Array;
    challenge: string;
    keyID: string;
    teamID: string;
    bundleID: string;
    allowDevelopmentEnvironment: boolean;
  }): { publicKey: string; receipt: Uint8Array; environment: string };
  verifyAssertion(input: {
    assertion: Uint8Array;
    payload: string;
    publicKey: string;
    teamID: string;
    bundleID: string;
    signCount: number;
  }): { signCount: number };
}

export class NodeAppAttestCryptography implements AppAttestCryptography {
  verifyAttestation(
    input: Parameters<AppAttestCryptography["verifyAttestation"]>[0],
  ) {
    const result = verifyAttestation({
      attestation: Buffer.from(input.attestation),
      challenge: input.challenge,
      keyId: input.keyID,
      bundleIdentifier: input.bundleID,
      teamIdentifier: input.teamID,
      allowDevelopmentEnvironment: input.allowDevelopmentEnvironment,
    }) as { publicKey: string; receipt: Uint8Array; environment: string };
    return result;
  }

  verifyAssertion(
    input: Parameters<AppAttestCryptography["verifyAssertion"]>[0],
  ) {
    return verifyAssertion({
      assertion: Buffer.from(input.assertion),
      payload: input.payload,
      publicKey: input.publicKey,
      bundleIdentifier: input.bundleID,
      teamIdentifier: input.teamID,
      signCount: input.signCount,
    }) as { signCount: number };
  }
}

export class DeviceTokenService {
  constructor(
    private readonly secret: string,
    private readonly ttlMilliseconds: number,
    private readonly now: () => number = Date.now,
  ) {}

  issue(keyID: string): { token: string; expiresAt: string } {
    const expiresAtMilliseconds = this.now() + this.ttlMilliseconds;
    const payload = base64URL(
      Buffer.from(JSON.stringify({ v: 1, k: keyID, e: expiresAtMilliseconds })),
    );
    return {
      token: `${payload}.${this.signature(payload)}`,
      expiresAt: new Date(expiresAtMilliseconds).toISOString(),
    };
  }

  verify(value: string | null): string {
    const token = value?.startsWith("AppAttest ")
      ? value.slice("AppAttest ".length)
      : "";
    const [payload, providedSignature, extra] = token.split(".");
    if (!payload || !providedSignature || extra)
      throw new SecurityError("invalid_token");
    const expected = Buffer.from(this.signature(payload));
    const provided = Buffer.from(providedSignature);
    if (
      expected.length !== provided.length ||
      !timingSafeEqual(expected, provided)
    ) {
      throw new SecurityError("invalid_token");
    }
    const parsed = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Record<string, unknown>;
    if (
      parsed.v !== 1 ||
      typeof parsed.k !== "string" ||
      typeof parsed.e !== "number" ||
      parsed.e <= this.now()
    ) {
      throw new SecurityError("expired_token");
    }
    return parsed.k;
  }

  private signature(payload: string): string {
    return createHmac("sha256", this.secret)
      .update(payload)
      .digest("base64url");
  }
}

export class AppAttestSecurity {
  readonly challenges: ChallengeStore;
  readonly tokens: DeviceTokenService;

  constructor(
    private readonly config: ServerConfig["appAttest"],
    private readonly devices: DeviceStore,
    private readonly cryptography: AppAttestCryptography = new NodeAppAttestCryptography(),
  ) {
    this.challenges = new ChallengeStore(config.challengeTTLSeconds * 1_000);
    this.tokens = new DeviceTokenService(
      config.tokenSecret,
      config.tokenTTLSeconds * 1_000,
    );
  }

  issueChallenge(
    purpose: ChallengePurpose,
    keyID: string | undefined,
    authorization: string | null,
  ): Challenge {
    if (purpose === "attestation") {
      if (keyID) throw new SecurityError("invalid_challenge_request");
      return this.challenges.issue(purpose);
    }
    if (!keyID || !this.devices.get(keyID))
      throw new SecurityError("unknown_key");
    if (purpose === "request" && this.tokens.verify(authorization) !== keyID) {
      throw new SecurityError("invalid_token");
    }
    return this.challenges.issue(purpose, keyID);
  }

  async register(
    challengeID: string,
    keyID: string,
    attestation: string,
  ): Promise<{ token: string; expiresAt: string }> {
    const challenge = this.challenges.consume(challengeID, "attestation");
    let result: ReturnType<AppAttestCryptography["verifyAttestation"]>;
    try {
      result = this.cryptography.verifyAttestation({
        attestation: strictBase64(attestation, 24_000),
        challenge: challenge.challenge,
        keyID,
        teamID: this.config.teamID,
        bundleID: this.config.bundleID,
        allowDevelopmentEnvironment: this.config.mode !== "production",
      });
    } catch {
      throw new SecurityError("invalid_attestation");
    }
    const now = new Date().toISOString();
    await this.devices.register({
      keyID,
      publicKey: result.publicKey,
      signCount: 0,
      environment: result.environment,
      receipt: Buffer.from(result.receipt).toString("base64"),
      registeredAt: now,
      lastSeenAt: now,
    });
    return this.tokens.issue(keyID);
  }

  async refreshToken(
    request: Request,
    body: Uint8Array,
  ): Promise<{ token: string; expiresAt: string }> {
    const keyID = requiredHeader(request, AppAttestHeaders.keyID);
    const device = this.devices.get(keyID);
    if (!device) throw new SecurityError("unknown_key");
    const challengeID = requiredHeader(request, AppAttestHeaders.challengeID);
    const challenge = this.challenges.consume(challengeID, "token", keyID);
    await this.verifyDeviceAssertion(request, body, challenge, device);
    return this.tokens.issue(keyID);
  }

  async authorizeRequest(
    request: Request,
    body: Uint8Array,
  ): Promise<{ deviceID: string; trust: "attested" | "development" }> {
    if (
      this.config.mode !== "production" &&
      safeEqual(
        request.headers.get(AppAttestHeaders.developmentBypass),
        this.config.developmentBypassToken,
      )
    ) {
      return { deviceID: "development-bypass", trust: "development" };
    }

    const keyID = requiredHeader(request, AppAttestHeaders.keyID);
    if (
      this.tokens.verify(request.headers.get(AppAttestHeaders.token)) !== keyID
    ) {
      throw new SecurityError("invalid_token");
    }
    const device = this.devices.get(keyID);
    if (!device) throw new SecurityError("unknown_key");
    const challengeID = requiredHeader(request, AppAttestHeaders.challengeID);
    const challenge = this.challenges.consume(challengeID, "request", keyID);
    await this.verifyDeviceAssertion(request, body, challenge, device);
    return { deviceID: hashIdentifier(keyID), trust: "attested" };
  }

  private async verifyDeviceAssertion(
    request: Request,
    body: Uint8Array,
    challenge: StoredChallenge,
    device: VerifiedDevice,
  ): Promise<void> {
    let result: ReturnType<AppAttestCryptography["verifyAssertion"]>;
    try {
      result = this.cryptography.verifyAssertion({
        assertion: strictBase64(
          requiredHeader(request, AppAttestHeaders.assertion),
          8_000,
        ),
        payload: canonicalRequestPayload(request, body, challenge.challenge),
        publicKey: device.publicKey,
        teamID: this.config.teamID,
        bundleID: this.config.bundleID,
        signCount: device.signCount,
      });
    } catch {
      throw new SecurityError("invalid_assertion");
    }
    await this.devices.updateCounter(
      device.keyID,
      device.signCount,
      result.signCount,
    );
  }
}

export function canonicalRequestPayload(
  request: Request,
  body: Uint8Array,
  challenge: string,
): string {
  const url = new URL(request.url);
  const target = `${url.pathname}${url.search}`;
  const bodyDigest = createHash("sha256").update(body).digest("base64url");
  return [
    "opentv-app-attest-v1",
    challenge,
    request.method.toUpperCase(),
    target,
    bodyDigest,
  ].join("\n");
}

type RateLimitEntry = { count: number; resetAt: number };

export class BoundedRateLimiter {
  private readonly entries = new Map<string, RateLimitEntry>();

  constructor(
    private readonly maximumEntries = 20_000,
    private readonly now: () => number = Date.now,
  ) {}

  consume(
    key: string,
    limit: number,
    windowMilliseconds: number,
  ): { allowed: boolean; retryAfterSeconds: number } {
    this.prune();
    const now = this.now();
    let entry = this.entries.get(key);
    if (!entry || entry.resetAt <= now) {
      if (this.entries.size >= this.maximumEntries) {
        const oldest = this.entries.keys().next().value as string | undefined;
        if (oldest) this.entries.delete(oldest);
      }
      entry = { count: 0, resetAt: now + windowMilliseconds };
      this.entries.set(key, entry);
    }
    entry.count += 1;
    return {
      allowed: entry.count <= limit,
      retryAfterSeconds: Math.max(1, Math.ceil((entry.resetAt - now) / 1_000)),
    };
  }

  private prune(): void {
    const now = this.now();
    for (const [key, entry] of this.entries)
      if (entry.resetAt <= now) this.entries.delete(key);
  }
}

export class SecurityError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export function clientIPAddress(
  request: Request,
  peerAddress: string,
  trustedHeader?: string,
): string {
  const forwardedAddress = trustedHeader
    ? request.headers.get(trustedHeader)?.split(",", 1)[0]?.trim()
    : undefined;
  return forwardedAddress && isIP(forwardedAddress)
    ? forwardedAddress
    : peerAddress;
}

export function isDevelopmentMode(mode: AppAttestMode): boolean {
  return mode !== "production";
}

function strictBase64(value: string, maximumBytes: number): Uint8Array {
  if (
    !/^[A-Za-z0-9+/]+={0,2}$/.test(value) ||
    value.length > Math.ceil((maximumBytes * 4) / 3) + 4
  ) {
    throw new SecurityError("invalid_base64");
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.byteLength === 0 || decoded.byteLength > maximumBytes)
    throw new SecurityError("invalid_base64");
  return decoded;
}

function requiredHeader(request: Request, name: string): string {
  const value = request.headers.get(name)?.trim();
  if (!value || value.length > 12_000)
    throw new SecurityError("missing_authentication");
  return value;
}

function hashIdentifier(value: string): string {
  return createHash("sha256").update(value).digest("base64url").slice(0, 24);
}

function safeEqual(left: string | null, right: string | undefined): boolean {
  if (!left || !right) return false;
  const leftBytes = Buffer.from(left);
  const rightBytes = Buffer.from(right);
  return (
    leftBytes.length === rightBytes.length &&
    timingSafeEqual(leftBytes, rightBytes)
  );
}

function base64URL(value: Uint8Array): string {
  return Buffer.from(value).toString("base64url");
}

function parseStoredDevice(value: unknown): VerifiedDevice {
  const record =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const requiredStrings = [
    "keyID",
    "publicKey",
    "environment",
    "receipt",
    "registeredAt",
    "lastSeenAt",
  ] as const;
  if (
    requiredStrings.some((key) => typeof record[key] !== "string") ||
    !Number.isSafeInteger(record.signCount) ||
    Number(record.signCount) < 0
  ) {
    throw new Error("Invalid device record in App Attest state file");
  }
  return {
    keyID: record.keyID as string,
    publicKey: record.publicKey as string,
    signCount: record.signCount as number,
    environment: record.environment as string,
    receipt: record.receipt as string,
    registeredAt: record.registeredAt as string,
    lastSeenAt: record.lastSeenAt as string,
  };
}
