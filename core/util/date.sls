(library (http-pixiu core util date)
  (export date->string)
  (import (chezscheme))

(define (date->string date)
  (string-append 
    (case (date-week-day date)
      [0 "Sun"]
      [1 "Mon"]
      [2 "Tue"]
      [3 "Wen"]
      [4 "Thu"]
      [5 "Fri"]
      [6 "Sat"])
    ", "
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
    (date-zone-name date)))
)