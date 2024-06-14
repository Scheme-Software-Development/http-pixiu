(library (http-pixiu core protocol status)
  (export 
    status:continue
    status:switching-protocols

    status:ok
    status:created
    status:accepted
    status:non-authoritative-information
    status:no-content
    status:reset-content
    status:partial-content

    status:multiple-choices
    status:moved-permanently
    status:found
    status:see-other
    status:not-modified
    status:use-proxy
    status:temporary-redirect

    status:bad-request
    status:unauthorized
    status:payment-required
    status:forbidden
    status:not-found
    status:not-allowed
    status:not-acceptable
    status:proxy-authentication-required
    status:request-timeout
    status:conflict
    status:gone
    status:length-required
    status:precondition-failed
    status:payload-too-large
    status:uri-too-long
    status:unsupported-media-type
    status:range-not-satisfiable
    status:expectation-failed
    status:upgrade-required

    status:internal-server-error
    status:not-implemented
    status:bad-gateway
    status:service-unavailable
    status:gateway-timeout
    status:http-version-not-supported)
  (import (rnrs))

(define status:continue 100)
(define status:switching-protocols 101)

(define status:ok 200)
(define status:created 201)
(define status:accepted 202)
(define status:non-authoritative-information 203)
(define status:no-content 204)
(define status:reset-content 205)
(define status:partial-content 206)

(define status:multiple-choices 300)
(define status:moved-permanently 301)
(define status:found 302)
(define status:see-other 303)
(define status:not-modified 304)
(define status:use-proxy 305)
(define status:temporary-redirect 307)

(define status:bad-request 400)
(define status:unauthorized 401)
(define status:payment-required 402)
(define status:forbidden 403)
(define status:not-found 404)
(define status:not-allowed 405)
(define status:not-acceptable 406)
(define status:proxy-authentication-required 407)
(define status:request-timeout 408)
(define status:conflict 409)
(define status:gone 410)
(define status:length-required 411)
(define status:precondition-failed 412)
(define status:payload-too-large 413)
(define status:uri-too-long 414)
(define status:unsupported-media-type 415)
(define status:range-not-satisfiable 416)
(define status:expectation-failed 417)
(define status:upgrade-required 426)

(define status:internal-server-error 500)
(define status:not-implemented 501)
(define status:bad-gateway 502)
(define status:service-unavailable 503)
(define status:gateway-timeout 504)
(define status:http-version-not-supported 505)
)