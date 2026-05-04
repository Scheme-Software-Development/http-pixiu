(library (http-pixiu)
  (export start-server
          stop-server
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

(define (log-date->string date)
  (string-append
    (number->string (date-year date)) "-"
    (if (< (date-month date) 10) "0" "") (number->string (date-month date)) "-"
    (if (< (date-day date) 10) "0" "") (number->string (date-day date)) " "
    (if (< (date-hour date) 10) "0" "") (number->string (date-hour date)) ":"
    (if (< (date-minute date) 10) "0" "") (number->string (date-minute date)) ":"
    (if (< (date-second date) 10) "0" "") (number->string (date-second date))))

(define (log-access log-port method path status-code response-size)
  (if (and log-port (not (null? log-port)))
    (begin
      (put-string log-port
        (string-append
          "[" (log-date->string (current-date)) "] "
          "\"" method " " path " HTTP/1.1\" "
          (number->string status-code) " "
          (number->string response-size)
          "\n"))
      (flush-output-port log-port))))

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

(define (init-lifecycle socket handler log-port)
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
                    (begin
                      (log-access log-port method path status:ok 0)
                      'handler-done)
                    (if (not (safe-path? path))
                        (begin
                          (write-response binary-output-port status:forbidden '() '())
                          (log-access log-port method path status:forbidden 0))
                        (let ([local (string-append private-static-path path)])
                          (let ([fip (open-file-input-port local)])
                            (let ([body (get-bytevector-all fip)]
                                  [content-type (guess-mime-type path)])
                              (write-response binary-output-port status:ok 
                                `(("Content-Type" . ,content-type)) body
                                (not (equal? method "HEAD")))
                              (log-access log-port method path status:ok (if (bytevector? body) (bytevector-length body) 0))))))))))
          (except c
            [(number? c) 
             (write-response (socket-output-port socket) c '() '())
             (log-access log-port "UNKNOWN" "/" c 0)]
            [else 
             (write-response (socket-output-port socket) status:not-found '() '())
             (log-access log-port "UNKNOWN" "/" status:not-found 0)])))))

; ms
(define expire-duration 1000)
(define ticks 100000)

(define shutdown-flag #f)

(define (stop-server server request-queue)
  (set! shutdown-flag #t)
  (display "Graceful shutdown initiated...")
  (newline)
  (guard (ex [#t (void)]) (socket-close (server-socket server)))
  (request-queue-shutdown request-queue))

(define start-server
  (case-lambda 
    [(port) (start-server port (current-output-port) 1 expire-duration ticks #f)]
    [(port thread-num) (start-server port (current-output-port) thread-num expire-duration ticks #f)]
    [(port thread-num expire-duration ticks) (start-server port (current-output-port) thread-num expire-duration ticks #f)]
    [(port log-port thread-num expire-duration ticks) (start-server port log-port thread-num expire-duration ticks #f)]
    [(port log-port thread-num expire-duration ticks handler)
      (set! shutdown-flag #f)
      (let* ([thread-pool (init-thread-pool thread-num)]
             [request-queue (make-request-queue)]
             [server (make-server port log-port thread-pool)])
        (register-signal-handler 2
          (lambda (sig)
            (stop-server server request-queue)))
        (map 
          (lambda (i)
            (thread-pool-add-job thread-pool 
              (lambda () 
                (let loop ()
                  (let ([job (request-queue-pop request-queue)])
                    (if job
                        (begin
                          (job)
                          (loop))
                        (begin
                          (display "Worker shutting down.")
                          (newline))))))))
          (iota thread-num))
        (display "Http-pixiu is working!")
        (newline)
        (let loop ()
          (if shutdown-flag
              (begin
                (display "Waiting for workers to finish...")
                (newline)
                (sleep (make-time 'time-duration 0 2))
                (display "Shutdown complete.")
                (newline))
              (let ([received-socket 
                     (guard (ex [#t #f]) (socket-accept (server-socket server)))])
                (if received-socket
                    (begin
                      (request-queue-push request-queue (init-lifecycle received-socket handler (server-log-port server)) expire-duration ticks)
                      (loop))
                    (begin
                      (if shutdown-flag
                          (begin
                            (display "Waiting for workers to finish...")
                            (newline)
                            (sleep (make-time 'time-duration 0 2))
                            (display "Shutdown complete.")
                            (newline))
                          (begin
                            (display "Socket accept failed, retrying...")
                            (newline)
                            (loop)))))))))]))

