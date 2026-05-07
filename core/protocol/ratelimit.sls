(library (http-pixiu core protocol ratelimit)
  (export 
    make-rate-limiter
    rate-limiter-allow?)
  (import (chezscheme))

(define-record-type rate-limiter
  (fields (mutable table)
          window-seconds
          max-requests
          mutex))

(define (make-rate-limiter window-seconds max-requests)
  (make-rate-limiter (make-hashtable string-hash string=?) window-seconds max-requests (make-mutex)))

(define (current-epoch)
  (floor (time-second (current-time))))

(define (rate-limiter-allow? limiter client-id)
  (with-mutex (rate-limiter-mutex limiter)
    (let ([table (rate-limiter-table limiter)]
          [now (current-epoch)]
          [window (rate-limiter-window-seconds limiter)]
          [max-req (rate-limiter-max-requests limiter)])
      (let ([entry (eq-hashtable-ref table client-id #f)])
        (if entry
            (let ([bucket-start (car entry)]
                  [count (cdr entry)])
              (if (> (- now bucket-start) window)
                  (begin
                    (eq-hashtable-set! table client-id (cons now 1))
                    #t)
                  (if (< count max-req)
                      (begin
                        (eq-hashtable-set! table client-id (cons bucket-start (+ count 1)))
                        #t)
                      #f)))
            (begin
              (eq-hashtable-set! table client-id (cons now 1))
              #t))))))

)