import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

// Resolves the sources' extensionless relative imports to their .ts files.
register("./support/workers-loader.mjs", import.meta.url);
const { CLERK_JS_VERSION, CLERK_UI_VERSION } = await import("../lib/clerkScripts.ts");
const { AccountChangedError, startClerk } = await import("../lib/clerkSession.ts");

// Runs the real loader against a fake document and Clerk instance: script
// tags "load" on the next microtask and install the globals clerk-js and
// @clerk/ui would.
const publishableKey = `pk_live_${btoa("clerk.example.com$")}`;
const jsUrl = `https://clerk.example.com/npm/@clerk/clerk-js@${CLERK_JS_VERSION}/dist/clerk.browser.js`;
const uiUrl = `https://clerk.example.com/npm/@clerk/ui@${CLERK_UI_VERSION}/dist/ui.browser.js`;

function fakeSession(id, aud) {
  const calls = [];
  return {
    id,
    calls,
    lastActiveToken: aud ? { jwt: { claims: { aud } } } : null,
    async getToken(options) {
      calls.push(options);
      return `${id}:${options?.template ?? "session"}`;
    },
  };
}

function installFakeBrowser({ failing = new Set() } = {}) {
  const appended = [];
  function ClerkUI() {}
  const clerk = {
    loaded: false,
    session: null,
    loadCalls: [],
    listeners: new Set(),
    signInOpened: 0,
    mounted: [],
    unmounted: [],
    async load(options) {
      this.loadCalls.push(options);
      this.loaded = true;
    },
    addListener(listener) {
      this.listeners.add(listener);
      return () => this.listeners.delete(listener);
    },
    emit() {
      for (const listener of this.listeners) listener({});
    },
    openSignIn() {
      this.signInOpened += 1;
    },
    mountUserButton(element) {
      this.mounted.push(element);
    },
    unmountUserButton(element) {
      this.unmounted.push(element);
    },
  };
  globalThis.window = globalThis;
  globalThis.document = {
    querySelector: (selector) => (selector === "script[nonce]" ? { nonce: "page-nonce" } : null),
    createElement: (tagName) => {
      const element = {
        tagName,
        attributes: {},
        removed: false,
        setAttribute(name, value) {
          this.attributes[name] = value;
        },
        remove() {
          this.removed = true;
        },
      };
      return element;
    },
    head: {
      appendChild(element) {
        appended.push(element);
        queueMicrotask(() => {
          if (failing.has(element.src)) return element.onerror?.();
          if (element.src === jsUrl) globalThis.Clerk = clerk;
          if (element.src === uiUrl) globalThis.__internal_ClerkUICtor = ClerkUI;
          element.onload?.();
        });
      },
    },
  };
  return { appended, clerk, ClerkUI };
}

function uninstall() {
  delete globalThis.Clerk;
  delete globalThis.__internal_ClerkUICtor;
  delete globalThis.document;
  delete globalThis.window;
}

async function start(onAuthChange = () => {}) {
  return startClerk({ publishableKey, siteUrl: "https://v.paul.im", onAuthChange });
}

test("startup loads both pinned scripts with the page nonce and initializes Clerk with its UI", async (t) => {
  t.after(uninstall);
  const { appended, clerk, ClerkUI } = installFakeBrowser();
  const published = [];
  await start((auth) => published.push(auth));

  assert.deepEqual(appended.map((script) => script.src), [jsUrl, uiUrl]);
  for (const script of appended) {
    assert.equal(script.crossOrigin, "anonymous");
    assert.equal(script.nonce, "page-nonce");
    assert.equal(script.async, true);
    assert.equal(script.attributes["data-clerk-publishable-key"], publishableKey);
  }
  assert.equal(clerk.loadCalls.length, 1);
  assert.equal(clerk.loadCalls[0].ui.ClerkUI, ClerkUI);
  assert.equal(clerk.loadCalls[0].signInForceRedirectUrl, "https://v.paul.im");
  assert.equal(clerk.loadCalls[0].signUpForceRedirectUrl, "https://v.paul.im");

  // The signed-out identity is published once, and carries no token.
  assert.equal(published.length, 1);
  assert.deepEqual({ ...published[0], getConvexToken: undefined }, {
    enabled: true, isLoaded: true, isSignedIn: false, identityKey: "anonymous", getConvexToken: undefined,
  });
  assert.equal(await published[0].getConvexToken(), null);
});

test("identity changes publish once each, and tokens use the convex template unless aud is convex", async (t) => {
  t.after(uninstall);
  const { clerk } = installFakeBrowser();
  const published = [];
  await start((auth) => published.push(auth));

  const templated = fakeSession("sess_a");
  clerk.session = templated;
  clerk.emit();
  clerk.emit(); // A token refresh notifies again; the identity is unchanged.
  assert.equal(published.length, 2);
  assert.equal(published[1].isSignedIn, true);
  assert.equal(published[1].identityKey, "sess_a");
  assert.equal(await published[1].getConvexToken(), "sess_a:convex");
  assert.deepEqual(templated.calls, [{ template: "convex" }]);

  const convexAudience = fakeSession("sess_b", "convex");
  clerk.session = convexAudience;
  clerk.emit();
  assert.equal(published.length, 3);
  assert.equal(await published[2].getConvexToken(), "sess_b:session");
  assert.deepEqual(convexAudience.calls, [undefined]);
});

test("work captured under one account can never fetch another account's token", async (t) => {
  t.after(uninstall);
  const { clerk } = installFakeBrowser();
  const published = [];
  await start((auth) => published.push(auth));

  clerk.session = fakeSession("sess_a");
  clerk.emit();
  const accountA = published.at(-1);
  clerk.session = fakeSession("sess_b");
  clerk.emit();
  const accountB = published.at(-1);

  await assert.rejects(accountA.getConvexToken(), AccountChangedError);
  assert.equal(await accountB.getConvexToken(), "sess_b:convex");
  clerk.session = null;
  clerk.emit();
  await assert.rejects(accountB.getConvexToken(), AccountChangedError);
  assert.equal(await published.at(-1).getConvexToken(), null);
});

test("the controller opens sign-in only when signed out, mounts the account menu, and stops listening", async (t) => {
  t.after(uninstall);
  const { clerk } = installFakeBrowser();
  const published = [];
  const controller = await start((auth) => published.push(auth));

  controller.openSignIn();
  assert.equal(clerk.signInOpened, 1);
  const host = {};
  const unmount = controller.mountUserButton(host);
  assert.deepEqual(clerk.mounted, [host]);
  unmount();
  assert.deepEqual(clerk.unmounted, [host]);

  clerk.session = fakeSession("sess_a");
  controller.openSignIn();
  assert.equal(clerk.signInOpened, 1, "a signed-in visitor is never sent to sign-in");

  controller.stop();
  clerk.emit();
  assert.equal(published.length, 1, "a stopped controller publishes nothing");
});

test("a failed script load rejects, removes the tag, and a later start retries cleanly", async (t) => {
  t.after(uninstall);
  const failing = new Set([jsUrl]);
  const { appended, clerk } = installFakeBrowser({ failing });
  await assert.rejects(start(), /Failed to load https:\/\/clerk\.example\.com/);
  assert.equal(appended.find((script) => script.src === jsUrl).removed, true);
  assert.equal(clerk.loadCalls.length, 0);

  failing.clear();
  const published = [];
  await start((auth) => published.push(auth));
  assert.equal(clerk.loadCalls.length, 1);
  assert.equal(published.length, 1);
  // The UI bundle had already loaded, so only clerk-js is fetched again.
  assert.deepEqual(appended.map((script) => script.src), [jsUrl, uiUrl, jsUrl]);
});

test("an already-loaded Clerk is reused without new scripts or a second load", async (t) => {
  t.after(uninstall);
  const { appended, clerk } = installFakeBrowser();
  await start();
  await start();
  assert.equal(appended.length, 2);
  assert.equal(clerk.loadCalls.length, 1);
});
