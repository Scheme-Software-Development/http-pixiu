(library (http-pixiu core static)
  (export
    serve-static-file
    safe-path?
    connection-close?
    parse-range-header
    generate-multipart-body
    gzip-compress
    compressible?)

  (import (chezscheme)
          (http-pixiu core handler)
          (http-pixiu core mime)
          (http-pixiu core cache)
          (http-pixiu core zlib)
          (http-pixiu core protocol status)
          (http-pixiu core config)
          (chibi uri))

  ;; ------------------------------------------------------------------
  ;; String helpers
  ;; ------------------------------------------------------------------
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

  ;; ------------------------------------------------------------------
  ;; Range request support
  ;; ------------------------------------------------------------------
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

  ;; ------------------------------------------------------------------
  ;; Connection keep-alive logic
  ;; ------------------------------------------------------------------
  (define (connection-close? headers protocol)
    (let ([conn (assoc-ref headers "connection:")])
      (cond
        [(equal? protocol "HTTP/1.1")
         (and conn (equal? (string-downcase (string-trim-both conn)) "close"))]
        [else
         (or (not conn) (not (equal? (string-downcase (string-trim-both conn)) "keep-alive")))])))

  ;; ------------------------------------------------------------------
  ;; Path security
  ;; ------------------------------------------------------------------
  (define (safe-path? static-path uri-path)
    (let ([decoded (guard (ex [#t #f]) (uri-decode uri-path))])
      (and decoded
           (not (string-contains? decoded "\x00;"))
           (not (let loop ([i 0])
                  (and (< i (string-length decoded))
                       (or (char=? (string-ref decoded i) #\nul)
                           (loop (+ i 1))))))
           ;; Reject any bare .. sequence in raw path
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
                 [else (loop (+ i 1))])))
           ;; Normalize path and verify prefix
           (let ([parts (let split ([i 0] [start 0] [acc '()])
                          (cond
                            [(>= i (string-length decoded))
                             (reverse (if (>= start i) acc (cons (substring decoded start i) acc)))]
                            [(char=? (string-ref decoded i) #\/)
                             (split (+ i 1) (+ i 1) (cons (substring decoded start i) acc))]
                            [else (split (+ i 1) start acc)]))])
             (let ([norm-parts (let normalize ([ps parts] [stack '()])
                                 (cond
                                   [(null? ps) (reverse stack)]
                                   [(or (string=? (car ps) "") (string=? (car ps) "."))
                                    (normalize (cdr ps) stack)]
                                   [(string=? (car ps) "..")
                                    (if (null? stack)
                                        #f
                                        (normalize (cdr ps) (cdr stack)))]
                                   [else (normalize (cdr ps) (cons (car ps) stack))]))])
               (and norm-parts
                    (let ([full (apply string-append
                                       (cons static-path
                                             (map (lambda (p) (string-append "/" p)) norm-parts)))])
                      (and (>= (string-length full) (string-length static-path))
                           (string=? (substring full 0 (string-length static-path)) static-path)
                           (not (let loop ([i 0])
                                  (and (< i (string-length full))
                                       (or (char=? (string-ref full i) #\nul)
                                           (loop (+ i 1))))))))))))))

  ;; ------------------------------------------------------------------
  ;; Gzip compression
  ;; ------------------------------------------------------------------
  (define waitpid
    (foreign-procedure "waitpid" (int void* int) int))

  (define (gzip-compress bv)
    (if (zlib-gzip-available?)
        (zlib-gzip-compress bv 6)
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
                      (loop)))))))))

  (define (compressible? content-type size accept-encoding)
    (and accept-encoding
         (<= size (* 1024 1024))
         (guard (ex [#t #f])
           (string-contains? (string-downcase (string-trim-both accept-encoding)) "gzip"))
         (or (and (>= (string-length content-type) 5)
                  (equal? (substring content-type 0 5) "text/"))
             (member content-type '("application/javascript" "application/json" "application/xml")))))

  ;; ------------------------------------------------------------------
  ;; Static file serving
  ;; ------------------------------------------------------------------
  (define (serve-static-file static-path-default file-cache metrics)
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
                  (metrics-render metrics))
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
                                                    (let ([cached (cache-lookup file-cache actual-path headers)])
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
                                                                (cache-store! file-cache actual-path bv mtime size)
                                                                (make-response status:ok
                                                                  `(,@base-headers
                                                                    ("Content-Type" . ,content-type)
                                                                    ("ETag" . ,(cache-generate-etag mtime size)))
                                                                  bv))
                                                              (make-response status:ok
                                                                `(,@base-headers
                                                                  ("Content-Type" . ,content-type))
                                                                (cons actual-fip size)))))))))))))))))))))

)
)
