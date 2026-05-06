(library (http-pixiu core protocol request-construct)
  (export 
    construct-request-string)
  (import 
    (chezscheme))

(define (header-alist->string header-alist)
  (let ([out (open-output-string)])
    (for-each
      (lambda (p)
        (display (car p) out)
        (display ": " out)
        (display (cdr p) out)
        (display "\r\n" out))
      header-alist)
    (get-output-string out)))

(define construct-request-string
  (case-lambda 
    [(method url version header-alist)
      (string-append 
        (symbol->string method) " " url " " version "\r\n"
        (header-alist->string header-alist)
        "\r\n")]
    [(method url version header-alist body)
      (string-append 
        (construct-request-string method url version 
            `(,@header-alist ("Content-Length" . ,(number->string (bytevector-length (string->utf8 body))))))
          body)]))

)