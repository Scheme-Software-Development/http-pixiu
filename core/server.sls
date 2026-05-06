(library (http-pixiu core server)
  (export 
    make-server
    server?

    server-socket
    server-log-port
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
          (make-server-socket port)
          log-port 
          thread-pool)))))


)