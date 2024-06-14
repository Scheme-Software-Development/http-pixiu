(library (http-pixiu core protocol request-parse)
  ; (export hello)
  (import 
    (chezscheme)
    (ufo-coroutine)
    (http-pixiu core protocol status)
    (http-pixiu core util conditional-port-read)
    (http-pixiu core util association))

;4kiB
(define request-header-size 4*1024*1024)

(define parse-request-coroutine 
  (case-lambda 
    [(input-port) (parse-request-coroutine request-header-size)]
    [(input-port current-header-size)
      (let* ([origin-position (port-position input-port)])
        (init-coroutine
          (lambda (yield)
            (let loop ([env '()]
                [l 
                  (list
                    (lambda (env) `(method . ,(read-to-space input-port)))
                    (lambda (env) `(uri . ,(read-to-space input-port)))
                    (lambda (env) `(protocol . ,(read-to-nextline input-port))))])
              (cond 
                [(> (- (port-position input-port) origin-position) current-header-size)
                  (raise status:bad-request)]
                [(null? l) 
                  (if (read-with input-port "\n")
                    (let ([content-length (assq-ref environment "content-length: ")])
                      (if l
                        `(,@env (body . ,(read-with-length input-port l))
                        (raise status:bad-request)))
                      (loop `(,@env ,(yield (read-kv input-port)))l)))]
                [else (loop `(,@env ,(yield ((car l) env))) (cdr l))])))))]))

(define (read-kv input-port)
  `(,(string-downcase (read-to-space input-port)) . ,(read-to-nextline input-port)))

(define (read-with-length input-port length)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-with-length (current-output-port) input-port length))
        (raise status:bad-request)))))

(define (read-with input-port target-string)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-with (current-output-port) input-port (string->list target-string) char=? header-size))
        (raise status:bad-request)))))

(define (read-to-space input-port)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-port (string->list " ") char=? header-size))
        (raise status:bad-request)))))

(define (read-to-nextline input-port)
  (with-output-to-string 
    (lambda ()
      (if (not (step-forward-to (current-output-port) input-port (string->list "\n") char=? header-size))
        (raise status:bad-request)))))
)