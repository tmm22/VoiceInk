// Lazily imported Clerk loader. app/providers.tsx imports this module only
// when the __client_uat session hint says a session may exist or the visitor
// clicks Sign in, so anonymous visits never download it or any Clerk code.
//
// It drives Clerk's own browser scripts directly instead of through a
// framework SDK: the pinned clerk-js core and @clerk/ui bundle come from the
// Clerk frontend API, so the only Clerk code this app ships is this file.

import type { AccountAuth } from "./accountAuth";
import { clerkScriptUrls, pageNonce } from "./clerkScripts";

// The slice of the clerk-js instance API this app uses.
type ClerkSession = {
  id: string;
  lastActiveToken?: { jwt?: { claims?: { aud?: unknown } } } | null;
  getToken(options?: { template?: string }): Promise<string | null>;
};
type ClerkInstance = {
  loaded: boolean;
  session?: ClerkSession | null;
  load(options: Record<string, unknown>): Promise<void>;
  addListener(listener: () => void): () => void;
  openSignIn(): void;
  mountUserButton(element: HTMLDivElement): void;
  unmountUserButton(element: HTMLDivElement): void;
};

declare global {
  interface Window {
    Clerk?: ClerkInstance;
    __internal_ClerkUICtor?: unknown;
  }
}

export type ClerkController = {
  openSignIn(): void;
  // Mounts Clerk's account menu into the element; returns the unmount.
  mountUserButton(element: HTMLDivElement): () => void;
  // Detaches the identity listener.
  stop(): void;
};

const SCRIPT_TIMEOUT_MS = 15_000;

function loadScript(src: string, publishableKey: string, isReady: () => boolean): Promise<void> {
  if (isReady()) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    const timer = setTimeout(() => fail(new Error(`Timed out loading ${src}`)), SCRIPT_TIMEOUT_MS);
    function fail(error: Error) {
      clearTimeout(timer);
      // Remove the failed tag so a later Sign in click can retry cleanly.
      script.remove();
      reject(error);
    }
    script.src = src;
    script.async = true;
    script.crossOrigin = "anonymous";
    const nonce = pageNonce();
    if (nonce) script.nonce = nonce;
    script.setAttribute("data-clerk-publishable-key", publishableKey);
    script.onload = () => {
      clearTimeout(timer);
      if (isReady()) resolve();
      else fail(new Error(`${src} loaded without initializing Clerk`));
    };
    script.onerror = () => fail(new Error(`Failed to load ${src}`));
    document.head.appendChild(script);
  });
}

export class AccountChangedError extends Error {
  constructor() {
    super("The signed-in account changed before this request finished.");
    this.name = "AccountChangedError";
  }
}

function toAccountAuth(clerk: ClerkInstance): AccountAuth {
  const sessionId = clerk.session?.id ?? null;
  return {
    enabled: true,
    isLoaded: true,
    isSignedIn: sessionId !== null,
    identityKey: sessionId ?? "anonymous",
    // Bound to the session this identity was published for. Work captured
    // under one account (a transcription still in flight, say) must never be
    // saved with another account's token, so a switched or ended session
    // throws instead; callers then report the save as failed. The token is
    // read fresh each call, so Clerk's refreshed tokens are always used. A
    // session token customized with aud: "convex" is already a Convex token;
    // otherwise mint one from the "convex" JWT template.
    getConvexToken: async () => {
      if (sessionId === null) return null;
      const current = clerk.session;
      if (!current || current.id !== sessionId) throw new AccountChangedError();
      return current.lastActiveToken?.jwt?.claims?.aud === "convex"
        ? current.getToken()
        : current.getToken({ template: "convex" });
    },
  };
}

export async function startClerk({ publishableKey, siteUrl, onAuthChange }: {
  publishableKey: string;
  siteUrl: string;
  onAuthChange: (auth: AccountAuth) => void;
}): Promise<ClerkController> {
  const urls = clerkScriptUrls(publishableKey);
  if (!urls) throw new Error("The Clerk publishable key is malformed.");
  await Promise.all([
    loadScript(urls.js, publishableKey, () => Boolean(window.Clerk)),
    loadScript(urls.ui, publishableKey, () => Boolean(window.__internal_ClerkUICtor)),
  ]);
  const clerk = window.Clerk;
  if (!clerk) throw new Error("clerk-js did not initialize.");
  if (!clerk.loaded) {
    await clerk.load({
      ui: { ClerkUI: window.__internal_ClerkUICtor },
      signInForceRedirectUrl: siteUrl,
      signUpForceRedirectUrl: siteUrl,
    });
  }

  // Clerk notifies on every resource change, including token refreshes;
  // publish only when the identity itself changes so consumers keyed on it
  // do not refetch.
  let publishedKey = "";
  const publish = () => {
    const auth = toAccountAuth(clerk);
    const key = `${auth.isSignedIn}:${auth.identityKey}`;
    if (key === publishedKey) return;
    publishedKey = key;
    onAuthChange(auth);
  };
  const removeListener = clerk.addListener(publish);
  publish();

  return {
    openSignIn() {
      if (!clerk.session) clerk.openSignIn();
    },
    mountUserButton(element) {
      clerk.mountUserButton(element);
      return () => clerk.unmountUserButton(element);
    },
    stop: removeListener,
  };
}
