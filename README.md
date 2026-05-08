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
- **ETag / 304 Not Modified** — Static files emit ETags; conditional requests return `304` with no body.
- **Base headers** — Static file responses include `Accept-Ranges: bytes`, `Last-Modified`, and `Cache-Control: public, max-age=...`.
- **Trailing-slash redirect** — Directory URLs without a trailing `/` receive `301 Moved Permanently`.
- **Rate limiting** — Per-server token-bucket rate limiter (default: 1000 req/min); returns `429 Too Many Requests` when exceeded.
- **CORS preflight** — `OPTIONS` requests receive `204 No Content` with permissive CORS headers.
- **Custom error pages** — Looks for `<static-path>/error-{code}.html`; falls back to minimal HTML if absent.
- **Queue-full 503** — When the request queue is saturated, new connections receive `503 Service Unavailable` before being closed.
- **Health check endpoint** — `GET /health` returns `{"status":"ok"}`.
- **Request tracing** — Every response includes `X-Request-ID`.
- **Gzip compression** — Text responses ≤1 MiB are automatically gzip-compressed when client accepts it.
- **HTTP Range requests** — Supports `bytes=start-end` for `206 Partial Content`.
- **Chunked Transfer Encoding** — Request parser handles `Transfer-Encoding: chunked`.

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

### `serve-static-file`

```scheme
(serve-static-file static-path)
```

Returns a handler function `(lambda (env) ...)` that serves static files from `static-path` with caching, gzip, range requests, ETags, and base headers. Used internally by `start-server` when no custom handler is provided.

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

## TLS with Nginx Reverse Proxy

http-pixiu does not implement TLS natively. For production HTTPS, place Nginx in front as a reverse proxy:

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}
```

This preserves Keep-Alive, passes the original client IP via `X-Real-IP`, and terminates TLS before traffic reaches http-pixiu.

## License

MIT
