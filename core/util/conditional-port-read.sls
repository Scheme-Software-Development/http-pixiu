(library (http-pixiu core util conditional-port-read)
  (export 
      ignore-case-char=?
      step-forward-to
      step-forward-with
      chain->lambda)
  (import (chezscheme))

(define (ignore-case-char=? a b)
  (equal? (char-downcase a) (char-downcase b)))

(define (step-forward-to output-port input-port char-list predicator max-step)
  (let ([back-to-position (port-position input-port)])
    (let loop ([current-position back-to-position]
        [current-char-list char-list]
        [current-char (peek-char input-port)])
      (cond 
        [(null? current-char-list) #t]
        [(eof-object? current-char) #f]
        [(predicator current-char (car current-char-list)) 
          (write-char (read-char input-port) output-port)
          (loop (+ 1 current-position) (cdr current-char-list) (read-char input-port))]
        [(< (- current-position back-to-position) max-step)
          (write-char (read-char input-port) output-port)
          (loop (+ 1 current-position) char-list (peek-char input-port))]
        [else #f]))))

(define (step-forward-with output-port input-port char-list predicator)
  (let ([current-char (peek-char input-port)])
    (cond 
      [(null? char-list) #t]
      [(eof-object? current-char) #f]
      [(predicator current-char (car char-list)) 
        (write-char (read-char input-port) output-port)
        (step-forward-with output-port input-port (cdr char-list) predicator)]
      [else #f])))

(define (chain->lambda . conditions-list)
  (lambda (input-port)
    (call/1cc
      (lambda (return)
        (return 
          (fold-left 
            (lambda (l r)
              (if l
                (r input-port)
                (return #f)))
            #t
            conditions-list))))))
)