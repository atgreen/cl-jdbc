;;;; command-line-args.asd

(in-package asdf-user)

(defsystem "whereiseveryone.command-line-args"
  :version "0.1.1"
  :description
  "Automatically create a command-line-argument parser for a given
   Common Lisp function definition."
  :long-description
  "Command-Line-Args provides a main macro (`command') that wraps a
   `defun' form and creates a new function that parses the command
   line arguments.  It has support for command-line options,
   positoinal, and variadic arguments.  It also generates a basic help
   message. The interface is meant to be easy and non-intrusive."
  :author "Jorge & Charles"
  :mailto "~whereiseveryone/command-line-args@lists.sr.ht"
  :homepage "https://git.sr.ht/~whereiseveryone/command-line-args"
  :source-control "https://git.sr.ht/~whereiseveryone/command-line-args"
  :license "AGPL v3 or any later version"
  :depends-on
  ("alexandria"
   "serapeum"
   "str"
   "charje.documentation"
   "trivia")
  :serial t
  :in-order-to ((test-op (load-op "whereiseveryone.command-line-args/test")))
  :components
  ((:file "package")
   (:file "conditions")
   (:file "command-line-args")))

(defsystem "whereiseveryone.command-line-args/test"
  :depends-on ("whereiseveryone.command-line-args")
  :around-compile
  (lambda (thunk)
    (uiop:with-muffled-conditions ('(style-warning))
      (funcall thunk)))
  :components
  ((:file "t")))
