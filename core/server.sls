(library (http-pixiu core server)
  (export 
    make-server
    server?

    server-socket
    server-thread-pool)
  (import 
    (chezscheme)
    (ufo-socket))

(define-record-type server
  (fields 
    (immutable socket)
    (immutable log-port)
    (immutable thread-pool))
  (protocol
    (lambda (new)
      (lambda (port log-port thread-pool )
        (new 
          (make-server-socket (number->string port))
          log-port 
          thread-pool)))))

(define (do-log message server-instance)
  (if (not (null? (server-log-port server-instance)))
    (begin 
      (put-string (server-log-port server-instance) message)
      (put-string (server-log-port server-instance) "\n")
      (flush-output-port (server-log-port server-instance)))))

(define (do-log-timestamp server-instance)
  (let* ([date (current-date)]
      [current-date-string 
        (fold-left 
          (lambda (h t) (string-append h " " t )) 
          (number->string (date-year date))
          (map 
            number->string 
            (map 
              (lambda (f) (f date))
              (list date-month date-day date-hour date-minute date-second date-nanosecond))))])
    (if (not (null? (server-log-port server-instance)))
      (begin 
        (put-string (server-log-port server-instance) current-date-string)
        (put-string (server-log-port server-instance) "\n")
        (flush-output-port (server-log-port server-instance))))))
)