#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing) (http-pixiu core server))

(test-begin "make-server")
(let ([server (make-server 5000 '() '())])
    (test-equal "Hello World!" "Hello World!"))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
