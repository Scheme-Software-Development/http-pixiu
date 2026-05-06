(import 
    (chezscheme) 
    (http-pixiu))
(let ([args (command-line-arguments)])
  (if (null? args)
      (display "Usage: scheme --script run.ss <port> [thread-num] [expire-ms] [ticks]\n")
      (let ([port (car args)]
            [rest (map string->number (cdr args))])
        (case (length rest)
          [(0) (start-server port)]
          [(1) (start-server port (car rest))]
          [(2) (start-server port 1 (car rest) (cadr rest))]
          [else (apply start-server (cons port rest))]))))
