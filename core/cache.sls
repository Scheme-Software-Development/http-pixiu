(library (http-pixiu core cache)
  (export
    make-file-cache
    cache-lookup
    cache-store!
    cache-generate-etag
    cache-content
    cache-etag
    cache-mtime
    cache-match?)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; In-memory LRU cache for small static files
  ;; Max entry: 256KB, max items: 128
  ;; ------------------------------------------------------------------

  (define-record-type (file-cache make-file-cache-raw file-cache?)
    (fields
      (mutable table)
      (mutable keys)
      max-items
      max-size))

  (define (make-file-cache)
    (make-file-cache-raw
      (make-hashtable string-hash string=?)
      '()
      128
      (* 256 1024)))

  (define (cache-generate-etag mtime size)
    (string-append "\""
                   (number->string mtime 16)
                   "-"
                   (number->string size 16)
                   "\""))

  (define (cache-content entry) (car entry))
  (define (cache-etag entry) (cadr entry))
(define (cache-mtime entry) (caddr entry))

  (define (cache-lookup cache path headers)
    (let ([table (file-cache-table cache)])
      (let ([entry (hashtable-ref table path #f)])
        (when entry
          (set-car! (cddddr entry) (current-time))
          ;; Move to end for true LRU
          (file-cache-keys-set! cache
            (let loop ([keys (file-cache-keys cache)])
              (cond
                [(null? keys) (list path)]
                [(string=? (car keys) path) (append (cdr keys) (list path))]
                [else (cons (car keys) (loop (cdr keys)))]))))
        entry)))

  (define (cache-evict-oldest! cache)
    (let ([keys (file-cache-keys cache)])
      (when (not (null? keys))
        (let ([oldest (car keys)])
          (hashtable-delete! (file-cache-table cache) oldest)
          (file-cache-keys-set! cache (cdr keys))))))

  (define (cache-store! cache path content mtime size)
    (when (<= size (file-cache-max-size cache))
      (let ([table (file-cache-table cache)]
            [etag (cache-generate-etag mtime size)])
        (when (>= (hashtable-size table) (file-cache-max-items cache))
          (cache-evict-oldest! cache))
        (hashtable-set! table path (list content etag mtime size (current-time)))
        (file-cache-keys-set!
          cache
          (let loop ([keys (file-cache-keys cache)])
            (cond
              [(null? keys) (list path)]
              [(string=? (car keys) path) (cdr keys)]
              [else (cons (car keys) (loop (cdr keys)))]))))))

  (define (cache-match? cache path if-none-match)
    (let ([table (file-cache-table cache)])
      (let ([entry (hashtable-ref table path #f)])
        (and entry
             (equal? if-none-match (cadr entry))))))

)
