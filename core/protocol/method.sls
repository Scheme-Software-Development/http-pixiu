(library (http-pixiu core protocol method)
  (export 
    http-method:get
    http-method:post
    http-method:put
    http-method:delete

    http-method:get?
    http-method:post?
    http-method:put?
    http-method:delete?

    http-method?)
  (import (chezscheme))

(define (http-method? target-string)
  (not 
    (boolean=? #f
      (find 
        (lambda (proc) (proc target-string))
        (list 
          http-metehod:get
          http-metehod:post
          http-metehod:put
          http-metehod:delete)))))

(define http-method:get 'get)
(define (http-method:get? target-string) (equal? (symbol->string http-method:get) (string-downcase target-string)))

(define http-method:post 'post)
(define (http-method:post? target-string) (equal? (symbol->string http-method:post) (string-downcase target-string)))

(define http-method:put 'put)
(define (http-method:put? target-string) (equal? (symbol->string http-method:put) (string-downcase target-string)))

(define http-method:delete 'delete)
(define (http-method:delete? target-string) (equal? (symbol->string http-method:delete) (string-downcase target-string)))
)