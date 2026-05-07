(library (http-pixiu core buffer-pool)
  (export acquire-64k-buffer release-64k-buffer)

  (import (chezscheme))

  ;; Thread-local pool of 64KB bytevectors.
  ;; Each worker thread maintains its own small stash to avoid
  ;; cross-thread synchronization and reduce GC pressure.

  (define thread-local-64k
    (make-thread-parameter '()))

  (define (acquire-64k-buffer)
    (let ([pool (thread-local-64k)])
      (if (null? pool)
          (make-bytevector (* 64 1024))
          (let ([bv (car pool)])
            (thread-local-64k (cdr pool))
            bv))))

  (define (release-64k-buffer bv)
    (when (= (bytevector-length bv) (* 64 1024))
      (thread-local-64k (cons bv (thread-local-64k)))))
)
