// The account identity the UI and history calls read. Framework-free so the
// lazy Clerk loader (lib/clerkSession.ts) and the eager providers share it.
export type AccountAuth = {
  enabled: boolean;
  isLoaded: boolean;
  isSignedIn: boolean;
  identityKey: string;
  getConvexToken: () => Promise<string | null>;
};

// Every consumer stays on this fail-closed anonymous identity until Clerk
// loads and publishes a verified session.
export const anonymousAuth: AccountAuth = {
  enabled: false,
  isLoaded: true,
  isSignedIn: false,
  identityKey: "anonymous",
  getConvexToken: async () => null,
};
