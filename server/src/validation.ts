import type { MediaKind } from "./tmdb";
import type { ChallengePurpose } from "./security";

export class ValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export async function readJSONBody(
  request: Request,
  maximumBytes: number,
): Promise<{
  value: Record<string, unknown>;
  bytes: Uint8Array;
}> {
  const contentType = request.headers
    .get("content-type")
    ?.split(";", 1)[0]
    ?.trim()
    .toLowerCase();
  if (contentType !== "application/json")
    throw new ValidationError("invalid_content_type");
  const declaredLengthHeader = request.headers.get("content-length");
  if (declaredLengthHeader !== null) {
    if (!/^\d+$/.test(declaredLengthHeader))
      throw new ValidationError("invalid_content_length");
    const declaredLength = Number(declaredLengthHeader);
    if (!Number.isSafeInteger(declaredLength) || declaredLength > maximumBytes)
      throw new ValidationError("body_too_large");
  }
  const bytes = await readBoundedBody(request, maximumBytes);
  if (bytes.byteLength === 0 || bytes.byteLength > maximumBytes)
    throw new ValidationError("body_too_large");
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new ValidationError("invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new ValidationError("invalid_json");
  return { value: value as Record<string, unknown>, bytes };
}

async function readBoundedBody(
  request: Request,
  maximumBytes: number,
): Promise<Uint8Array> {
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) throw new ValidationError("body_too_large");
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export function validateChallengeRequest(value: Record<string, unknown>): {
  purpose: ChallengePurpose;
  keyID?: string;
} {
  exactKeys(value, ["purpose", "keyID"]);
  const purpose = value.purpose;
  if (
    purpose !== "attestation" &&
    purpose !== "token" &&
    purpose !== "request"
  ) {
    throw new ValidationError("invalid_purpose");
  }
  const keyID = optionalString(value.keyID, 256);
  if (keyID && !/^[A-Za-z0-9_\-+/=]+$/.test(keyID))
    throw new ValidationError("invalid_key_id");
  return { purpose, keyID };
}

export function validateRegistrationRequest(value: Record<string, unknown>): {
  challengeID: string;
  keyID: string;
  attestation: string;
} {
  exactKeys(value, ["challengeID", "keyID", "attestation"]);
  return {
    challengeID: requiredToken(value.challengeID, 128, "invalid_challenge_id"),
    keyID: requiredToken(value.keyID, 256, "invalid_key_id"),
    attestation: requiredString(
      value.attestation,
      36_000,
      "invalid_attestation",
    ),
  };
}

export function validateEmptyObject(value: Record<string, unknown>): void {
  exactKeys(value, []);
}

export function validateCatalogSearch(url: URL): {
  query: string;
  kind: MediaKind | null;
  page: number;
  region: string;
} {
  exactQueryKeys(url, ["q", "kind", "page", "region"]);
  const query = (url.searchParams.get("q") ?? "").trim();
  if (query.length > 100 || /[\u0000-\u001F\u007F]/.test(query))
    throw new ValidationError("invalid_query");
  const kindValue = url.searchParams.get("kind");
  if (kindValue !== null && kindValue !== "movie" && kindValue !== "series") {
    throw new ValidationError("invalid_kind");
  }
  const page = strictInteger(
    url.searchParams.get("page") ?? "1",
    1,
    20,
    "invalid_page",
  );
  const region = (url.searchParams.get("region") ?? "MT").toUpperCase();
  if (!/^[A-Z]{2}$/.test(region)) throw new ValidationError("invalid_region");
  return { query, kind: kindValue as MediaKind | null, page, region };
}

export function validateCatalogTitle(
  match: RegExpMatchArray,
  url: URL,
): {
  kind: MediaKind;
  id: number;
  region: string;
} {
  exactQueryKeys(url, ["region"]);
  const kind = match[1];
  if (kind !== "movie" && kind !== "series")
    throw new ValidationError("invalid_kind");
  const id = strictInteger(
    match[2] ?? "",
    1,
    2_147_483_647,
    "invalid_catalog_id",
  );
  const region = (url.searchParams.get("region") ?? "MT").toUpperCase();
  if (!/^[A-Z]{2}$/.test(region)) throw new ValidationError("invalid_region");
  return { kind, id, region };
}

export function validateCatalogReviews(
  match: RegExpMatchArray,
  url: URL,
): {
  kind: MediaKind;
  id: number;
  page: number;
} {
  exactQueryKeys(url, ["page"]);
  const kind = match[1];
  if (kind !== "movie" && kind !== "series")
    throw new ValidationError("invalid_kind");
  const id = strictInteger(
    match[2] ?? "",
    1,
    2_147_483_647,
    "invalid_catalog_id",
  );
  const page = strictInteger(
    url.searchParams.get("page") ?? "1",
    1,
    100,
    "invalid_page",
  );
  return { kind, id, page };
}

export function validateCatalogExternalID(
  match: RegExpMatchArray,
  url: URL,
): {
  source: "tvdb";
  id: number;
  kind: MediaKind;
  region: string;
} {
  exactQueryKeys(url, ["kind", "region"]);
  const source = match[1];
  if (source !== "tvdb") throw new ValidationError("invalid_catalog_source");
  const id = strictInteger(
    match[2] ?? "",
    1,
    2_147_483_647,
    "invalid_external_id",
  );
  const kind = url.searchParams.get("kind");
  if (kind !== "movie" && kind !== "series")
    throw new ValidationError("invalid_kind");
  const region = (url.searchParams.get("region") ?? "MT").toUpperCase();
  if (!/^[A-Z]{2}$/.test(region)) throw new ValidationError("invalid_region");
  return { source, id, kind, region };
}

export function validateCinemaShowings(
  url: URL,
  now: Date = new Date(),
): { country: "MT"; day: string } {
  exactQueryKeys(url, ["country", "date"]);
  const country = (url.searchParams.get("country") ?? "MT").toUpperCase();
  if (country !== "MT") throw new ValidationError("unsupported_country");
  const day = url.searchParams.get("date") ?? now.toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day))
    throw new ValidationError("invalid_date");
  const parsed = new Date(`${day}T00:00:00Z`);
  if (
    Number.isNaN(parsed.valueOf()) ||
    parsed.toISOString().slice(0, 10) !== day
  ) {
    throw new ValidationError("invalid_date");
  }
  const today = new Date(`${now.toISOString().slice(0, 10)}T00:00:00Z`);
  const difference = Math.round(
    (parsed.valueOf() - today.valueOf()) / 86_400_000,
  );
  if (difference < -1 || difference > 14)
    throw new ValidationError("date_out_of_range");
  return { country: "MT", day };
}

function exactKeys(value: Record<string, unknown>, allowed: string[]): void {
  if (Object.keys(value).some((key) => !allowed.includes(key)))
    throw new ValidationError("unknown_field");
}

function exactQueryKeys(url: URL, allowed: string[]): void {
  const seen = new Set<string>();
  for (const key of url.searchParams.keys()) {
    if (!allowed.includes(key))
      throw new ValidationError("unknown_query_parameter");
    if (seen.has(key)) throw new ValidationError("duplicate_query_parameter");
    seen.add(key);
  }
}

function requiredToken(value: unknown, maximum: number, code: string): string {
  const result = requiredString(value, maximum, code);
  if (!/^[A-Za-z0-9_\-+/=.]+$/.test(result)) throw new ValidationError(code);
  return result;
}

function requiredString(value: unknown, maximum: number, code: string): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum)
    throw new ValidationError(code);
  return value;
}

function optionalString(value: unknown, maximum: number): string | undefined {
  if (value === undefined) return undefined;
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maximum
  ) {
    throw new ValidationError("invalid_string");
  }
  return value;
}

function strictInteger(
  value: string,
  minimum: number,
  maximum: number,
  code: string,
): number {
  if (!/^\d+$/.test(value)) throw new ValidationError(code);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum)
    throw new ValidationError(code);
  return parsed;
}
