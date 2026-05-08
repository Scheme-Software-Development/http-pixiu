(library (http-pixiu core protocol request-parse)
  (export 
    parse-request-coroutine
    get-values-from-coroutine 

    request-header-size
    request-body-size)
  (import 
    (chezscheme)
    (ufo-coroutines)
    (ufo-try)
    (http-pixiu core protocol status)
    (http-pixiu core util binary-read)
    (http-pixiu core util association)
    (only (srfi :13) string-trim-right string-trim-both))

;4kiB
(define request-header-size (* 4 1024 1024))
;2miB
(define request-body-size (* 2 1024 1024 1024))
(define max-request-line-length 8192)
(define max-header-lines 100)
(define max-header-name-length 1024)
(define max-header-value-length 8192)

(define (get-values-from-coroutine closure key)
  (let-values ([(resume val) (closure)])
    (if resume 
      (if (assoc-ref val key)
        (values (lambda () (resume val)) (assoc-ref val key))
        (get-values-from-coroutine (lambda () (resume val)) key))
      (values (lambda () (values resume val)) (assoc-ref val key)))))

(define parse-request-coroutine 
  (case-lambda 
    [(input-binary-port) (parse-request-coroutine input-binary-port request-header-size request-body-size (* 1024 1024))]
    [(input-binary-port current-header-size) (parse-request-coroutine input-binary-port current-header-size request-body-size (* 1024 1024))]
    [(input-binary-port current-header-size current-body-size) (parse-request-coroutine input-binary-port current-header-size current-body-size (* 1024 1024))]
    [(input-binary-port current-header-size current-body-size stream-threshold)
      (init-coroutine
        (lambda (yield)
          (let loop ([env '()]
              [l 
                (list
                  `(method . ,(lambda (current-remain-length) (read-to-space input-binary-port (min max-request-line-length current-remain-length))))
                  `(uri . ,(lambda (current-remain-length) (read-to-space input-binary-port (min max-request-line-length current-remain-length))))
                  `(protocol . ,(lambda (current-remain-length) (read-to-nextline/eof input-binary-port (min max-request-line-length current-remain-length)))))]
              [remain-length current-header-size]
              [header-count 0])
            (if (null? l) 
              (cond 
                [(eof-object? (lookahead-u8 input-binary-port)) env]
                [(or 
                  (= (lookahead-u8 input-binary-port) (char->integer #\return))
                  (= (lookahead-u8 input-binary-port) (char->integer #\newline)))
                  (read-to-nextline/eof input-binary-port 2)
                  (let ([method (assoc-ref env 'method)]
                      [new-env `(,@env (should-has-body? . #t))]
                      [content-length (assoc-ref env "content-length:")]
                      [transfer-encoding (assoc-ref env "transfer-encoding:")])
                    (cond
                      [(and (not content-length)
                            (or (equal? method "GET")
                                (equal? method "HEAD")
                                (equal? method "DELETE")
                                (equal? method "OPTIONS")
                                (equal? method "TRACE")))
                       env]
                      [(and transfer-encoding
                            (equal? (string-trim-both transfer-encoding) "chunked"))
                       `(,@new-env (body . ,(read-chunked-body input-binary-port current-body-size)))]
                      [(not content-length) (raise status:bad-request)]
                      [else
                       (let ([n (guard (ex [#t #f]) (string->number content-length))])
                         (cond
                           [(or (not n) (not (integer? n)) (< n 0)) (raise status:bad-request)]
                           [(> n current-body-size) (raise status:bad-request)]
                           [(> n stream-threshold)
                            `(,@new-env (body . stream) (content-length . ,n))]
                           [else `(,@new-env (body . ,(get-bytevector-n input-binary-port n)))]))]))]
                [else 
                  (if (>= header-count max-header-lines)
                    (raise status:bad-request)
                    (let-values ([(new-pair newest-remain-length) (read-kv input-binary-port remain-length)])
                      (loop (yield `(,@env ,new-pair)) '() newest-remain-length (+ header-count 1))))])
              (let ([limit (min max-request-line-length remain-length)])
                (let-values ([(target-string newest-remain-length) ((cdr (car l)) limit)])
                  (let ([consumed (- limit newest-remain-length)])
                    (loop 
                      (yield `(,@env (,(car (car l)) . ,(string-trim-right target-string)))) 
                      (cdr l)
                      (- remain-length consumed)
                      header-count))))))))]))

(define (read-kv input-binary-port length)
  (let*-values ([(k consumed-length) (read-to-space input-binary-port length)])
    (if (> (string-length k) max-header-name-length)
      (raise status:bad-request)
      (let-values ([(v final-consumed-length) (read-to-nextline/eof input-binary-port (- length consumed-length))])
        (if (> (string-length v) max-header-value-length)
          (raise status:bad-request)
          (values `(,(string-trim-right (string-downcase k)) . ,(string-trim-right v)) (- length final-consumed-length)))))))

(define (read-to-space input-binary-port length)
  (let ([bytevector
        (call-with-bytevector-output-port
          (lambda (output-port)
            (if (not (step-forward-to output-port input-binary-port (char->integer #\space) length))
              (raise status:bad-request))))])
    (values (utf8->string bytevector) (- length (bytevector-length bytevector)))))

(define (read-to-nextline/eof input-binary-port length)
  (let ([bytevector 
        (call-with-bytevector-output-port
          (lambda (output-port)
            (if (not (step-forward-to output-port input-binary-port (char->integer #\newline) length))
              (if (not (eof-object? (lookahead-u8 input-binary-port)))
                (raise status:bad-request)))))])
    (values (utf8->string bytevector) (- length (bytevector-length bytevector)))))

(define (read-chunked-body input-binary-port max-size)
  (let-values (((out get-bv) (open-bytevector-output-port)))
    (let ((line-limit 1024))
    (let loop ((total-size 0))
      (let-values (((size-line _) (read-to-nextline/eof input-binary-port line-limit)))
        (let* ((trimmed (string-trim-right size-line))
               (semi (let find-semi ((i 0))
                       (cond
                         ((>= i (string-length trimmed)) #f)
                         ((char=? (string-ref trimmed i) #\;) i)
                         (else (find-semi (+ i 1))))))
               (hex-str (if semi (substring trimmed 0 semi) trimmed))
               (size (guard (ex (#t #f)) (string->number hex-str 16))))
          (cond
            ((or (not size) (not (integer? size)) (< size 0))
             (raise status:bad-request))
            ((zero? size)
             (read-to-nextline/eof input-binary-port line-limit)
             (get-bv))
            ((> (+ total-size size) max-size)
             (raise status:bad-request))
            (else
             (let ((chunk (get-bytevector-n input-binary-port size)))
               (if (or (not chunk) (eof-object? chunk) (< (bytevector-length chunk) size))
                   (raise status:bad-request)
                   (begin
                     (put-bytevector out chunk)
                     (read-to-nextline/eof input-binary-port line-limit)
                     (loop (+ total-size size)))))))))))))
)