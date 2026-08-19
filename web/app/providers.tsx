"use client";

import {
  Component,
  createContext,
  lazy,
  startTransition,
  Suspense,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type AccountAuth = {
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

// The default value keeps every consumer on the anonymous identity until the
// lazily mounted Clerk bridge (app/clerk-subtree.tsx) publishes the verified
// one into AppProviders state.
export const AccountAuthContext = createContext<AccountAuth>(anonymousAuth);

type ClerkGateValue = {
  clerkMounted: boolean;
  requestSignIn: () => void;
  setControlsHost: (element: HTMLElement | null) => void;
};
const ClerkGateContext = createContext<ClerkGateValue>({
  clerkMounted: false,
  requestSignIn: () => {},
  setControlsHost: () => {},
});

const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
const clerkKey = process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;
const accountsConfigured = Boolean(convexUrl && clerkKey);

// The whole Clerk machinery (ClerkProvider + auth bridge + account controls)
// lives in one lazily loaded chunk so anonymous hydration ships no Clerk SDK
// bytes.
const ClerkSubtree = lazy(() => import("./clerk-subtree"));

// Clerk keeps a client-readable session hint in the __client_uat cookie
// ("updated at"; suffixed with an instance hash when several Clerk apps share
// a registrable domain). A non-zero value means a session may exist, so the
// Clerk subtree must mount and verify it; absent or "0" means signed out and
// clerk-js is never loaded.
function hasClerkSessionHint(): boolean {
  if (typeof document === "undefined") return false;
  return document.cookie.split(";").some((pair) => {
    const separator = pair.indexOf("=");
    if (separator === -1) return false;
    const name = pair.slice(0, separator).trim();
    if (name !== "__client_uat" && !name.startsWith("__client_uat_")) return false;
    const value = pair.slice(separator + 1).trim();
    return value !== "" && value !== "0";
  });
}

type ClerkGateState = "anonymous" | "mounted" | "sign-in";

// Catches a failed clerk-subtree chunk load or a crash inside the Clerk
// machinery. It wraps ONLY the Clerk sibling subtree — never the application —
// so an app render error still reaches Next.js error handling; a Clerk failure
// is reported upward, where AppProviders logs it and drops back to the
// fail-closed anonymous identity.
class ClerkLoadBoundary extends Component<
  { onFailure: (error: unknown) => void; children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: unknown) {
    this.props.onFailure(error);
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

export function AppProviders({ children }: { children: ReactNode }) {
  // History flows through the Worker's /api/history routes; the browser never
  // talks to Convex directly, so no Convex client (or its WebSocket) is created.
  const [gate, setGate] = useState<ClerkGateState>("anonymous");
  const [clerkFailed, setClerkFailed] = useState(false);
  // The verified account identity, lifted out of the Clerk sibling subtree by
  // ClerkAuthBridge. Holding it in state here lets {children} keep one fixed
  // tree position in every gate state: opening the gate mounts Clerk NEXT TO
  // the app instead of re-parenting it, so in-memory recording and
  // transcription state is never lost to a remount.
  const [accountAuth, setAccountAuth] = useState<AccountAuth>(anonymousAuth);
  // The header element the Clerk chunk portals its account controls into.
  const [controlsHost, setControlsHost] = useState<HTMLElement | null>(null);

  // The server render and the first client render are always anonymous so
  // hydration matches; the session-hint cookie check runs afterwards in an
  // effect. startTransition keeps the anonymous UI interactive while the
  // Clerk chunk loads.
  useEffect(() => {
    if (!accountsConfigured || !hasClerkSessionHint()) return;
    startTransition(() => setGate((current) => (current === "anonymous" ? "mounted" : current)));
  }, []);

  const requestSignIn = useCallback(() => {
    // Clearing the failure flag lets a visitor retry after a chunk-load or
    // Clerk crash fallback.
    setClerkFailed(false);
    startTransition(() => setGate((current) => (current === "sign-in" ? current : "sign-in")));
  }, []);

  const handleClerkFailure = useCallback((error: unknown) => {
    // Chunk-load or Clerk render failure: log it (never tokens or transcript
    // data) and stay fail-closed on the anonymous identity. The application
    // subtree is a sibling, so it keeps running untouched.
    console.error("Clerk subtree failed to load or crashed; continuing anonymously", error);
    setAccountAuth(anonymousAuth);
    setClerkFailed(true);
  }, []);

  const clerkMounted = gate !== "anonymous" && !clerkFailed;
  const gateValue = useMemo<ClerkGateValue>(
    () => ({ clerkMounted, requestSignIn, setControlsHost }),
    [clerkMounted, requestSignIn],
  );

  if (!accountsConfigured) return children;

  // {children} renders at the same position in every gate state. The Clerk
  // machinery mounts as a sibling with no visible output of its own (the
  // account controls reach their header slot through a portal), and its
  // Suspense fallback is null, so the anonymous UI simply stays on screen
  // while the chunk loads — never a spinner, never a remount.
  return (
    <ClerkGateContext.Provider value={gateValue}>
      <AccountAuthContext.Provider value={accountAuth}>{children}</AccountAuthContext.Provider>
      {clerkMounted && (
        <ClerkLoadBoundary onFailure={handleClerkFailure}>
          <Suspense fallback={null}>
            <ClerkSubtree
              openSignIn={gate === "sign-in"}
              onAuthChange={setAccountAuth}
              controlsHost={controlsHost}
            />
          </Suspense>
        </ClerkLoadBoundary>
      )}
    </ClerkGateContext.Provider>
  );
}

export function useAccountAuth() {
  return useContext(AccountAuthContext);
}

function SignInRequestButton() {
  const { requestSignIn } = useContext(ClerkGateContext);
  return (
    <div className="account-controls">
      <button onClick={requestSignIn}>Sign in</button>
    </div>
  );
}

export function AccountControls() {
  const { clerkMounted, setControlsHost } = useContext(ClerkGateContext);
  if (!accountsConfigured) return null;
  // Before the Clerk subtree mounts, show a plain Sign in button; clicking it
  // mounts the sibling Clerk subtree, which then opens the sign-in modal.
  // Once mounted, this renders only the host element that subtree portals the
  // Clerk-backed controls into — useAuth is never called outside
  // ClerkProvider, because those controls render inside it (portals keep the
  // React context of their render position, not their DOM position).
  if (!clerkMounted) return <SignInRequestButton />;
  return <div style={{ display: "contents" }} ref={setControlsHost} />;
}
