import type { AuthConfig } from "convex/server";

// Rename this file to auth.config.ts after CLERK_JWT_ISSUER_DOMAIN has been
// configured in both the development and production Convex deployments.
export default {
  providers: [
    {
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
