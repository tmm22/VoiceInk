"use client";

// Lazily loaded Clerk machinery. app/providers.tsx imports this module only
// after its mount gate opens (the __client_uat session-hint cookie is
// non-zero, or the visitor clicks Sign in), so anonymous hydration ships no
// Clerk SDK bytes and never loads clerk-js. It mounts as a SIBLING of the
// application subtree and publishes the verified identity upward through
// onAuthChange, so opening the gate never re-parents (and therefore never
// remounts) the app.

import { ClerkProvider, SignInButton, UserButton, useAuth, useClerk } from "@clerk/nextjs";
import { useEffect, useMemo, useRef } from "react";
import { createPortal } from "react-dom";
import type { AccountAuth } from "./providers";

// Pin clerk-js to the exact version the installed @clerk/nextjs resolves to
// (the versionSelector packageVersion default in @clerk/shared). The unpinned
// major-version CDN URL answers every visit with an uncacheable 307 redirect;
// the fully pinned URL is served directly and caches. A regression test
// compares this constant against node_modules so an SDK upgrade cannot leave
// the pin stale.
const CLERK_JS_VERSION = "6.29.1";
// @clerk/nextjs 7 dropped the public clerkJSVersion prop from its types, but
// mergeNextClerkPropsWithEnv still honors the __internal_clerkJSVersion prop
// (its env fallback is NEXT_PUBLIC_CLERK_JS_VERSION), and loadClerkJsScript
// feeds it through versionSelector, which returns an explicit version as-is.
const clerkScriptPin: { __internal_clerkJSVersion: string } = {
  __internal_clerkJSVersion: CLERK_JS_VERSION,
};

const clerkKey = process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "/";

// Publishes the verified account identity up into AppProviders state instead
// of wrapping the app in a context provider, keeping the application subtree
// at a fixed tree position. Renders nothing.
function ClerkAuthBridge({ onAuthChange }: { onAuthChange: (auth: AccountAuth) => void }) {
  const { getToken, isLoaded, isSignedIn, sessionId, sessionClaims } = useAuth();
  const value = useMemo<AccountAuth>(() => ({
    enabled: true,
    isLoaded,
    isSignedIn: Boolean(isSignedIn),
    identityKey: sessionId ?? "anonymous",
    getConvexToken: async () => sessionClaims?.aud === "convex"
      ? getToken()
      : getToken({ template: "convex" }),
  }), [getToken, isLoaded, isSignedIn, sessionClaims?.aud, sessionId]);
  useEffect(() => {
    onAuthChange(value);
  }, [onAuthChange, value]);
  return null;
}

// When the subtree was mounted because the visitor clicked the anonymous
// Sign in button, open the sign-in modal once clerk-js finishes loading. The
// provider-level force-redirect options apply to this modal too.
function OpenSignInOnLoad() {
  const clerk = useClerk();
  const { isLoaded, isSignedIn } = useAuth();
  const opened = useRef(false);
  useEffect(() => {
    if (!isLoaded || isSignedIn || opened.current) return;
    opened.current = true;
    clerk.openSignIn();
  }, [clerk, isLoaded, isSignedIn]);
  return null;
}

export default function ClerkSubtree({ openSignIn, onAuthChange, controlsHost }: {
  openSignIn: boolean;
  onAuthChange: (auth: AccountAuth) => void;
  controlsHost: HTMLElement | null;
}) {
  // The gate in app/providers.tsx only mounts this subtree when the key is
  // configured; this guard just keeps the fallback behavior fail-safe.
  if (!clerkKey) return null;
  return (
    <ClerkProvider
      publishableKey={clerkKey}
      {...clerkScriptPin}
      signInForceRedirectUrl={siteUrl}
      signUpForceRedirectUrl={siteUrl}
    >
      <ClerkAuthBridge onAuthChange={onAuthChange} />
      {openSignIn && <OpenSignInOnLoad />}
      {controlsHost && createPortal(<ClerkAccountControls />, controlsHost)}
    </ClerkProvider>
  );
}

// Portaled into the host element AccountControls (app/providers.tsx) renders
// while the subtree is mounted. The portal's React position is inside
// ClerkProvider, so useAuth always runs under it.
export function ClerkAccountControls() {
  const { isLoaded, isSignedIn } = useAuth();
  if (!isLoaded) return <div className="account-controls"><span>Loading</span></div>;
  return (
    <div className="account-controls">
      {!isSignedIn && <SignInButton mode="modal"><button>Sign in</button></SignInButton>}
      {isSignedIn && <><span>Synced</span><UserButton /></>}
    </div>
  );
}
