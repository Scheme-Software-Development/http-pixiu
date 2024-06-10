(library (http-pixiu socket socket)
  (export 
    execl
    fork
    kill
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
(define close (foreign-procedure "close" (int) int))

(define dup (foreign-procedure "dup" (int) int))

(define execl4
  (let ((execl-help
      (foreign-procedure "execl"
        (string string string string void*)
        int)))
    (lambda (s1 s2 s3 s4)
      (execl-help s1 s2 s3 s4 0))))

(define fork (foreign-procedure "fork" () int))

(define kill (foreign-procedure "kill" (int int) int))

(define listen (foreign-procedure "listen" (int int) int))

(define tmpnam (foreign-procedure "tmpnam" (void*) string))

(define unlink (foreign-procedure "unlink" (string) int))
;;; routines defined in csocket.c
(define accept (foreign-procedure "do_accept" (int) int))

(define bytes-ready?
  (foreign-procedure "bytes_ready" (int) boolean))

(define bind (foreign-procedure "do_bind" (int string) int))

(define c-error (foreign-procedure "get_error" () string))

(define c-read (foreign-procedure "c_read" (int u8* size_t size_t) ssize_t))

(define c-write (foreign-procedure "c_write" (int u8* size_t ssize_t) ssize_t))
(define connect (foreign-procedure "do_connect" (int string) int))
(define socket (foreign-procedure "do_socket" () int))
;;; higher-level routines
(define (dodup old new)
; (dodup old new) closes old and dups new, then checks to
; make sure that resulting fd is the same as old
  (check ’close (close old))
  (unless (= (dup new) old)
    (error ’dodup
    "couldn’t set up child process io for fd ~s" old))))

(define (dofork child parent)
; (dofork child parent) forks a child process and invokes child
; without arguments and parent with the child’s pid
  (let ([pid (fork)])
    (cond
      [(= pid 0) (child)]
      [(> pid 0) (parent pid)]
      [else (error ’fork (c-error))]))))

(define (setup-server-socket name)
; create a socket, bind it to name, and listen for connections
  (let ([sock (check ’socket (socket))])
    (unlink name)
    (check ’bind (bind sock name))
    (check ’listen (listen sock 1))
    sock)))

(define (setup-client-socket name)
; create a socket and attempt to connect to server
  (let ([sock (check ’socket (socket))])
    (check ’connect (connect sock name))
    sock)))

(define (accept-socket sock)
; accept a connection
  (check ’accept (accept sock))))

(define (check who x)
; signal an error if status x is negative, using c-error to
; obtain the operating-system’s error message
  (if (< x 0)
    (error who (c-error))
    x)))

(define (terminate-process pid)
; kill the process identified by pid
  (kill pid 15)
  (void))
)
