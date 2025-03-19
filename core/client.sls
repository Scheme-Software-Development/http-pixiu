(library (http-pixiu core client)
  (export 
    make-client
    client?
    client-socket
    client-send
    client-receive)
  (import 
    (chezscheme)
    (ufo-socket))

; 1MB
(define buff-size (* 1024 1024))
(define-record-type client
  (fields 
    (immutable socket)
    (immutable log-port))
  (protocol
    (lambda (new)
      (lambda (host port log-port)
        (new 
          (make-client-socket host port
            (address-family inet)
            (socket-domain stream)
            (address-info v4mapped addrconfig)
            (ip-protocol ip))
          log-port)))))

(define (client-send client-instance buff-bytevector)
  (socket-send (client-socket client-instance) buff-bytevector))

(define client-receive
  (case-lambda 
    [(client-instance) (client-receive client-instance buff-size 0)]
    [(client-instance buff-size flag) (socket-recv (client-socket client-instance) buff-size flag)]))

(define (do-log message client-instance)
  (if (not (null? (client-log-port client-instance)))
    (begin 
      (put-string (client-log-port client-instance) message)
      (put-string (client-log-port client-instance) "\n")
      (flush-output-port (client-log-port client-instance)))))

(define (do-log-timestamp client-instance)
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
    (if (not (null? (client-log-port client-instance)))
      (begin 
        (put-string (client-log-port client-instance) current-date-string)
        (put-string (client-log-port client-instance) "\n")
        (flush-output-port (client-log-port client-instance))))))
)