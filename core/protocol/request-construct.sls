(library (http-pixiu core protocol request-construct)
  (export 
    construct-request-string)
  (import 
    (chezscheme))

(define construct-request-string
  (case-lambda 
    [(method url version header-alist)
      (string-append 
        method " " url " " version "\r\n"
        (fold-left
          string-append
          ""
          (map (lambda (p) (string-append (car p) ": " (cdr p) "\r\n")) header-alist))
        "\r\n")]
    [(method url version header-alist body)
      (string-append 
        (construct-request-string method url version 
            `(,@header-alist ("content-length" . ,(bytevector-length (string->utf8 body)))))
          body)]))
)