(library (http-pixiu)
  (export start-server
          stop-server
          write-response
          write-chunked-response
          write-json-response
          write-text-response
          write-html-response
          safe-path?
          connection-close?
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
    (ufo-socket socket c)
    (ufo-thread-pool))

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

(define (string-trim-both s)
  (let ([len (string-length s)])
    (let loop-start ([i 0])
      (if (and (< i len) (char-whitespace? (string-ref s i)))
          (loop-start (+ i 1))
          (let loop-end ([j len])
            (if (and (> j i) (char-whitespace? (string-ref s (- j 1))))
                (loop-end (- j 1))
                (substring s i j)))))))

(define (string-contains? s substr)
  (let ([len (string-length s)]
        [sub-len (string-length substr)])
    (let loop ([i 0])
      (cond
        [(> (+ i sub-len) len) #f]
        [(equal? (substring s i (+ i sub-len)) substr) #t]
        [else (loop (+ i 1))]))))

(define (parse-range-header range-value file-size)
  (let ([s (string-trim-both range-value)])
    (if (and (>= (string-length s) 6)
             (equal? (substring s 0 6) "bytes="))
        (let ([rest (substring s 6 (string-length s))])
          (let find-dash ([i 0])
            (cond
              [(>= i (string-length rest)) #f]
              [(char=? (string-ref rest i) #\-)
               (let ([start-str (string-trim-both (substring rest 0 i))]
                     [end-str (string-trim-both (substring rest (+ i 1) (string-length rest)))])
                 (let ([start (guard (ex [#t #f]) (string->number start-str))]
                       [end (if (zero? (string-length end-str))
                                (- file-size 1)
                                (guard (ex [#t #f]) (string->number end-str)))])
                   (if (and start end (>= start 0) (<= start end) (< end file-size))
                       (cons start end)
                       #f)))]
              [else (find-dash (+ i 1))])))
        #f)))

(define (connection-close? headers protocol)
  (let ([conn (assoc-ref headers "connection:")])
    (cond
      [(equal? protocol "HTTP/1.1")
       (and conn (equal? (string-downcase (string-trim-both conn)) "close"))]
      [else
       (or (not conn) (not (equal? (string-downcase (string-trim-both conn)) "keep-alive")))])))

(define (safe-path? static-path uri-path)
  (let ([decoded (uri-decode uri-path)])
    (let ([full (string-append static-path decoded)])
      (let loop ([i 0])
        (cond
          [(>= i (string-length full)) #t]
          [(and (char=? (string-ref full i) #\.)
                (< (+ i 1) (string-length full))
                (char=? (string-ref full (+ i 1)) #\.)
                (or (zero? i)
                    (char=? (string-ref full (- i 1)) #\/))
                (or (>= (+ i 2) (string-length full))
                    (char=? (string-ref full (+ i 2)) #\/)))
           #f]
          [else (loop (+ i 1))])))))

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
        (let ([path (uri-path uri)])
          ; HTTP/1.1 requires Host header
          (when (and (equal? protocol "HTTP/1.1")
                     (not (assoc-ref headers "host:")))
            (raise status:bad-request))
          `((method . ,method)
            (uri . ,uri-str)
            (path . ,path)
            (query . ,(guard (ex [#t #f]) (uri-query uri)))
            (protocol . ,protocol)
            (headers . ,headers)
            (body . ,(if body-pair (cdr body-pair) #f))))))))

; default request timeout in milliseconds
(define default-expire-duration 1000)
; default Chez Scheme engine ticks before yielding
(define default-ticks 100000)

(define shutdown-flag #f)

(define (socket-set-timeout! sock ms)
  (guard (ex [#t (void)])
    (let ([seconds (div ms 1000)]
          [microseconds (* (mod ms 1000) 1000)])
      (let ([f (foreign-procedure "setsockopt" (int int int void* int) int)]
            [sz (* 2 (foreign-sizeof 'long))])
        (let ([tv (foreign-alloc sz)])
          (foreign-set! 'long tv 0 seconds)
          (foreign-set! 'long tv (foreign-sizeof 'long) microseconds)
          (let ([rc (f (socket-file-descriptor sock) 1 20 tv sz)])
            (foreign-free tv)
            rc))))))

(define (gzip-compress bv)
  (let-values ([(to-stdin from-stdout from-stderr pid) (open-process-ports "gzip -c")])
    (put-bytevector to-stdin bv)
    (close-output-port to-stdin)
    (let-values ([(out get) (open-bytevector-output-port)])
      (let loop ()
        (let ([chunk (get-bytevector-n from-stdout 65536)])
          (if (eof-object? chunk)
              (begin
                (close-input-port from-stdout)
                (close-input-port from-stderr)
                (get))
              (begin
                (put-bytevector out chunk)
                (loop))))))))

(define (compressible? content-type size accept-encoding)
  (and accept-encoding
       (<= size (* 1024 1024))
       (guard (ex [#t #f])
         (string-contains? (string-downcase (string-trim-both accept-encoding)) "gzip"))
       (or (and (>= (string-length content-type) 5)
                (equal? (substring content-type 0 5) "text/"))
           (member content-type '("application/javascript" "application/json" "application/xml")))))

(define stop-server
  (case-lambda
    [(server request-queue)
     (stop-server server request-queue #f)]
    [(server request-queue port)
     (set! shutdown-flag #t)
     (display "Graceful shutdown initiated...")
     (newline)
     (request-queue-shutdown request-queue)
     (when port
       (guard (ex [#t (void)])
         (let ([dummy (make-client-socket "127.0.0.1" port)])
           (socket-close dummy))))
     (guard (ex [#t (void)]) (socket-close (server-socket server)))]))

(define *current-server-info* #f)

(define start-server
  (case-lambda 
    [(port) (start-server port (current-output-port) 1 default-expire-duration default-ticks #f "./static")]
    [(port thread-num) (start-server port (current-output-port) thread-num default-expire-duration default-ticks #f "./static")]
    [(port thread-num expire-duration ticks) (start-server port (current-output-port) thread-num expire-duration ticks #f "./static")]
    [(port log-port thread-num expire-duration ticks) (start-server port log-port thread-num expire-duration ticks #f "./static")]
    [(port log-port thread-num expire-duration ticks handler)
     (start-server port log-port thread-num expire-duration ticks handler "./static")]
    [(port log-port thread-num expire-duration ticks handler static-path)
      (set! shutdown-flag #f)
      (let* ([thread-pool (init-thread-pool thread-num)]
             [max-queue-size (max (* thread-num 16) 64)]
             [request-queue (make-request-queue max-queue-size)]
             [server (make-server port log-port thread-pool)])
        (set! *current-server-info* (cons server request-queue))
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
                (newline)
                (cons server request-queue))
              (let ([received-socket 
                     (guard (ex [#t #f]) (socket-accept (server-socket server)))])
                (if received-socket
                    (if (request-queue-push request-queue (init-lifecycle received-socket handler (server-log-port server) static-path) expire-duration ticks)
                        (loop)
                        (begin
                          (guard (ex [#t (void)]) (socket-close received-socket))
                          (loop)))
                    (begin
                      (if shutdown-flag
                          (begin
                            (display "Waiting for workers to finish...")
                            (newline)
                            (sleep (make-time 'time-duration 0 2))
                            (display "Shutdown complete.")
                            (newline)
                            (cons server request-queue))
                          (begin
                            (display "Socket accept failed, retrying...")
                            (newline)
                            (sleep (make-time 'time-duration 50000000 0))
                            (loop)))))))))]))

(define (serve-static-file binary-output-port method path headers static-path close? log-port)
  (if (not (safe-path? static-path path))
      (begin
        (write-response binary-output-port status:forbidden '() '() #t (not close?))
        (log-access log-port method path status:forbidden 0))
      (let ([local (string-append static-path path)])
        (let ([fip (guard (ex [#t #f])
                     (open-file-input-port local))])
          (let ([actual-fip
                 (if (not fip)
                     (guard (ex [#t #f])
                       (open-file-input-port (string-append local "/index.html")))
                     fip)]
                [actual-path
                 (if (not fip)
                     (string-append path "/index.html")
                     path)])
            (if (not actual-fip)
                (begin
                  (if (file-exists? local)
                      (begin
                        (write-response binary-output-port status:forbidden '() '() #t (not close?))
                        (log-access log-port method path status:forbidden 0))
                      (begin
                        (write-response binary-output-port status:not-found '() '() #t (not close?))
                        (log-access log-port method path status:not-found 0)))
                  (flush-output-port binary-output-port)
                  (void))
                (let ([size (file-length actual-fip)]
                      [content-type (guess-mime-type actual-path)]
                      [range (assoc-ref headers "range:")])
                  (if range
                      (let ([range-pair (parse-range-header range size)])
                        (if range-pair
                            (let* ([start (car range-pair)]
                                   [end (cdr range-pair)]
                                   [partial-size (+ (- end start) 1)])
                              (set-port-position! actual-fip start)
                              (guard (ex [#t (begin (close-input-port actual-fip) (raise ex))])
                                (write-response binary-output-port status:partial-content
                                  `(("Content-Type" . ,content-type)
                                    ("Content-Range" . ,(string-append "bytes " (number->string start) "-" (number->string end) "/" (number->string size))))
                                  (cons actual-fip partial-size)
                                  (not (equal? method "HEAD"))
                                  (not close?)))
                              (close-input-port actual-fip)
                              (log-access log-port method path status:partial-content partial-size))
                            (begin
                              (close-input-port actual-fip)
                              (write-response binary-output-port status:range-not-satisfiable '() '() #t #f)
                              (log-access log-port method path status:range-not-satisfiable 0))))
                      (if (compressible? content-type size (assoc-ref headers "accept-encoding:"))
                          (let ([bv (make-bytevector size)])
                            (get-bytevector-n! actual-fip bv 0 size)
                            (close-input-port actual-fip)
                            (let ([compressed (gzip-compress bv)])
                              (write-response binary-output-port status:ok
                                `(("Content-Type" . ,content-type)
                                  ("Content-Encoding" . "gzip")) compressed
                                (not (equal? method "HEAD"))
                                (not close?))
                              (log-access log-port method path status:ok (bytevector-length compressed))))
                          (begin
                            (guard (ex [#t (begin (close-input-port actual-fip) (raise ex))])
                              (write-response binary-output-port status:ok
                                `(("Content-Type" . ,content-type)) (cons actual-fip size)
                                (not (equal? method "HEAD"))
                                (not close?)))
                            (close-input-port actual-fip)
                            (log-access log-port method path status:ok size)))))))))))

(define (init-lifecycle socket handler log-port static-path)
  (lambda ()
    (call-with-socket socket
      (lambda (socket)
        (socket-set-timeout! socket 30000)
        (let ([binary-input-port (socket-input-port socket)]
              [binary-output-port (socket-output-port socket)])
          (let loop ([request-count 0])
            (guard (c
                     [(number? c)
                      (write-response binary-output-port c '() '() #t #f)
                      (log-access log-port "UNKNOWN" "/" c 0)
                      (flush-output-port binary-output-port)]
                     [else
                      (write-response binary-output-port status:internal-server-error '() '() #t #f)
                      (log-access log-port "UNKNOWN" "/" status:internal-server-error 0)
                      (flush-output-port binary-output-port)])
              (let ([closure (parse-request-coroutine binary-input-port)])
                (let*-values ([(closure0 method) (get-values-from-coroutine closure 'method)]
                              [(closure1 target-string) (get-values-from-coroutine closure0 'uri)])
                  (let* ([env (build-request-env closure1 method target-string)]
                         [path (assq-ref env 'path)]
                         [headers (assq-ref env 'headers)]
                         [protocol (assq-ref env 'protocol)]
                         [close? (or (>= request-count 100)
                                     (connection-close? headers protocol))])
                    (if (and handler
                             (handler env binary-output-port))
                        (log-access log-port method path status:ok 0)
                        (serve-static-file binary-output-port method path headers static-path close? log-port))
                    (flush-output-port binary-output-port)
                    (if (not close?) (loop (+ request-count 1)))))))))))))


)
