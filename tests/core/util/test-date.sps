#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core util date))

(test-begin "date->string format")
(let ([d (make-date 0 37 49 8 6 11 1994 0)])
  (test-equal "Sun, 06 Nov 1994 08:49:37 GMT" (date->string d)))

(let ([d (make-date 0 5 5 5 1 1 2000 0)])
  (test-equal "Sat, 01 Jan 2000 05:05:05 GMT" (date->string d)))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
