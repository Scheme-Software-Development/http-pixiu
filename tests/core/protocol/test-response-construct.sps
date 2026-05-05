#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core protocol response-construct)
  (http-pixiu core protocol status))

(define (string-contains? haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

(define (get-response-string write-fn)
  (let-values ([(port getter) (open-bytevector-output-port)])
    (write-fn port)
    (utf8->string (getter))))

(test-begin "write-response with string body")
(let ([result (get-response-string 
                (lambda (out) (write-response out status:ok '() "Hello, World!")))])
  (test-assert (string-contains? result "HTTP/1.1 200 OK\r\n"))
  (test-assert (string-contains? result "Content-Length: 13\r\n"))
  (test-assert (string-contains? result "Connection: close\r\n"))
  (test-assert (string-contains? result "\r\n\r\nHello, World!")))
(test-end)

(test-begin "write-response with bytevector body")
(let ([result (get-response-string 
                (lambda (out) (write-response out status:not-found '() (string->utf8 "Not Found"))))])
  (test-assert (string-contains? result "HTTP/1.1 404 Not Found\r\n"))
  (test-assert (string-contains? result "Content-Length: 9\r\n"))
  (test-assert (string-contains? result "\r\n\r\nNot Found")))
(test-end)

(test-begin "write-json-response")
(let ([result (get-response-string 
                (lambda (out) (write-json-response out status:ok '() "{\"key\":\"value\"}")))])
  (test-assert (string-contains? result "Content-Type: application/json\r\n"))
  (test-assert (string-contains? result "\r\n\r\n{\"key\":\"value\"}")))
(test-end)

(test-begin "write-text-response")
(let ([result (get-response-string 
                (lambda (out) (write-text-response out status:ok '() "plain text")))])
  (test-assert (string-contains? result "Content-Type: text/plain\r\n"))
  (test-assert (string-contains? result "\r\n\r\nplain text")))
(test-end)

(test-begin "write-html-response")
(let ([result (get-response-string 
                (lambda (out) (write-html-response out status:ok '() "<h1>Hi</h1>")))])
  (test-assert (string-contains? result "Content-Type: text/html\r\n"))
  (test-assert (string-contains? result "\r\n\r\n<h1>Hi</h1>")))
(test-end)

(test-begin "write-response HEAD no body")
(let ([result (get-response-string 
                (lambda (out) (write-response out status:ok '() "Body Here" #f)))])
  (test-assert (string-contains? result "Content-Length: 9\r\n"))
  (test-assert (not (string-contains? result "\r\n\r\nBody Here"))))
(test-end)

(test-begin "write-response keep-alive")
(let ([result (get-response-string 
                (lambda (out) (write-response out status:ok '() "Hi" #t #t)))])
  (test-assert (string-contains? result "Connection: keep-alive\r\n"))
  (test-assert (string-contains? result "\r\n\r\nHi")))
(test-end)

(test-begin "write-response streaming body")
(let ([input (open-bytevector-input-port (string->utf8 "Streamed Content"))]
      [size 16])
  (let ([result (get-response-string 
                  (lambda (out) (write-response out status:ok '() (cons input size) #t #f)))])
    (test-assert (string-contains? result "Content-Length: 16\r\n"))
    (test-assert (string-contains? result "\r\n\r\nStreamed Content"))))
(test-end)

(test-begin "write-response streaming HEAD no body")
(let ([input (open-bytevector-input-port (string->utf8 "Skip Me"))]
      [size 7])
  (let ([result (get-response-string 
                  (lambda (out) (write-response out status:ok '() (cons input size) #f #f)))])
    (test-assert (string-contains? result "Content-Length: 7\r\n"))
    (test-assert (not (string-contains? result "\r\n\r\nSkip Me")))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
