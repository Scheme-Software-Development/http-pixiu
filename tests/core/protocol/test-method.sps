#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core protocol method))

(test-begin "http methods")
(test-assert (http-method:get? "GET"))
(test-assert (http-method:head? "HEAD"))
(test-assert (http-method:post? "POST"))
(test-assert (http-method:put? "PUT"))
(test-assert (http-method:delete? "DELETE"))
(test-assert (http-method:get? "get"))
(test-assert (http-method? "GET"))
(test-assert (http-method? "HEAD"))
(test-assert (http-method? "POST"))
(test-assert (not (http-method? "FOOBAR")))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
