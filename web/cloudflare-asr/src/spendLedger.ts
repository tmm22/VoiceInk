import { DurableObject } from "cloudflare:workers";
import { RESERVATION_EXPIRY_MS, utcDay } from "./budget.ts";

export type ReserveRequest = {
  estimateMicros: number;
  secondsEstimate: number;
  clientKey: string;
  spendLimitMicros: number;
  clientSecondsLimit: number;
};

export type ReserveResult =
  | { ok: true; id: string }
  | { ok: false; reason: "budget" | "client" };

// daily_spend holds no client data and keeps a month of cost telemetry;
// client_usage rows are pseudonymous per-day quota counters that are useless
// after the day ends, so they are dropped almost immediately (one extra day
// covers midnight skew between the Worker's clock and this object's).
const LEDGER_RETENTION_DAYS = 35;
const CLIENT_USAGE_RETENTION_DAYS = 2;
const PURGE_ALARM_INTERVAL_MS = 6 * 60 * 60 * 1_000;

// Single global instance (idFromName("global")). All methods do their reads and
// writes with synchronous sql.exec calls and no awaits in between, so the
// object's input gates make every reservation decision linearizable: concurrent
// requests cannot overshoot the ceiling.
export class SpendLedger extends DurableObject {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS daily_spend (
      day TEXT PRIMARY KEY,
      committed_micros INTEGER NOT NULL DEFAULT 0,
      reserved_micros INTEGER NOT NULL DEFAULT 0
    )`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS reservations (
      id TEXT PRIMARY KEY,
      day TEXT NOT NULL,
      amount_micros INTEGER NOT NULL,
      client_key TEXT NOT NULL,
      seconds_estimate INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    )`);
    this.sql.exec("CREATE INDEX IF NOT EXISTS idx_reservations_expiry ON reservations(expires_at)");
    this.sql.exec(`CREATE TABLE IF NOT EXISTS client_usage (
      day TEXT NOT NULL,
      client_key TEXT NOT NULL,
      seconds INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (day, client_key)
    )`);
    // The purge must not depend on inbound traffic: an idle ledger would
    // otherwise hold expired rows indefinitely. The alarm re-arms itself.
    ctx.blockConcurrencyWhile(async () => {
      if (await ctx.storage.getAlarm() === null) {
        await ctx.storage.setAlarm(Date.now() + PURGE_ALARM_INTERVAL_MS);
      }
    });
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    this.expireStaleReservations(now);
    this.deleteExpiredHistory(now);
    await this.ctx.storage.setAlarm(now + PURGE_ALARM_INTERVAL_MS);
  }

  reserve(request: ReserveRequest): ReserveResult {
    const now = Date.now();
    const day = utcDay(now);
    this.expireStaleReservations(now);
    this.deleteExpiredHistory(now);

    const totals = this.sql
      .exec<{ committed_micros: number; reserved_micros: number }>(
        "SELECT committed_micros, reserved_micros FROM daily_spend WHERE day = ?", day)
      .toArray()[0] ?? { committed_micros: 0, reserved_micros: 0 };
    if (totals.committed_micros + totals.reserved_micros + request.estimateMicros > request.spendLimitMicros) {
      return { ok: false, reason: "budget" };
    }

    // Worst-case byte pricing overestimates audio seconds by an order of
    // magnitude for real recordings, so a single request's seconds estimate is
    // clamped to the full daily client quota: one request may claim at most a
    // whole day's audio allowance and settles to the actual duration. Without
    // the clamp, the seconds axis would deny any upload larger than
    // clientSecondsLimit x WORST_CASE_BYTES_PER_SECOND bytes (~3.4 MB) outright.
    // The money axis stays unclamped, so spend is still reserved at true worst case.
    const secondsEstimate = Math.min(request.secondsEstimate, request.clientSecondsLimit);
    if (secondsEstimate > 0) {
      const used = this.sql
        .exec<{ seconds: number }>("SELECT seconds FROM client_usage WHERE day = ? AND client_key = ?", day, request.clientKey)
        .toArray()[0]?.seconds ?? 0;
      const pending = this.sql
        .exec<{ total: number | null }>("SELECT SUM(seconds_estimate) AS total FROM reservations WHERE client_key = ? AND day = ?", request.clientKey, day)
        .toArray()[0]?.total ?? 0;
      if (used + pending + secondsEstimate > request.clientSecondsLimit) {
        return { ok: false, reason: "client" };
      }
    }

    const id = crypto.randomUUID();
    this.sql.exec(
      "INSERT INTO reservations (id, day, amount_micros, client_key, seconds_estimate, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
      id, day, request.estimateMicros, request.clientKey, secondsEstimate, now + RESERVATION_EXPIRY_MS);
    this.sql.exec(
      `INSERT INTO daily_spend (day, committed_micros, reserved_micros) VALUES (?, 0, ?)
       ON CONFLICT(day) DO UPDATE SET reserved_micros = reserved_micros + excluded.reserved_micros`,
      day, request.estimateMicros);
    return { ok: true, id };
  }

  // Deleting the reservation row on settle makes commit and release idempotent:
  // a retried call finds no row and does nothing. Committed spend is clamped to
  // the reserved amount so a request can never settle for more than admission
  // priced, keeping the daily ceiling a true upper bound.
  commit(id: string, actualMicros: number, actualSeconds: number): void {
    const reservation = this.takeReservation(id);
    if (!reservation) return;
    const chargedMicros = Math.min(reservation.amount_micros, Math.max(0, Math.round(actualMicros)));
    const chargedSeconds = Math.min(reservation.seconds_estimate, Math.max(0, Math.round(actualSeconds)));
    this.sql.exec(
      `UPDATE daily_spend SET
         reserved_micros = MAX(0, reserved_micros - ?),
         committed_micros = committed_micros + ?
       WHERE day = ?`,
      reservation.amount_micros, chargedMicros, reservation.day);
    if (chargedSeconds > 0) {
      this.sql.exec(
        `INSERT INTO client_usage (day, client_key, seconds) VALUES (?, ?, ?)
         ON CONFLICT(day, client_key) DO UPDATE SET seconds = seconds + excluded.seconds`,
        reservation.day, reservation.client_key, chargedSeconds);
    }
  }

  release(id: string): void {
    const reservation = this.takeReservation(id);
    if (!reservation) return;
    this.sql.exec(
      "UPDATE daily_spend SET reserved_micros = MAX(0, reserved_micros - ?) WHERE day = ?",
      reservation.amount_micros, reservation.day);
  }

  private takeReservation(id: string) {
    const reservation = this.sql
      .exec<{ day: string; amount_micros: number; client_key: string; seconds_estimate: number }>(
        "SELECT day, amount_micros, client_key, seconds_estimate FROM reservations WHERE id = ?", id)
      .toArray()[0];
    if (reservation) this.sql.exec("DELETE FROM reservations WHERE id = ?", id);
    return reservation;
  }

  // A crash between reserve and commit must not consume headroom for the rest
  // of the day; expiry returns it. Until then spend is over-counted, never under.
  private expireStaleReservations(now: number) {
    const stale = this.sql
      .exec<{ id: string; day: string; amount_micros: number }>(
        "SELECT id, day, amount_micros FROM reservations WHERE expires_at < ?", now)
      .toArray();
    for (const reservation of stale) {
      this.sql.exec(
        "UPDATE daily_spend SET reserved_micros = MAX(0, reserved_micros - ?) WHERE day = ?",
        reservation.amount_micros, reservation.day);
      this.sql.exec("DELETE FROM reservations WHERE id = ?", reservation.id);
    }
  }

  private deleteExpiredHistory(now: number) {
    const dayMs = 24 * 60 * 60 * 1_000;
    this.sql.exec("DELETE FROM daily_spend WHERE day < ?", utcDay(now - LEDGER_RETENTION_DAYS * dayMs));
    this.sql.exec("DELETE FROM client_usage WHERE day < ?", utcDay(now - CLIENT_USAGE_RETENTION_DAYS * dayMs));
  }
}
