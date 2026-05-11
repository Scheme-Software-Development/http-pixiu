(library (http-pixiu core util binary-read)
  (export step-forward-to
          make-buffered-binary-input-port)
  (import (chezscheme))

(define (step-forward-to bytevector-output-port binary-input-port target-u8-integer length)
  (let loop ([b (lookahead-u8 binary-input-port)]
      [remain-length length])
    (cond 
      [(eof-object? b) #f]
      [(zero? remain-length) #f]
      [(= b target-u8-integer) (put-u8 bytevector-output-port (get-u8 binary-input-port)) #t]
      [else 
        (put-u8 bytevector-output-port (get-u8 binary-input-port))
        (loop (lookahead-u8 binary-input-port) (- length 1))])))

;; ------------------------------------------------------------------
;; Buffered binary input port wrapper
;; Reduces syscall overhead for small sequential reads (e.g. HTTP headers)
;; by reading larger chunks into memory and serving get-u8 from there.
;; ------------------------------------------------------------------
(define (make-buffered-binary-input-port port buffer-size)
  (let ([buffer (make-bytevector buffer-size)]
        [pos 0]
        [limit 0])
    (make-custom-binary-input-port
      "buffered-input"
      (lambda (dst start count)
        (let ([result 0])
          (let loop ()
            (if (>= result count)
                result
                (if (< pos limit)
                    (let ([to-copy (min (- count result) (- limit pos))])
                      (bytevector-copy! buffer pos dst (+ start result) to-copy)
                      (set! pos (+ pos to-copy))
                      (set! result (+ result to-copy))
                      (loop))
                    (let ([n (get-bytevector-some! port buffer 0 buffer-size)])
                      (if (or (not n) (eof-object? n) (zero? n))
                          result
                          (begin
                            (set! pos 0)
                            (set! limit n)
                            (loop)))))))))
      #f
      #f
      (lambda () (close-input-port port)))))
)
