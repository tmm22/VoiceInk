// Invisible-first Turnstile client for the transcription action. The managed
// widget runs with interaction-only appearance: nothing is shown unless
// Cloudflare decides the visitor must complete an interactive check, in which
// case the widget surfaces in a fixed corner container.
//
// Recording start pre-executes the challenge and HOLDS the resulting
// single-use token so stop time usually pays no Turnstile latency. Tokens
// expire after roughly 300 seconds while recordings can run far longer, so
// the widget's expired-callback re-executes while the hold is active, keeping
// the held token fresh. Stop consumes the held token exactly once; when none
// is held (expiry race, widget failure, uploads, retries) the caller falls
// back to a fresh stop-time acquisition. A consumed, expired, or released
// token is never reused.

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
let turnstileApi: TurnstileApi | null = null;
let widgetId: string | null = null;
let widgetUsed = false;
let pendingToken: { resolve: (token: string | null) => void } | null = null;
// Pre-executed token held between recording start and stop.
let heldToken: string | null = null;
// True while a recording is in progress, so expired tokens are replaced.
let holdActive = false;

export function turnstileEnabled() {
  return typeof SITE_KEY === "string" && SITE_KEY.length > 0;
}

function loadTurnstile(): Promise<TurnstileApi | null> {
  scriptPromise ??= new Promise((resolve) => {
    if (window.turnstile) {
      turnstileApi = window.turnstile;
      resolve(window.turnstile);
      return;
    }
    window.__voiceinkTurnstileReady = () => {
      turnstileApi = window.turnstile ?? null;
      resolve(turnstileApi);
    };
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

// A fresh token arrived from the widget: an awaiting acquisition wins,
// otherwise an active recording hold stores it for stop time. Tokens are
// single-use, so one that nobody is waiting for is simply dropped rather
// than parked for an unrelated later request.
function receiveToken(token: string) {
  if (pendingToken) {
    settlePendingToken(token);
    return;
  }
  if (holdActive) heldToken = token;
}

// The current token expired. During a recording hold, re-execute so the stop
// click still finds a fresh held token; an expired token is never consumed.
function handleTokenExpired() {
  heldToken = null;
  if (pendingToken) {
    settlePendingToken(null);
    return;
  }
  if (holdActive && turnstileApi && widgetId !== null) executeChallenge(turnstileApi, widgetId);
}

function handleWidgetFailure() {
  heldToken = null;
  settlePendingToken(null);
}

// Performs the one-time widget render (no challenge execution — execution
// stays "execute", so nothing runs until turnstile.execute is called).
// Synchronous after the awaits in its callers, so a concurrent hold kickoff
// and token acquisition can never render two widgets.
function ensureWidget(turnstile: TurnstileApi): string | null {
  if (widgetId !== null) return widgetId;
  try {
    widgetId = turnstile.render(widgetContainer(), {
      sitekey: SITE_KEY as string,
      action: "transcribe",
      execution: "execute",
      appearance: "interaction-only",
      callback: (token) => receiveToken(token),
      "error-callback": () => handleWidgetFailure(),
      "expired-callback": () => handleTokenExpired(),
      "timeout-callback": () => handleWidgetFailure(),
    });
  } catch {
    widgetId = null;
  }
  return widgetId;
}

// Tokens are single-use; a used widget must be reset before re-executing.
function executeChallenge(turnstile: TurnstileApi, id: string) {
  try {
    if (widgetUsed) turnstile.reset(id);
    widgetUsed = true;
    turnstile.execute(id);
  } catch {
    handleWidgetFailure();
  }
}

// Fire-and-forget kickoff called when recording starts: loads the script,
// renders the widget, executes the challenge, and holds the resulting token
// for the stop click. Best effort — stop time falls back to a fresh
// acquisition when nothing is held.
export function beginTranscriptionTokenHold(): void {
  if (!turnstileEnabled()) return;
  // Never reuse a token held for an earlier recording.
  heldToken = null;
  holdActive = true;
  void loadTurnstile().then((turnstile) => {
    if (!turnstile || !holdActive) return;
    const id = ensureWidget(turnstile);
    // An in-flight stop-time acquisition owns the widget; don't preempt it.
    if (id === null || pendingToken) return;
    executeChallenge(turnstile, id);
  });
}

// Consumes the held token exactly once (single-use) and ends the hold so
// expiry no longer re-executes. Returns null when nothing usable is held.
export function takeHeldTranscriptionToken(): string | null {
  holdActive = false;
  const token = heldToken;
  heldToken = null;
  return token;
}

// Abandoned recordings (encoder failure, size limit, unmount) discard the
// held token and stop the expiry re-execution loop.
export function releaseTranscriptionTokenHold(): void {
  holdActive = false;
  heldToken = null;
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
    executeChallenge(turnstile, id);
  });
  return token;
}
