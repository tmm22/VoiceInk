// Node module hooks that let handler tests import Worker sources directly:
// `cloudflare:workers` resolves to a local stub, and the extensionless relative
// imports the Next.js routes use resolve to their `.ts` files.
const stubUrl = new URL("./cloudflare-workers-stub.mjs", import.meta.url).href;

export async function resolve(specifier, context, nextResolve) {
  if (specifier === "cloudflare:workers") return { url: stubUrl, shortCircuit: true };
  try {
    return await nextResolve(specifier, context);
  } catch (error) {
    const relative = specifier.startsWith("./") || specifier.startsWith("../");
    if (!relative || /\.[cm]?[jt]sx?$/.test(specifier) || error?.code !== "ERR_MODULE_NOT_FOUND") throw error;
    return nextResolve(`${specifier}.ts`, context);
  }
}
