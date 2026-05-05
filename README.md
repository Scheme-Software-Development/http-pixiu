# Http-pixiu

> Target: Regarding HTTP requests as continuations, http-pixiu can directly respond without fully digesting the request body.

A lightweight continuation-based HTTP server written in Chez Scheme (R6RS).

## Features

- **Continuation-based parsing** — HTTP requests are parsed incrementally via coroutines, allowing early response.
- **Keep-Alive** — HTTP/1.1 persistent connections with automatic `Connection` header handling.
- **Streaming static files** — Large files are streamed without loading into memory.
- **HEAD support** — Efficient HEAD responses with correct `Content-Length` and no body.
- **Index fallback** — Directory paths automatically serve `index.html`.
- **Path traversal protection** — Blocks `..` escapes, returns `403 Forbidden`.
- **Custom handler** — Programmable request handlers via `start-server`.
- **Tickal task queue** — Request scheduling with Chez Scheme engines and configurable timeout.
- **Thread pool** — Fixed-size worker thread pool for concurrent request handling.

## Install

```bash
akku install
bash build.sh
bash .akku/env
```

## Run

### Basic (static file server)

```bash
scheme --script run.ss 5000
```

Then in another shell:

```bash
curl -i localhost:5000/index.html
```

### With options

```bash
scheme --script run.ss <port> [thread-num] [expire-ms] [ticks]
```

Example:

```bash
scheme --script run.ss 5000 4 1000 100000
```

- `port` — Listening port (required)
- `thread-num` — Worker thread count (default: 1)
- `expire-ms` — Request timeout in milliseconds (default: 1000)
- `ticks` — Chez Scheme engine ticks before yielding (default: 100000)

> Note: Chez Scheme counts non-leaf S-expression executions. When the tick limit is reached, the task re-enters the queue to allow other threads to continue.

## API

### `start-server`

```scheme
(start-server port)
(start-server port thread-num)
(start-server port thread-num expire-duration ticks)
(start-server port log-port thread-num expire-duration ticks)
(start-server port log-port thread-num expire-duration ticks handler)
(start-server port log-port thread-num expire-duration ticks handler static-path)
```

Returns a `(server . request-queue)` pair.

- `handler` — `(lambda (env out-port) ...)`  Return `#t` if handled; `#f` to fall through to static file serving.
- `static-path` — Root directory for static files (default: `"./static"`).

Example with custom handler:

```scheme
(import (chezscheme) (http-pixiu))

(define (my-handler env out)
  (let ([path (assoc-ref env 'path)])
    (if (equal? path "/api/hello")
        (begin
          (write-json-response out status:ok '() "{\"msg\":\"hi\"}")
          #t)
        #f)))

(start-server 5000 (current-output-port) 4 1000 100000 my-handler "./static")
```

### `stop-server`

```scheme
(stop-server server request-queue)
(stop-server server request-queue connect-port)
```

Gracefully shuts down the server. If `connect-port` is provided, a dummy connection is made to unblock the accept loop.

### `write-response`

```scheme
(write-response out status-id headers body)
(write-response out status-id headers body send-body?)
(write-response out status-id headers body send-body? keep-alive?)
```

`body` can be:
- `string` — UTF-8 encoded
- `bytevector` — Raw bytes
- `(cons input-port size)` — Streamed from an open input port

Convenience wrappers:
- `write-json-response`
- `write-text-response`
- `write-html-response`

### `connection-close?`

```scheme
(connection-close? headers protocol)
```

Returns `#t` if the connection should be closed after this request.

### `safe-path?`

```scheme
(safe-path? static-path uri-path)
```

Returns `#t` if `uri-path` does not escape `static-path` via `..`.

## Tests

```bash
bash test.sh
```

Runs all `.sps` test files under `tests/`.

## Release History

| Version | Notes |
|---------|-------|
| 1.0.3 | Add feature: yield among requests (tickal task queue with Chez engines) |
| 1.0.2 | Fix bug: `\r\n` compatibility |
| 1.0.1 | Fix bug: get body with coroutine |
| 1.0.0 | Initial release — static server only |

## License

MIT
