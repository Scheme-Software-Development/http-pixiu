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
  status.sls            ; HTTP status code constants (200, 404, 408, 500, etc.)
core/protocol/
  method.sls            ; HTTP method predicates/symbols (GET, POST, PUT, DELETE)
core/util/
  io.sls                ; read-lines, read-line, read-to-CRNL, write-lines, write-string
core/util/
  binary-read.sls       ; step-forward-to (read binary until target byte)
core/util/
  association.sls       ; assq-ref, assoc-ref, assv-ref, make-alist
core/util/
  date.sls              ; date->string (RFC-like date formatting)

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

Default behavior: serves static files from the hardcoded path `./static` (`private-static-path`). Only static file serving is implemented; the `init-lifecycle` handler reads the URI path, prepends `./static`, and streams the file content back.

### Request Coroutine (`parse-request-coroutine`)
Returns a coroutine closure. Use `get-values-from-coroutine` to extract fields:
```scheme
(let ([c (parse-request-coroutine binary-input-port)])
  (let-values ([(c2 method) (get-values-from-coroutine c 'method)]
               [(c3 uri)    (get-values-from-coroutine c2 'uri)])
    ...))
```

### Response Construction (`write-response`)
```scheme
(write-response binary-output-port status:ok '() body-bytevector)
```

### Error Handling in `init-lifecycle`
Inside the main request handler (`http-pixiu.sls`):
- `ufo-try` / `except` catches exceptions
- If the exception is a `number?`, it is treated as an HTTP status code and returned directly
- Any other exception returns `status:not-found` (404)

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
- Tests use SRFI-64 (`(srfi :64 testing)`). Add new `.sps` files under `tests/`; `test.sh` will pick them up automatically.
- The server currently only implements static file serving in the main library; dynamic handlers would need to modify `init-lifecycle` in `http-pixiu.sls`.
- `bin/http-pixiu.sps` appears to be a stale template (references `(hello "World")` which is not exported by the library). Prefer `run.ss` for launching the server.
- `.gitignore` ignores `llm-script/**`, `*.so`, `*.o`, `.akku/**`, `socket/`, and IDE artifacts.
