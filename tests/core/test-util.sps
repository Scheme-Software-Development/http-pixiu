#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu))

(test-begin "safe-path?")
(test-assert (safe-path? "./static" "/index.html"))
(test-assert (safe-path? "./static" "/"))
(test-assert (not (safe-path? "./static" "/../secret.txt")))
(test-assert (not (safe-path? "./static" "/foo/../secret.txt")))
(test-assert (not (safe-path? "./static" "/foo/..")))
(test-assert (safe-path? "./static" "/foo/..bar"))
(test-assert (safe-path? "./static" "/foo/bar.."))
(test-end)

(test-begin "connection-close?")
(test-assert (not (connection-close? '(("connection:" . "keep-alive")) "HTTP/1.1")))
(test-assert (connection-close? '(("connection:" . "close")) "HTTP/1.1"))
(test-assert (connection-close? '() "HTTP/1.0"))
(test-assert (not (connection-close? '(("connection:" . "keep-alive")) "HTTP/1.0")))
(test-assert (not (connection-close? '() "HTTP/1.1")))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
