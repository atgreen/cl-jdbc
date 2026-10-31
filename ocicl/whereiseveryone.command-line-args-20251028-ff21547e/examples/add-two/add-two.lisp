(defpackage add-two
  (:use cl)
  (:local-nicknames (cli whereiseveryone.command-line-args)))
(in-package add-two)

@cli:command
(defun add-two (&key apple banana)
  (declare (cli:parser parse-integer apple banana))
  (uiop:println (+ apple banana)))
