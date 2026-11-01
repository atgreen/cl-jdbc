;;;; cl-jdbc.asd --- A native Common Lisp API for JDBC on OpenLDK.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(asdf:defsystem "cl-jdbc"
  :description "A native Common Lisp API for JDBC databases, running on OpenLDK."
  :author "Anthony Green <green@moxielogic.com>"
  :license "MIT"
  :version "1.0.0"
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

;;; Opt-in integration tests against a live PostgreSQL (and dbd-jdbc through it).
;;; They skip unless a server is reachable; point them with CL_JDBC_TEST_PG_URL
;;; (and CL_JDBC_TEST_PG_USER / CL_JDBC_TEST_PG_PASSWORD), or run the container
;;; the README documents, which the defaults match.  Run with:
;;;   (asdf:test-system "cl-jdbc/postgres-tests")
(asdf:defsystem "cl-jdbc/postgres-tests"
  :description "Integration tests for cl-jdbc and dbd-jdbc against a live PostgreSQL."
  :depends-on ("cl-jdbc" "dbd-jdbc" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "postgres-tests"))))
  :perform (test-op (op c)
             (unless (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :cl-jdbc-postgres :cl-jdbc/postgres-tests))
               (error "cl-jdbc PostgreSQL tests failed"))))
