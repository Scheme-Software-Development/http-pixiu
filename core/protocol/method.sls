(library (http-pixiu core protocol method)
  (export 
    http-method:get
    http-method:head
    http-method:post
    http-method:put
    http-method:delete

    http-method:get?
    http-method:head?
    http-method:post?
    http-method:put?
    http-method:delete?

    http-method?)
  (import (chezscheme))

(define (http-method? target-string)
  (exists 
    (lambda (proc) (proc target-string))
    (list 
      http-method:get?
      http-method:head?
      http-method:post?
      http-method:put?
      http-method:delete?)))

(define http-method:get 'GET)
(define (http-method:get? target-string) (equal? (symbol->string http-method:get) (string-upcase target-string)))

(define http-method:head 'HEAD)
(define (http-method:head? target-string) (equal? (symbol->string http-method:head) (string-upcase target-string)))

(define http-method:post 'POST)
(define (http-method:post? target-string) (equal? (symbol->string http-method:post) (string-upcase target-string)))

(define http-method:put 'PUT)
(define (http-method:put? target-string) (equal? (symbol->string http-method:put) (string-upcase target-string)))

(define http-method:delete 'DELETE)
(define (http-method:delete? target-string) (equal? (symbol->string http-method:delete) (string-upcase target-string)))
)