"use client";

import { useContext, useSyncExternalStore } from "react";
import { accountsConfigured, ClerkGateContext, hasClerkSessionHint } from "./providers";

function SignInRequestButton() {
  const { requestSignIn } = useContext(ClerkGateContext);
  return (
    <div className="account-controls">
      <button onClick={requestSignIn}>Sign in</button>
    </div>
  );
}

// Mount-safe session-hint read for render decisions. The server render and
// the hydration render use the server snapshot (false), so the markup always
// matches SSR; right after hydration React re-reads the cookie-backed
// snapshot and re-renders if it differs. Cookies emit no change events, so
// the subscription is a no-op.
const subscribeToNothing = () => () => {};
const noServerHint = () => false;
function useClerkSessionHint(): boolean {
  return useSyncExternalStore(subscribeToNothing, hasClerkSessionHint, noServerHint);
}

export function AccountControls() {
  const { clerkMounted, clerkFailed, setControlsHost } = useContext(ClerkGateContext);
  const sessionHint = useClerkSessionHint();
  if (!accountsConfigured) return null;
  // Before the Clerk subtree mounts, show a plain Sign in button; clicking it
  // mounts the sibling Clerk subtree, which then opens the sign-in modal.
  // Once mounted, this renders only the host element that subtree portals the
  // Clerk-backed controls into — useAuth is never called outside
  // ClerkProvider, because those controls render inside it (portals keep the
  // React context of their render position, not their DOM position).
  if (!clerkMounted) {
    // A present session hint means the gate is about to mount the Clerk
    // subtree, which will almost certainly resolve to a signed-in session, so
    // show the same Loading placeholder ClerkAccountControls starts with
    // instead of flashing Sign in. If the Clerk chunk failed to load or
    // crashed, drop back to the Sign in button so the visitor can retry
    // (fail-closed anonymous).
    if (sessionHint && !clerkFailed) {
      return (
        <div className="account-controls">
          <span>Loading</span>
        </div>
      );
    }
    return <SignInRequestButton />;
  }
  return <div style={{ display: "contents" }} ref={setControlsHost} />;
}
