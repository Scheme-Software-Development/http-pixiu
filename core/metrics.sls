(library (http-pixiu core metrics)
  (export
    metrics-new
    metrics-increment-request!
    metrics-active-connections-inc!
    metrics-active-connections-dec!
    metrics-render)

  (import (chezscheme))

  (define *histogram-buckets*
    '(5 10 25 50 100 250 500 1000 2500 5000 10000))

  (define-record-type metrics-collector
    (fields
      (mutable requests-total-table)
      (mutable active-connections)
      (mutable duration-sums)
      (mutable duration-buckets)
      mutex))

  (define (metrics-new)
    (make-metrics-collector
      (make-hashtable equal-hash equal?)
      0
      (make-hashtable equal-hash equal?)
      (make-hashtable equal-hash equal?)
      (make-mutex)))

  (define (metrics-increment-request! metrics method status duration-ms)
    (with-mutex (metrics-collector-mutex metrics)
      (let ([key (cons method status)])
        (hashtable-set! (metrics-collector-requests-total-table metrics)
                        key
                        (+ 1 (hashtable-ref (metrics-collector-requests-total-table metrics) key 0)))
        (let ([old (hashtable-ref (metrics-collector-duration-sums metrics) key '(0 . 0))])
          (hashtable-set! (metrics-collector-duration-sums metrics)
                          key
                          (cons (+ 1 (car old)) (+ duration-ms (cdr old)))))
        ;; Update histogram buckets
        (let ([buckets (metrics-collector-duration-buckets metrics)])
          (for-each
            (lambda (b)
              (when (<= duration-ms b)
                (let ([bkey (list method status b)])
                  (hashtable-set! buckets bkey (+ 1 (hashtable-ref buckets bkey 0))))))
            *histogram-buckets*)
          (let ([inf-key (list method status "+Inf")])
            (hashtable-set! buckets inf-key (+ 1 (hashtable-ref buckets inf-key 0))))))))

  (define (metrics-active-connections-inc! metrics)
    (with-mutex (metrics-collector-mutex metrics)
      (metrics-collector-active-connections-set! metrics
        (+ 1 (metrics-collector-active-connections metrics)))))

  (define (metrics-active-connections-dec! metrics)
    (with-mutex (metrics-collector-mutex metrics)
      (metrics-collector-active-connections-set! metrics
        (- (metrics-collector-active-connections metrics) 1))))

  (define (metrics-render metrics)
    (with-mutex (metrics-collector-mutex metrics)
      (let ([port (open-output-string)])
        ;; Active connections gauge
        (put-string port "# HELP http_connections_active Current active connections\n")
        (put-string port "# TYPE http_connections_active gauge\n")
        (put-string port "http_connections_active ")
        (put-string port (number->string (metrics-collector-active-connections metrics)))
        (put-string port "\n\n")

        ;; Requests counter
        (put-string port "# HELP http_requests_total Total HTTP requests\n")
        (put-string port "# TYPE http_requests_total counter\n")
        (let ([req-keys (vector->list (hashtable-keys (metrics-collector-requests-total-table metrics)))])
          (for-each
            (lambda (key)
              (let ([count (hashtable-ref (metrics-collector-requests-total-table metrics) key 0)])
                (put-string port "http_requests_total{method=\"")
                (put-string port (car key))
                (put-string port "\",status=\"")
                (put-string port (number->string (cdr key)))
                (put-string port "\"} ")
                (put-string port (number->string count))
                (put-string port "\n")))
            req-keys))
        (put-string port "\n")

        ;; Duration summary
        (put-string port "# HELP http_request_duration_ms_sum Sum of request durations in ms\n")
        (put-string port "# TYPE http_request_duration_ms_sum summary\n")
        (let ([dur-keys (vector->list (hashtable-keys (metrics-collector-duration-sums metrics)))])
          (for-each
            (lambda (key)
              (let ([pair (hashtable-ref (metrics-collector-duration-sums metrics) key '(0 . 0))])
                (put-string port "http_request_duration_ms_sum{method=\"")
                (put-string port (car key))
                (put-string port "\",status=\"")
                (put-string port (number->string (cdr key)))
                (put-string port "\"} ")
                (put-string port (number->string (cdr pair)))
                (put-string port "\n")
                (put-string port "http_request_duration_ms_count{method=\"")
                (put-string port (car key))
                (put-string port "\",status=\"")
                (put-string port (number->string (cdr key)))
                (put-string port "\"} ")
                (put-string port (number->string (car pair)))
                (put-string port "\n")))
            dur-keys))
        (put-string port "\n")

        ;; Duration histogram buckets
        (put-string port "# HELP http_request_duration_ms_bucket Request duration histogram\n")
        (put-string port "# TYPE http_request_duration_ms_bucket histogram\n")
        (let ([bucket-keys (vector->list (hashtable-keys (metrics-collector-duration-buckets metrics)))])
          (for-each
            (lambda (key)
              (let ([count (hashtable-ref (metrics-collector-duration-buckets metrics) key 0)])
                (put-string port "http_request_duration_ms_bucket{method=\"")
                (put-string port (car key))
                (put-string port "\",status=\"")
                (put-string port (number->string (cadr key)))
                (put-string port "\",le=\"")
                (put-string port (caddr key))
                (put-string port "\"} ")
                (put-string port (number->string count))
                (put-string port "\n")))
            bucket-keys))

        (string->utf8 (get-output-string port)))))
)
