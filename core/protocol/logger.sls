(library (http-pixiu core protocol logger)
  (export
    make-logger
    logger?
    logger-port
    logger-shutdown!
    log-request
    log-error
    log-info)

  (import (chezscheme)
          (slib queue)
          (http-pixiu core util date))

  (define log-lock (make-mutex))

  (define-record-type (logger make-logger-raw logger?)
    (fields (mutable port)
            (mutable date-str)
            (mutable base-path)
            format
            (mutable queue)
            (mutable mutex)
            (mutable condition)
            (mutable shutdown?)
            (mutable thread)))

  (define (current-date-str)
    (let ([t (current-date)])
      (string-append
        (number->string (date-year t)) "-"
        (string-pad (number->string (date-month t)) 2 #\0) "-"
        (string-pad (number->string (date-day t)) 2 #\0))))

  (define (open-log-file base-path date-str)
    (open-file-output-port
      (string-append base-path "-" date-str ".log")
      (file-options no-fail)
      (buffer-mode block)
      (native-transcoder)))

  (define (make-logger base-path format)
    (let ([d (current-date-str)]
          [q (make-queue)]
          [m (make-mutex)]
          [c (make-condition)])
      (let ([port (open-log-file base-path d)])
        (let ([logger (make-logger-raw port d base-path format q m c #f #f)])
          (logger-thread-set! logger
            (fork-thread
              (lambda ()
                (let loop ()
                  (with-mutex m
                    (if (queue-empty? q)
                        (if (logger-shutdown? logger)
                            (begin
                              (close-output-port (logger-port logger))
                              (display "Logger thread shutting down.") (newline))
                            (begin
                              (condition-wait c m)
                              (loop)))
                        (let ([msg (dequeue! q)])
                          (with-mutex log-lock
                            (maybe-rotate! logger)
                            (put-string (logger-port logger) msg)
                            (flush-output-port (logger-port logger)))
                          (loop))))))))
          logger))))

  (define (maybe-rotate! log-info)
    (when (logger? log-info)
      (let ([new-date (current-date-str)])
        (when (not (equal? new-date (logger-date-str log-info)))
          (close-output-port (logger-port log-info))
          (logger-port-set! log-info (open-log-file (logger-base-path log-info) new-date))
          (logger-date-str-set! log-info new-date)))))

  (define (month-name m)
    (case m
      [(1) "Jan"] [(2) "Feb"] [(3) "Mar"] [(4) "Apr"]
      [(5) "May"] [(6) "Jun"] [(7) "Jul"] [(8) "Aug"]
      [(9) "Sep"] [(10) "Oct"] [(11) "Nov"] [(12) "Dec"]))

  (define (string-pad s n c)
    (if (< (string-length s) n)
        (string-append (make-string (- n (string-length s)) c) s)
        s))

  (define (clf-date-string)
    (let ([t (current-date)])
      (string-append
        (string-pad (number->string (date-day t)) 2 #\0) "/"
        (month-name (date-month t)) "/"
        (number->string (date-year t)) ":"
        (string-pad (number->string (date-hour t)) 2 #\0) ":"
        (string-pad (number->string (date-minute t)) 2 #\0) ":"
        (string-pad (number->string (date-second t)) 2 #\0)
        " +0800")))

  (define (current-timestamp)
    (date->string (current-date 0)))

  (define (logger-shutdown! logger)
    (with-mutex (logger-mutex logger)
      (logger-shutdown?-set! logger #t)
      (condition-signal (logger-condition logger))))

(define (log-message level msg port-or-logger)
    (with-mutex log-lock
      (maybe-rotate! port-or-logger)
      (let ([port (if (logger? port-or-logger) (logger-port port-or-logger) port-or-logger)])
        (let ([line (string-append "[" (current-timestamp) "] " level " " msg "\n")])
          (if (and port (not (null? port)))
              (begin
                (put-string port line)
                (flush-output-port port))
              (begin
                (display line)
                (flush-output-port (current-output-port))))))))

  (define (log-request port-or-logger method path status response-size . rest)
    (let ([protocol (if (>= (length rest) 1) (list-ref rest 0) "HTTP/1.1")]
          [client-ip (if (>= (length rest) 2) (list-ref rest 1) #f)]
          [user-agent (if (>= (length rest) 3) (list-ref rest 2) #f)])
      (if (logger? port-or-logger)
          (let ([msg
                 (case (logger-format port-or-logger)
                   [(json)
                    (string-append
                      "{\"time\":\"" (current-timestamp) "\","
                      "\"client\":\"" (or client-ip "-") "\","
                      "\"method\":\"" method "\","
                      "\"path\":\"" path "\","
                      "\"status\":" (number->string status) ","
                      "\"size\":" (number->string response-size) "}\n")]
                   [else
                    ;; Nginx CLF
                    (string-append
                      (or client-ip "-") " - - [" (clf-date-string) "] \""
                      method " " path " " protocol "\" "
                      (number->string status) " "
                      (number->string response-size) " \"-\" \""
                      (or user-agent "-") "\"\n")])])
            (with-mutex (logger-mutex port-or-logger)
              (enqueue! (logger-queue port-or-logger) msg)
              (condition-signal (logger-condition port-or-logger))))
          ;; Fallback: old flat format for raw ports
          (let ([msg (string-append method " \"" path "\" " (number->string status) " " (number->string response-size))])
            (log-message "INFO" msg port-or-logger)))))

  (define (log-error port-or-logger msg)
    (log-message "ERROR" msg port-or-logger))

  (define (log-info port-or-logger msg)
    (log-message "INFO" msg port-or-logger))
)
