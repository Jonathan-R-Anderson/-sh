(defmodule tut21
  (export (start-ping 1) (start-pong 0) (ping 2) (pong 0)))

(defun ping
  ((0 pong-node)
   (! (tuple 'pong pong-node) 'finished)
   (lfe_io:format "Ping finished~n" ()))
  ((n pong-node)
   (! (tuple 'pong pong-node) (tuple 'ping (self)))
   (receive
     ('pong (lfe_io:format "Ping received pong~n" ())))
   (ping (- n 1) pong-node)))

(defun pong ()
  (receive
    ('finished
     (lfe_io:format "Pong finished~n" ()))
    ((tuple 'ping ping-pid)
     (lfe_io:format "Pong received ping~n" ())
     (! ping-pid 'pong)
     (pong))))

(defun start-pong ()
  (register 'pong (spawn 'tut21 'pong ())))

(defun start-ping (pong-node)
  (spawn 'tut21 'ping (list 3 pong-node)))
