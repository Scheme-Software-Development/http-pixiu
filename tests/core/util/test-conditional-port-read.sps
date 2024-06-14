#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024 WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import (chezscheme) (srfi :64 testing) (http-pixiu core util conditional-port-read))

(test-begin "step-forward-to")
(test-equal 
  "GET /politics/2024_06_14_737908.shtml HTTP/1.1\n"
  (with-output-to-string 
    (lambda () 
      (with-input-from-file "./tests/resources/http-header"
        (lambda () (test-equal #t (step-forward-to (current-output-port) (current-input-port) (string->list "\n") char=? 50)))))))
(test-end)

(test-begin "step-forward-with")
(test-equal 
  "GET"
  (with-output-to-string 
    (lambda () 
      (with-input-from-file "./tests/resources/http-header"
        (lambda () (test-equal #t (step-forward-with (current-output-port) (current-input-port) (string->list "GET") char=?)))))))
(test-end)

(test-begin "ignore-case-char=?")
(test-equal 
  "GET"
  (with-output-to-string 
    (lambda () 
      (with-input-from-file "./tests/resources/http-header"
        (lambda () (test-equal #t (step-forward-with (current-output-port) (current-input-port) (string->list "get") ignore-case-char=?)))))))
(test-end)

(test-begin "condition->lambda")
(test-equal 
  "GET /politics/2024_06_14_737908.shtml HTTP/1.1\n"
  (with-output-to-string 
    (lambda () 
      (let* ([output-port (current-output-port)]
          [condition-chain 
            (chain->lambda
              (lambda (input-port) (step-forward-with output-port input-port (string->list "get") ignore-case-char=?))
              (lambda (input-port) (step-forward-to output-port input-port (string->list "\n") char=? 50)))])
        (with-input-from-file "./tests/resources/http-header"
          (lambda () (test-equal #t (condition-chain (current-input-port)))))))))
(test-end)

(test-begin "step-forward-with")
(test-equal 
  ""
  (with-output-to-string 
    (lambda ()
      (with-input-from-file "./tests/resources/http-header"
        (lambda () (test-equal #f (step-forward-with (current-output-port) (current-input-port) (string->list "POST") char=?)))))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
