(library (http-pixiu core connection-counter)
  (export
    make-connection-counter
    connection-counter-acquire!
    connection-counter-release!
    connection-counter-current)

  (import (chezscheme))

  (define-record-type (connection-counter make-connection-counter-raw connection-counter?)
    (fields (mutable count) max mutex))

  (define (make-connection-counter max)
    (make-connection-counter-raw 0 max (make-mutex)))

  (define (connection-counter-acquire! counter)
    (with-mutex (connection-counter-mutex counter)
      (if (< (connection-counter-count counter) (connection-counter-max counter))
          (begin
            (connection-counter-count-set! counter (+ 1 (connection-counter-count counter)))
            #t)
          #f)))

  (define (connection-counter-release! counter)
    (with-mutex (connection-counter-mutex counter)
      (let ([c (connection-counter-count counter)])
        (when (> c 0)
          (connection-counter-count-set! counter (- c 1))))))

  (define (connection-counter-current counter)
    (with-mutex (connection-counter-mutex counter)
      (connection-counter-count counter)))
)
