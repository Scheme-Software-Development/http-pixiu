#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2022 WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs
;;to read log and reproduce similar action for debug
(import (rnrs (6)) 
    (srfi :64 testing) 
    (http-pixiu socket socket) )

(test-begin "socket session")
(define client-pid)
(define client-socket)
(let* ([server-docket-name (tmpnam 0)])
  [server-socket (setup-server-socket server-socket-name)]
)
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
