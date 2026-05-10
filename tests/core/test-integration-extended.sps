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
(define pid-file "/tmp/http-pixiu-integration-extended.pid")
(define base-url (string-append "http://127.0.0.1:" test-port))

(define (setup-files)
  (system (string-append "mkdir -p " tmp-dir))
  (guard (ex [#t (void)]) (delete-file (string-append tmp-dir "/index.html")))
  (guard (ex [#t (void)]) (delete-file (string-append tmp-dir "/foo.txt")))
  (call-with-output-file (string-append tmp-dir "/index.html")
    (lambda (p) (put-string p "<html><body>Hello</body></html>")))
  (call-with-output-file (string-append tmp-dir "/foo.txt")
    (lambda (p) (put-string p "bar content here"))))

(define (cleanup-files)
  (guard (ex [#t (void)])
    (delete-file (string-append tmp-dir "/index.html"))
    (delete-file (string-append tmp-dir "/foo.txt"))
    (system (string-append "rmdir " tmp-dir))))

(define (start-server-process)
  (let ([script "/tmp/http-pixiu-test-server-extended.sps"])
    (guard (ex [#t (void)]) (delete-file script))
    (guard (ex [#t (void)]) (delete-file pid-file))
    ;; Clean up any leftover processes from previous runs
    (system (string-append "pkill -15 -f \"scheme --script " script "\" 2>/dev/null >/dev/null 2>&1"))
    (sleep (make-time 'time-duration 0 1))
    (call-with-output-file script
      (lambda (p)
        (put-string p "(import (chezscheme) (http-pixiu))\n")
        (put-string p "(guard (ex [#t (void)]) (delete-file \"")
        (put-string p pid-file)
        (put-string p "\"))\n")
        (put-string p "(call-with-output-file \"")
        (put-string p pid-file)
        (put-string p "\"\n  (lambda (p) (display (get-process-id) p) (newline p)))\n")
        (put-string p "(start-server \"")
        (put-string p test-port)
        (put-string p "\" (current-output-port) 1 30000 100000 #f \"")
        (put-string p tmp-dir)
        (put-string p "\")\n")))
    (system 
      (string-append 
        "cd " (current-directory) " && source .akku/bin/activate && scheme --script " script 
        " > /tmp/http-pixiu-test-server.log 2>&1 & echo $! > " pid-file))
    (sleep (make-time 'time-duration 0 2))))

(define (stop-server-process)
  (guard (ex [#t (void)])
    (let ([pid (guard (ex [#t #f]) (call-with-input-file pid-file get-string-all))])
      (when pid
        (system (string-append "kill -15 " pid " 2>/dev/null >/dev/null 2>&1")))
      (guard (ex [#t (void)]) (delete-file pid-file)))))

(define (wait-for-server)
  (let loop ([retries 30])
    (if (zero? retries)
        (error 'wait-for-server "Server did not start in time"))
    (let ([code (curl-get "/index.html")])
      (if (equal? code "000")
          (begin
            (sleep (make-time 'time-duration 100000000 0))
            (loop (- retries 1)))
          code))))

(define (curl-get path . headers)
  (let ([header-args (apply string-append 
                            (map (lambda (h) (string-append " -H \"" h "\"")) headers))])
    (system (string-append "curl -s --connect-timeout 2 --max-time 10 -o /dev/null -w '%{http_code}' -H \"Connection: close\""
                           header-args " " base-url path
                           " > /tmp/http-pixiu-response.rc 2>/dev/null"))
    (let ([code (guard (ex [#t "000"]) (call-with-input-file "/tmp/http-pixiu-response.rc" get-string-all))])
      code)))

(test-begin "integration extended")
(dynamic-wind
  setup-files
  (lambda ()
    (start-server-process)
    (wait-for-server)
    (sleep (make-time 'time-duration 0 1))
    (test-equal "GET existing file returns 200" "200" (curl-get "/index.html"))
    (test-equal "GET non-existing file returns 404" "404" (curl-get "/notfound.txt"))
    (test-equal "Directory with index returns 200" "200" (curl-get "/"))
    (test-equal "Range request returns 206" "206" (curl-get "/foo.txt" "Range: bytes=0-3"))
    (test-equal "Range request with bad range returns 416" "416" (curl-get "/foo.txt" "Range: bytes=100-200"))
    (test-equal "gzip request returns 200" "200" (curl-get "/index.html" "Accept-Encoding: gzip")))
  (lambda ()
    (stop-server-process)
    (cleanup-files)))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
