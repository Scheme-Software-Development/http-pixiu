(library (http-pixiu socket socket)
  (export 
    close
    dup
    execl
    fork
    kill
    listen
    tmpnam
    unlink
    accept
    bytes-ready?)
  (import (chescheme))

;;; Requires socket.so, built from socket.c.
(load-shared-object "./socket.so")
;;; Requires from C library:
;;; close, dup, execl, fork, kill, listen, tmpnam, unlink
(case (machine-type)
  [(i3le ti3le a6le ta6le) (load-shared-object "libc.so.6")]
  [(i3osx ti3osx a6osx ta6osx) (load-shared-object "libc.dylib")]
  [else (load-shared-object "libc.so")])

;;; basic C-library stuff
(define close
  (foreign-procedure "close" (int) int))

(define dup
  (foreign-procedure "dup" (int) int))

(define execl
  (let ((execl-help (foreign-procedure "execl" (string string string string void*) int)))
    (lambda (s1 s2 s3 s4)
      (execl-help s1 s2 s3 s4 0))))

(define fork
  (foreign-procedure "fork" () int))

(define kill
  (foreign-procedure "kill" (int int) int))

(define listen
  (foreign-procedure "listen" (int int) int))

(define tmpnam
  (foreign-procedure "tmpnam" (void*) string))

(define unlink
  (foreign-procedure "unlink" (string) int))

;;; routines defined in socket.c
(define accept
  (foreign-procedure "do_accept" (int) int))

(define bytes-ready?
  (foreign-procedure "bytes_ready" (int) boolean))
)
