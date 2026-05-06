(library (http-pixiu core protocol cors)
  (export cors-preflight-response
          add-cors-headers)
  (import (chezscheme)
          (http-pixiu core protocol status)
          (http-pixiu core protocol response-construct))

(define (cors-preflight-response out)
  (write-response out status:no-content
    `(("Access-Control-Allow-Origin" . "*")
      ("Access-Control-Allow-Methods" . "GET, POST, PUT, DELETE, OPTIONS, HEAD")
      ("Access-Control-Allow-Headers" . "Content-Type, Authorization")
      ("Access-Control-Max-Age" . "86400"))
    '() #f #f))

(define (add-cors-headers alist allow-origin)
  (cons (cons "Access-Control-Allow-Origin" allow-origin) alist))

)
