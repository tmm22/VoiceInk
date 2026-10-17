import { useContext, useEffect, useRef } from "preact/hooks";
import { AccountAuthContext, AccountGateContext, accountsConfigured } from "./providers";

// Clerk renders its account menu into this element; unmounted on cleanup.
function UserButtonHost({ mount }: { mount: (element: HTMLDivElement) => () => void }) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (!hostRef.current) return;
    return mount(hostRef.current);
  }, [mount]);
  return <div ref={hostRef} />;
}

export function AccountControls() {
  const account = useContext(AccountAuthContext);
  const { status, requestSignIn, mountUserButton } = useContext(AccountGateContext);
  if (!accountsConfigured) return null;
  // While Clerk loads (a session hint was present, or the visitor clicked
  // Sign in) show a Loading placeholder instead of flashing Sign in. If Clerk
  // failed to load, the Sign in button stays available so the visitor can
  // retry (fail-closed anonymous).
  if (status === "loading") {
    return (
      <div className="account-controls">
        <span>Loading</span>
      </div>
    );
  }
  if (status === "ready" && account.isSignedIn) {
    return (
      <div className="account-controls">
        <span>Synced</span>
        <UserButtonHost mount={mountUserButton} />
      </div>
    );
  }
  return (
    <div className="account-controls">
      <button onClick={requestSignIn}>Sign in</button>
    </div>
  );
}
