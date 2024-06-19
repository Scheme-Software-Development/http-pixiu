(library (http-pixiu core protocol request-parse)
  (export 
    parse-request-coroutine
    get-values-from-coroutine 

    request-header-size
    request-body-size)
  (import 
    (chezscheme)
    (ufo-coroutines)
    (http-pixiu core protocol status)
    (http-pixiu core util try)
    (http-pixiu core util binary-read)
    (http-pixiu core util association)
    (only (srfi :13) string-trim-right))

;4kiB
(define request-header-size (* 4 1024 1024))
;2miB
(define request-body-size (* 2 1024 1024 1024))

(define (get-values-from-coroutine closure key)
  (let-values ([(resume val) (closure)])
    (if resume 
      (if (assoc-ref val key)
        (values (lambda () (resume val)) (assoc-ref val key))
        (get-values-from-coroutine (lambda () (resume val)) key))
      (values (lambda () (values resume val)) (assoc-ref val key)))))

(define parse-request-coroutine 
  (case-lambda 
    [(input-binary-port) (parse-request-coroutine input-binary-port request-header-size request-body-size)]
    [(input-binary-port current-header-size current-body-size)
      (let ([origin-position (port-position input-binary-port)])
        (init-coroutine
          (lambda (yield)
            (let loop ([env '()]
                [l 
                  (list
                    (lambda () `(method . ,(string-trim-right (read-to-space input-binary-port (- current-header-size (- (port-position input-binary-port) origin-position))))))
                    (lambda () `(uri . ,(string-trim-right (read-to-space input-binary-port (- current-header-size (- (port-position input-binary-port) origin-position))))))
                    (lambda () `(protocol . ,(string-trim-right (read-to-nextline/eof input-binary-port (- current-header-size (- (port-position input-binary-port) origin-position)))))))])
              (try 
                (if (null? l) 
                  (cond 
                    [(eof-object? (lookahead-u8 input-binary-port)) env]
                    [(= (lookahead-u8 input-binary-port) (char->integer #\newline))
                      (let ([new-env `(,@env (should-has-body? . #t))]
                          [content-length (find (lambda (pair) (equal? "content-length:" (string-downcase (car pair)))) env)])
                        (cond 
                          [(not content-length) (raise status:bad-request)]
                          [(> content-length current-body-size) (raise status:bad-request)]
                          [else `(,@new-env (body . ,(get-bytevector-n input-binary-port content-length)))]))]
                    [else (loop (yield `(,@env ,(read-kv input-binary-port (- current-header-size (- (port-position input-binary-port) origin-position))))) l)])
                  (loop (yield `(,@env ,((car l)))) (cdr l)))
                (except e
                  [else (raise status:bad-request)]))))))]))

(define (read-kv input-binary-port length)
  (let* ([origin-position (port-position input-binary-port)]
      [k (string-downcase (read-to-space input-binary-port length))]
      [current-position (port-position input-binary-port)]
      [v (read-to-nextline/eof input-binary-port (- length (- current-position origin-position)))])
    `(,(string-trim-right k) . ,(string-trim-right v))))

(define (read-to-space input-binary-port length)
  (utf8->string 
    (call-with-bytevector-output-port
      (lambda (output-port)
        (if (not (step-forward-to output-port input-binary-port (char->integer #\space) length))
          (raise status:bad-request))))))

(define (read-to-nextline/eof input-binary-port length)
  (utf8->string 
    (call-with-bytevector-output-port
      (lambda (output-port)
        (if (not (step-forward-to output-port input-binary-port (char->integer #\newline) length))
          (if (not (eof-object? (lookahead-u8 input-binary-port)))
            (raise status:bad-request)))))))
)