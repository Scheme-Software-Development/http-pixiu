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
    (http-pixiu core handler)
    (http-pixiu core middleware)
    (http-pixiu core protocol request-parse)
    (http-pixiu core protocol request-queue)
    (http-pixiu core protocol response-construct)
    (http-pixiu core protocol status)
    (http-pixiu core protocol logger)
    (http-pixiu core protocol ratelimit)
    (http-pixiu core config)
    (http-pixiu core util io)
    (http-pixiu core util binary-read)
    (http-pixiu core util association)
    (http-pixiu core util date)
    (http-pixiu core mime)
    (http-pixiu core cache)
    (http-pixiu core zlib)
    (http-pixiu core connection-counter)
    (http-pixiu core metrics)

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

;; log-access removed; use logger:log-request instead

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

(define (parse-single-range part file-size)
  (let ([s (string-trim-both part)])
    (let find-dash ([i 0])
      (cond
        [(>= i (string-length s)) #f]
        [(char=? (string-ref s i) #\-)
         (let ([start-str (string-trim-both (substring s 0 i))]
               [end-str (string-trim-both (substring s (+ i 1) (string-length s)))])
           (let ([start (guard (ex [#t #f]) (string->number start-str))]
                 [end (if (zero? (string-length end-str))
                          (- file-size 1)
                          (guard (ex [#t #f]) (string->number end-str)))])
             (if (and start end (>= start 0) (<= start end) (< end file-size))
                 (cons start end)
                 #f)))]
        [else (find-dash (+ i 1))]))))

(define (parse-range-header range-value file-size)
  (let ([s (string-trim-both range-value)])
    (if (and (>= (string-length s) 6)
             (equal? (substring s 0 6) "bytes="))
        (let ([rest (substring s 6 (string-length s))])
          (let parse-parts ([start 0] [result '()])
            (let find-comma ([i start])
              (cond
                [(>= i (string-length rest))
                 (let ([range (parse-single-range (substring rest start i) file-size)])
                   (let ([final (if range (cons range result) result)])
                     (if (null? final) #f (reverse final))))]
                [(char=? (string-ref rest i) #\,)
                 (let ([range (parse-single-range (substring rest start i) file-size)])
                   (parse-parts (+ i 1) (if range (cons range result) result)))]
                [else (find-comma (+ i 1))]))))
        #f)))

(define (generate-boundary)
  (let ([chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"])
    (let loop ([i 0] [result ""])
      (if (>= i 16)
          result
          (loop (+ i 1)
                (string-append result (string (string-ref chars (random (string-length chars))))))))))

(define (generate-multipart-body fip ranges total-size boundary content-type)
  (let-values ([(out get) (open-bytevector-output-port)])
    (for-each
      (lambda (range)
        (let ([start (car range)]
              [end (cdr range)])
          (put-bytevector out (string->utf8 (string-append "--" boundary "\r\n")))
          (put-bytevector out (string->utf8 (string-append "Content-Type: " content-type "\r\n")))
          (put-bytevector out (string->utf8 (string-append "Content-Range: bytes " (number->string start) "-" (number->string end) "/" (number->string total-size) "\r\n\r\n")))
          (set-port-position! fip start)
          (let ([bv (make-bytevector (+ (- end start) 1))])
            (get-bytevector-n! fip bv 0 (+ (- end start) 1))
            (put-bytevector out bv))
          (put-bytevector out (string->utf8 "\r\n"))))
      ranges)
    (put-bytevector out (string->utf8 (string-append "--" boundary "--\r\n")))
    (close-input-port fip)
    (get)))

(define (connection-close? headers protocol)
  (let ([conn (assoc-ref headers "connection:")])
    (cond
      [(equal? protocol "HTTP/1.1")
       (and conn (equal? (string-downcase (string-trim-both conn)) "close"))]
      [else
       (or (not conn) (not (equal? (string-downcase (string-trim-both conn)) "keep-alive")))])))

(define (safe-path? static-path uri-path)
  (let ([decoded (uri-decode uri-path)])
    (and (not (string-contains? decoded "\x00;"))
         (let ([full (string-append static-path decoded)])
           (let loop ([i 0])
             (cond
               [(>= i (string-length full)) #t]
               [(char=? (string-ref full i) #\nul) #f]
               [(and (char=? (string-ref full i) #\.)
                     (< (+ i 1) (string-length full))
                     (char=? (string-ref full (+ i 1)) #\.)
                     (or (zero? i)
                         (char=? (string-ref full (- i 1)) #\/))
                     (or (>= (+ i 2) (string-length full))
                         (char=? (string-ref full (+ i 2)) #\/)))
                #f]
               [else (loop (+ i 1))]))))))

(define (consume-coroutine closure)
  (let-values ([(resume val) (closure)])
    (if resume
        (consume-coroutine (lambda () (resume val)))
        val)))

(define (generate-request-id)
  (let ([t (current-time)])
    (string-append
      (number->string (time-second t) 16)
      "-"
      (number->string (mod (time-nanosecond t) (expt 2 31)) 16)
      "-"
      (number->string (random (expt 2 16)) 16))))

(define max-header-count 100)
(define max-header-key-length 8192)
(define max-content-length (* 10 1024 1024)) ; 10 MiB

(define (build-request-env closure method uri-str)
  (let ([full-result (consume-coroutine closure)])
    (let ([protocol (assq-ref full-result 'protocol)]
          [body-pair (assq 'body full-result)]
          [headers (filter (lambda (p) (string? (car p))) full-result)])
      ;; Hard limits on headers
      (when (> (length headers) max-header-count)
        (raise status:bad-request))
      (when (ormap (lambda (h) (> (string-length (car h)) max-header-key-length)) headers)
        (raise status:bad-request))
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
            (body . ,(if body-pair (cdr body-pair) #f))
            (request-id . ,(generate-request-id))))))))

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
          (f (socket-file-descriptor sock) 1 20 tv sz)   ; SO_RCVTIMEO
          (f (socket-file-descriptor sock) 1 21 tv sz)   ; SO_SNDTIMEO
          (foreign-free tv))))))

(define waitpid
  (foreign-procedure "waitpid" (int void* int) int))

(define (gzip-compress bv)
  (let-values ([(to-stdin from-stdout from-stderr pid) (open-process-ports "gzip -c")])
    (put-bytevector to-stdin bv)
    (flush-output-port to-stdin)
    (close-output-port to-stdin)
    (let-values ([(out get) (open-bytevector-output-port)])
      (let loop ()
        (let ([chunk (get-bytevector-n from-stdout 65536)])
          (if (eof-object? chunk)
              (begin
                (close-input-port from-stdout)
                (close-input-port from-stderr)
                (let ([status-ptr (foreign-alloc (foreign-sizeof 'int))])
                  (waitpid pid status-ptr 0)
                  (foreign-free status-ptr))
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

(define (stop-server server request-queue)
  (set! shutdown-flag #t)
  (request-queue-shutdown request-queue)
  (guard (ex [#t (display "Error stopping thread pool: ") (display ex) (newline)])
    (thread-pool-stop! (server-thread-pool server))))

(define *current-server-info* #f)
(define *current-config* #f)

(define start-server
  (case-lambda 
    [(port) (start-server port (make-logger "access" 'clf) 1 default-expire-duration default-ticks #f "./static" (make-config))]
    [(port thread-num) (start-server port (make-logger "access" 'clf) thread-num default-expire-duration default-ticks #f "./static" (make-config))]
    [(port thread-num expire-duration ticks) (start-server port (make-logger "access" 'clf) thread-num expire-duration ticks #f "./static" (make-config))]
    [(port log-port thread-num expire-duration ticks) (start-server port log-port thread-num expire-duration ticks #f "./static" (make-config))]
    [(port log-port thread-num expire-duration ticks handler)
     (start-server port log-port thread-num expire-duration ticks handler "./static" (make-config))]
    [(port log-port thread-num expire-duration ticks handler static-path)
     (start-server port log-port thread-num expire-duration ticks handler static-path (make-config))]
    [(port log-port thread-num expire-duration ticks handler static-path config)
      (set! shutdown-flag #f)
      (let* ([thread-pool (init-thread-pool thread-num)]
             [max-queue-size (max (* thread-num 16) 64)]
             [request-queue (make-request-queue max-queue-size)]
             [conn-counter (make-connection-counter 1024)]
             [server (make-server port log-port thread-pool)])
        (set! *current-server-info* (cons server request-queue))
        (set! *current-config* config)
        (register-signal-handler 2
          (lambda (sig)
            (stop-server server request-queue)
            (when (logger? log-port)
              (logger-shutdown! log-port))))
        (register-signal-handler 1
          (lambda (sig)
            (display "Reloading configuration...") (newline)
            (guard (ex [#t (display "Config reload failed: ") (display ex) (newline)])
              (let ([new-config (config-load "config.scm")])
                (set! *current-config* new-config)
                (display "Configuration reloaded.") (newline)))))
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
                    (if (connection-counter-acquire! conn-counter)
                        (let ([job (init-lifecycle received-socket handler (server-log-port server) static-path config conn-counter)])
                          (if (request-queue-push request-queue
                                  (lambda () (dynamic-wind
                                              (lambda () #f)
                                              (lambda () (job))
                                              (lambda () (connection-counter-release! conn-counter))))
                                  expire-duration ticks)
                              (loop)
                              (begin
                                (connection-counter-release! conn-counter)
                                (guard (ex [#t (void)])
                                  (let ([out (socket-output-port received-socket)])
                                    (put-bytevector out (string->utf8 "HTTP/1.1 503 Service Unavailable
Content-Length: 0
Connection: close

"))
                                    (flush-output-port out)))
                                (guard (ex [#t (void)]) (socket-close received-socket))
                                (loop))))
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

(define file-cache-inst (make-file-cache))
(define metrics-inst (metrics-new))

(define (serve-static-file static-path-default)
  (lambda (env)
    (let* ([method (env-method env)]
           [path (env-path env)]
           [headers (env-headers env)]
           [static-path
            (let ([host (assoc-ref headers "host:")]
                  [config *current-config*])
             (if (and config host)
                 (let ([vhosts (config-get config 'vhosts)])
                   (if vhosts
                       (let ([h (let loop ([i 0])
                                  (if (>= i (string-length host))
                                      host
                                      (if (char=? (string-ref host i) #\:)
                                          (substring host 0 i)
                                          (loop (+ i 1)))))])
                         (let ([entry (assoc h vhosts)])
                           (if entry (cdr entry) static-path-default)))
                       static-path-default))
                 static-path-default))])
      (if (equal? path "/health")
          (make-response status:ok
            '(("Content-Type" . "application/json"))
            (string->utf8 "{\"status\":\"ok\"}"))
          (if (equal? path "/metrics")
              (make-response status:ok
                '(("Content-Type" . "text/plain; version=0.0.4"))
                (metrics-render metrics-inst))
              (if (not (safe-path? static-path path))
                  (make-response status:forbidden '() '())
              (let ([local (string-append static-path path)])
            (let ([fip (guard (ex [#t #f])
                         (open-file-input-port local))])
              (let ([actual-fip
                     (if (or (not fip) (guard (ex [#t #f]) (file-directory? local)))
                         (guard (ex [#t #f])
                           (open-file-input-port (string-append local "/index.html")))
                         fip)]
                    [actual-path
                     (if (or (not fip) (guard (ex [#t #f]) (file-directory? local)))
                         (string-append path "/index.html")
                         path)])
                (if (not actual-fip)
                    (if (file-exists? local)
                        (if (guard (ex [#t #f]) (file-directory? local))
                            (if (not (equal? (string-ref path (- (string-length path) 1)) #\/))
                                (make-response status:moved-permanently
                                  `(("Location" . ,(string-append path "/")))
                                  '())
                                (let ([entries (directory-list local)])
                                  (make-response status:ok
                                '(("Content-Type" . "text/html"))
                                (string->utf8
                                  (let ([title (string-append "Index of " path)])
                                    (string-append
                                      "<!DOCTYPE html>\n<html>\n<head><title>" title "</title></head>\n"
                                      "<body>\n<h1>" title "</h1>\n<hr>\n<ul>\n"
                                      (if (equal? path "/")
                                          ""
                                          "<li><a href=\"../\">Parent Directory</a></li>\n")
                                      (let loop ([entries (sort string<? entries)])
                                        (if (null? entries)
                                            ""
                                            (let ([entry (car entries)])
                                              (string-append
                                                "<li><a href=\"" entry (if (guard (ex [#t #f]) (file-directory? (string-append local "/" entry))) "/" "") "\">" entry "</a></li>\n"
                                                (loop (cdr entries))))))
                                      "</ul>\n<hr>\n</body>\n</html>\n"))))))
                            (make-response status:forbidden '() '()))
                        (make-response status:not-found '() '()))
                    (let ([size (file-length actual-fip)]
                          [mtime-time (guard (ex [#t (make-time 'time-utc 0 0)]) (file-modification-time local))]
                          [content-type (let ([ct (guess-mime-type actual-path)])
                                          (if (or (and (>= (string-length ct) 5)
                                                       (equal? (substring ct 0 5) "text/"))
                                                  (member ct '("application/json" "application/javascript" "application/xml")))
                                              (string-append ct "; charset=utf-8")
                                              ct))]
                          [range (assoc-ref headers "range:")]
                          [if-none-match (assoc-ref headers "if-none-match:")])
                      (let* ([mtime (time-second mtime-time)]
                             [last-modified (date->string (time-utc->date mtime-time 0))]
                             [cache-max-age (let ([c *current-config*])
                                              (or (and c (config-get c 'cache-control-max-age)) 3600))]
                             [base-headers `(,(cons "Accept-Ranges" "bytes")
                                            ("Last-Modified" . ,last-modified)
                                            ("Cache-Control" . ,(string-append "public, max-age=" (number->string cache-max-age))))])
                      (if (and if-none-match (equal? if-none-match (cache-generate-etag mtime size)))
                          (begin
                            (close-input-port actual-fip)
                            (make-response status:not-modified
                              `(,@base-headers
                                ("Content-Type" . ,content-type)
                                ("ETag" . ,(cache-generate-etag mtime size)))
                              '()))
                          (if range
                              (let ([ranges (parse-range-header range size)])
                            (if ranges
                                (if (null? (cdr ranges))
                                    ;; single range
                                    (let* ([start (caar ranges)]
                                           [end (cdar ranges)]
                                           [partial-size (+ (- end start) 1)])
                                      (guard (ex [#t (begin (close-input-port actual-fip) (raise ex))])
                                        (set-port-position! actual-fip start))
                                      (make-response status:partial-content
                                        `(,@base-headers
                                          ("Content-Type" . ,content-type)
                                          ("Content-Range" . ,(string-append "bytes " (number->string start) "-" (number->string end) "/" (number->string size))))
                                        (cons actual-fip partial-size)))
                                    ;; multiple ranges
                                    (let ([boundary (generate-boundary)])
                                      (let ([body (generate-multipart-body actual-fip ranges size boundary content-type)])
                                        (make-response status:partial-content
                                          `(,@base-headers
                                            ("Content-Type" . ,(string-append "multipart/byteranges; boundary=" boundary))
                                            ("Content-Length" . ,(number->string (bytevector-length body))))
                                          body))))
                                (begin
                                  (close-input-port actual-fip)
                                  (make-response status:range-not-satisfiable '() '()))))
                          (let ((precompressed
                                  (guard (ex [#t #f])
                                    (let ((gz-path (string-append local ".gz")))
                                      (and (file-exists? gz-path)
                                           (>= (time-second (guard (ex [#t 0]) (file-modification-time gz-path)))
                                               (time-second mtime-time))
                                           (open-file-input-port gz-path))))))
                            (if (and precompressed (assoc-ref headers "accept-encoding:"))
                                (let ([gz-size (file-length precompressed)])
                                  (close-input-port actual-fip)
                                  (make-response status:ok
                                    `(,@base-headers
                                      ("Content-Type" . ,content-type)
                                      ("Content-Encoding" . "gzip"))
                                    (cons precompressed gz-size)))
                                (if (compressible? content-type size (assoc-ref headers "accept-encoding:"))
                                    (guard (ex [#t (begin (close-input-port actual-fip) (raise ex))])
                                      (let ([bv (make-bytevector size)])
                                        (get-bytevector-n! actual-fip bv 0 size)
                                        (close-input-port actual-fip)
                                        (let ([compressed (gzip-compress bv)])
                                          (make-response status:ok
                                            `(,@base-headers
                                              ("Content-Type" . ,content-type)
                                              ("Content-Encoding" . "gzip"))
                                            compressed))))
                              (let ([cached (cache-lookup file-cache-inst actual-path headers)])
                                (if cached
                                    (begin
                                      (close-input-port actual-fip)
                                      (make-response status:ok
                                        `(,@base-headers
                                          ("Content-Type" . ,content-type)
                                          ("ETag" . ,(cache-etag cached)))
                                        (cache-content cached)))
                                    (if (<= size (* 256 1024))
                                        (let ([bv (make-bytevector size)])
                                          (get-bytevector-n! actual-fip bv 0 size)
                                          (close-input-port actual-fip)
                                          (cache-store! file-cache-inst actual-path bv mtime size)
                                          (make-response status:ok
                                            `(,@base-headers
                                              ("Content-Type" . ,content-type)
                                              ("ETag" . ,(cache-generate-etag mtime size)))
                                            bv))
                                        (make-response status:ok
                                          `(,@base-headers
                                            ("Content-Type" . ,content-type))
                                          (cons actual-fip size))))))))))))))))))))))

(define (init-lifecycle socket handler log-port static-path config conn-counter)
  (let ([default-handler (serve-static-file static-path)]
        [rate-limiter (if config (make-rate-limiter (config-get config 'rate-limit-window) (config-get config 'rate-limit-max)) #f)])
    (lambda ()
      (let ([binary-input-port (socket-input-port socket)]
            [binary-output-port (socket-output-port socket)])
        (let loop ([request-count 0])
              (if (eof-object? (lookahead-u8 binary-input-port))
                  (begin
                    (close-input-port binary-input-port)
                    (close-output-port binary-output-port)
                    (socket-close socket))
                  (let ([config (or *current-config* config)])
                    (socket-set-timeout! socket (or (and config (config-get config 'idle-timeout-ms)) 5000))
                (guard (c
                       [(number? c)
                        (guard (ex [#t (void)]) (write-response binary-output-port c '() '() #t #f))
                        (log-request log-port "UNKNOWN" "/" c 0 "HTTP/1.1")
                        (guard (ex [#t (void)]) (flush-output-port binary-output-port))]
                       [else
                        (guard (ex [#t (void)]) (write-response binary-output-port status:internal-server-error '() '() #t #f))
                        (log-request log-port "UNKNOWN" "/" status:internal-server-error 0 "HTTP/1.1")
                        (guard (ex [#t (void)]) (flush-output-port binary-output-port))])
                (let ([closure (parse-request-coroutine binary-input-port)])
                  (let*-values ([(closure0 method) (get-values-from-coroutine closure 'method)]
                                [(closure1 target-string) (get-values-from-coroutine closure0 'uri)])
                    (if (not method)
                        (begin
                          (close-input-port binary-input-port)
                          (close-output-port binary-output-port)
                          (socket-close socket))
                        (begin
                          (socket-set-timeout! socket 30000)
                    (let* ([env (build-request-env closure1 method target-string)]
                           [env (if (eq? (env-body env) 'stream)
                                    (let ([content-length (assq-ref env 'content-length)])
                                      (let ([remaining-box (box content-length)]
                                            [count-box (box 0)])
                                        (let ([counting-port (make-custom-binary-input-port
                                                               "body-port"
                                                               (lambda (bv start n)
                                                                 (let ([remaining (unbox remaining-box)])
                                                                   (if (<= remaining 0)
                                                                       0
                                                                       (let ([to-read (min n remaining)])
                                                                         (let ([actual (get-bytevector-n! binary-input-port bv start to-read)])
                                                                           (if (number? actual)
                                                                               (begin
                                                                                 (set-box! remaining-box (- remaining actual))
                                                                                 (set-box! count-box (+ (unbox count-box) actual))
                                                                                 actual)
                                                                               0))))))
                                                               #f #f
                                                               (lambda () (void)))])
                                          `(,@env (body-port . ,counting-port) (body-count . ,count-box)))))
                                    env)]
                           [path (assq-ref env 'path)]
                           [headers (assq-ref env 'headers)]
                           [protocol (assq-ref env 'protocol)]
                           [close? (or (>= request-count 100)
                                       (connection-close? headers protocol)
                                       (and (eq? (env-body env) 'stream)
                                            (let ([count-box (assq-ref env 'body-count)])
                                              (let ([content-length (assq-ref env 'content-length)])
                                                (< (unbox count-box) content-length)))))])
                      ;; Enforce max Content-Length
                      (let ([content-length-str (assoc-ref headers "content-length:")])
                        (when content-length-str
                          (let ([len (guard (ex [#t #f]) (string->number content-length-str))])
                            (when (and len (> len max-content-length))
                              (raise status:payload-too-large)))))
                      (let ([final-handler
                             (if config
                                 (let ([h (or handler default-handler)])
                                   (let ([h2 ((cors-middleware (config-get config 'cors-allow-origin)) h)])
                                     (let ([h3 (if rate-limiter
                                                   ((ratelimit-middleware rate-limiter) h2)
                                                   h2)])
                                       (let ([h4 ((logging-middleware log-port) h3)])
                                         (let ([h5 (security-headers-middleware h4)])
                                           ((error-page-middleware static-path) h5))))))
                                 (security-headers-middleware (or handler default-handler)))])
                        (let ([request-id (assq-ref env 'request-id)])
                          (let ([start-time (current-time)]
                                [resp (final-handler env)])
                            (let ([status (response-status resp)]
                                  [resp-headers (cons (cons "X-Request-ID" (or request-id "-"))
                                                      (response-headers resp))]
                                  [body (response-body resp)])
                              ;; Record metrics
                              (let ([duration-ms (let ([dt (time-difference (current-time) start-time)])
                                                   (+ (* (time-second dt) 1000)
                                                      (div (time-nanosecond dt) 1000000)))])
                                (metrics-increment-request! metrics-inst method (or status status:not-found) duration-ms))
                              ;; 100 Continue
                              (when (equal? (assoc-ref headers "expect:") "100-continue")
                                (write-response binary-output-port status:continue '() '() #f (not close?))
                                (flush-output-port binary-output-port))
                              ;; Chunked vs Content-Length
                              (if (and (pair? body) (input-port? (car body)) (not (cdr body)))
                                  (write-chunked-response binary-output-port (or status status:not-found) resp-headers body
                                                          (not (equal? method "HEAD"))
                                                          (not close?))
                                  (write-response binary-output-port (or status status:not-found) resp-headers body
                                                  (not (equal? method "HEAD"))
                                                  (not close?)))
                              (when (and (pair? body) (input-port? (car body)))
                                (close-input-port (car body)))
                              (if (not config)
                                  (log-request log-port method path (or status status:not-found) (body-size body) protocol (assq-ref env 'client-ip) (assoc-ref headers "user-agent:")))
                              (flush-output-port binary-output-port)
                              (sleep (make-time 'time-duration 0 0))
                              (if (not close?)
                                  (loop (+ request-count 1))
                                  (begin
                                    (close-input-port binary-input-port)
                                    (close-output-port binary-output-port)
                                    (socket-close socket)))))))))))))))))))))



