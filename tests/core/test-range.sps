#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing))

;; Copy of parse-range-header from http-pixiu.sls for testing
(define (string-trim-both s)
  (let ([len (string-length s)])
    (let loop-start ([i 0])
      (if (and (< i len) (char-whitespace? (string-ref s i)))
          (loop-start (+ i 1))
          (let loop-end ([j len])
            (if (and (> j i) (char-whitespace? (string-ref s (- j 1))))
                (loop-end (- j 1))
                (substring s i j)))))))

(define (parse-range-header range-value file-size)
  (let ([s (string-trim-both range-value)])
    (if (and (>= (string-length s) 6)
             (equal? (substring s 0 6) "bytes="))
        (let ([rest (substring s 6 (string-length s))])
          (let find-dash ([i 0])
            (cond
              [(>= i (string-length rest)) #f]
              [(char=? (string-ref rest i) #\-)
               (let ([start-str (string-trim-both (substring rest 0 i))]
                     [end-str (string-trim-both (substring rest (+ i 1) (string-length rest)))])
                 (let ([start (guard (ex [#t #f]) (string->number start-str))]
                       [end (if (zero? (string-length end-str))
                                (- file-size 1)
                                (guard (ex [#t #f]) (string->number end-str)))])
                   (if (and start end (>= start 0) (<= start end) (< end file-size))
                       (cons start end)
                       #f)))]
              [else (find-dash (+ i 1))])))
        #f)))

(test-begin "parse-range-header")
(test-equal "Valid range" '(0 . 4) (parse-range-header "bytes=0-4" 10))
(test-equal "Range with spaces" '(2 . 5) (parse-range-header "bytes= 2 - 5 " 10))
(test-equal "Open-ended range" '(5 . 9) (parse-range-header "bytes=5-" 10))
(test-equal "Range to end" '(0 . 9) (parse-range-header "bytes=0-9" 10))
(test-assert "Start > end" (not (parse-range-header "bytes=5-3" 10)))
(test-assert "Start negative" (not (parse-range-header "bytes=-1-5" 10)))
(test-assert "End >= file-size" (not (parse-range-header "bytes=0-10" 10)))
(test-assert "End > file-size" (not (parse-range-header "bytes=0-100" 10)))
(test-assert "Invalid prefix" (not (parse-range-header "items=0-4" 10)))
(test-assert "Empty range" (not (parse-range-header "" 10)))
(test-assert "Non-numeric start" (not (parse-range-header "bytes=abc-5" 10)))
(test-assert "Non-numeric end" (not (parse-range-header "bytes=0-xyz" 10)))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
