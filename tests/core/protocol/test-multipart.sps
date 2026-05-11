#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu))

(test-begin "parse-multipart-form-data")
(let ([boundary "----WebKitFormBoundary7MA4YWxkTrZu0gW"])
  (let ([body (string->utf8
                (string-append
                  "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n"
                  "Content-Disposition: form-data; name=\"field1\"\r\n"
                  "\r\n"
                  "value1\r\n"
                  "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n"
                  "Content-Disposition: form-data; name=\"file1\"; filename=\"test.txt\"\r\n"
                  "Content-Type: text/plain\r\n"
                  "\r\n"
                  "hello world\r\n"
                  "------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n"))])
    (let ([parts (parse-multipart-form-data body (string-append "multipart/form-data; boundary=" boundary))])
      (test-equal 2 (length parts))
      (let ([p1 (car parts)])
        (test-equal "field1" (multipart-part-name p1))
        (test-equal #f (multipart-part-filename p1))
        (test-equal #f (multipart-part-content-type p1))
        (test-equal "value1" (utf8->string (multipart-part-body p1))))
      (let ([p2 (cadr parts)])
        (test-equal "file1" (multipart-part-name p2))
        (test-equal "test.txt" (multipart-part-filename p2))
        (test-equal "text/plain" (multipart-part-content-type p2))
        (test-equal "hello world" (utf8->string (multipart-part-body p2)))))))
(test-end)

(test-begin "multipart empty body")
(let ([parts (parse-multipart-form-data #vu8() "multipart/form-data; boundary=xyz")])
  (test-equal '() parts))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
