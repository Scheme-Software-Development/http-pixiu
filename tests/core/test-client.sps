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
    )

(test-begin "http client")

(let ([client (make-client "www.baidu.com" "80" '())]
        [request-string (construct-request-string "get" "/" "HTTP/1.0" '())])
(pretty-print 1)
    ; (call-with-socket (client-socket client)
    (pretty-print request-string)
        (client-send client (string->utf8 request-string))
(pretty-print 2)
        (pretty-print 
        (utf8->string (client-receive client))
        )
(pretty-print 3)
    ; )
    )
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
