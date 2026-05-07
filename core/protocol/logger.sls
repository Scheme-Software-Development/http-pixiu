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
        (if (and port (not (null? port)))
            (begin
              (put-string port line)
              (flush-output-port port))
            (begin
              (display line)
              (flush-output-port (current-output-port)))))))

  ;; Main access log: compatible with http-pixiu's old log-access
  (define (log-request log-port method path status response-size)
    (let ([msg (string-append method " \"" path "\" " (number->string status) " " (number->string response-size))])
      (log-message "INFO" msg log-port)))

  (define (log-error msg port)
    (log-message "ERROR" msg port))

  (define (log-info msg port)
    (log-message "INFO" msg port))

)
