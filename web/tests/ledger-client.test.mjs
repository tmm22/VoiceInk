import assert from "node:assert/strict";
import test from "node:test";
import { commitSpend, reserveSpend, withTimeout } from "../cloudflare-asr/src/ledgerClient.ts";

function ledgerEnv(stub) {
  return { SPEND_LEDGER: { idFromName: (name) => name, get: () => stub } };
}

test("a settled ledger call leaves no pending timer behind", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const cleared = [];
  const realClear = globalThis.clearTimeout;
  globalThis.clearTimeout = (id) => { cleared.push(id); return realClear(id); };
  try {
    assert.equal(await withTimeout(Promise.resolve("ok")), "ok");
    await assert.rejects(withTimeout(Promise.reject(new Error("boom"))), /boom/);
  } finally {
    globalThis.clearTimeout = realClear;
  }
  assert.equal(cleared.length, 2, "the timer is cleared on success and on failure");
  // Advancing past the timeout must not fire a stale rejection.
  t.mock.timers.tick(10_000);
});

test("a ledger call that never answers times out and fails closed", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const hanging = ledgerEnv({ reserve: () => new Promise(() => {}), commit: () => new Promise(() => {}) });
  const admission = reserveSpend(hanging, { estimateMicros: 1, secondsEstimate: 1, clientKey: "k" });
  const commit = commitSpend(hanging, "id", 1, 1);
  t.mock.timers.tick(3_000);
  assert.deepEqual(await admission, { ok: false, reason: "unavailable" });
  assert.equal(await commit, undefined);
});
