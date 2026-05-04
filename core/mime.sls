(library (http-pixiu core mime)
  (export guess-mime-type)
  (import (chezscheme))

  (define mime-table
    '(("html" . "text/html")
      ("htm"  . "text/html")
      ("css"  . "text/css")
      ("js"   . "application/javascript")
      ("json" . "application/json")
      ("png"  . "image/png")
      ("jpg"  . "image/jpeg")
      ("jpeg" . "image/jpeg")
      ("gif"  . "image/gif")
      ("svg"  . "image/svg+xml")
      ("ico"  . "image/x-icon")
      ("txt"  . "text/plain")
      ("xml"  . "application/xml")
      ("pdf"  . "application/pdf")
      ("woff" . "font/woff")
      ("woff2" . "font/woff2")
      ("ttf"  . "font/ttf")
      ("otf"  . "font/otf")
      ("eot"  . "application/vnd.ms-fontobject")))

  (define (file-extension path)
    (let ([len (string-length path)])
      (let loop ([i (- len 1)])
        (cond
          [(< i 0) ""]
          [(char=? (string-ref path i) #\.)
           (substring path (+ i 1) len)]
          [else (loop (- i 1))]))))

  (define (guess-mime-type path)
    (let ([ext (string-downcase (file-extension path))])
      (let ([pair (assoc ext mime-table)])
        (if pair
            (cdr pair)
            "application/octet-stream"))))
)
