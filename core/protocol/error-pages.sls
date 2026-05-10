(library (http-pixiu core protocol error-pages)
  (export load-error-page
          error-page-response)
  (import (chezscheme)
          (http-pixiu core protocol status)
          (http-pixiu core protocol response-construct))

(define *error-page-cache* (make-hashtable string-hash string=?))
(define *error-page-cache-mutex* (make-mutex))
(define *error-page-cache-keys* '())
(define *error-page-max-entries* 64)

(define (error-page-cache-evict!)
  (when (>= (hashtable-size *error-page-cache*) *error-page-max-entries*)
    (let loop ([keys *error-page-cache-keys*] [count (div *error-page-max-entries* 2)])
      (when (and (not (null? keys)) (> count 0))
        (hashtable-delete! *error-page-cache* (car keys))
        (loop (cdr keys) (- count 1))))
    (set! *error-page-cache-keys*
      (let trim ([keys *error-page-cache-keys*] [count (div *error-page-max-entries* 2)])
        (if (or (null? keys) (<= count 0))
            keys
            (trim (cdr keys) (- count 1)))))))

(define (status->reason-phrase code)
  (case code
    [(100) "Continue"]
    [(101) "Switching Protocols"]
    [(200) "OK"]
    [(201) "Created"]
    [(202) "Accepted"]
    [(204) "No Content"]
    [(206) "Partial Content"]
    [(301) "Moved Permanently"]
    [(302) "Found"]
    [(304) "Not Modified"]
    [(307) "Temporary Redirect"]
    [(400) "Bad Request"]
    [(401) "Unauthorized"]
    [(403) "Forbidden"]
    [(404) "Not Found"]
    [(405) "Method Not Allowed"]
    [(408) "Request Timeout"]
    [(416) "Range Not Satisfiable"]
    [(429) "Too Many Requests"]
    [(500) "Internal Server Error"]
    [(501) "Not Implemented"]
    [(502) "Bad Gateway"]
    [(503) "Service Unavailable"]
    [else "Unknown"]))

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
              (error-page-cache-evict!)
              (hashtable-set! *error-page-cache* key content)
              (set! *error-page-cache-keys*
                (let loop ([keys *error-page-cache-keys*])
                  (cond [(null? keys) (list key)]
                        [(string=? (car keys) key) (cdr keys)]
                        [else (cons (car keys) (loop (cdr keys)))])))
              content))))))

(define (error-page-response out status-code static-path keep-alive?)
  (write-response out status-code
    `(("Content-Type" . "text/html"))
    (load-error-page static-path status-code)
    #t keep-alive?))

)