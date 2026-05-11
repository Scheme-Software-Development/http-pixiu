#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu))

(test-begin "router path-match")
(let ([r (make-router)])
  (router-get r "/" (lambda (env) 'root))
  (router-get r "/users" (lambda (env) 'users))
  (router-get r "/users/:id" (lambda (env) 'user-by-id))
  (router-post r "/users" (lambda (env) 'create-user))
  (router-get r "/users/:id/posts/:post-id" (lambda (env) 'user-post))

  (test-equal 'root (router-dispatch r '((method . "GET") (path . "/"))))
  (test-equal 'users (router-dispatch r '((method . "GET") (path . "/users"))))
  (test-equal 'user-by-id (router-dispatch r '((method . "GET") (path . "/users/42"))))
  (test-equal 'create-user (router-dispatch r '((method . "POST") (path . "/users"))))
  (test-equal 'user-post (router-dispatch r '((method . "GET") (path . "/users/42/posts/7"))))
  (test-assert (not (router-dispatch r '((method . "GET") (path . "/notfound")))))
  (test-assert (not (router-dispatch r '((method . "DELETE") (path . "/users"))))))
(test-end)

(test-begin "router params")
(let ([r (make-router)])
  (router-get r "/users/:id" (lambda (env) (let ([p (assq 'params env)]) (if p (cdr p) '()))))
  (let ([params (router-dispatch r '((method . "GET") (path . "/users/123")))])
    (test-equal "123" (cdr (assoc "id" params)))))
(test-end)

(test-begin "router case-insensitive method")
(let ([r (make-router)])
  (router-get r "/test" (lambda (env) 'ok))
  (test-equal 'ok (router-dispatch r '((method . "get") (path . "/test"))))
  (test-equal 'ok (router-dispatch r '((method . "GET") (path . "/test")))))
(test-end)

(test-begin "router->handler")
(let ([r (make-router)])
  (router-get r "/found" (lambda (env) (make-response 200 '() (string->utf8 "ok"))))
  (let ([h (router->handler r)])
    (test-assert (response? (h '((method . "GET") (path . "/found")))))
    (test-equal #f (h '((method . "GET") (path . "/missing"))))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
