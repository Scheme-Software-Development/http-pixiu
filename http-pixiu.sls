(library (http-pixiu)
  (export start-server)
  (import 
    (chezscheme)

    (http-pixiu core server)
    (http-pixiu core protocol request-parse)
    (http-pixiu core protocol request-queue)
    (http-pixiu core protocol response)
    (http-pixiu core protocol status)
    (http-pixiu core util io)

    (chibi uri)
    (ufo-socket)
    (ufo-try)
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
              [closure (parse-request-coroutine binary-input-port)])
            (let*-values ([(closure0 method) (get-values-from-coroutine closure 'method)]
                [(closure1 target-string) (get-values-from-coroutine closure0 'uri)])
              (let* ([uri (string->path-uri 'http target-string)]
                  [path (uri-path uri)]
                  [local (string-append private-static-path path)])
                (let ([fip (open-file-input-port local)])
                  (write-response binary-output-port status:ok '()
                    (call-with-bytevector-output-port 
                      (lambda (op)
                        (let loop ([c (get-u8 fip)])
                          (cond
                            [(eof-object? c) #t]
                            [else 
                              (put-u8 op c)
                              (loop (get-u8 fip))])))))))))
          (except c
            [(number? c) (write-response (socket-output-port socket) c '() '())]
            [else (write-response (socket-output-port socket) status:not-found '() '())]))))))

; ms
(define expire-duration 1000)
(define ticks 100000)

(define start-server
  (case-lambda 
    [(port) (start-server port (current-output-port) 1 expire-duration ticks)]
    [(port thread-num) (start-server port (current-output-port) thread-num expire-duration ticks)]
    [(port thread-num expire-duration ticks) (start-server port (current-output-port) thread-num expire-duration ticks)]
    [(port log-port thread-num expire-duration ticks)
      (let* ([thread-pool (init-thread-pool thread-num)]
          [request-queue (make-request-queue)]
          [server (make-server port log-port thread-pool)])
        (map 
          (lambda (i)
            (thread-pool-add-job thread-pool 
              (lambda () 
                (let loop ()
                  ((request-queue-pop request-queue))
                  (loop))))) 
          (iota thread-num))
        (display "Http-pixiu is working!")
        (newline)
        (let loop ([received-socket (socket-accept (server-socket server))])
          (request-queue-push request-queue (init-lifecycle received-socket) expire-duration ticks)
          (loop (socket-accept (server-socket server)))))]))
)
