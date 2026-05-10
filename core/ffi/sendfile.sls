(library (http-pixiu core ffi sendfile)
  (export
    sendfile-available?
    sendfile-copy)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Linux sendfile64 FFI binding
  ;; Falls back to manual copy on non-Linux or when unavailable.
  ;; ------------------------------------------------------------------

  (define (try-load-sendfile)
    (guard (ex [#t #f])
      (load-shared-object "libc.so.6")
      #t))

  (define sendfile-proc
    (and (try-load-sendfile)
         (guard (ex [#t #f])
           (foreign-procedure "sendfile64"
                              (int int (* long) size_t)
                             long))))

  (define (sendfile-available?)
    (procedure? sendfile-proc))

  (define (sendfile-fallback out-fd in-fd count)
    (let ([buffer (make-bytevector 65536)])
      (let loop ([remaining count] [total 0])
        (if (<= remaining 0)
            total
            (let ([n ((foreign-procedure "read" (int void* size_t) long)
                      in-fd buffer (min remaining 65536))])
              (if (<= n 0)
                  total
                  (let ([w ((foreign-procedure "write" (int void* size_t) long)
                            out-fd buffer n)])
                    (if (<= w 0)
                        total
                        (loop (- remaining w) (+ total w))))))))))

  (define (sendfile-copy out-fd in-fd count)
    (if (sendfile-available?)
        (let ([offset (foreign-alloc (foreign-sizeof 'long))])
          (foreign-set! 'long offset 0 0)
          (let ([sent (sendfile-proc out-fd in-fd offset count)])
            (foreign-free offset)
            (if (< sent 0)
                (sendfile-fallback out-fd in-fd count)
                sent)))
        (sendfile-fallback out-fd in-fd count)))

)