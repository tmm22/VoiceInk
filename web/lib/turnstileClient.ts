// Invisible-first Turnstile client for the transcription action. The managed
// widget runs with interaction-only appearance: nothing is shown unless
// Cloudflare decides the visitor must complete an interactive check, in which
// case the widget surfaces in a fixed corner container.

type TurnstileApi = {
  render(container: HTMLElement, parameters: {
    sitekey: string;
    action: string;
    execution: "execute";
    appearance: "interaction-only";
    callback: (token: string) => void;
    "error-callback": () => void;
    "expired-callback": () => void;
    "timeout-callback": () => void;
  }): string;
  execute(widgetId: string): void;
  reset(widgetId: string): void;
};

declare global {
  interface Window { turnstile?: TurnstileApi; __voiceinkTurnstileReady?: () => void }
}

const SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
const ACQUIRE_TIMEOUT_MS = 60_000;

let scriptPromise: Promise<TurnstileApi | null> | null = null;
let widgetId: string | null = null;
let widgetUsed = false;
let pendingToken: { resolve: (token: string | null) => void } | null = null;

export function turnstileEnabled() {
  return typeof SITE_KEY === "string" && SITE_KEY.length > 0;
}

function loadTurnstile(): Promise<TurnstileApi | null> {
  scriptPromise ??= new Promise((resolve) => {
    if (window.turnstile) {
      resolve(window.turnstile);
      return;
    }
    window.__voiceinkTurnstileReady = () => resolve(window.turnstile ?? null);
    const script = document.createElement("script");
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=__voiceinkTurnstileReady";
    script.async = true;
    script.onerror = () => resolve(null);
    document.head.appendChild(script);
  });
  return scriptPromise;
}

function widgetContainer() {
  const existing = document.getElementById("voiceink-turnstile");
  if (existing) return existing;
  const container = document.createElement("div");
  container.id = "voiceink-turnstile";
  container.style.position = "fixed";
  container.style.bottom = "16px";
  container.style.right = "16px";
  container.style.zIndex = "1000";
  document.body.appendChild(container);
  return container;
}

function settlePendingToken(token: string | null) {
  const pending = pendingToken;
  pendingToken = null;
  pending?.resolve(token);
}

// Performs the one-time widget render (no challenge execution — execution
// stays "execute", so nothing runs until turnstile.execute is called at stop
// time). Synchronous after the awaits in its callers, so a concurrent warm-up
// and token acquisition can never render two widgets.
function ensureWidget(turnstile: TurnstileApi): string | null {
  if (widgetId !== null) return widgetId;
  try {
    widgetId = turnstile.render(widgetContainer(), {
      sitekey: SITE_KEY as string,
      action: "transcribe",
      execution: "execute",
      appearance: "interaction-only",
      callback: (token) => settlePendingToken(token),
      "error-callback": () => settlePendingToken(null),
      "expired-callback": () => settlePendingToken(null),
      "timeout-callback": () => settlePendingToken(null),
    });
  } catch {
    widgetId = null;
  }
  return widgetId;
}

// Fire-and-forget warm-up called when recording starts: injects the
// challenges.cloudflare.com script and renders the widget so the stop-time
// token acquisition skips the script download and widget bootstrap. It never
// executes a challenge — tokens are single-use and are still acquired only at
// stop time by acquireTranscriptionToken.
export function warmTranscriptionChallenge(): void {
  if (!turnstileEnabled()) return;
  void loadTurnstile().then((turnstile) => {
    if (turnstile) ensureWidget(turnstile);
  }).catch(() => {
    // Warm-up is best effort; acquisition retries the full path at stop time.
  });
}

// Returns a fresh single-use token, or null when Turnstile is not configured
// or the token could not be obtained (the server then decides the outcome).
export async function acquireTranscriptionToken(): Promise<string | null> {
  if (!turnstileEnabled()) return null;
  const turnstile = await loadTurnstile();
  if (!turnstile) return null;

  settlePendingToken(null);
  const id = ensureWidget(turnstile);
  if (id === null) return null;
  const token = await new Promise<string | null>((resolve) => {
    pendingToken = { resolve };
    const timeout = window.setTimeout(() => settlePendingToken(null), ACQUIRE_TIMEOUT_MS);
    const originalResolve = pendingToken.resolve;
    pendingToken.resolve = (value) => {
      window.clearTimeout(timeout);
      originalResolve(value);
    };
    try {
      // Tokens are single-use; a used widget must be reset before re-executing.
      if (widgetUsed) turnstile.reset(id);
      widgetUsed = true;
      turnstile.execute(id);
    } catch {
      settlePendingToken(null);
    }
  });
  return token;
}
