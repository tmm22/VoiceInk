import assert from "node:assert/strict";
import test from "node:test";
import { CLERK_JS_VERSION, CLERK_UI_VERSION, clerkScriptUrls, frontendApiFromKey } from "../lib/clerkScripts.ts";

const keyFor = (host, env = "live") => `pk_${env}_${btoa(`${host}$`)}`;

test("the Clerk frontend API host is decoded from the publishable key", () => {
  assert.equal(frontendApiFromKey(keyFor("clerk.example.com")), "clerk.example.com");
  assert.equal(frontendApiFromKey(keyFor("happy-otter-12.clerk.accounts.dev", "test")), "happy-otter-12.clerk.accounts.dev");
  // Malformed keys never produce a script origin.
  assert.equal(frontendApiFromKey("pk_live_"), null);
  assert.equal(frontendApiFromKey("pk_live_%%%"), null);
  assert.equal(frontendApiFromKey(`pk_live_${btoa("clerk.example.com")}`), null);
  assert.equal(clerkScriptUrls("not-a-key"), null);
});

test("both Clerk scripts load from the key's frontend API at exact pinned versions", () => {
  assert.deepEqual(clerkScriptUrls(keyFor("clerk.example.com")), {
    origin: "https://clerk.example.com",
    js: `https://clerk.example.com/npm/@clerk/clerk-js@${CLERK_JS_VERSION}/dist/clerk.browser.js`,
    ui: `https://clerk.example.com/npm/@clerk/ui@${CLERK_UI_VERSION}/dist/ui.browser.js`,
  });
  for (const version of [CLERK_JS_VERSION, CLERK_UI_VERSION]) assert.match(version, /^\d+\.\d+\.\d+$/);
});
