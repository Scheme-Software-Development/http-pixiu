#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme)
  (srfi :64 testing)
  (http-pixiu))

(define tmp-dir "tests/tmp-static")
(define test-port (number->string (+ 10000 (mod (time-nanosecond (current-time)) 50000))))
(define pid-file "/tmp/http-pixiu-integration.pid")

(define (setup-files)
  (system (string-append "mkdir -p " tmp-dir))
  (guard (ex [#t (void)]) (delete-file (string-append tmp-dir "/index.html")))
  (guard (ex [#t (void)]) (delete-file (string-append tmp-dir "/foo.txt")))
  (call-with-output-file (string-append tmp-dir "/index.html")
    (lambda (p) (put-string p "<html><body>Hello</body></html>")))
  (call-with-output-file (string-append tmp-dir "/foo.txt")
    (lambda (p) (put-string p "bar"))))

(define (cleanup-files)
  (guard (ex [#t (void)])
    (delete-file (string-append tmp-dir "/index.html"))
    (delete-file (string-append tmp-dir "/foo.txt"))
    (system (string-append "rmdir " tmp-dir))))

(define (start-server-process)
  (let ([script "/tmp/http-pixiu-test-server.sps"])
    (guard (ex [#t (void)]) (delete-file script))
    (call-with-output-file script
      (lambda (p)
        (put-string p "(import (chezscheme) (http-pixiu))\n")
        (put-string p "(start-server \"")
        (put-string p test-port)
        (put-string p "\" (current-output-port) 1 1000 100000 #f \"")
        (put-string p tmp-dir)
        (put-string p "\")\n")))
    (system 
      (string-append 
        "source .akku/bin/activate && scheme --script " script 
        " > /dev/null 2>&1 & echo $! > " pid-file))))

(define (stop-server-process)
  (guard (ex [#t (void)])
    (let ([pid (call-with-input-file pid-file get-string-all)])
      (system (string-append "kill " pid " 2>/dev/null"))
      (delete-file pid-file))))

(test-begin "integration: static file serving")
(setup-files)
(start-server-process)
(sleep (make-time 'time-duration 500000000 0))

(test-assert "Server PID file exists" (file-exists? pid-file))

(stop-server-process)
(cleanup-files)
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
