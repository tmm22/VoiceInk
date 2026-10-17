import { hydrate, render } from "preact";
import "./globals.css";
import Home from "./page";
import { AppProviders } from "./providers";

function App() {
  return (
    <AppProviders>
      <Home />
    </AppProviders>
  );
}

// The build prerenders the anonymous shell into index.html (see prerender()
// below), so the browser hydrates that markup instead of painting from blank.
if (typeof document !== "undefined") {
  const container = document.getElementById("app");
  if (container) {
    if (container.firstElementChild) hydrate(<App />, container);
    else render(<App />, container);
  }
}

// Called once at build time by @preact/preset-vite to fill index.html.
export async function prerender() {
  const { renderToStringAsync } = await import("preact-render-to-string");
  return { html: await renderToStringAsync(<App />) };
}
