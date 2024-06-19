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
    (http-pixiu core util conditional-port-read)
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
    [(input-textual-port input-binary-port) (parse-request-coroutine input-textual-port input-binary-port request-header-size request-body-size)]
    [(input-textual-port input-binary-port current-header-size current-body-size)
      (let ([origin-position (port-position input-textual-port)])
        (init-coroutine
          (lambda (yield)
            (let loop ([env '()]
                [l 
                  (list
                    (lambda () `(method . ,(string-trim-right (read-to-space input-textual-port (- current-header-size (- (port-position input-textual-port) origin-position))))))
                    (lambda () `(uri . ,(string-trim-right (read-to-space input-textual-port (- current-header-size (- (port-position input-textual-port) origin-position))))))
                    (lambda () `(protocol . ,(string-trim-right (read-to-nextline input-textual-port (- current-header-size (- (port-position input-textual-port) origin-position)))))))])
              (cond 
                [(> (- (port-position input-textual-port) origin-position current-header-size) 0)
                  (raise status:bad-request)]
                [(null? l) 
                  (cond 
                    [(eof-object? (peek-char input-textual-port)) env]
                    [(char=? (peek-char input-textual-port) #\newline)
                      (let ([new-env `(,@env (should-has-body? . #t))]
                          [content-length (find (lambda (pair) (equal? "content-length:" (string-downcase (car pair)))) env)])
                        (cond 
                          [(not content-length) (raise status:bad-request)]
                          [(> content-length current-body-size) (raise status:bad-request)]
                          [else `(,@new-env (body . ,(get-bytevector-n input-binary-port content-length)))]))]
                    [else (loop (yield `(,@env ,(read-kv input-textual-port (- current-header-size (- (port-position input-textual-port) origin-position))))) l)])]
                [else (loop (yield `(,@env ,((car l)))) (cdr l))])))))]))

(define (read-kv input-textual-port length)
  (let* ([origin-position (port-position input-textual-port)]
      [k (string-downcase (read-to-space input-textual-port length))]
      [current-position (port-position input-textual-port)]
      [v (read-to-nextline/eof input-textual-port (- length (- current-position origin-position)))])
    `(,(string-trim-right k) . ,(string-trim-right v))))

(define (read-with input-textual-port target-string length)
  (with-output-to-string 
    (lambda ()
      (cond 
        [(> (string-length target-string) length) (raise status:bad-request)]
        [(not (step-forward-with (current-output-port) input-textual-port (string->list target-string) ignore-case-char=?)) 
          (raise status:bad-request)]))))

(define (read-to-space input-textual-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-textual-port (string->list " ") char=? length))
        (raise status:bad-request)))))

(define (read-to-nextline input-textual-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-textual-port (string->list "\n") char=? length))
        (raise status:bad-request)))))

(define (read-to-nextline/eof input-textual-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-textual-port (string->list "\n") char=? length))
        (if (not (eof-object? (peek-char input-textual-port)))
          (raise status:bad-request))))))
)