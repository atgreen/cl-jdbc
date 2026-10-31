;;;; t.lisp


(in-package whereiseveryone.command-line-args)

(defun set-args (args)
  (setf sb-ext:*posix-argv*
        (cons "/home/args-user/sbcl" args)))

(defmacro assert-condition (condition &body body)
  `(handler-case (progn,@body)
     (,condition () nil)
     (:no-error (&rest result)
       (declare (ignore result))
       (error "The test failed because `~A' was not signaled."
              ',condition))))

;;; standard positional arguments

(command
 (defun add-one (x y z)
   "Add all of X, Y, Z, and 1."
   (declare (parser parse-integer x y z))
   (+ x y z 1)))

(progn
  (set-args '("2" "3" "4"))
  (assert (= 10 (add-one-command))))

(progn
  (set-args '("2" "3" "4" "5"))
  (assert-condition wrong-number-of-args
    (add-one-command)))

;;; optional arguments

(command
 (defun add-some (x y &optional (z 0))
   (declare (parser parse-integer x y z))
   (+ x y z 1)))

(progn
  (set-args '("2" "3"))
  (assert (= 6 (add-some-command))))

(progn
  (set-args '("2" "3" "4"))
  (assert (= 10 (add-some-command))))

;;; keyword arguments

(command
 (defun add-some-with-keyword-args (&key (x 0) (y 0) (z 0))
   (declare (parser parse-integer x y z))
   (+ x y z)))

(progn
  (set-args '("-x" "3" "--y" "5"))
  (assert (= 8 (add-some-with-keyword-args-command))))

(progn
  (set-args '("-x" "3" "-n" "5"))
  (assert-condition invalid-flag
    (add-some-with-keyword-args-command)))

;;; short flag override

(command
 (defun what (&key (cat "kitty") (cake "yummy"))
   (declare (flag #\C cat))
   (format nil "~A ~A" cat cake)))

(progn
  (set-args '("-C" "a" "-c" "b"))
  (assert (string= "a b" (what-command))))

(progn
  (set-args '("--cat" "a" "--cake" "b"))
  (assert (string= "a b" (what-command))))

;;; boolean flags

(command
 (defun boolean-flag-test (&key apple berry cashew other)
   (declare (parser parse-boolean apple berry cashew))
   (with-output-to-string (*standard-output*)
     (when apple
       (princ "apple "))
     (when berry
       (princ "berry "))
     (when cashew
       (princ "cashew "))
     (when other
       (princ other)))))

(progn
  (set-args '("-a" "-b" "-c"))
  (assert (string= "apple berry cashew "
                   (boolean-flag-test-command))))


(command
 (defun boolean-verbose-test (&key verbose)
   (declare (parser parse-boolean verbose))
   (with-output-to-string (*standard-output*)
     (when (< 0 verbose)
       (princ "level one "))
     (when (< 1 verbose)
       (princ "level two "))
     (when (< 2 verbose)
       (princ "level three ")))))

(progn
  (set-args '("-vvv"))
  (assert (string= "level one level two level three "
                   (boolean-verbose-test-command))))

(progn
  (set-args '("-v" "-v" "-v"))
  (assert (string= "level one level two level three "
                   (boolean-verbose-test-command))))

;;; combined short flags

(progn
  (set-args '("-abc"))
  (assert (string= "apple berry cashew "
                   (boolean-flag-test-command))))

(progn
  (set-args '("-ca"))
  (assert (string= "apple cashew "
                   (boolean-flag-test-command))))

(progn
  (set-args '("-abco" "pom"))
  (assert-condition invalid-combined-short-flag
    (boolean-flag-test-command)))


;;; parse-boolean positional

(command
 (defun test-parse-boolean-positional (&optional o)
   (declare (parser parse-boolean o))
   (when o
     "true")))

(progn
  (set-args '(""))
  (assert (eq nil
              (test-parse-boolean-positional-command))))

(progn
  (set-args '("true"))
  (assert (string= "true"
                   (test-parse-boolean-positional-command))))

;; end of options

(command
 (defun concat-args (one two)
   (format nil "~A~A" one two)))

(progn
  (set-args '("-one" "-two"))
  (assert-condition invalid-flag
    (concat-args-command)))

(progn
  (set-args '("--" "-one" "-two"))
  (concat-args-command))

;;; variadic arguments

(command
 (defun kill-pod (cluster pods &key humane)
   (declare (parser (list parse-integer) pods)
            (parser parse-boolean humane))
   (when humane
     (format t "\"humanely\"...~%"))
   (format t "In ~A:~%" cluster)
   (dolist (pod pods)
     (format t "killed ~A~%" pod))))

(progn
  (set-args '("--humane" "prod" "1234" "4534" "2342"))
  (assert
   (string=
    "\"humanely\"...
In prod:
killed 1234
killed 4534
killed 2342
"
    (with-output-to-string (*standard-output*)
      (kill-pod-command)))))

(progn
  (set-args '())
  (assert-condition wrong-number-of-args
    (kill-pod-command)))

(assert-condition invalid-variadic-parser
  (macroexpand
   '(command
     (defun bad-variadic (a b)
       (declare (parser (list parse-integer)
                        a b))))))

(assert-condition invalid-variadic-parser
  (macroexpand
   '(command
     (defun bad-variadic (&key a)
       (declare (parser (list parse-integer)
                        a))))))

(assert-condition rest-used-for-variadic
  (macroexpand
   '(command
     (defun bad-variadic (&rest a)
       (declare (parser parse-integer a))))))

;;; subcommands

(command
 (defun create-pod (cluster name)
   "Create a pod named NAME in CLUSTER."
   (format t "created ~A in ~A~%"
           name
           cluster)))

(command
 (defun hexctl (subcommand)
   "Top level command for controlling The Hex."
   (subcommand-case subcommand
     create-pod
     kill-pod)))

(progn
  (set-args '("create-pod" "foo" "bar"))
  (assert (string= "created bar in foo
"
                   (with-output-to-string (*standard-output*)
                     (hexctl-command)))))

(command
 (defun test-help (apple bobby carrot &optional pills &key count-apple count-carrot)
   "Just print everything for absolutely no reason.

    APPLE: The Apple obviously.

    BOBBY: The bobby object of this scenario.

    CARROT: BOBBY's carrot.

    PILLS: The types of pills BOBBY should make.

    COUNT-APPLE: The amount of apple that should go into each
    pill. The unit is miligrams.

    COUNT-CARROT: The amount of carrot that should go into each
    pill. The unit is miligrams. This depends greatly on if BOBBY is
    willing to give up his carrot.

    I really do not know where I was going with this description."
   (declare (parser (list identity) pills)
            (parser parse-integer count-apple count-carrot))
   (print apple)
   (print bobby)
   (print carrot)
   (print pills)
   (print count-apple)
   (print count-carrot)))
