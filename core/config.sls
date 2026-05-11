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
    (idle-timeout-ms . 5000)
    (vhosts . ())
    (cache-control-max-age . 3600)))

(define (config-get config key)
  (let ([pair (assoc key config)])
    (if pair (cdr pair) #f)))

(define *valid-config-keys*
  '(port thread-num expire-duration ticks static-path log-file log-format
    max-queue-size rate-limit-window rate-limit-max cors-allow-origin
    session-timeout idle-timeout-ms vhosts cache-control-max-age))

(define (config-safe-read content)
  (let ([data (read (open-string-input-port content))])
    (if (not (list? data))
        (error 'config-safe-read "Config must be an association list"))
    (for-each
      (lambda (pair)
        (if (not (and (pair? pair) (symbol? (car pair))))
            (error 'config-safe-read "Invalid config entry"))
        (if (not (member (car pair) *valid-config-keys*))
            (error 'config-safe-read (string-append "Unknown config key: " (symbol->string (car pair))))))
      data)
    data))

(define (config-validate! config)
  (define (check key pred expected)
    (let ([v (config-get config key)])
      (when (and v (not (pred v)))
        (error 'config-validate (string-append "Invalid config value for " (symbol->string key) ": expected " expected)))))
  (check 'port string? "string")
  (check 'thread-num integer? "integer")
  (check 'expire-duration integer? "integer")
  (check 'ticks integer? "integer")
  (check 'static-path string? "string")
  (check 'max-queue-size integer? "integer")
  (check 'rate-limit-window integer? "integer")
  (check 'rate-limit-max integer? "integer")
  (check 'session-timeout integer? "integer")
  (check 'idle-timeout-ms integer? "integer")
  (check 'cache-control-max-age integer? "integer")
  config)

(define (config-load path)
  (guard (ex [#t (begin
                    (display "Config file not found, using defaults.") (newline)
                    (make-config))])
    (let ([port (open-file-input-port path)])
      (let ([content (get-string-all port)])
        (close-input-port port)
        (config-validate! (config-safe-read content))))))
)
