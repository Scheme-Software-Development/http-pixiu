(library (http-pixiu core protocol response-construct)
  (export 
    write-response)
  (import 
    (chezscheme)
    (http-pixiu core util date)
    (http-pixiu core util association)
    (http-pixiu core protocol status))

(define (write-response binary-output-port status-id alist body-bytevector)
  (put-bytevector binary-output-port (string->bytevector "HTTP/1.1 " (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector (number->string status-id) (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector " OK\n" (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector "Server: http-pixiu\n" (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector "date: " (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector (date->string (current-date)) (current-transcoder)))
  (put-bytevector binary-output-port (string->bytevector "\n" (current-transcoder)))
  (put-bytevector binary-output-port 
    (string->bytevector
      (fold-left 
        string-append
        ""
        (map (lambda (p) (string-append (car p) ": " (cdr p) "\n")) alist))
      (current-transcoder)))
  (if (bytevector? body-bytevector)
    (begin 
      (put-bytevector binary-output-port (string->bytevector "content-length: " (current-transcoder)))
      (put-bytevector binary-output-port (string->bytevector (number->string (bytevector-length body-bytevector)) (current-transcoder)))
      (put-bytevector binary-output-port (string->bytevector "\n" (current-transcoder)))
      (put-bytevector binary-output-port (string->bytevector "\n" (current-transcoder)))
      (put-bytevector binary-output-port body-bytevector))))
)