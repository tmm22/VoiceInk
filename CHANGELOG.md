# Changelog

All notable changes to the VoiceLink Community application are documented here.

## 2025-12-19

### Security
- Enforced HTTPS validation for custom AI provider verification to prevent
  insecure API key transmission.

### Performance
- Avoided blocking audio file reads by using async loaders and upload-by-file
  where supported.

### Concurrency
- Removed redundant main-thread hops in `@MainActor` classes.

### I/O
- Removed forced `UserDefaults.synchronize()` calls in hot paths.
