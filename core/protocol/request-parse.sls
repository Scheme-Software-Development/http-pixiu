(library (http-pixiu core protocol request-parse)
  (export parse-request-coroutine)
  (import 
    (chezscheme)
    (ufo-coroutines)
    (http-pixiu core protocol status)
    (http-pixiu core util conditional-port-read)
    (http-pixiu core util association)
    (only (srfi :13) string-trim-right))

;4kiB
(define request-header-size (* 4 1024 1024))

(define parse-request-coroutine 
  (case-lambda 
    [(input-port) (parse-request-coroutine input-port request-header-size)]
    [(input-port current-header-size)
      (let ([origin-position (port-position input-port)])
        (init-coroutine
          (lambda (yield)
            (let loop ([env '()]
                [l 
                  (list
                    (lambda () `(method . ,(string-trim-right (read-to-space input-port (- current-header-size (- (port-position input-port) origin-position))))))
                    (lambda () `(uri . ,(string-trim-right (read-to-space input-port (- current-header-size (- (port-position input-port) origin-position))))))
                    (lambda () `(protocol . ,(string-trim-right (read-to-nextline input-port (- current-header-size (- (port-position input-port) origin-position)))))))])
              (cond 
                [(> (- (port-position input-port) origin-position current-header-size) 0)
                  (raise status:bad-request)]
                [(null? l) 
                  (cond 
                    [(eof-object? (peek-char input-port)) env]
                    [(char=? (peek-char input-port) #\newline)
                      (let ([content-length (assq-ref env "content-length:")])
                        (if content-length
                          `(,@env (body . ,(read-with-length input-port content-length)))
                          (raise status:bad-request)))]
                    [else (loop (yield `(,@env ,(read-kv input-port (- current-header-size (- (port-position input-port) origin-position))))) l)])]
                [else (loop (yield `(,@env ,((car l)))) (cdr l))])))))]))

(define (read-kv input-port length)
  (let* ([origin-position (port-position input-port)]
      [k (string-downcase (read-to-space input-port length))]
      [current-position (port-position input-port)]
      [v (read-to-nextline/eof input-port (- length (- current-position origin-position)))])
    `(,(string-trim-right k) . ,(string-trim-right v))))

(define (read-with-length input-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-with-length (current-output-port) input-port length))
        (raise status:bad-request)))))

(define (read-with input-port target-string length)
  (with-output-to-string 
    (lambda ()
      (cond 
        [(> (string-length target-string) length) (raise status:bad-request)]
        [(not (step-forward-with (current-output-port) input-port (string->list target-string) ignore-case-char=?)) 
          (raise status:bad-request)]))))

(define (read-to-space input-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-port (string->list " ") char=? length))
        (raise status:bad-request)))))

(define (read-to-nextline input-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-port (string->list "\n") char=? length))
        (raise status:bad-request)))))

(define (read-to-nextline/eof input-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-port (string->list "\n") char=? length))
        (if (not (eof-object? (peek-char input-port)))
          (raise status:bad-request))))))
)