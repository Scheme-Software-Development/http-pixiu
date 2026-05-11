(library (http-pixiu core protocol ratelimit)
  (export 
    make-rate-limiter
    rate-limiter-allow?)
  (import (chezscheme))

(define-record-type (rate-limiter make-rate-limiter-raw rate-limiter?)
  (fields (mutable table)
          window-seconds
          max-requests
          max-entries
          mutex))

(define (make-rate-limiter window-seconds max-requests)
  (let ([limiter (make-rate-limiter-raw (make-hashtable string-hash string=?)
                                        window-seconds
                                        max-requests
                                        10000
                                        (make-mutex))])
    ;; Start background cleanup thread
    (fork-thread
      (lambda ()
        (let loop ()
          (sleep (make-time 'time-duration 0 60))  ; every 60 seconds
          (rate-limiter-cleanup! limiter)
          (loop))))
    limiter))

(define (current-epoch)
  (floor (time-second (current-time))))

(define (rate-limiter-cleanup! limiter)
  (with-mutex (rate-limiter-mutex limiter)
    (let ([table (rate-limiter-table limiter)]
          [window (rate-limiter-window-seconds limiter)]
          [now (current-epoch)])
      (vector-for-each
        (lambda (key)
          (let ([entry (hashtable-ref table key #f)])
            (when (and entry (> (- now (car entry)) (* window 2)))
              (hashtable-delete! table key))))
        (hashtable-keys table)))))

(define (rate-limiter-allow? limiter client-id)
  (with-mutex (rate-limiter-mutex limiter)
    (let ([table (rate-limiter-table limiter)]
          [now (current-epoch)]
          [window (rate-limiter-window-seconds limiter)]
          [max-req (rate-limiter-max-requests limiter)]
          [max-entries (rate-limiter-max-entries limiter)])
      (when (>= (hashtable-size table) max-entries)
        (rate-limiter-cleanup! limiter))
      (let ([entry (hashtable-ref table client-id #f)])
        (if entry
            (let ([bucket-start (car entry)]
                  [count (cdr entry)])
              (if (> (- now bucket-start) window)
                  (begin
                    (hashtable-set! table client-id (cons now 1))
                    #t)
                  (if (< count max-req)
                      (begin
                        (hashtable-set! table client-id (cons bucket-start (+ count 1)))
                        #t)
                      #f)))
            (begin
              (hashtable-set! table client-id (cons now 1))
              #t))))))

)
