(library (http-pixiu core protocol response-parse)
  (export 
    parse-response-coroutine)
  (import 
    (chezscheme)
    (ufo-coroutines)
    (http-pixiu core protocol status)
    (http-pixiu core util binary-read)
    (http-pixiu core util association)
    (only (srfi :13) string-trim-right))

;4kiB
(define response-header-size (* 4 1024 1024))
;2miB
(define response-body-size (* 2 1024 1024 1024))

(define (get-values-from-coroutine closure key)
  (let-values ([(resume val) (closure)])
    (if resume 
      (if (assoc-ref val key)
        (values (lambda () (resume val)) (assoc-ref val key))
        (get-values-from-coroutine (lambda () (resume val)) key))
      (values (lambda () (values resume val)) (assoc-ref val key)))))

(define parse-response-coroutine 
  (case-lambda 
    [(input-binary-port) (parse-response-coroutine input-binary-port response-header-size response-body-size)]
    [(input-binary-port current-header-size current-body-size)
      (init-coroutine
        (lambda (yield)
          (let loop ([env '()]
              [l 
                (list
                  `(version . ,(lambda (current-remain-length) (read-to-space input-binary-port current-remain-length)))
                  `(status . ,(lambda (current-remain-length) (read-to-space input-binary-port current-remain-length)))
                  `(description . ,(lambda (current-remain-length) (read-to-nextline/eof input-binary-port current-remain-length))))]
              [remain-length current-header-size])
            (if (null? l) 
              (cond 
                [(eof-object? (lookahead-u8 input-binary-port)) env]
                [(or 
                  (= (lookahead-u8 input-binary-port) (char->integer #\return))
                  (= (lookahead-u8 input-binary-port) (char->integer #\newline)))
                  (read-to-nextline/eof input-binary-port 2)
                  (let ([new-env `(,@env (should-has-body? . #t))]
                      [content-length (assoc-ref env "content-length:")])
                    (cond 
                      [(not content-length) (raise 'status:bad-response)]
                      [(> (string->number content-length) current-body-size) (raise 'status:bad-response)]
                      [else `(,@new-env (body . ,(get-bytevector-n input-binary-port (string->number content-length))))]))]
                [else 
                  (let-values ([(new-pair newest-remain-length) (read-kv input-binary-port remain-length)])
                    (loop (yield `(,@env ,new-pair)) '() newest-remain-length))])
              (let-values ([(target-string newest-remain-length) ((cdr (car l)) remain-length)])
                (loop 
                  (yield `(,@env (,(car (car l)) . ,(string-trim-right target-string)))) 
                  (cdr l)
                  newest-remain-length))))))]))

(define (read-kv input-binary-port length)
  (let*-values ([(k consumed-length) (read-to-space input-binary-port length)]
      [(v final-consumed-length) (read-to-nextline/eof input-binary-port (- length consumed-length))])
    (values `(,(string-trim-right (string-downcase k)) . ,(string-trim-right v)) (- length final-consumed-length))))

(define (read-to-space input-binary-port length)
  (let ([bytevector
        (call-with-bytevector-output-port
          (lambda (output-port)
            (if (not (step-forward-to output-port input-binary-port (char->integer #\space) length))
              (raise 'status:bad-response))))])
    (values (utf8->string bytevector) (- length (bytevector-length bytevector)))))

(define (read-to-nextline/eof input-binary-port length)
  (let ([bytevector 
        (call-with-bytevector-output-port
          (lambda (output-port)
            (if (not (step-forward-to output-port input-binary-port (char->integer #\newline) length))
              (if (not (eof-object? (lookahead-u8 input-binary-port)))
                (raise 'status:bad-response)))))])
    (values (utf8->string bytevector) (- length (bytevector-length bytevector)))))
)