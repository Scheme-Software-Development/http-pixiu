(library (http-pixiu core protocol http)
  ; (export hello)
  (import 
    (chezscheme)
    (http-pixiu core util conditional-port-read))

;4kiB
(define header-size 4*1024*1024)

(define read-http
  (case-lambda 
    [(input-port) (read-http input-port '())]
    [(input-port environment) 
    ]))

(define (private-http-condition output
  (condition->lambda 
    (lambda ()))))
)