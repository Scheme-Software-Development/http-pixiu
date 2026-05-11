(library (http-pixiu core server)
  (export 
    make-server
    server?

    server-socket
    server-log-port
    server-thread-pool
    server-shutdown?
    server-shutdown?-set!
    server-in-flight-counter
    server-in-flight-counter-set!)
  (import 
    (chezscheme)
    (ufo-socket))

(define-record-type server
  (fields 
    (immutable socket)
    (immutable log-port)
    (immutable thread-pool)
    (mutable shutdown?)
    (mutable in-flight-counter))
  (protocol
    (lambda (new)
      (lambda (port log-port thread-pool )
        (new 
          (make-server-socket port)
          log-port 
          thread-pool
          #f
          0)))))


)
