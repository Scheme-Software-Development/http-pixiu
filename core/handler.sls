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
    env-body-string
    env-body-form
    env-body-port

    make-env
    env-get)

  (import (chezscheme)
          (http-pixiu core util form)
          (only (srfi :13) string-contains))

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

  (define (env-body-string env)
    (let ([body (env-body env)])
      (cond
        [(bytevector? body) (utf8->string body)]
        [(eq? body 'stream)
         (let ([port (env-body-port env)])
           (if port
               (utf8->string (get-bytevector-all port))
               ""))]
        [else body])))

  (define (env-body-form env)
    (let ([content-type (assoc-ref (env-headers env) "content-type:")])
      (if (and content-type
               (string-contains (string-downcase content-type) "application/x-www-form-urlencoded"))
          (parse-form-urlencoded (env-body-string env))
          '())))

  (define (env-body-port env)
    (let ([body (env-body env)])
      (cond
        [(eq? body 'stream) (assq-ref env 'body-port)]
        [(bytevector? body) (open-bytevector-input-port body)]
        [else #f])))

  (define (assq-ref alist key)
    (let ([pair (assq key alist)])
      (if pair (cdr pair) #f)))

  (define (assoc-ref alist key)
    (let ([pair (assoc key alist)])
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
