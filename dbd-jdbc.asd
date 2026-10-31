;;;; dbd-jdbc.asd --- A cl-dbi driver backed by JDBC through cl-jdbc.
;;;;
;;;; Copyright (C) 2026  Anthony Green <anthony@atgreen.org>
;;;; SPDX-License-Identifier: MIT

(asdf:defsystem "dbd-jdbc"
  :description "A cl-dbi (DBI) driver that reaches any database through its JDBC driver."
  :author "Anthony Green <anthony@atgreen.org>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-jdbc" "dbi")
  :serial t
  :components ((:file "dbd-jdbc"))
  :in-order-to ((test-op (test-op "dbd-jdbc/tests"))))

(asdf:defsystem "dbd-jdbc/tests"
  :description "Tests for dbd-jdbc, exercised through the cl-dbi API against H2."
  :depends-on ("dbd-jdbc" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "dbd-jdbc-tests"))))
  :perform (test-op (op c)
             (unless (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :dbd-jdbc :dbd-jdbc/tests))
               (error "dbd-jdbc tests failed"))))
