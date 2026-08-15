import assert from "node:assert/strict";
import test from "node:test";
import { extractReadableArticle } from "../lib/imports/readability.ts";

test("article extraction removes scripts, styles, and markup", () => {
  const article = extractReadableArticle(`<html><head><title>Useful &amp; Safe</title><script>steal()</script></head><body><article><h1>Heading</h1><p>${"Readable content. ".repeat(12)}</p><style>body{display:none}</style></article></body></html>`);
  assert.equal(article.title, "Useful & Safe");
  assert.match(article.content, /Readable content/);
  assert.doesNotMatch(article.content, /steal|display:none|<p>/);
});

test("article extraction prefers Open Graph titles and bounds output", () => {
  const article = extractReadableArticle(`<meta property="og:title" content="Preferred title"><main>${"Long content sentence. ".repeat(7_000)}</main>`);
  assert.equal(article.title, "Preferred title");
  assert.ok(article.content.length <= 100_000);
});

test("article extraction falls back safely for minimal documents", () => {
  assert.deepEqual(extractReadableArticle("<div>Hello &lt;world&gt;</div>"), { title: "Imported article", content: "Hello <world>" });
});
