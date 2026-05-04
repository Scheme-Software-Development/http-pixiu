#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core mime))

(test-begin "mime type guessing")
(test-equal "text/html" (guess-mime-type "/index.html"))
(test-equal "text/html" (guess-mime-type "/page.htm"))
(test-equal "text/css" (guess-mime-type "/style.css"))
(test-equal "application/javascript" (guess-mime-type "/app.js"))
(test-equal "application/json" (guess-mime-type "/data.json"))
(test-equal "image/png" (guess-mime-type "/img/logo.png"))
(test-equal "image/jpeg" (guess-mime-type "/img/photo.jpg"))
(test-equal "application/octet-stream" (guess-mime-type "/file.unknown"))
(test-equal "application/octet-stream" (guess-mime-type "/no-extension"))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
