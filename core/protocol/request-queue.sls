(library (http-pixiu core protocol request-queue)
  (export 
    make-request-queue
    request-queue-pop
    request-queue-push)
  (import 
    (chezscheme)
    (slib queue)
    (http-pixiu core protocol status)

    (http-pixiu core protocol request-parse))

(define-record-type request-queue 
  (fields 
    (immutable mutex)
    (immutable condition)
    (immutable queue)
    (mutable tickal-task-list))
  (protocol
    (lambda (new)
      (lambda ()
        (new (make-mutex) (make-condition) (make-queue) '())))))

(define-record-type tickal-task 
  (fields 
    (immutable request)
    (immutable request-queue)
    (immutable mutex)
    (mutable job)
    (mutable expire)
    (mutable complete))
  (protocol
    ;must have request-queue-mutex
    (lambda (new)
      (lambda (request request-queue expire-duration ticks request-processor)
        (letrec* ([now (current-time)]
            [nano (time-nanosecond now)]
            ;ms
            [expire-timestamp (+ (* 1000 (time-second now)) nano)]
            [new-task 
              (new 
                request request-queue (make-mutex) 
                (lambda () ((make-engine (request-processor request)) ticks (tickal-task-complete new-task) (tickal-task-expire new-task)))
                '() '())]
            [complete 
              (lambda (ticks value) 
                (remove:from-request-tickal-task-list request-queue new-task)
                value)]
            [expire 
              (lambda (remains) 
                (let* ([new-pair
                    (with-mutex (tickal-task-mutex new-task)
                      (cons 
                        (tickal-task-complete new-task)
                        (tickal-task-expire new-task)))]
                    [job (lambda () 
                      (if (current-time))
                      (let* ([now (current-time)] 
                          [nano (time-nanosecond now)]
                          [current-timestamp (+ (* 1000 (time-second now)) nano)])
                        (if (< current-timestamp expire-timestamp)
                          (remains ticks (car new-pair) (cdr new-pair))
                          (begin 
                            (remove:from-request-tickal-task-list request-queue new-task)
                            (raise status:request-timeout)))))])
                  (tickal-task-job-set! new-task job)
                  (with-mutex (request-queue-mutex request-queue)
                    (enqueue! (request-queue-queue request-queue) new-task))))])
          (enqueue! (request-queue-queue request-queue) new-task)
          (request-queue-tickal-task-list-set! 
            request-queue
            `(,@(request-queue-tickal-task-list request-queue) ,new-task))

          (tickal-task-expire-set! new-task expire)
          (tickal-task-complete-set! new-task complete)

          new-task)))))

(define (request-queue-pop queue)
  (with-mutex (request-queue-mutex queue)
    (let loop ()
      (if (queue-empty? (request-queue-queue queue))
        (begin
          (condition-wait (request-queue-condition queue) (request-queue-mutex queue))
          (loop))
        (letrec* ([task (dequeue! (request-queue-queue queue))]
            [job (tickal-task-request task)])
          ;will be in another thread
          (job))))))

(define (remove:from-request-tickal-task-list queue task)
  (with-mutex (request-queue-mutex queue)
    (request-queue-tickal-task-list-set! 
      queue
      (remove task (request-queue-tickal-task-list queue)))))

(define (request-queue-push queue request expire-duration ticks request-processor)
  (with-mutex (request-queue-mutex queue)
    (make-tickal-task request queue expire-duration ticks request-processor))
  (condition-signal (request-queue-condition queue)))
)