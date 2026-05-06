(library (http-pixiu core protocol error-pages)
  (export load-error-page
          error-page-response)
  (import (chezscheme)
          (http-pixiu core protocol status)
          (http-pixiu core protocol response-construct))

(define *error-page-cache* (make-hashtable string-hash string=?))
(define *error-page-cache-mutex* (make-mutex))

(define (cache-key static-path status-code)
  (string-append static-path "#" (number->string status-code)))

(define (load-error-page-raw static-path status-code)
  (let ([path (string-append static-path "/error-" (number->string status-code) ".html")])
    (let ([content (guard (ex [#t #f])
                     (let ([p (open-file-input-port path)])
                       (let ([bv (get-bytevector-all p)])
                         (close-input-port p)
                         bv)))])
      (if (bytevector? content)
          content
          (string->utf8
            (string-append
              "<!DOCTYPE html><html><head><title>Error " (number->string status-code) "</title></head>"
              "<body><h1>" (number->string status-code) " " (status->reason-phrase status-code) "</h1></body></html>"))))))

(define (load-error-page static-path status-code)
  (let ([key (cache-key static-path status-code)])
    (with-mutex *error-page-cache-mutex*
      (let ([cached (hashtable-ref *error-page-cache* key #f)])
        (if (bytevector? cached)
            cached
            (let ([content (load-error-page-raw static-path status-code)])
              (hashtable-set! *error-page-cache* key content)
              content))))))

(define (error-page-response out status-code static-path keep-alive?)
  (write-response out status-code
    `(("Content-Type" . "text/html"))
    (load-error-page static-path status-code)
    #t keep-alive?))

)