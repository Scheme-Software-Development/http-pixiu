(library (http-pixiu)
  (export )
  (import 
    (chezscheme)

    (http-pixiu core server)
    (http-pixiu core protocol )

    (ufo-thread-pool))

(define start-server
  (case-lambda 
    [(port) (make-server port (current-output-port) 1)]
    [(port log-port thread-num)
      (let* ([thread-pool (init-thread-pool thread-num)]
          [server (make-server port log-port thread-pool)])
        (display "Http-pixiu is working!")
        (newline)
        (let loop ([socket (socket-accept srv)])
            ; (in (socket-input-port sock))
            ; (out (socket-output-port sock))

        ))]
  ))
)
