"use client";

import { ClerkProvider, SignInButton, UserButton, useAuth } from "@clerk/nextjs";
import { createContext, useContext, useMemo, type ReactNode } from "react";

type AccountAuth = {
  enabled: boolean;
  isLoaded: boolean;
  isSignedIn: boolean;
  identityKey: string;
  getConvexToken: () => Promise<string | null>;
};

const anonymousAuth: AccountAuth = {
  enabled: false,
  isLoaded: true,
  isSignedIn: false,
  identityKey: "anonymous",
  getConvexToken: async () => null,
};

const AccountAuthContext = createContext<AccountAuth>(anonymousAuth);
const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
const clerkKey = process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "/";

function ClerkAuthBridge({ children }: { children: ReactNode }) {
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
  return <AccountAuthContext.Provider value={value}>{children}</AccountAuthContext.Provider>;
}

export function AppProviders({ children }: { children: ReactNode }) {
  // History flows through the Worker's /api/history routes; the browser never
  // talks to Convex directly, so no Convex client (or its WebSocket) is created.
  if (!convexUrl || !clerkKey) return children;

  return (
    <ClerkProvider
      publishableKey={clerkKey}
      signInForceRedirectUrl={siteUrl}
      signUpForceRedirectUrl={siteUrl}
    >
      <ClerkAuthBridge>{children}</ClerkAuthBridge>
    </ClerkProvider>
  );
}

export function useAccountAuth() {
  return useContext(AccountAuthContext);
}

function ClerkAccountControls() {
  const { isLoaded, isSignedIn } = useAuth();
  if (!isLoaded) return <div className="account-controls"><span>Loading</span></div>;
  return (
    <div className="account-controls">
      {!isSignedIn && <SignInButton mode="modal"><button>Sign in</button></SignInButton>}
      {isSignedIn && <><span>Synced</span><UserButton /></>}
    </div>
  );
}

export function AccountControls() {
  // Must match the AppProviders gate: ClerkAccountControls calls useAuth,
  // which throws unless ClerkProvider is mounted above it.
  if (!convexUrl || !clerkKey) return null;
  return <ClerkAccountControls />;
}
