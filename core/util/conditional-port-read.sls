(library (http-pixiu core util conditional-port-read)
  (export 
      ignore-case-char=?
      step-forward-to
      step-forward-with)
  (import (chezscheme))

(define (ignore-case-char=? a b)
  (equal? (char-downcase a) (char-downcase b)))

(define (step-forward-to port char-list predicator max-step)
  (let ([back-to-position (port-position port)])
    (let loop ([current-position back-to-position]
        [current-char-list char-list]
        [current-char (read-char port)])
      (cond 
        [(null? current-char-list) #t]
        [(eof-object? current-char) 
          (set-port-position! port back-to-position)
          #f]
        [(predicator current-char (car current-char-list)) 
          (loop (+ 1 current-position) (cdr current-char-list) (read-char port))]
        [(< (- current-position back-to-position) max-step)
          (loop (+ 1 current-position) char-list (read-char port))]
        [else 
          (set-port-position! port back-to-position)
           #f]))))

(define (step-forward-with port char-list predicator)
  (let ([back-to-position (port-position port)]
      [current-char (read-char port)])
    (cond 
      [(null? char-list) #t]
      [(eof-object? current-char) 
        (set-port-position! port back-to-position)
        #f]
      [(predicator current-char (car char-list)) 
        (if (step-forward-with port (cdr char-list) predicator)
          #t
          (begin 
            (set-port-position! port back-to-position)
            #f))]
      [else 
        (set-port-position! port back-to-position)
        #f])))

(define (chain->lamdba . conditions-list)
  (lambda (port)
    (call/1cc
      (lambda (return)
        (let ([back-to-position (port-position port)])
          (return 
            (fold-left 
              (lambda (l r)
                (if l
                  (r port)
                  (begin 
                    (set-port-position! port back-to-position)
                    (return #f))))
              #t
              conditions-list)))))))
)