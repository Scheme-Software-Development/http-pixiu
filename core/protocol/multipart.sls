(library (http-pixiu core protocol multipart)
  (export
    parse-multipart-form-data
    multipart-part-name
    multipart-part-filename
    multipart-part-content-type
    multipart-part-body)

  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Multipart/form-data parser (RFC 7578)
  ;;
  ;; Returns a list of parts:
  ;;   ((name filename content-type body-bytevector) ...)
  ;; ------------------------------------------------------------------

  (define (parse-boundary content-type)
    (let ([s (string-downcase content-type)])
      (let ([idx (string-index-of s "boundary=")])
        (if idx
            (let ([start (+ idx 9)])
              (let ([end (let loop ([i start])
                           (cond
                             [(>= i (string-length s)) i]
                             [(char=? (string-ref s i) #\;) i]
                             [else (loop (+ i 1))]))])
                (let ([b (substring content-type start end)])
                  (string-trim-both b))))
            #f))))

  (define (string-index-of s substr)
    (let ([sub-len (string-length substr)]
          [len (string-length s)])
      (let loop ([i 0])
        (cond
          [(> (+ i sub-len) len) #f]
          [(string-ci=? (substring s i (+ i sub-len)) substr) i]
          [else (loop (+ i 1))]))))

  (define (string-trim-both s)
    (let ([len (string-length s)])
      (let ([start (let loop ([i 0])
                     (if (and (< i len) (char-whitespace? (string-ref s i)))
                         (loop (+ i 1))
                         i))]
            [end (let loop ([i len])
                   (if (and (> i 0) (char-whitespace? (string-ref s (- i 1))))
                       (loop (- i 1))
                       i))])
        (if (>= start end)
            ""
            (substring s start end)))))

  (define (string-split-CRNL s)
    (let ([len (string-length s)])
      (let loop ([i 0] [start 0] [acc '()])
        (cond
          [(>= i len) (reverse (cons (substring s start i) acc))]
          [(and (< (+ i 1) len)
                (char=? (string-ref s i) #\return)
                (char=? (string-ref s (+ i 1)) #\newline))
           (loop (+ i 2) (+ i 2) (cons (substring s start i) acc))]
          [(char=? (string-ref s i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
          [else (loop (+ i 1) start acc)]))))

  (define (parse-content-disposition line)
    ;; "form-data; name=\"field\"; filename=\"file.txt\""
    ;; Returns (name . filename) or (#f . #f)
    (let ([name-re "name="]
          [filename-re "filename="])
      (let ([name (extract-quoted-value line name-re)]
            [filename (extract-quoted-value line filename-re)])
        (cons name filename))))

  (define (extract-quoted-value line prefix)
    (let ([idx (string-index-of line prefix)])
      (if idx
          (let ([start (+ idx (string-length prefix))])
            (let ([quote-char (if (< start (string-length line)) (string-ref line start) #f)])
              (if (or (char=? quote-char #\") (char=? quote-char #\'))
                  (let ([end (let loop ([i (+ start 1)])
                               (cond
                                 [(>= i (string-length line)) i]
                                 [(char=? (string-ref line i) quote-char) i]
                                 [else (loop (+ i 1))]))])
                    (substring line (+ start 1) end))
                  ;; unquoted value
                  (let ([end (let loop ([i start])
                               (cond
                                 [(>= i (string-length line)) i]
                                 [(char-whitespace? (string-ref line i)) i]
                                 [(char=? (string-ref line i) #\;) i]
                                 [else (loop (+ i 1))]))])
                    (substring line start end)))))
          #f)))

  (define (parse-part-headers header-lines)
    (let loop ([lines header-lines] [name #f] [filename #f] [content-type #f])
      (if (null? lines)
          (list name filename content-type)
          (let ([line (car lines)])
            (cond
              [(string-index-of line "Content-Disposition:")
               (let ([disp (parse-content-disposition line)])
                 (loop (cdr lines) (car disp) (cdr disp) content-type))]
              [(string-index-of line "Content-Type:")
               (let ([ct (substring line (+ (string-index-of line "Content-Type:") 13) (string-length line))])
                 (loop (cdr lines) name filename (string-trim-both ct)))]
              [else (loop (cdr lines) name filename content-type)])))))

  (define (find-subbytevector bv pattern start)
    ;; Find index of pattern in bv, starting from start.
    ;; Returns index or #f.
    (let ([pat-len (bytevector-length pattern)]
          [bv-len (bytevector-length bv)])
      (let loop ([i start])
        (cond
          [(> (+ i pat-len) bv-len) #f]
          [(bytevector-prefix-match? bv i pattern) i]
          [else (loop (+ i 1))]))))

  (define (bytevector-prefix-match? bv offset pattern)
    (let ([pat-len (bytevector-length pattern)])
      (let loop ([i 0])
        (cond
          [(>= i pat-len) #t]
          [(not (= (bytevector-u8-ref bv (+ offset i)) (bytevector-u8-ref pattern i))) #f]
          [else (loop (+ i 1))]))))

  (define (bytevector-slice bv start end)
    (let ([len (- end start)])
      (let ([result (make-bytevector len)])
        (bytevector-copy! bv start result 0 len)
        result)))

  (define (parse-multipart-form-data body-bv content-type)
    (let ([boundary (parse-boundary content-type)])
      (if (not boundary)
          '()
          (let ([boundary-bv (string->utf8 (string-append "--" boundary))])
            (let ([parts (split-by-boundaries body-bv boundary-bv)])
              (filter (lambda (p) p) (map parse-part parts)))))))

  (define (split-by-boundaries body-bv boundary-bv)
    ;; Find all occurrences of boundary and split body into parts
    (let ([blen (bytevector-length boundary-bv)])
      (let loop ([start 0] [acc '()])
        (let ([idx (find-subbytevector body-bv boundary-bv start)])
          (if (not idx)
              (reverse acc)
              (let ([part-start (+ idx blen)])
                ;; Skip \r\n or \n after boundary
                (let ([data-start
                       (cond
                         [(and (< part-start (bytevector-length body-bv))
                               (= (bytevector-u8-ref body-bv part-start) 13)
                               (< (+ part-start 1) (bytevector-length body-bv))
                               (= (bytevector-u8-ref body-bv (+ part-start 1)) 10))
                          (+ part-start 2)]
                         [(and (< part-start (bytevector-length body-bv))
                               (= (bytevector-u8-ref body-bv part-start) 10))
                          (+ part-start 1)]
                         [else part-start])])
                  (let ([next-idx (find-subbytevector body-bv boundary-bv data-start)])
                    (if (not next-idx)
                        (reverse acc)
                        (let ([part-end
                               (cond
                                 [(and (> next-idx 1)
                                       (= (bytevector-u8-ref body-bv (- next-idx 2)) 13)
                                       (= (bytevector-u8-ref body-bv (- next-idx 1)) 10))
                                  (- next-idx 2)]
                                 [(and (> next-idx 0)
                                       (= (bytevector-u8-ref body-bv (- next-idx 1)) 10))
                                  (- next-idx 1)]
                                 [else next-idx])])
                          (loop data-start (cons (bytevector-slice body-bv data-start part-end) acc))))))))))))

  (define (parse-part part-bv)
    ;; part-bv contains headers + empty line + body
    ;; Find the empty line (\r\n\r\n or \n\n)
    (let ([bv-len (bytevector-length part-bv)])
      (let find-empty ([i 0])
        (cond
          [(>= i bv-len) #f]
          [(and (< (+ i 3) bv-len)
                (= (bytevector-u8-ref part-bv i) 13)
                (= (bytevector-u8-ref part-bv (+ i 1)) 10)
                (= (bytevector-u8-ref part-bv (+ i 2)) 13)
                (= (bytevector-u8-ref part-bv (+ i 3)) 10))
           (let ([header-bv (bytevector-slice part-bv 0 i)]
                 [body-bv (bytevector-slice part-bv (+ i 4) bv-len)])
             (let ([header-lines (string-split-CRNL (utf8->string header-bv))])
               (let ([parsed (parse-part-headers header-lines)])
                 (list (car parsed) (cadr parsed) (caddr parsed) body-bv))))]
          [(and (< (+ i 1) bv-len)
                (= (bytevector-u8-ref part-bv i) 10)
                (= (bytevector-u8-ref part-bv (+ i 1)) 10))
           (let ([header-bv (bytevector-slice part-bv 0 i)]
                 [body-bv (bytevector-slice part-bv (+ i 2) bv-len)])
             (let ([header-lines (string-split-CRNL (utf8->string header-bv))])
               (let ([parsed (parse-part-headers header-lines)])
                 (list (car parsed) (cadr parsed) (caddr parsed) body-bv))))]
          [else (find-empty (+ i 1))]))))

  (define (multipart-part-name part) (list-ref part 0))
  (define (multipart-part-filename part) (list-ref part 1))
  (define (multipart-part-content-type part) (list-ref part 2))
  (define (multipart-part-body part) (list-ref part 3))

)
