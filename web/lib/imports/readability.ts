const entityMap: Record<string, string> = {
  "&nbsp;": " ",
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
};

function decodeEntities(text: string) {
  return Object.entries(entityMap).reduce(
    (result, [entity, character]) => result.replaceAll(entity, character),
    text,
  );
}

function cleanText(html: string) {
  return decodeEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(p|div|section|article|li|h[1-6])>/gi, "\n\n")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function meaningful(text: string) {
  return text.length > 120 && /[a-zA-Z]/.test(text);
}

function extractTag(html: string, tag: string) {
  const matches = Array.from(html.matchAll(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "gi")))
    .map((match) => cleanText(match[1] ?? ""))
    .filter(meaningful)
    .sort((left, right) => right.length - left.length);
  return matches[0];
}

export function extractReadableArticle(html: string) {
  const openGraphTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']+)["'][^>]*>/i)?.[1];
  const title = cleanText(openGraphTitle ?? html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? "Imported article");

  for (const tag of ["article", "main", "section"]) {
    const content = extractTag(html, tag);
    if (content) return { title, content: content.slice(0, 100_000) };
  }

  const paragraphs = Array.from(html.matchAll(/<p[^>]*>([\s\S]*?)<\/p>/gi))
    .map((match) => cleanText(match[1] ?? ""))
    .filter(meaningful)
    .slice(0, 80);
  const content = paragraphs.length ? paragraphs.join("\n\n") : cleanText(html);
  return { title, content: content.slice(0, 100_000) };
}
