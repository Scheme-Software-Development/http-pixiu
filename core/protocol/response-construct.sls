(library (http-pixiu core protocol response-construct)
  (export 
    write-response
    write-json-response
    write-text-response
    write-html-response)
  (import 
    (chezscheme)
    (http-pixiu core util date)
    (http-pixiu core util association)
    (http-pixiu core protocol status))

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
     (write-response binary-output-port status-id alist body #t)]
    [(binary-output-port status-id alist body send-body?)
     (let ([body-bytevector (if (string? body) (string->utf8 body) body)])
       (put-bytevector binary-output-port (string->bytevector "HTTP/1.1 " (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector (number->string status-id) (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector " " (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector (status->reason-phrase status-id) (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector "\r\n" (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector "Server: http-pixiu\r\n" (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector "Date: " (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector (date->string (current-date)) (current-transcoder)))
       (put-bytevector binary-output-port (string->bytevector "\r\n" (current-transcoder)))
       (put-bytevector binary-output-port 
         (string->bytevector
           (fold-left 
             string-append
             ""
             (map (lambda (p) (string-append (car p) ": " (cdr p) "\r\n")) alist))
           (current-transcoder)))
       (if (bytevector? body-bytevector)
         (begin 
           (put-bytevector binary-output-port (string->bytevector "Content-Length: " (current-transcoder)))
           (put-bytevector binary-output-port (string->bytevector (number->string (bytevector-length body-bytevector)) (current-transcoder)))
           (put-bytevector binary-output-port (string->bytevector "\r\n" (current-transcoder)))
           (put-bytevector binary-output-port (string->bytevector "Connection: close\r\n" (current-transcoder)))
           (put-bytevector binary-output-port (string->bytevector "\r\n" (current-transcoder)))
           (if send-body?
             (put-bytevector binary-output-port body-bytevector)))
         (begin
           (put-bytevector binary-output-port (string->bytevector "Connection: close\r\n" (current-transcoder)))
           (put-bytevector binary-output-port (string->bytevector "\r\n" (current-transcoder))))))]))

(define (write-json-response out status-id alist body)
  (write-response out status-id 
    (cons (cons "Content-Type" "application/json") alist)
    body))

(define (write-text-response out status-id alist body)
  (write-response out status-id 
    (cons (cons "Content-Type" "text/plain") alist)
    body))

(define (write-html-response out status-id alist body)
  (write-response out status-id 
    (cons (cons "Content-Type" "text/html") alist)
    body))

)