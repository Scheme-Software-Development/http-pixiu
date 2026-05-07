(library (http-pixiu core middleware)
  (export
    compose-middlewares
    wrap-handler

    cors-middleware
    ratelimit-middleware
    session-middleware
    logging-middleware
    error-page-middleware)

  (import (chezscheme)
          (http-pixiu core handler)
          (http-pixiu core protocol status)
          (http-pixiu core protocol cors)
          (http-pixiu core protocol ratelimit)
          (http-pixiu core protocol session)
          (http-pixiu core protocol logger)
          (http-pixiu core protocol error-pages)
          (http-pixiu core util association))

  ;; ------------------------------------------------------------------
  ;; Middleware: (handler → handler)
  ;; A handler is (env → response)
  ;; ------------------------------------------------------------------

  (define (compose-middlewares . middlewares)
    (lambda (handler)
      (let loop ([ms (reverse middlewares)] [h handler])
        (if (null? ms)
            h
            (loop (cdr ms) ((car ms) h))))))

  ;; Wrap a plain handler so that a #f status falls through to the
  ;; next handler in the chain.
  (define (wrap-handler user-handler default-handler)
    (lambda (env)
      (let ([result (user-handler env)])
        (if (and (response? result) (response-status result))
            result
            (default-handler env)))))

  ;; ------------------------------------------------------------------
  ;; CORS middleware
  ;; ------------------------------------------------------------------
  (define (cors-middleware allow-origin)
    (lambda (handler)
      (lambda (env)
        (if (equal? (env-method env) "OPTIONS")
            (make-response status:no-content
              `(("Access-Control-Allow-Origin" . ,allow-origin)
                ("Access-Control-Allow-Methods" . "GET, POST, PUT, DELETE, OPTIONS, HEAD")
                ("Access-Control-Allow-Headers" . "Content-Type, Authorization")
                ("Access-Control-Max-Age" . "86400"))
              '())
            (let ([resp (handler env)])
              (make-response (response-status resp)
                (cons (cons "Access-Control-Allow-Origin" allow-origin)
                      (response-headers resp))
                (response-body resp)))))))

  ;; ------------------------------------------------------------------
  ;; Rate limit middleware
  ;; ------------------------------------------------------------------
  (define (ratelimit-middleware limiter)
    (lambda (handler)
      (lambda (env)
        (let ([client-id (or (env-client-ip env) "unknown")])
          (if (rate-limiter-allow? limiter client-id)
              (handler env)
              (make-response status:too-many-requests
                '(("Content-Type" . "text/plain"))
                (string->utf8 "Rate limit exceeded")))))))

  ;; ------------------------------------------------------------------
  ;; Session middleware
  ;; ------------------------------------------------------------------
  (define (session-middleware store)
    (lambda (handler)
      (lambda (env)
        (let* ([cookie-header (assoc-ref (env-headers env) "cookie:")]
               [cookies (if cookie-header
                            (parse-cookie-header cookie-header)
                            '())]
               [session-id (or (assoc-ref cookies "session-id") #f)]
               [session-data (if session-id
                                 (session-get store session-id)
                                 '())]
               [env-with-session (cons (cons 'session session-data) env)])
          (let ([resp (handler env-with-session)])
            ;; TODO: if session was modified, set new cookie
            resp)))))

  ;; ------------------------------------------------------------------
  ;; Logging middleware
  ;; ------------------------------------------------------------------
  (define (logging-middleware log-port)
    (lambda (handler)
      (lambda (env)
        (let ([start (current-time)])
          (let ([resp (handler env)])
            (let ([elapsed (time-difference (current-time) start)])
              (log-request
                log-port
                (env-method env)
                (env-path env)
                (response-status resp)
                (response-size resp)
                (env-protocol env)
                (env-client-ip env)
                (assoc-ref (env-headers env) "user-agent:"))
              resp))))))

  ;; ------------------------------------------------------------------
  ;; Error page middleware
  ;; ------------------------------------------------------------------
  (define (error-page-middleware static-path)
    (lambda (handler)
      (lambda (env)
        (let ([resp (handler env)])
          (let ([status (response-status resp)])
            (if (and status (>= status 400))
                (let ([err-body (load-error-page static-path status)])
                  (make-response status
                    (response-headers resp)
                    err-body))
                resp))))))

)
