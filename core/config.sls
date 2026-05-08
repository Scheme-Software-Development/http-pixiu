(library (http-pixiu core config)
  (export 
    config-get
    config-load
    make-config)
  (import (chezscheme))

(define (make-config)
  `((port . "5000")
    (thread-num . 4)
    (expire-duration . 1000)
    (ticks . 100000)
    (static-path . "./static")
    (log-file . #f)
    (log-format . "combined")
    (max-queue-size . 64)
    (rate-limit-window . 60)
    (rate-limit-max . 100)
    (cors-allow-origin . "*")
    (session-timeout . 3600)
    (idle-timeout-ms . 5000)))

(define (config-get config key)
  (let ([pair (assoc key config)])
    (if pair (cdr pair) #f)))

(define (config-load path)
  (guard (ex [#t (begin
                    (display "Config file not found, using defaults.") (newline)
                    (make-config))])
    (let ([port (open-file-input-port path)])
      (let ([content (get-string-all port)])
        (close-input-port port)
        (read (open-string-input-port content))))))
)
