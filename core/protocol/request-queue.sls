(library (http-pixiu core protocol request-queue)
  (export 
    make-request-queue
    request-queue-pop
    request-queue-push
    request-queue-shutdown)
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
    (mutable tickal-task-list)
    (mutable shutdown?)
    (immutable max-size)
    (mutable current-size))
  (protocol
    (lambda (new)
      (lambda (max-size)
        (new (make-mutex) (make-condition) (make-queue) '() #f max-size 0)))))

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
            [expire-timestamp (+ (* 1000 (time-second now)) (div nano 1000000) expire-duration)]
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
                          [current-timestamp (+ (* 1000 (time-second now)) (div nano 1000000))])
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
      (if (request-queue-shutdown? queue)
        #f
        (begin
          (condition-wait (request-queue-condition queue) (request-queue-mutex queue))
          (request-queue-pop queue)))
      (begin
        (request-queue-current-size-set! queue (- (request-queue-current-size queue) 1))
        (tickal-task-job (dequeue! (request-queue-queue queue)))))))

(define (request-queue-shutdown queue)
  (with-mutex (request-queue-mutex queue)
    (request-queue-shutdown?-set! queue #t)
    (condition-broadcast (request-queue-condition queue))))

(define (remove:from-request-tickal-task-list queue task)
  (with-mutex (request-queue-mutex queue)
    (request-queue-tickal-task-list-set! 
      queue
      (remove task (request-queue-tickal-task-list queue)))))

(define (request-queue-push queue request-thunk expire-duration ticks)
  (with-mutex (request-queue-mutex queue)
    (if (and (request-queue-max-size queue)
             (>= (request-queue-current-size queue) (request-queue-max-size queue)))
        #f
        (begin
          (make-tickal-task request-thunk queue expire-duration ticks)
          (request-queue-current-size-set! queue (+ (request-queue-current-size queue) 1))
          #t)))
  (condition-broadcast (request-queue-condition queue)))
)