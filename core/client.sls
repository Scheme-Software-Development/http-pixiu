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


)