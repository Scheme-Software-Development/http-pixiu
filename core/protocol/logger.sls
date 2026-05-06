(library (http-pixiu core protocol logger)
  (export 
    log-request
    log-error
    log-info)
  (import (chezscheme)
          (http-pixiu core util date))

(define log-lock (make-mutex))

(define (current-timestamp)
  (date->string (current-date)))

(define (log-message level msg port)
  (with-mutex log-lock
    (let ([line (string-append "[" (current-timestamp) "] " level " " msg "\n")])
      (if port
          (begin
            (put-string port line)
            (flush-output-port port))
          (begin
            (display line)
            (flush-output-port (current-output-port)))))))

(define (log-request method uri status client-ip user-agent port)
  (let ([msg (string-append client-ip " - - \"" method " " uri " HTTP/1.1\" " (number->string status)
                            " \"-\" \"" (if user-agent user-agent "-") "\"")])
    (log-message "INFO" msg port)))

(define (log-error msg port)
  (log-message "ERROR" msg port))

(define (log-info msg port)
  (log-message "INFO" msg port))

)