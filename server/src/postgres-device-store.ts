import { SQL } from "bun";
import {
  SecurityError,
  type DeviceStore,
  type VerifiedDevice,
} from "./security";

type DeviceRow = {
  key_id: string;
  public_key: string;
  sign_count: number | bigint;
  environment: string;
  receipt: string;
  registered_at: Date | string;
  last_seen_at: Date | string;
};

const maximumVerifiedDevices = 100_000;
const registrationLock = 1_335_129_167;

export class PostgresDeviceStore implements DeviceStore {
  private constructor(private readonly sql: SQL) {}

  static async open(databaseURL: string): Promise<PostgresDeviceStore> {
    const sql = new SQL(databaseURL);
    await sql`
      CREATE TABLE IF NOT EXISTS app_attest_devices (
        key_id text PRIMARY KEY,
        public_key text NOT NULL,
        sign_count bigint NOT NULL CHECK (sign_count >= 0),
        environment text NOT NULL,
        receipt text NOT NULL,
        registered_at timestamptz NOT NULL,
        last_seen_at timestamptz NOT NULL
      )
    `;
    return new PostgresDeviceStore(sql);
  }

  async get(keyID: string): Promise<VerifiedDevice | undefined> {
    const rows = (await this.sql`
      SELECT
        key_id,
        public_key,
        sign_count,
        environment,
        receipt,
        registered_at,
        last_seen_at
      FROM app_attest_devices
      WHERE key_id = ${keyID}
    `) as DeviceRow[];
    return rows[0] ? deviceFromRow(rows[0]) : undefined;
  }

  async register(device: VerifiedDevice): Promise<void> {
    await this.sql.begin(async (transaction) => {
      await transaction`SELECT pg_advisory_xact_lock(${registrationLock})`;
      const existing = (await transaction`
        SELECT public_key
        FROM app_attest_devices
        WHERE key_id = ${device.keyID}
        FOR UPDATE
      `) as { public_key: string }[];

      if (existing[0]) {
        if (existing[0].public_key !== device.publicKey)
          throw new SecurityError("duplicate_key");
        return;
      }

      const counts = (await transaction`
        SELECT count(*)::integer AS count
        FROM app_attest_devices
      `) as { count: number }[];
      if ((counts[0]?.count ?? 0) >= maximumVerifiedDevices)
        throw new SecurityError("device_capacity_reached");

      await transaction`
        INSERT INTO app_attest_devices (
          key_id,
          public_key,
          sign_count,
          environment,
          receipt,
          registered_at,
          last_seen_at
        )
        VALUES (
          ${device.keyID},
          ${device.publicKey},
          ${device.signCount},
          ${device.environment},
          ${device.receipt},
          ${device.registeredAt},
          ${device.lastSeenAt}
        )
      `;
    });
  }

  async updateCounter(
    keyID: string,
    previous: number,
    next: number,
  ): Promise<void> {
    const updated = (await this.sql`
      UPDATE app_attest_devices
      SET
        sign_count = ${next},
        last_seen_at = now()
      WHERE
        key_id = ${keyID}
        AND sign_count = ${previous}
        AND ${next} > sign_count
      RETURNING key_id
    `) as { key_id: string }[];
    if (!updated[0]) throw new SecurityError("replayed_assertion");
  }
}

function deviceFromRow(row: DeviceRow): VerifiedDevice {
  const signCount = Number(row.sign_count);
  if (!Number.isSafeInteger(signCount) || signCount < 0)
    throw new Error("Invalid App Attest counter in PostgreSQL");
  return {
    keyID: row.key_id,
    publicKey: row.public_key,
    signCount,
    environment: row.environment,
    receipt: row.receipt,
    registeredAt: new Date(row.registered_at).toISOString(),
    lastSeenAt: new Date(row.last_seen_at).toISOString(),
  };
}
