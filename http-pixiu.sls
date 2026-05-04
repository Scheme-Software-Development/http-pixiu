(library (http-pixiu)
  (export start-server
          write-response
          write-json-response
          write-text-response
          write-html-response
          assoc-ref)
  (import 
    (chezscheme)

    (http-pixiu core server)
    (http-pixiu core protocol request-parse)
    (http-pixiu core protocol request-queue)
    (http-pixiu core protocol response-construct)
    (http-pixiu core protocol status)
    (http-pixiu core util io)
    (http-pixiu core util association)
    (http-pixiu core mime)

    (chibi uri)
    (ufo-socket)
    (ufo-try)
    (ufo-thread-pool))

(define private-static-path "./static")

(define (safe-path? uri-path)
  (define (check-double-dot s i)
    (and (< (+ i 2) (string-length s))
         (char=? (string-ref s i) #\.)
         (char=? (string-ref s (+ i 1)) #\.)
         (or (zero? i)
             (char=? (string-ref s (- i 1)) #\/))))
  (let ([full (string-append private-static-path uri-path)])
    (let loop ([i 0])
      (cond
        [(>= i (string-length full)) #t]
        [(check-double-dot full i) #f]
        [else (loop (+ i 1))]))))

(define (consume-coroutine closure)
  (let-values ([(resume val) (closure)])
    (if resume
        (consume-coroutine (lambda () (resume val)))
        val)))

(define (build-request-env closure method uri-str)
  (let ([full-result (consume-coroutine closure)])
    (let ([protocol (assq-ref full-result 'protocol)]
          [body-pair (assq 'body full-result)]
          [headers (filter (lambda (p) (string? (car p))) full-result)])
      (let ([uri (string->path-uri 'http uri-str)])
        `((method . ,method)
          (uri . ,uri-str)
          (path . ,(uri-path uri))
          (query . ,(guard (ex [#t #f]) (uri-query uri)))
          (protocol . ,protocol)
          (headers . ,headers)
          (body . ,(if body-pair (cdr body-pair) #f)))))))

(define (init-lifecycle socket handler)
  (lambda ()
    (call-with-socket socket
      (lambda (socket)
        (try 
          (let* ([binary-input-port (socket-input-port socket)]
                 [binary-output-port (socket-output-port socket)]
                 [closure (parse-request-coroutine binary-input-port)])
            (let*-values ([(closure0 method) (get-values-from-coroutine closure 'method)]
                          [(closure1 target-string) (get-values-from-coroutine closure0 'uri)])
              (let* ([uri (string->path-uri 'http target-string)]
                     [path (uri-path uri)])
                (if (and handler 
                         (handler (build-request-env closure1 method target-string) binary-output-port))
                    'handler-done
                    (if (not (safe-path? path))
                        (write-response binary-output-port status:forbidden '() '())
                        (let ([local (string-append private-static-path path)])
                          (let ([fip (open-file-input-port local)])
                            (let ([body (get-bytevector-all fip)]
                                  [content-type (guess-mime-type path)])
                              (write-response binary-output-port status:ok 
                                `(("Content-Type" . ,content-type)) body
                                (not (equal? method "HEAD"))))))))))
          (except c
            [(number? c) (write-response (socket-output-port socket) c '() '())]
            [else (write-response (socket-output-port socket) status:not-found '() '())]))))))

; ms
(define expire-duration 1000)
(define ticks 100000)

(define start-server
  (case-lambda 
    [(port) (start-server port (current-output-port) 1 expire-duration ticks #f)]
    [(port thread-num) (start-server port (current-output-port) thread-num expire-duration ticks #f)]
    [(port thread-num expire-duration ticks) (start-server port (current-output-port) thread-num expire-duration ticks #f)]
    [(port log-port thread-num expire-duration ticks) (start-server port log-port thread-num expire-duration ticks #f)]
    [(port log-port thread-num expire-duration ticks handler)
      (let* ([thread-pool (init-thread-pool thread-num)]
             [request-queue (make-request-queue)]
             [server (make-server port log-port thread-pool)])
        (map 
          (lambda (i)
            (thread-pool-add-job thread-pool 
              (lambda () 
                (let loop ()
                  ((request-queue-pop request-queue))
                  (loop))))) 
          (iota thread-num))
        (display "Http-pixiu is working!")
        (newline)
        (let loop ([received-socket (socket-accept (server-socket server))])
          (request-queue-push request-queue (init-lifecycle received-socket handler) expire-duration ticks)
          (loop (socket-accept (server-socket server)))))]))

