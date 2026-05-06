(library (http-pixiu core protocol session)
  (export 
    session-store-create
    session-get
    session-set!
    session-destroy!
    parse-cookie-header
    generate-session-id
    make-session-cookie-header)
  (import (chezscheme))

(define-record-type session-store
  (fields (mutable table)
          timeout-seconds
          mutex))

(define (session-store-create timeout-seconds)
  (make-session-store (make-hashtable string-hash string=?) timeout-seconds (make-mutex)))

(define (current-epoch)
  (floor (time-second (current-time))))

(define (generate-session-id)
  (number->string
    (mod (bitwise-ior (random (expt 2 31)) (bitwise-arithmetic-shift (current-epoch) 32)) (expt 2 48))
    16))

(define (session-get store session-id)
  (with-mutex (session-store-mutex store)
    (let ([entry (hashtable-ref (session-store-table store) session-id #f)])
      (if entry
          (let ([expires (cadr entry)])
            (if (> (current-epoch) expires)
                (begin
                  (hashtable-delete! (session-store-table store) session-id)
                  '())
                (caddr entry)))
          '()))))

(define (session-set! store session-id data)
  (with-mutex (session-store-mutex store)
    (let ([expires (+ (current-epoch) (session-store-timeout-seconds store))])
      (hashtable-set! (session-store-table store) session-id (list 'session expires data)))))

(define (session-destroy! store session-id)
  (with-mutex (session-store-mutex store)
    (hashtable-delete! (session-store-table store) session-id)))

(define (parse-cookie-header header-value)
  (if (string? header-value)
      (let ([parts (string-split header-value #\;)])
        (let loop ([remaining parts] [result '()])
          (if (null? remaining)
              result
              (let* ([trimmed (string-trim (car remaining))]
                     [kv (string-split trimmed #\=)])
                (if (= (length kv) 2)
                    (loop (cdr remaining)
                          (cons (cons (car kv) (cadr kv)) result))
                    (loop (cdr remaining) result))))))
      '()))

(define (string-split str delim)
  (let loop ([i 0] [start 0] [result '()])
    (if (>= i (string-length str))
        (reverse (cons (substring str start i) result))
        (if (char=? (string-ref str i) delim)
            (loop (+ i 1) (+ i 1) (cons (substring str start i) result))
            (loop (+ i 1) start result)))))

(define (string-trim str)
  (let ([len (string-length str)])
    (let ([start (let loop ([i 0])
                   (if (and (< i len) (char=? (string-ref str i) #\space))
                       (loop (+ i 1))
                       i))]
          [end (let loop ([i len])
                 (if (and (> i 0) (char=? (string-ref str (- i 1)) #\space))
                     (loop (- i 1))
                     i))])
      (substring str start end))))

(define (make-session-cookie-header session-id timeout-seconds)
  (string-append "session-id=" session-id
                 "; HttpOnly; Path=/; Max-Age=" (number->string timeout-seconds)))

)