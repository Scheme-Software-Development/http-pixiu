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
    (mutable job)
    (mutable expire)
    (mutable complete))
  (protocol
    ;must have request-queue-mutex
    (lambda (new)
      (lambda (job request-queue expire-duration ticks)
        (letrec* ([now (current-time)]
            [nano (time-nanosecond now)]
            ;ms
            [expire-timestamp (+ (* 1000 (time-second now)) nano)]
            [new-task 
              (new 
                (lambda () ((make-engine job) ticks (tickal-task-complete new-task) (tickal-task-expire new-task)))
                '() '())]
            [complete 
              (lambda (ticks value) 
                (remove:from-request-tickal-task-list request-queue new-task)
                value)]
            [expire 
              (lambda (remains) 
                (let* ([new-job (lambda () 
                      (let* ([now (current-time)] 
                          [nano (time-nanosecond now)]
                          [current-timestamp (+ (* 1000 (time-second now)) nano)])
                        (if (< current-timestamp expire-timestamp)
                          (remains ticks (tickal-task-complete new-task) (tickal-task-expire new-task))
                          (begin 
                            (remove:from-request-tickal-task-list request-queue new-task)
                            (raise status:request-timeout)))))])
                  (tickal-task-job-set! new-task new-job)
                  (with-mutex (request-queue-mutex request-queue)
                    (enqueue! (request-queue-queue request-queue) new-task))
                  (condition-signal (request-queue-condition request-queue))))])
          (enqueue! (request-queue-queue request-queue) new-task)
          (request-queue-tickal-task-list-set! 
            request-queue
            `(,@(request-queue-tickal-task-list request-queue) ,new-task))

          (tickal-task-expire-set! new-task expire)
          (tickal-task-complete-set! new-task complete)

          new-task)))))

(define (request-queue-pop queue)
  (with-mutex (request-queue-mutex queue)
    (if (queue-empty? (request-queue-queue queue))
      (condition-wait (request-queue-condition queue) (request-queue-mutex queue)))
    (tickal-task-job (dequeue! (request-queue-queue queue)))))

(define (remove:from-request-tickal-task-list queue task)
  (with-mutex (request-queue-mutex queue)
    (request-queue-tickal-task-list-set! 
      queue
      (remove task (request-queue-tickal-task-list queue)))))

(define (request-queue-push queue request-thunk expire-duration ticks)
  (with-mutex (request-queue-mutex queue)
    (make-tickal-task request-thunk queue expire-duration ticks))
  (condition-broadcast (request-queue-condition queue)))
)