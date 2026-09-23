// Test stand-in for the `cloudflare:workers` runtime module. Tests mutate `env`
// in place to install fake bindings for the route under test.
export const env = {};

export class DurableObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }
}
