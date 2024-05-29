;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2024 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(library (http-pixiu)
  (export hello)
  (import (rnrs))

(define (hello whom)
  (string-append "Hello " whom "!")))
