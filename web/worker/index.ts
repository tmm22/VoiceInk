/**
 * Worker entry point for both local development (vite.config.ts) and the
 * production build (dist/server/index.js). The app renders no optimized images,
 * so no IMAGES binding or /_vinext/image handler is wired.
 */
import handler from "vinext/server/app-router-entry";

export default handler;
