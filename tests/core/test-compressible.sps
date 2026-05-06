#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing))

;; Copy of compressible? from http-pixiu.sls for testing
(define (string-trim-both s)
  (let ([len (string-length s)])
    (let loop-start ([i 0])
      (if (and (< i len) (char-whitespace? (string-ref s i)))
          (loop-start (+ i 1))
          (let loop-end ([j len])
            (if (and (> j i) (char-whitespace? (string-ref s (- j 1))))
                (loop-end (- j 1))
                (substring s i j)))))))

(define (string-contains? s substr)
  (let ([len (string-length s)]
        [sub-len (string-length substr)])
    (let loop ([i 0])
      (cond
        [(> (+ i sub-len) len) #f]
        [(equal? (substring s i (+ i sub-len)) substr) #t]
        [else (loop (+ i 1))]))))

(define (compressible? content-type size accept-encoding)
  (and accept-encoding
       (<= size (* 1024 1024))
       (guard (ex [#t #f])
         (string-contains? (string-downcase (string-trim-both accept-encoding)) "gzip"))
       (or (and (>= (string-length content-type) 5)
                (equal? (substring content-type 0 5) "text/"))
           (member content-type '("application/javascript" "application/json" "application/xml")))))

(test-begin "compressible?")
(test-assert "text/html with gzip" (compressible? "text/html" 1024 "gzip, deflate"))
(test-assert "text/css with gzip" (compressible? "text/css" 512 "gzip"))
(test-assert "application/javascript with gzip" (compressible? "application/javascript" 1024 "gzip"))
(test-assert "application/json with gzip" (compressible? "application/json" 1024 "gzip"))
(test-assert "application/xml with gzip" (compressible? "application/xml" 1024 "gzip"))
(test-assert "No accept-encoding" (not (compressible? "text/html" 1024 #f)))
(test-assert "No gzip in accept-encoding" (not (compressible? "text/html" 1024 "deflate")))
(test-assert "Too large" (not (compressible? "text/html" (+ (* 1024 1024) 1) "gzip")))
(test-assert "Binary type" (not (compressible? "image/png" 1024 "gzip")))
(test-assert "Application/octet-stream" (not (compressible? "application/octet-stream" 1024 "gzip")))
(test-assert "Exact size limit" (compressible? "text/html" (* 1024 1024) "gzip"))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
