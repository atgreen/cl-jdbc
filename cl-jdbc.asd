;;;; cl-jdbc.asd --- A native Common Lisp API for JDBC on OpenLDK.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(asdf:defsystem "cl-jdbc"
  :description "A native Common Lisp API for JDBC databases, running on OpenLDK."
  :author "Anthony Green <green@moxielogic.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("openldk/interop")
  :serial t
  :components ((:file "package")
               (:file "runtime")
               (:file "types")
               (:file "connection")
               (:file "statement"))
  :in-order-to ((test-op (test-op "cl-jdbc/tests"))))

(asdf:defsystem "cl-jdbc/tests"
  :description "Tests for cl-jdbc."
  :depends-on ("cl-jdbc" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "tests"))))
  :perform (test-op (op c)
             (unless (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :cl-jdbc :cl-jdbc/tests))
               (error "cl-jdbc tests failed"))))
