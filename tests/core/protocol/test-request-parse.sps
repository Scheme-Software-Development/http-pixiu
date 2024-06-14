#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing) (http-pixiu core protocol request-parse))

(test-begin "test parse coroutine")
(with-input-from-file "./tests/resources/http-header"
  (lambda () (parse-request-coroutine (current-input-port))))
(test-end)

(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
