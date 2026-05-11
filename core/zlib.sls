(library (http-pixiu core zlib)
  (export
    zlib-compress
    zlib-gzip-compress
    zlib-available?
    zlib-gzip-available?)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Dynamic library discovery
  ;; ------------------------------------------------------------------
  (define (try-load-shared-object path)
    (guard (ex [#t #f])
      (load-shared-object path)
      #t))

  (define (find-zlib)
    (let ([paths '(
      "/nix/store/v2ny69wp81ch6k4bxmp4lnhh77r0n4h1-zlib-1.3.1/lib/libz.so.1.3.1"
      "/nix/store/phnpfqk1j35nil4hqgaslqm9a1q2gffy-zlib-1.3.1/lib/libz.so.1.3.1"
      "/usr/lib/x86_64-linux-gnu/libz.so.1"
      "/lib/x86_64-linux-gnu/libz.so.1"
      "/usr/lib64/libz.so.1"
      "/usr/lib/libz.so.1"
      "libz.so.1"
      "libz.so")])
      (let loop ([ps paths])
        (if (null? ps)
            #f
            (if (try-load-shared-object (car ps))
                (car ps)
                (loop (cdr ps)))))))

  (define *zlib-loaded* (find-zlib))

  (define (zlib-available?)
    *zlib-loaded*)

  ;; ------------------------------------------------------------------
  ;; FFI bindings (only valid if zlib-available?)
  ;; ------------------------------------------------------------------
  (define compress2
    (foreign-procedure "compress2" (u8* uptr u8* unsigned-long int) int))

  (define compressBound
    (foreign-procedure "compressBound" (unsigned-long) unsigned-long))

  ;; ------------------------------------------------------------------
  ;; Compress a bytevector using zlib (RFC 1950).
  ;; level: -1=default, 0=none, 1=fast, 9=best
  ;; Returns a new bytevector with compressed data.
  ;; ------------------------------------------------------------------
  (define (zlib-compress bv level)
    (if (not *zlib-loaded*)
        (error 'zlib-compress "zlib not available"))
    (let* ([src-len (bytevector-length bv)]
           [max-len (compressBound src-len)]
           [dest (make-bytevector max-len)]
           [dest-len-ptr (foreign-alloc (foreign-sizeof 'unsigned-long))])
      (foreign-set! 'unsigned-long dest-len-ptr 0 max-len)
      (let ([rc (compress2 dest dest-len-ptr bv src-len level)])
        (if (= rc 0)
            (let ([actual-len (foreign-ref 'unsigned-long dest-len-ptr 0)])
              (foreign-free dest-len-ptr)
              (let ([result (make-bytevector actual-len)])
                (bytevector-copy! dest 0 result 0 actual-len)
                result))
            (begin
              (foreign-free dest-len-ptr)
              (error 'zlib-compress "compression failed" rc))))))

  ;; ------------------------------------------------------------------
  ;; Gzip compression via custom C wrapper.
  ;; The wrapper calls deflateInit2 with windowBits=31 for gzip format.
  ;; ------------------------------------------------------------------
  (define (try-load-gzip-wrapper)
    (guard (ex [#t #f])
      (load-shared-object "./socket/zlib-gzip-wrapper.so")
      #t))

  (define *gzip-wrapper-loaded* (and *zlib-loaded* (try-load-gzip-wrapper)))

  (define gzip-compress-proc
    (and *gzip-wrapper-loaded*
         (guard (ex [#t #f])
           (foreign-procedure "http_pixiu_gzip_compress"
             (u8* unsigned-long u8* void* int) int))))

  (define (zlib-gzip-available?)
    (procedure? gzip-compress-proc))

  (define (zlib-gzip-compress bv level)
    (if (not (procedure? gzip-compress-proc))
        (error 'zlib-gzip-compress "gzip compression not available"))
    (let* ([src-len (bytevector-length bv)]
           [max-len (+ 18 (compressBound src-len))]
           [dest (make-bytevector max-len)]
           [dest-len-ptr (foreign-alloc (foreign-sizeof 'unsigned-long))])
      (foreign-set! 'unsigned-long dest-len-ptr 0 max-len)
      (let ([rc (gzip-compress-proc bv src-len dest dest-len-ptr level)])
        (if (= rc 0)
            (let ([actual-len (foreign-ref 'unsigned-long dest-len-ptr 0)])
              (foreign-free dest-len-ptr)
              (let ([result (make-bytevector actual-len)])
                (bytevector-copy! dest 0 result 0 actual-len)
                result))
            (begin
              (foreign-free dest-len-ptr)
              (error 'zlib-gzip-compress "gzip compression failed" rc))))))

)
