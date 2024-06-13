#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (chezscheme) (srfi :64 testing) (http-pixiu core util conditional-port-read))

(test-begin "step-forward-to")
(with-input-from-file "./tests/resources/http-header"
  (lambda () (test-equal #t (step-forward-to (current-input-port) (string->list "\n") char=? 50))))
(test-end)

(test-begin "step-forward-with")
(with-input-from-file "./tests/resources/http-header"
  (lambda () (test-equal #t (step-forward-with (current-input-port) (string->list "GET") char=?))))
(test-end)

(test-begin "ignore-case-char=?")
(with-input-from-file "./tests/resources/http-header"
  (lambda () (test-equal #t (step-forward-with (current-input-port) (string->list "get") ignore-case-char=?))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
