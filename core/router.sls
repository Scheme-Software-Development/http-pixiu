(library (http-pixiu core router)
  (export
    make-router
    router-get
    router-post
    router-put
    router-delete
    router-options
    router-head
    router-dispatch
    router->handler)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Simple path-based router with parameter capture.
  ;;
  ;; (define r (make-router))
  ;; (router-get r "/users/:id" (lambda (env) ...))
  ;; (router-post r "/users" (lambda (env) ...))
  ;;
  ;; (router-dispatch r env) => response or #f
  ;; (router->handler r) => handler that falls through to 404
  ;; ------------------------------------------------------------------

  (define-record-type (router make-router-raw router?)
    (fields (mutable routes)))

  (define (make-router)
    (make-router-raw '()))

  (define (router-add! r method path handler)
    (router-routes-set! r (cons (list method path handler) (router-routes r))))

  (define (router-get r path handler)    (router-add! r "GET" path handler))
  (define (router-post r path handler)   (router-add! r "POST" path handler))
  (define (router-put r path handler)    (router-add! r "PUT" path handler))
  (define (router-delete r path handler) (router-add! r "DELETE" path handler))
  (define (router-options r path handler)(router-add! r "OPTIONS" path handler))
  (define (router-head r path handler)   (router-add! r "HEAD" path handler))

  (define (split-path path)
    (let ([len (string-length path)])
      (let loop ([i 0] [start (if (and (> len 0) (char=? (string-ref path 0) #\/)) 1 0)] [acc '()])
        (cond
          [(>= i len)
           (reverse (if (> i start) (cons (substring path start i) acc) acc))]
          [(char=? (string-ref path i) #\/)
           (loop (+ i 1) (+ i 1) (if (> i start) (cons (substring path start i) acc) acc))]
          [else (loop (+ i 1) start acc)]))))

  (define (path-match? pattern-parts actual-parts)
    (let loop ([pp pattern-parts] [ap actual-parts] [params '()])
      (cond
        [(and (null? pp) (null? ap)) (reverse params)]
        [(or (null? pp) (null? ap)) #f]
        [(and (> (string-length (car pp)) 0)
              (char=? (string-ref (car pp) 0) #\:))
         (loop (cdr pp) (cdr ap) (cons (cons (substring (car pp) 1 (string-length (car pp))) (car ap)) params))]
        [(string=? (car pp) (car ap)) (loop (cdr pp) (cdr ap) params)]
        [else #f])))

  (define (router-dispatch r env)
    (let ([method (let ([m (assq 'method env)])
                    (if m (cdr m) #f))]
          [path (let ([p (assq 'path env)])
                  (if p (cdr p) #f))])
      (if (and method path)
          (let ([path-parts (split-path path)])
            (let loop ([routes (router-routes r)])
              (if (null? routes)
                  #f
                  (let ([route (car routes)])
                    (let ([match-result (path-match? (split-path (cadr route)) path-parts)])
                      (if (and (string-ci=? (car route) method) match-result)
                          ((caddr route) (cons `(params . ,match-result) env))
                          (loop (cdr routes))))))))
          #f)))

  (define (env-params env)
    (let ([p (assq 'params env)])
      (if p (cdr p) '())))

  (define (router->handler r)
    (lambda (env)
      (or (router-dispatch r env)
          #f)))

)
