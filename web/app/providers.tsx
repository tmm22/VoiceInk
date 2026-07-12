"use client";

import { ClerkProvider, SignInButton, UserButton, useAuth } from "@clerk/nextjs";
import { ConvexReactClient, ConvexProvider } from "convex/react";
import { ConvexProviderWithClerk } from "convex/react-clerk";
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
const convex = convexUrl ? new ConvexReactClient(convexUrl) : null;

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
  if (!convex) return children;
  if (!clerkKey) return <ConvexProvider client={convex}>{children}</ConvexProvider>;

  return (
    <ClerkProvider publishableKey={clerkKey}>
      <ConvexProviderWithClerk client={convex} useAuth={useAuth}>
        <ClerkAuthBridge>{children}</ClerkAuthBridge>
      </ConvexProviderWithClerk>
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
  if (!clerkKey) return null;
  return <ClerkAccountControls />;
}
