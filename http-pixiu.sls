(library (http-pixiu)
  (export )
  (import 
    (chezscheme)

    (http-pixiu core server)
    (http-pixiu core protocol request-parse)
    (http-pixiu core protocol response)
    (http-pixiu core protocol status)
    (http-pixiu core util try)
    (http-pixiu core util io)

    (chibi uri)
    (ufo-thread-pool))

(define private-static-path "./static")

(define (init-lifecycle socket)
  (call-with-socket socket
    (lambda (socket)
      (try 
        ;now only static pages
        (let* ([binary-input-port (socket-input-port socket)]
            [binary-output-port (socket-output-port socket)]
            [textual-input-port (transcoded-port binary-input-port (current-transcorder))]
            [closure (parse-request-coroutine textual-input-port binary-input-port)]
            [method (get-values-from-coroutine closure 'method)]
            [target-string (get-values-from-coroutine closure 'uri)])
            [uri (string->uri target-string)]
            [path (uri-path uri)]
            [fip (open-file-input-port (string-append private-static-path path))])
          (pretty-print path)
          (write-response binary-output-port status:ok '()
            (call-with-bytevector-output-port fip
              (lambda (op)
                (let loop ([c (get-u8 fip)])
                  (case 
                    [(#!eof) #t]
                    [else 
                      (put-u8 op c)
                      (loop (get-u8 fip))]))))))
        (except e
          [(number? e) (write-response (socket-output-port socket) e alist body-bytevector)]
          [else (raise e)]))))

(define start-server
  (case-lambda 
    [(port) (make-server port (current-output-port) 1)]
    [(port log-port thread-num)
      (let* ([thread-pool (init-thread-pool thread-num)]
          [server (make-server port log-port thread-pool)])
        (display "Http-pixiu is working!")
        (newline)
        (let loop ([received-socket (socket-accept (server-socket server))])
          (thread-pool-add-job thread-pool (init-lifecycle received-socket))
          (loop (socket-accept (server-socket server)))))]))
)
