#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng 
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core protocol request-parse)
  (http-pixiu core util association))

; (test-begin "test parse coroutine:get method")
; (with-input-from-file "./tests/resources/http-header"
;   (lambda () 
;     (let ([coroutine (parse-request-coroutine (current-input-port))])
;       (let-values ([(resume val) (coroutine)])
;         (test-equal (assq-ref val 'method) "GET")))))
; (test-end)

(test-begin "test parse coroutine")
(with-input-from-file "./tests/resources/http-header"
  (lambda () 
    (let loop ([coroutine (parse-request-coroutine (current-input-port))]
          [target-val '()])
      (let-values ([(resume val) (apply coroutine target-val)])
        (pretty-print 'val)
        (pretty-print val)
        (if resume 
          (loop resume (list val))
          (pretty-print val)
        )))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
