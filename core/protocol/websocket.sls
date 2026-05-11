(library (http-pixiu core protocol websocket)
  (export
    websocket-request?
    websocket-accept-key
    make-websocket-response)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; WebSocket upgrade detection and handshake (RFC 6455)
  ;; Requires OpenSSL for SHA-1.
  ;; ------------------------------------------------------------------

  (define (try-load-openssl)
    (let ([paths '("libcrypto.so.3" "libcrypto.so.1.1" "libcrypto.so.1.0.0" "libcrypto.so")])
      (let loop ([ps paths])
        (if (null? ps)
            #f
            (guard (ex [#t (loop (cdr ps))])
              (load-shared-object (car ps))
              #t)))))

  (define *openssl-loaded* (try-load-openssl))

  (define sha1-proc
    (and *openssl-loaded*
         (guard (ex [#t #f])
           (foreign-procedure "SHA1" (u8* unsigned-long u8*) void*))))

  (define (websocket-available?)
    (procedure? sha1-proc))

  ;; ------------------------------------------------------------------
  ;; Base64 encoding (RFC 4648)
  ;; ------------------------------------------------------------------
  (define base64-chars
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  (define (base64-encode bv)
    (let ([len (bytevector-length bv)]
          [out (open-output-string)])
      (let loop ([i 0])
        (cond
          [(>= i len) (get-output-string out)]
          [(>= (+ i 1) len)
           (let ([b0 (bytevector-u8-ref bv i)])
             (put-string out (string (string-ref base64-chars (bitwise-arithmetic-shift-right b0 2))))
             (put-string out (string (string-ref base64-chars (bitwise-and (bitwise-arithmetic-shift-left b0 4) #x3F))))
             (put-string out "==")
             (get-output-string out))]
          [(>= (+ i 2) len)
           (let ([b0 (bytevector-u8-ref bv i)]
                 [b1 (bytevector-u8-ref bv (+ i 1))])
             (put-string out (string (string-ref base64-chars (bitwise-arithmetic-shift-right b0 2))))
             (put-string out (string (string-ref base64-chars (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left b0 4) (bitwise-arithmetic-shift-right b1 4)) #x3F))))
             (put-string out (string (string-ref base64-chars (bitwise-and (bitwise-arithmetic-shift-left b1 2) #x3F))))
             (put-string out "=")
             (get-output-string out))]
          [else
           (let ([b0 (bytevector-u8-ref bv i)]
                 [b1 (bytevector-u8-ref bv (+ i 1))]
                 [b2 (bytevector-u8-ref bv (+ i 2))])
             (put-string out (string (string-ref base64-chars (bitwise-arithmetic-shift-right b0 2))))
             (put-string out (string (string-ref base64-chars (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left b0 4) (bitwise-arithmetic-shift-right b1 4)) #x3F))))
             (put-string out (string (string-ref base64-chars (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left b1 2) (bitwise-arithmetic-shift-right b2 6)) #x3F))))
             (put-string out (string (string-ref base64-chars (bitwise-and b2 #x3F))))
             (loop (+ i 3)))]))))

  ;; ------------------------------------------------------------------
  ;; WebSocket key acceptance
  ;; ------------------------------------------------------------------
  (define (websocket-request? headers)
    (let ([upgrade (guard (ex [#t #f]) (string-downcase (string-trim-both (or (assoc-ref headers "upgrade:") ""))))]
          [connection (guard (ex [#t #f]) (string-downcase (string-trim-both (or (assoc-ref headers "connection:") ""))))]
          [ws-key (assoc-ref headers "sec-websocket-key:")])
      (and ws-key
           upgrade
           (string-contains? upgrade "websocket")
           connection
           (string-contains? connection "upgrade"))))

  (define (websocket-accept-key key)
    (if (not (procedure? sha1-proc))
        #f
        (let ([magic (string->utf8 (string-append (string-trim-both key) "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))])
          (let ([hash (make-bytevector 20)])
            (sha1-proc magic (bytevector-length magic) hash)
            (base64-encode hash)))))

  (define (make-websocket-response accept-key)
    `(("Upgrade" . "websocket")
      ("Connection" . "Upgrade")
      ("Sec-WebSocket-Accept" . ,accept-key)))

  ;; Helper: case-insensitive assoc-ref for headers
  (define (assoc-ref alist key)
    (let ([pair (find (lambda (p) (string-ci=? (car p) key)) alist)])
      (if pair (cdr pair) #f)))

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

)
