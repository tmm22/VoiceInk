"use client";

import { useEffect, useState } from "react";

export type Theme = "editorial" | "mac";

// The saved appearance is applied to <html data-theme> immediately and to
// React state on the next tick, so the first render matches the server HTML.
export function useTheme() {
  const [theme, setTheme] = useState<Theme>("editorial");

  useEffect(() => {
    let themeUpdate: number | undefined;
    const savedTheme = window.localStorage.getItem("voiceink-theme");
    if (savedTheme === "mac" || savedTheme === "editorial") {
      themeUpdate = window.setTimeout(() => setTheme(savedTheme), 0);
      document.documentElement.dataset.theme = savedTheme;
    }
    return () => {
      if (themeUpdate !== undefined) window.clearTimeout(themeUpdate);
    };
  }, []);

  function selectTheme(nextTheme: Theme) {
    setTheme(nextTheme);
    document.documentElement.dataset.theme = nextTheme;
    window.localStorage.setItem("voiceink-theme", nextTheme);
  }

  return { theme, selectTheme };
}
