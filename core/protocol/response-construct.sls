(library (http-pixiu core protocol response-construct)
  (export 
    write-response
    write-chunked-response
    write-json-response
    write-text-response
    write-html-response)
  (import 
    (chezscheme)
    (http-pixiu core util date)
    (http-pixiu core util association)
    (http-pixiu core protocol status)
    (http-pixiu core ffi sendfile)
    (http-pixiu core buffer-pool))

;; Pre-computed constant bytevectors to avoid repeated allocation
(define *bv-http11*          (string->utf8 "HTTP/1.1 "))
(define *bv-sp*              (string->utf8 " "))
(define *bv-crlf*            (string->utf8 "\r\n"))
(define *bv-server*          (string->utf8 "Server: http-pixiu\r\n"))
(define *bv-date-label*      (string->utf8 "Date: "))
(define *bv-conn-keep*       (string->utf8 "Connection: keep-alive\r\n"))
(define *bv-conn-close*      (string->utf8 "Connection: close\r\n"))
(define *bv-content-length-zero* (string->utf8 "Content-Length: 0\r\n"))
(define *bv-transfer-encoding-chunked* (string->utf8 "Transfer-Encoding: chunked\r\n"))
(define *bv-chunk-end*       (string->utf8 "0\r\n\r\n"))

;; Date header is cached at second granularity — HTTP only needs 1s precision.
(define *cached-date-second* 0)
(define *cached-date-bv* #f)

(define (get-cached-date-bv)
  (let ([now (time-second (current-time))])
    (if (= now *cached-date-second*)
        *cached-date-bv*
        (let ([bv (string->utf8 (date->string (current-date)))])
          (set! *cached-date-second* now)
          (set! *cached-date-bv* bv)
          bv))))

(define (status->reason-phrase status-id)
  (case status-id
    [(100) "Continue"]
    [(101) "Switching Protocols"]
    [(200) "OK"]
    [(201) "Created"]
    [(202) "Accepted"]
    [(203) "Non-Authoritative Information"]
    [(204) "No Content"]
    [(205) "Reset Content"]
    [(206) "Partial Content"]
    [(300) "Multiple Choices"]
    [(301) "Moved Permanently"]
    [(302) "Found"]
    [(303) "See Other"]
    [(304) "Not Modified"]
    [(305) "Use Proxy"]
    [(307) "Temporary Redirect"]
    [(400) "Bad Request"]
    [(401) "Unauthorized"]
    [(402) "Payment Required"]
    [(403) "Forbidden"]
    [(404) "Not Found"]
    [(405) "Method Not Allowed"]
    [(406) "Not Acceptable"]
    [(407) "Proxy Authentication Required"]
    [(408) "Request Timeout"]
    [(409) "Conflict"]
    [(410) "Gone"]
    [(411) "Length Required"]
    [(412) "Precondition Failed"]
    [(413) "Payload Too Large"]
    [(414) "URI Too Long"]
    [(415) "Unsupported Media Type"]
    [(416) "Range Not Satisfiable"]
    [(417) "Expectation Failed"]
    [(426) "Upgrade Required"]
    [(500) "Internal Server Error"]
    [(501) "Not Implemented"]
    [(502) "Bad Gateway"]
    [(503) "Service Unavailable"]
    [(504) "Gateway Timeout"]
    [(505) "HTTP Version Not Supported"]
    [else "Unknown"]))

(define write-response
  (case-lambda
    [(binary-output-port status-id alist body)
     (write-response binary-output-port status-id alist body #t #f)]
    [(binary-output-port status-id alist body send-body?)
     (write-response binary-output-port status-id alist body send-body? #f)]
    [(binary-output-port status-id alist body send-body? keep-alive?)
     (let ([is-stream (and (pair? body) (input-port? (car body)) (number? (cdr body)))]
           [body-bytevector (if (string? body) (string->utf8 body) body)])
       (put-bytevector binary-output-port *bv-http11*)
       (put-bytevector binary-output-port (string->utf8 (number->string status-id)))
       (put-bytevector binary-output-port *bv-sp*)
       (put-bytevector binary-output-port (string->utf8 (status->reason-phrase status-id)))
       (put-bytevector binary-output-port *bv-crlf*)
       (put-bytevector binary-output-port *bv-server*)
       (put-bytevector binary-output-port *bv-date-label*)
       (put-bytevector binary-output-port (get-cached-date-bv))
       (put-bytevector binary-output-port *bv-crlf*)
       (for-each
         (lambda (p)
           (put-bytevector binary-output-port (string->utf8 (car p)))
           (put-bytevector binary-output-port (string->utf8 ": "))
           (put-bytevector binary-output-port (string->utf8 (cdr p)))
           (put-bytevector binary-output-port *bv-crlf*))
         alist)
       (let ([body-size (cond
                          [is-stream (cdr body)]
                          [(bytevector? body-bytevector) (bytevector-length body-bytevector)]
                          [else #f])])
         (if body-size
           (begin 
             (put-bytevector binary-output-port (string->utf8 "Content-Length: "))
             (put-bytevector binary-output-port (string->utf8 (number->string body-size)))
             (put-bytevector binary-output-port *bv-crlf*)
             (put-bytevector binary-output-port
               (if keep-alive? *bv-conn-keep* *bv-conn-close*))
             (put-bytevector binary-output-port *bv-crlf*)
             (if send-body?
               (if is-stream
                 (let ([port (car body)] [size (cdr body)])
                   (let ([in-fd (guard (ex [#t #f]) (port-file-descriptor port))]
                         [out-fd (guard (ex [#t #f]) (port-file-descriptor binary-output-port))])
                     (if (and in-fd out-fd (sendfile-available?))
                         (sendfile-copy out-fd in-fd size)
                         (let ([buff (acquire-64k-buffer)])
                           (let loop ()
                             (let ([n (get-bytevector-n! port buff 0 65536)])
                               (if (and n (not (eof-object? n)) (> n 0))
                                 (begin (put-bytevector binary-output-port buff 0 n) (loop))
                                 (begin (release-64k-buffer buff) (void)))))))))
                 (put-bytevector binary-output-port body-bytevector)))
           (begin
             (put-bytevector binary-output-port *bv-content-length-zero*)
             (put-bytevector binary-output-port
               (if keep-alive? *bv-conn-keep* *bv-conn-close*))
             (put-bytevector binary-output-port *bv-crlf*))))))]))

(define write-json-response
  (case-lambda
    [(out status-id alist body)
     (write-json-response out status-id alist body #f)]
    [(out status-id alist body keep-alive?)
     (write-response out status-id 
       (cons (cons "Content-Type" "application/json") alist)
       body #t keep-alive?)]))

(define write-text-response
  (case-lambda
    [(out status-id alist body)
     (write-text-response out status-id alist body #f)]
    [(out status-id alist body keep-alive?)
     (write-response out status-id 
       (cons (cons "Content-Type" "text/plain") alist)
       body #t keep-alive?)]))

(define write-chunked-response
  (case-lambda
    ((binary-output-port status-id alist body)
     (write-chunked-response binary-output-port status-id alist body #t #f))
    ((binary-output-port status-id alist body send-body?)
     (write-chunked-response binary-output-port status-id alist body send-body? #f))
    ((binary-output-port status-id alist body send-body? keep-alive?)
     (put-bytevector binary-output-port *bv-http11*)
     (put-bytevector binary-output-port (string->utf8 (number->string status-id)))
     (put-bytevector binary-output-port *bv-sp*)
     (put-bytevector binary-output-port (string->utf8 (status->reason-phrase status-id)))
     (put-bytevector binary-output-port *bv-crlf*)
     (put-bytevector binary-output-port *bv-server*)
     (put-bytevector binary-output-port *bv-date-label*)
     (put-bytevector binary-output-port (get-cached-date-bv))
     (put-bytevector binary-output-port *bv-crlf*)
     (for-each
       (lambda (p)
         (put-bytevector binary-output-port (string->utf8 (car p)))
         (put-bytevector binary-output-port (string->utf8 ": "))
         (put-bytevector binary-output-port (string->utf8 (cdr p)))
         (put-bytevector binary-output-port *bv-crlf*))
       alist)
     (put-bytevector binary-output-port
       (if keep-alive? *bv-conn-keep* *bv-conn-close*))
     (put-bytevector binary-output-port *bv-transfer-encoding-chunked*)
     (put-bytevector binary-output-port *bv-crlf*)
     (when send-body?
       (if (and (pair? body) (input-port? (car body)))
           (let ((port (car body)) (buff (acquire-64k-buffer)))
             (let loop ()
               (let ((n (get-bytevector-n! port buff 0 65536)))
                 (if (and n (not (eof-object? n)) (> n 0))
                     (begin
                       (put-bytevector binary-output-port (string->utf8 (string-append (number->string n 16) "\r\n")))
                       (put-bytevector binary-output-port buff 0 n)
                       (put-bytevector binary-output-port *bv-crlf*)
                       (loop))
                     (begin (release-64k-buffer buff) (void))))))
           (let ((bv (if (string? body) (string->utf8 body) body)))
             (put-bytevector binary-output-port (string->utf8 (string-append (number->string (bytevector-length bv) 16) "\r\n")))
             (put-bytevector binary-output-port bv 0 (bytevector-length bv))
             (put-bytevector binary-output-port *bv-crlf*))))
     (put-bytevector binary-output-port *bv-chunk-end*))))

(define write-html-response
  (case-lambda
    [(out status-id alist body)
     (write-html-response out status-id alist body #f)]
    [(out status-id alist body keep-alive?)
     (write-response out status-id 
       (cons (cons "Content-Type" "text/html") alist)
       body #t keep-alive?)]))

)