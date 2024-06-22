#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2024-Now WANG Zheng 
;; SPDX-License-Identifier: MIT
#!r6rs

(import 
  (chezscheme) 
  (srfi :64 testing) 
  (http-pixiu core protocol request-parse)
  (http-pixiu core util association))

(test-begin "get body from coroutine")
(let* ([binary-input-port (open-file-input-port "./tests/resources/http-header-with-body")]
    [coroutine (parse-request-coroutine binary-input-port)])
  (let-values ([(closure val) (get-values-from-coroutine coroutine 'body)] )
    (test-equal "SU% ( (zhiwang-lexer)) - zhiwang and TI= zhiwang" (bytevector->string val (current-transcoder)))))
(test-end)

(test-begin "get from coroutine")
(let* ([binary-input-port (open-file-input-port "./tests/resources/http-header")]
    [coroutine (parse-request-coroutine binary-input-port)])
  (let-values ([(closure val) (get-values-from-coroutine coroutine "connection:")] )
    (test-equal val "keep-alive")))
(test-end)

(test-begin "parse coroutine:get method")
(let* ([binary-input-port (open-file-input-port "./tests/resources/http-header")]
    [coroutine (parse-request-coroutine binary-input-port)])
  (let-values ([(closure val) (coroutine)] )
    (test-equal (assq-ref val 'method) "GET")))
(test-end)

(test-begin "parse coroutine")
(let ([binary-input-port (open-file-input-port "./tests/resources/http-header")])
  (let loop ([coroutine (parse-request-coroutine binary-input-port)]
      [target-val '()])
    (let-values ([(resume val) (apply coroutine target-val)])
      (if resume 
        (loop resume (list val))
          (test-equal 
            val
  '((method . "GET") (uri . "/politics/2024_06_14_737908.shtml")
  (protocol . "HTTP/1.1") ("host:" . "www.guancha.cn")
  ("user-agent:"
    .
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:88.0) Gecko/20100101 Firefox/88.0")
  ("accept:"
    .
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")
  ("accept-language:" . "zh-CN,en-US;q=0.7,en;q=0.3")
  ("accept-encoding:" . "gzip, deflate, br")
  ("referer:" . "https://www.guancha.cn/")
  ("connection:" . "keep-alive")
  ("cookie:"
    .
    "Hm_lvt_8ab18ec6e3ee89210917ef2c8572b30e=1717724408; sensorsdata2015jssdkcross=%7B%22distinct_id%22%3A%22217349%22%2C%22first_id%22%3A%2217dfaef76821a9-09882ea285058c8-712d675c-2359296-17dfaef7683597%22%2C%22props%22%3A%7B%22%24latest_traffic_source_type%22%3A%22%E7%9B%B4%E6%8E%A5%E6%B5%81%E9%87%8F%22%2C%22%24latest_search_keyword%22%3A%22%E6%9C%AA%E5%8F%96%E5%88%B0%E5%80%BC_%E7%9B%B4%E6%8E%A5%E6%89%93%E5%BC%80%22%2C%22%24latest_referrer%22%3A%22%22%7D%2C%22%24device_id%22%3A%2217dfaef76821a9-09882ea285058c8-712d675c-2359296-17dfaef7683597%22%2C%22identities%22%3A%22eyIkaWRlbnRpdHlfbG9naW5faWQiOiIyMTczNDkiLCIkaWRlbnRpdHlfY29va2llX2lkIjoiMTdlMDQ0NDlhYTMyNWUtMGYzMWY0MGY3Mzg4OWE4LTcxMmQ2NzVjLTIzNTkyOTYtMTdlMDQ0NDlhYTQ3Y2QifQ%3D%3D%22%2C%22history_login_id%22%3A%7B%22name%22%3A%22%24identity_login_id%22%2C%22value%22%3A%22217349%22%7D%7D; Hm_lpvt_8ab18ec6e3ee89210917ef2c8572b30e=1718325895; PHPSESSID=lq6hlkttj52althnkvtdb07cbk; _v_=737908")
  ("upgrade-insecure-requests:" . "1")
  ("pragma:" . "no-cache") ("cache-control:" . "no-cache")))))))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
