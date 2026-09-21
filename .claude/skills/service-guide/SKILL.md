---
name: service-guide
description: Language-agnostic checklist of cross-cutting conventions for a new or existing service in this repo — error handling (throw-based, two-tier client/server split), response envelope, structured logging, and related boundary concerns. Use when scaffolding a new service/language backend, adding a new route/handler to an existing service, or when asked how errors/logging/responses should be structured. Not about file/folder layout, which is left to each language's own idioms.
---

# Service Guide

A rough, language-agnostic guide for the cross-cutting plumbing every service in this
system should have, regardless of what language or framework it's written in. This is
about _behavior at the boundary_ (errors, responses, logs) — not file structure. Each
language keeps its own idiomatic layout.

## Core principles

### 1. Business logic throws, it doesn't return error codes

A service/handler function that hits a business-rule failure (missing param, not found,
downstream said no) should `throw`/`raise`, not return `{ok: false, ...}` or a null and
expect the caller to check it. Let the throw propagate up through routes to one place
that decides how to render it. This keeps service functions readable as straight-line
happy-path code.

### 2. Two-tier error handling: known vs. unknown

Distinguish **errors you defined** (bad input, not-found, a downstream service returning
a structured failure) from **everything else** (a null pointer, an unhandled exception, a
library throwing something you didn't anticipate):

- **Known / user-defined error → 4xx.** Tag these errors (a dedicated error type, a
  marker field, whatever the language makes easy) so the boundary handler can recognize
  them, carrying a stable machine-readable code plus a human-readable message.
- **Anything else → 500.** One catch-all at the boundary checks for the known-error tag
  first; if it doesn't match, log the _real_ error server-side and respond with a
  generic, non-leaking message. Never let a raw stack trace or exception message reach
  the client on the unknown-error path — that's the difference between "your input was
  bad" (safe to expose) and "our system broke" (must not expose internals).

Keep error codes as a stable enum, not raw strings scattered across call sites — it's
the contract client code can branch on, decoupled from the human-readable message.

Being tagged as a known error marks something as _renderable to the client_, not
automatically _safe_ — it still needs a message you deliberately chose to expose. Watch
for downstream error text getting forwarded verbatim into a known error: wrapping a raw
upstream/dependency error message and re-throwing it as a "known" error silently makes
it client-visible, even though nobody decided that message was safe to show.

### 3. One response envelope, always

Every response — success or failure — goes through the same shape so clients don't need
per-endpoint parsing logic:

```
ok(data)              // { code: 'SUCCESS', message: 'success', data }
fail(code, message?)  // { code, message, data: null }
```

Handlers call `ok(...)` on the happy path; the boundary error handler calls `fail(...)`
on the way out. No handler hand-rolls its own response shape.

### 4. Structured logging, not ad hoc print statements

- Emit **structured** (JSON) log lines with a level, an event name, and a fields object —
  not interpolated strings.
- **Request/response logging** wraps every request, carrying a request/correlation id,
  method, path, status, and duration. Generate the id if the caller didn't supply one,
  and propagate it — this is also how you'd eventually trace one logical request across
  a hop to another service, so don't drop it when a request fans out.
- **Redact sensitive fields** (auth headers, passwords, tokens, API keys, license keys,
  etc.) before logging headers/bodies. Any new sensitive field added to a
  request/response payload should be added to that redaction set too.
- Log level should differ by environment (verbose in dev, quieter in prod) via one
  config flag, not scattered conditionals sprinkled through the code.

## Other things worth having (beyond what you listed)

- **Fail fast on startup.** Validate required env vars / config before accepting
  traffic — crash immediately with a clear message rather than starting
  half-configured and failing mysteriously on the first request. A config value that's
  required for the service to make sense (an API key, a connection string) shouldn't
  have a silent default; it should be absent-by-default so startup fails loudly instead
  of the service running degraded.
- **Timeouts on every outbound call.** Anything that leaves the process — an HTTP call,
  an RPC, a DB query — needs a timeout so a stuck dependency can't hang the request
  forever. A timeout firing should itself become a clean known-error, not an unhandled
  rejection/exception.
- **Health check endpoint.** Every service needs a cheap health/readiness endpoint that
  reports the status of its real dependencies, not just "process is up" — useful for
  orchestration to gate startup order and for on-call to triage quickly.
- **Graceful shutdown.** Handle termination signals to stop accepting new work, close
  connections/channels cleanly, and exit — as a generic shutdown hook, not ad hoc
  per-service.
- **Correlation across service hops.** In a system where one logical request crosses
  multiple processes (a gateway calling into a worker, a worker calling into another
  service), a request/correlation id set at the entry point is only useful if it's
  threaded through every hop so logs from all of them can be joined for one request.
  Worth doing before debugging a cross-service issue gets painful.

## Checklist when scaffolding a new service

- [ ] Error code enum defined (stable identifiers, not ad hoc strings)
- [ ] A known/user error type distinct from unexpected exceptions
- [ ] One boundary handler: known error → 4xx via `fail()`, anything else → log + generic 500
- [ ] `ok()` / `fail()` response envelope, used by every handler
- [ ] Structured (JSON) logger, env-driven log level
- [ ] Request/response logging with a propagated request/correlation id
- [ ] Sensitive-field redaction list kept in sync with actual payload fields
- [ ] Config/env validated at startup; crash loud and early if missing
- [ ] Timeouts on every outbound call (HTTP, RPC, DB)
- [ ] Health endpoint reflecting real dependency status
