(library (http-pixiu core handler)
  (export
    make-response
    response?
    response-status
    response-headers
    response-body

    response-size
    body-size

    env-method
    env-path
    env-headers
    env-query
    env-protocol
    env-body
    env-client-ip

    make-env
    env-get)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Response record: unified return type for handlers
  ;; ------------------------------------------------------------------
  (define-record-type response
    (fields status headers body))

  (define (body-size body)
    (cond
      [(bytevector? body) (bytevector-length body)]
      [(and (pair? body) (input-port? (car body)) (number? (cdr body))) (cdr body)]
      [else 0]))

  (define (response-size r)
    (body-size (response-body r)))

  ;; ------------------------------------------------------------------
  ;; Env accessors
  ;; ------------------------------------------------------------------
  (define (env-get env key) (assq-ref env key))
  (define (env-method env)   (assq-ref env 'method))
  (define (env-path env)     (assq-ref env 'path))
  (define (env-headers env)  (assq-ref env 'headers))
  (define (env-query env)    (assq-ref env 'query))
  (define (env-protocol env) (assq-ref env 'protocol))
  (define (env-body env)     (assq-ref env 'body))
  (define (env-client-ip env) (assq-ref env 'client-ip))

  (define (assq-ref alist key)
    (let ([pair (assq key alist)])
      (if pair (cdr pair) #f)))

  ;; ------------------------------------------------------------------
  ;; Convenience constructor for env alist
  ;; ------------------------------------------------------------------
  (define (make-env method uri path query protocol headers body client-ip)
    `((method . ,method)
      (uri . ,uri)
      (path . ,path)
      (query . ,query)
      (protocol . ,protocol)
      (headers . ,headers)
      (body . ,body)
      (client-ip . ,client-ip)))

)
