# http-pixiu — Agent Context

> Merged from all applicable `AGENTS.md` files. This file governs the project root and all subdirectories.

## Project Overview

- **Name**: http-pixiu
- **Version**: 1.0.3
- **Language**: Scheme (Chez Scheme)
- **License**: MIT
- **Author**: Wang Zheng
- **Package Manager**: [Akku](https://akkuscm.org/)
- **Repository**: https://github.com/Scheme-Software-Development/http-pixiu.git
- **Synopsis**: A lightweight HTTP server that treats HTTP requests as continuations, allowing direct responses without fully digesting the request body.

## Release History

| Version | Notes |
|---------|-------|
| 1.0.7 | Production hardening: vhosts, multirange, directory index, request body streaming, SO_SNDTIMEO slow-write protection, FD leak hardening (waitpid), gzip flush fix, graceful shutdown, config hot reload |
| 1.0.6 | Production optimizations: Linux sendfile zero-copy, in-memory LRU hot-file cache, per-phase socket timeouts (5s header / 30s response), access-log rotation with CLF/JSON formats, HTTP/1.1 Keep-Alive pipeline |
| 1.0.5 | Performance & security hardening: O(n²) → O(1) response headers, constant bytevector caching, SO_SNDTIMEO, duplicate header defense, null-byte path protection, error-page cache, ETag cache, MIME hashtable, Accept-Encoding cache, read-to-colon |
| 1.0.4 | Production features: ETag/304, rate limiting, CORS, error pages, health check, request tracing, gzip, ranges, chunked encoding, Nginx TLS docs |
| 1.0.3 | Add feature: yield among requests (tickal task queue with Chez engines) |
| 1.0.2 | Fix bug: `\r\n` compatibility |
| 1.0.1 | Fix bug: get body with coroutine |
| 1.0.0 | Initial release — static server only |

## Core Concepts

- **Continuation-based HTTP**: The server parses HTTP requests incrementally using coroutines. It can yield/resume among requests via Chez Scheme's `make-engine` mechanism.
- **Coroutine Parsing**: HTTP request/response parsing is done via `ufo-coroutines`. Parsers yield key-value pairs (method, uri, headers, body) one at a time.
- **Tickal Task Queue**: Requests are wrapped in `tickal-task` records and scheduled through a mutex/condition-variable queue. Tasks expire after a configurable duration.
- **Thread Pool**: A fixed-size thread pool (`ufo-thread-pool`) processes popped requests in a loop.

## Project Structure

```
http-pixiu.sls          ; Main library entry point — exports start-server
run.ss                  ; CLI launcher: scheme --script run.ss <port> [expire-ms] [ticks]
build.sh                ; Builds ufo-socket native objects into ./socket/
test.sh                 ; Runs all .sps test files under ./tests/

core/
  server.sls            ; server record-type, socket, log-port, thread-pool
core/
  client.sls            ; client record-type, socket-send, socket-receive
core/protocol/
  request-parse.sls     ; parse-request-coroutine, get-values-from-coroutine
core/protocol/
  request-construct.sls ; construct-request-string
core/protocol/
  response-construct.sls; write-response (status, headers, body-bytevector)
core/protocol/
  response-parse.sls    ; parse-response-coroutine
core/protocol/
  request-queue.sls     ; make-request-queue, request-queue-pop/push, tickal-task
core/protocol/
  status.sls            ; HTTP status code constants (200, 404, 408, 429, 500, etc.)
core/protocol/
  method.sls            ; HTTP method predicates/symbols (GET, POST, PUT, DELETE)
core/protocol/
  cors.sls              ; CORS preflight response and header injection
core/protocol/
  error-pages.sls       ; Custom error page loader and responder
core/protocol/
  logger.sls            ; Structured request/error logging with mutex
core/protocol/
  ratelimit.sls         ; Token-bucket rate limiter with per-key tracking
core/protocol/
  session.sls           ; Cookie/session store with TTL and mutex
core/
  cache.sls             ; In-memory LRU cache for small static files (<256KB)
core/ffi/
  sendfile.sls          ; Linux sendfile64 FFI wrapper for zero-copy socket output
core/
  config.sls            ; Default configuration alist and file loader
core/util/
  io.sls                ; read-lines, read-line, read-to-CRNL, write-lines, write-string
core/util/
  binary-read.sls       ; step-forward-to (read binary until target byte)
core/util/
  association.sls       ; assq-ref, assoc-ref, assv-ref, make-alist
core/util/
  date.sls              ; date->string (RFC-like date formatting)
core/util/
  form.sls              ; parse-form-urlencoded, string-split helpers

tests/
  core/protocol/test-request-parse.sps  ; Tests request coroutine parsing
tests/
  core/test-client.sps                  ; Tests HTTP client against baidu.com
tests/
  core/test-server.sps                  ; Tests server record creation
tests/resources/
  http-header                           ; Sample GET request for tests
tests/resources/
  http-header-with-body                 ; Sample POST request with body for tests

static/
  index.html            ; Default static file served by the example server

bin/
  http-pixiu.sps        ; Legacy/placeholder script (references non-existent hello fn)

llm-script/             ; Local-only LLM API client scripts (gitignored)
  client.sps            ; Example: POSTs to activity.scnet.cn LLM endpoint
```

## Build & Run

### Install dependencies
```bash
akku install
bash build.sh          # builds ufo-socket native code into ./socket/
bash .akku/env         # activate Akku environment
```

### Run the server
```bash
scheme --script run.ss <port> [expire-ms] [ticks]
# Example:
scheme --script run.ss 5000 1000 100000
```

- `expire-ms`: Request timeout in milliseconds (default: 1000)
- `ticks`: Chez Scheme engine ticks before yielding (default: 100000)

### Run tests
```bash
bash test.sh
```

## Key APIs

### `start-server` (from `http-pixiu`)
Case-lambda signatures:
- `(start-server port)`
- `(start-server port thread-num)`
- `(start-server port thread-num expire-duration ticks)`
- `(start-server port log-port thread-num expire-duration ticks)`

Default behavior: serves static files from the hardcoded path `./static` (`private-static-path`). The `init-lifecycle` handler reads the URI path, prepends the static path, and streams the file content back.

**Static file features:**
- **ETag / 304 Not Modified**: compares `If-None-Match` and `If-Modified-Since` against file mtime.
- **Range requests**: single-range (`206 Partial Content`) and multirange (`multipart/byteranges`) are supported.
- **HEAD**: returns headers without body; `Content-Length` and `ETag` are preserved.
- **gzip**: compresses text/json/javascript responses >128 bytes when `Accept-Encoding: gzip` is present.
- **Directory index**: if a directory has no `index.html`, an HTML listing is generated automatically.
- **Vhosts**: `Host` header is matched against `config` `vhosts` alist to select a per-domain `static-path`.
- **Method whitelist**: non-GET/HEAD/OPTIONS requests receive `405 Not Allowed`.

**Connection & lifecycle:**
- Per-connection Keep-Alive loop supports HTTP/1.1 pipelining up to 100 requests per connection.
- Header-read phase uses a 5-second socket timeout; response-write phase uses 30 seconds.
- `socket-set-timeout!` sets both `SO_RCVTIMEO` and `SO_SNDTIMEO` for slow-client protection.
- SIGINT triggers graceful shutdown (`stop-server`); SIGHUP reloads `config.scm` into `*current-config*`.
- `port` can be a raw output port or a `logger` record. When omitted, a rotating CLF logger is created automatically.

### Request Coroutine (`parse-request-coroutine`)
Returns a coroutine closure. Use `get-values-from-coroutine` to extract fields:
```scheme
(let ([c (parse-request-coroutine binary-input-port)])
  (let-values ([(c2 method) (get-values-from-coroutine c 'method)]
               [(c3 uri)    (get-values-from-coroutine c2 'uri)])
    ...))
```

**Body streaming:** When `Content-Length` exceeds the default 1MB `stream-threshold`, the coroutine yields `body` as the symbol `stream` instead of a bytevector. The connection handler wraps the underlying socket in a counting port (see `env-body-port`). If the handler does not consume the full body, the connection is closed automatically.

### Response Construction (`write-response`)
```scheme
(write-response binary-output-port status:ok '() body-bytevector)
```

**Zero-copy sendfile (Linux only):** When `body` is a `sendfile-body` record (from `(http-pixiu core ffi sendfile)`), `write-response` delegates to the `sendfile64` system call using the input file descriptor and output socket descriptor. Falls back to the user-space 64KB read/write loop on non-Linux or when the transfer is interrupted.

### Logging (`make-logger` from `http-pixiu core protocol logger`)
```scheme
(make-logger base-path format)   ; format: 'clf (default) or 'json
```
- **CLF** (Common Log Format): `client - - [date] "METHOD PATH PROTOCOL" status size "-" "user-agent"`
- **JSON**: `{"time":"...","client":"...","method":"...","path":"...","status":200,"size":1234}`
- Date-based rotation: when the day changes, a new file `base-path-YYYY-MM-DD.log` is opened automatically.

### In-Memory Hot-File Cache (`core/cache.sls`)
- LRU eviction (max 128 entries, 256KB per entry).
- Keys are file paths; entries store `(content etag mtime size last-access)`.
- `serve-static-file` automatically caches files ≤256KB and returns `304 Not Modified` when `If-None-Match` matches the cached ETag.

### Env Body Accessors (`core/handler.sls`)
```scheme
(env-body-string env)   ; bytevector -> string, or reads stream port -> string
(env-body-form env)     ; parses application/x-www-form-urlencoded body into alist
(env-body-port env)     ; returns an input port for the request body
```
For small bodies (`≤ 1MB`), `env-body-port` wraps the cached bytevector. For streamed bodies, it returns a custom port that reads directly from the socket and tracks consumed bytes.

### Error Handling in `init-lifecycle`
Inside the main request handler (`http-pixiu.sls`):
- `ufo-try` / `except` catches exceptions
- If the exception is a `number?`, it is treated as an HTTP status code and returned directly
- Any other exception returns `status:internal-server-error` (500)

## Dependencies (via Akku)

- `ufo-socket` — Socket wrapper (requires native build)
- `ufo-try` — Exception handling macros
- `ufo-thread-pool` — Thread pool implementation
- `ufo-coroutines` — Coroutine/yield mechanism
- `chibi uri` — URI parsing
- `chez-srfi` — SRFI compatibility for Chez Scheme
- `slib` — Queue utilities (used in `request-queue.sls`)

> **Note**: `llm-script/` contains user-specific scripts that call external APIs (including hardcoded API keys). This directory is listed in `.gitignore` (`llm-script/**`) and should not be committed.

## Important Constants

- `request-header-size`: 4 MiB
- `request-body-size`: 2 GiB
- `response-header-size`: 4 MiB
- `response-body-size`: 2 GiB
- `buff-size` (client receive): 1 MiB

## Coding Style

- Use `lambdas` with explicit brackets: `(lambda (x) ...)`
- Lists with backquote: `` `(,@env ,new-pair) ``
- Record types use `define-record-type` with immutable/mutable fields
- Error handling via `ufo-try`/`except` or `raise` with numeric status codes
- Binary I/O uses `bytevector` operations; text uses `utf8->string` / `string->utf8`

## Notes for Agents

- **Do not** modify `.akku/` or `socket/` directories manually; they are generated by `akku install` and `build.sh`.
- When adding new protocol modules, place them under `core/protocol/` and update imports in `http-pixiu.sls`.
- When adding new FFI modules, place them under `core/ffi/` and run `akku install` so that `.akku/lib/` symlinks are regenerated.
- Tests use SRFI-64 (`(srfi :64 testing)`). Add new `.sps` files under `tests/`; `test.sh` will pick them up automatically.
- The server currently only implements static file serving in the main library; dynamic handlers would need to modify `init-lifecycle` in `http-pixiu.sls`.
- `bin/http-pixiu.sps` appears to be a stale template (references `(hello "World")` which is not exported by the library). Prefer `run.ss` for launching the server.
- `.gitignore` ignores `llm-script/**`, `*.so`, `*.o`, `.akku/**`, `socket/`, and IDE artifacts.
