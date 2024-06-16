(library (http-pixiu core protocol response)
  (export 
    make-response)
  (import 
    (chezscheme)
    (http-pixiu core util date)
    (http-pixiu core util association)
    (http-pixiu core protocol status))

(define (make-response alist body)
  (let* ([line0 "HTTP/1.1 " (number->string (assoc-ref 'status-id alist)) " OK"]
      [line1 "Server: http-pixiu"]
      [line2 (string-append line0 "date: " (date->string (current-date)))]
      [must (string-append line0 "\n" line1 "\n" line2 "\n")]
      [without-body
        (fold-left 
          string-append
          must
          (map (lambda (p) (string-append (car p) ": " (cdr p) "\n")) alist))])
    (if (null? body)
      without-body
    )
    ; (string-append 
    ;   without-body
    ;   )
      ))

)