"use client";

import {
  createContext,
  use,
  useCallback,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { anonymousAuth, type AccountAuth } from "../lib/accountAuth";
import { clerkPublishableKey, hasClerkSessionHint, preloadClerkScripts } from "../lib/clerkScripts";
import type { ClerkController } from "../lib/clerkSession";

export type { AccountAuth } from "../lib/accountAuth";

const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "/";
export const accountsConfigured = Boolean(convexUrl && clerkPublishableKey);

// idle: Clerk not requested (anonymous visit, nothing loaded).
// loading: lib/clerkSession.ts and Clerk's scripts are loading.
// ready: Clerk loaded; AccountAuthContext carries the verified identity.
// failed: loading failed; the visitor stays anonymous and may retry.
export type ClerkStatus = "idle" | "loading" | "ready" | "failed";

type AccountGate = {
  status: ClerkStatus;
  requestSignIn: () => void;
  mountUserButton: (element: HTMLDivElement) => () => void;
};

// The default value keeps every consumer on the anonymous identity until
// lib/clerkSession.ts publishes the verified one into AppProviders state.
export const AccountAuthContext = createContext<AccountAuth>(anonymousAuth);
AccountAuthContext.displayName = "AccountAuthContext";

export const AccountGateContext = createContext<AccountGate>({
  status: "idle",
  requestSignIn: () => {},
  mountUserButton: () => () => {},
});
AccountGateContext.displayName = "AccountGateContext";

// Module-scope warm start: when the session hint is already present at client
// module evaluation, Clerk is certain to load, so start the loader chunk and
// both pinned Clerk scripts downloading during hydration instead of after it.
// Server-side evaluation is skipped by the document guard.
if (typeof document !== "undefined" && accountsConfigured && clerkPublishableKey && hasClerkSessionHint()) {
  void import("../lib/clerkSession");
  preloadClerkScripts(clerkPublishableKey);
}

export function AppProviders({ children }: { children: ReactNode }) {
  // The server render and the first client render are always anonymous so
  // hydration matches.
  const [status, setStatus] = useState<ClerkStatus>("idle");
  const [accountAuth, setAccountAuth] = useState<AccountAuth>(anonymousAuth);
  const controllerRef = useRef<ClerkController | null>(null);
  const startingRef = useRef<Promise<void> | null>(null);
  const openSignInWhenReadyRef = useRef(false);

  const handleClerkFailure = useCallback((error: unknown) => {
    // Blocked or failed Clerk load: log it (never tokens or transcript data)
    // and stay fail-closed on the anonymous identity. Clearing the in-flight
    // marker lets a later Sign in click retry.
    console.error("Clerk failed to load; continuing anonymously", error);
    startingRef.current = null;
    openSignInWhenReadyRef.current = false;
    setAccountAuth(anonymousAuth);
    setStatus("failed");
  }, []);

  const startClerk = useCallback(() => {
    const publishableKey = clerkPublishableKey;
    if (startingRef.current || !publishableKey) return;
    setStatus("loading");
    startingRef.current = import("../lib/clerkSession")
      .then(({ startClerk: start }) => start({ publishableKey, siteUrl, onAuthChange: setAccountAuth }))
      .then((controller) => {
        controllerRef.current = controller;
        setStatus("ready");
        if (openSignInWhenReadyRef.current) {
          openSignInWhenReadyRef.current = false;
          controller.openSignIn();
        }
      })
      .catch(handleClerkFailure);
  }, [handleClerkFailure]);

  // A present session hint means Clerk must load to verify the session. A
  // layout effect flips the header to its Loading placeholder before the
  // first paint, so a likely-signed-in visitor never sees a Sign in flash.
  useLayoutEffect(() => {
    if (accountsConfigured && hasClerkSessionHint()) startClerk();
  }, [startClerk]);

  const requestSignIn = useCallback(() => {
    if (controllerRef.current) {
      controllerRef.current.openSignIn();
      return;
    }
    openSignInWhenReadyRef.current = true;
    startClerk();
  }, [startClerk]);

  const mountUserButton = useCallback(
    (element: HTMLDivElement) => controllerRef.current?.mountUserButton(element) ?? (() => {}),
    [],
  );

  const gate = useMemo<AccountGate>(
    () => ({ status, requestSignIn, mountUserButton }),
    [status, requestSignIn, mountUserButton],
  );

  if (!accountsConfigured) return children;
  return (
    <AccountGateContext value={gate}>
      <AccountAuthContext value={accountAuth}>{children}</AccountAuthContext>
    </AccountGateContext>
  );
}

export function useAccountAuth() {
  return use(AccountAuthContext);
}
