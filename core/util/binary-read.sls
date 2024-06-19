(library (http-pixiu core util binary-read)
  (export step-forward-to)
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
)