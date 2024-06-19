(library (http-pixiu)
  (export start-server)
  (import 
    (chezscheme)

    (http-pixiu core server)
    (http-pixiu core protocol request-parse)
    (http-pixiu core protocol response)
    (http-pixiu core protocol status)
    (http-pixiu core util try)
    (http-pixiu core util io)

    (chibi uri)
    (ufo-socket)
    (ufo-thread-pool))

(define private-static-path "./static")

(define (init-lifecycle socket)
  (lambda ()
    (call-with-socket socket
      (lambda (socket)
        (try 
          ;now only static pages
          (let* ([binary-input-port (socket-input-port socket)]
              [binary-output-port (socket-output-port socket)]
              [textual-input-port (transcoded-port binary-input-port (current-transcoder))]
              [closure (parse-request-coroutine textual-input-port binary-input-port)]
              [method (get-values-from-coroutine closure 'method)]
              [target-string (get-values-from-coroutine closure 'uri)]
              [uri (string->uri target-string)]
              [path (uri-path uri)]
              [local (string-append private-static-path path)])
            (pretty-print local)
            (cond 
              [(not (file-exists? local)) (write-response binary-output-port status:not-found '() '())]
              [else 
                (let ([fip (open-file-input-port (string-append private-static-path local))])
                  (write-response binary-output-port status:ok '()
                    (call-with-bytevector-output-port 
                      (lambda (op)
                        (let loop ([c (get-u8 fip)])
                          (cond
                            [(eof-object? c) #t]
                            [else 
                              (put-u8 op c)
                              (loop (get-u8 fip))]))))))]))
          (except c
            [(number? c) (write-response (socket-output-port socket) c '() '())]
            [else 
              (pretty-print `(format ,(condition-message c) ,@(condition-irritants c)))
              (raise c)]))))))

(define start-server
  (case-lambda 
    [(port) (start-server port (current-output-port) 1)]
    [(port thread-num) (start-server port (current-output-port) thread-num)]
    [(port log-port thread-num)
      (let* ([thread-pool (init-thread-pool thread-num)]
          [server (make-server port log-port thread-pool)])
        (display "Http-pixiu is working!")
        (newline)
        (let loop ([received-socket (socket-accept (server-socket server))])
          (pretty-print 'loop)
          (thread-pool-add-job thread-pool (init-lifecycle received-socket))
          (loop (socket-accept (server-socket server)))))]))
)
