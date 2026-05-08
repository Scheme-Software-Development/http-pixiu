(library (http-pixiu core util date)
  (export date->string http-date->seconds)
  (import (chezscheme))

(define (date->string date)
  (string-append 
    (case (date-week-day date)
      [0 "Sun"]
      [1 "Mon"]
      [2 "Tue"]
      [3 "Wed"]
      [4 "Thu"]
      [5 "Fri"]
      [6 "Sat"])
    ", "
    (if (< (date-day date) 10)
      "0"
      "")
    (number->string (date-day date))
    " "
    (case (date-month date)
      [1 "Jan"]
      [2 "Feb"]
      [3 "Mar"]
      [4 "Apr"]
      [5 "May"]
      [6 "Jun"]
      [7 "Jul"]
      [8 "Aug"]
      [9 "Sep"]
      [10 "Oct"]
      [11 "Nov"]
      [12 "Dec"])
    " "
    (number->string (date-year date))
    " "
    (if (< (date-hour date) 10)
      "0"
      "")
    (number->string (date-hour date))
    ":"
    (if (< (date-minute date) 10)
      "0"
      "")
    (number->string (date-minute date))
    ":"
    (if (< (date-second date) 10)
      "0"
      "")
    (number->string (date-second date))
    " "
    "GMT"))

;; ------------------------------------------------------------------
;; HTTP date parsing (RFC 7231)
;; ------------------------------------------------------------------

(define (string-split str delim)
  (let loop ([i 0] [start 0] [acc '()])
    (if (>= i (string-length str))
        (reverse (if (> start i)
                     acc
                     (cons (substring str start i) acc)))
        (if (char=? (string-ref str i) delim)
            (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))
            (loop (+ i 1) start acc)))))

(define (month-name->number name)
  (case (string-downcase name)
    [("jan") 1]
    [("feb") 2]
    [("mar") 3]
    [("apr") 4]
    [("may") 5]
    [("jun") 6]
    [("jul") 7]
    [("aug") 8]
    [("sep") 9]
    [("oct") 10]
    [("nov") 11]
    [("dec") 12]
    [else #f]))

(define (http-date->seconds s)
  (guard (ex [#t #f])
    (let ([parts (string-split s #\space)])
      (if (< (length parts) 6)
          #f
          (let ([day (guard (ex [#t #f]) (string->number (list-ref parts 1)))]
                [month (month-name->number (list-ref parts 2))]
                [year (guard (ex [#t #f]) (string->number (list-ref parts 3)))]
                [time-parts (string-split (list-ref parts 4) #\:)]
                [tz (list-ref parts 5)])
            (if (or (not day) (not month) (not year) (not (equal? tz "GMT"))
                    (< (length time-parts) 3))
                #f
                (let ([hour (guard (ex [#t #f]) (string->number (list-ref time-parts 0)))]
                      [minute (guard (ex [#t #f]) (string->number (list-ref time-parts 1)))]
                      [second (guard (ex [#t #f]) (string->number (list-ref time-parts 2)))])
                  (if (or (not hour) (not minute) (not second))
                      #f
                      (let ([dt (make-date 0 second minute hour day month year 0)])
                        (time-second (date->time-utc dt)))))))))))

) ; end library
