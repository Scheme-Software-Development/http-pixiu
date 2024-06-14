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
                  (if (read-with input-port "\n" (- current-header-size (- (port-position input-port) origin-position)))
                    (let ([content-length (assq-ref environment "content-length: ")])
                      (if l
                        `(,@env (body . ,(read-with-length input-port l))
                        (raise status:bad-request)))
                      (loop (yield `(,@env ,(read-kv input-port (- (port-position input-port) origin-position current-header-size)))) l)))]
                [else (loop (yield `(,@env ,((car l)))) (cdr l))])))))]))

(define (read-kv input-port length)
  (let* ([origin-position (port-position input-port)]
      [k (string-downcase (read-to-space input-port length))]
      [current-position (port-position input-port)]
      [v (read-to-nextline input-port (- length (- current-position origin-position)))])
    `(,k . ,(string-trim-right v))))

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
        [(not (step-forward-with (current-output-port) input-port (string->list target-string) char=? length)) (raise status:bad-request)]))))

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
)