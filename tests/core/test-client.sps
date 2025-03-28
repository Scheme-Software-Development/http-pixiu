#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
    (chezscheme) 
    (srfi :64 testing) 
    (ufo-socket)
    (http-pixiu core client)
    (http-pixiu core protocol request-construct)
    (http-pixiu core protocol response-parse)
    (http-pixiu core protocol method)
    )

(test-begin "http client")

(let ([client (make-client "www.baidu.com" "80" '())]
        [request-string (construct-request-string http-method:get "/" "HTTP/1.1" '())])
    (client-send client (string->utf8 request-string))
    (test-equal #t (string? (utf8->string (client-receive client)))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
