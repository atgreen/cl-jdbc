;;;; tests/postgres-tests.lisp --- Integration tests against a live PostgreSQL.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Unlike the H2 suites, these need a running PostgreSQL.  Start one with:
;;;;
;;;;   podman run -d --name cl-jdbc-pg \
;;;;     -e POSTGRES_USER=test -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=testdb \
;;;;     -p 55432:5432 postgres:17
;;;;
;;;; The defaults below match that container; override with CL_JDBC_TEST_PG_URL,
;;;; CL_JDBC_TEST_PG_USER and CL_JDBC_TEST_PG_PASSWORD.  Every test SKIPs (rather
;;;; than fails) when no server is reachable, so the suite is safe to run anywhere.

(defpackage #:cl-jdbc/postgres-tests
  (:use #:cl #:fiveam)
  (:export #:cl-jdbc-postgres))

(in-package #:cl-jdbc/postgres-tests)

(def-suite cl-jdbc-postgres
  :description "cl-jdbc and dbd-jdbc against a live PostgreSQL server.")

(in-suite cl-jdbc-postgres)

(defun pg-url ()      (or (uiop:getenv "CL_JDBC_TEST_PG_URL")      "jdbc:postgresql://localhost:55432/testdb"))
(defun pg-user ()     (or (uiop:getenv "CL_JDBC_TEST_PG_USER")     "test"))
(defun pg-password () (or (uiop:getenv "CL_JDBC_TEST_PG_PASSWORD") "secret"))

(defun call-with-pg (fn)
  "Open a cl-jdbc connection to the test PostgreSQL and call FN with it, closing
it after.  If the server cannot be reached, SKIP the current test instead."
  (let ((conn (handler-case (jdbc:connect (pg-url) :user (pg-user) :password (pg-password))
                (error (e)
                  (skip "PostgreSQL not reachable at ~A (~A)" (pg-url) e)
                  (return-from call-with-pg)))))
    (unwind-protect (funcall fn conn)
      (jdbc:close conn))))

(defmacro with-pg ((conn) &body body)
  `(call-with-pg (lambda (,conn) ,@body)))

(test connect-and-report-version
  "cl-jdbc connects to PostgreSQL and reads its version string."
  (with-pg (c)
    (let ((version (jdbc:row-value (first (jdbc:query c "select version() v")) "v")))
      (is (search "PostgreSQL" version)))))

(test round-trip-types
  "DDL, parameters and PostgreSQL types round-trip through the native API."
  (with-pg (c)
    (jdbc:execute c "drop table if exists cl_jdbc_t")
    (jdbc:execute c "create table cl_jdbc_t (id serial primary key, name text, score double precision, flag boolean, note text)")
    (jdbc:execute c "insert into cl_jdbc_t (name, score, flag, note) values (?, ?, ?, ?)" "one" 1.5d0 t :null)
    (jdbc:execute c "insert into cl_jdbc_t (name, score, flag, note) values (?, ?, ?, ?)" "two" 2.5d0 nil "n")
    (multiple-value-bind (rows cols) (jdbc:query c "select id, name, score, flag, note from cl_jdbc_t order by id")
      (is (equal '("id" "name" "score" "flag" "note") cols))   ; PostgreSQL lowercases
      (is (= 2 (length rows)))
      (let ((a (first rows)) (b (second rows)))
        (is (integerp (jdbc:row-value a "id")))
        (is (string= "one" (jdbc:row-value a "name")))
        (is (= 1.5d0 (jdbc:row-value a "score")))
        (is (eq t (jdbc:row-value a "flag")))
        (is (null (jdbc:row-value a "note")))        ; :null -> SQL NULL -> NIL
        (is (eq nil (jdbc:row-value b "flag")))       ; NIL bound as boolean false
        (is (string= "n" (jdbc:row-value b "note")))))
    ;; A parameter can't inject SQL.
    (is (null (jdbc:query c "select * from cl_jdbc_t where name = ?" "'; drop table cl_jdbc_t; --")))
    (is (= 2 (jdbc:row-value (first (jdbc:query c "select count(*) c from cl_jdbc_t")) "c")))))

(test transaction-rolls-back
  "WITH-TRANSACTION rolls back the body's changes on PostgreSQL when it unwinds."
  (with-pg (c)
    (jdbc:execute c "drop table if exists cl_jdbc_tx")
    (jdbc:execute c "create table cl_jdbc_tx (id int primary key, n int)")
    (jdbc:execute c "insert into cl_jdbc_tx values (1, 10)")
    (ignore-errors
     (jdbc:with-transaction (c)
       (jdbc:execute c "update cl_jdbc_tx set n = 999 where id = 1")
       (error "boom")))
    (is (= 10 (jdbc:row-value (first (jdbc:query c "select n from cl_jdbc_tx where id = 1")) "n")))))

(test through-cl-dbi
  "dbd-jdbc drives PostgreSQL through the cl-dbi API."
  ;; Skip only when the *connection* can't be made; let any later error surface.
  ;; Rows are read with :format :values rather than the plist, because cl-dbi
  ;; interns plist keys verbatim from the column labels and PostgreSQL lowercases
  ;; them (:|id|, not :id), so positional access stays portable across databases.
  (let ((conn (handler-case
                  (dbi:connect :jdbc :url (pg-url) :username (pg-user) :password (pg-password))
                (error (e)
                  (skip "PostgreSQL not reachable via cl-dbi at ~A (~A)" (pg-url) e)
                  (return-from through-cl-dbi)))))
    (unwind-protect
         (progn
           (dbi:do-sql conn "drop table if exists cl_jdbc_dbi")
           (dbi:do-sql conn "create table cl_jdbc_dbi (id int primary key, name text)")
           (is (= 1 (dbi:do-sql conn "insert into cl_jdbc_dbi values (?, ?)" (list 1 "one"))))
           (let ((vals (first (dbi:fetch-all
                               (dbi:execute (dbi:prepare conn "select id, name from cl_jdbc_dbi where id = ?")
                                            (list 1))
                               :format :values))))
             (is (equal '(1 "one") vals))))
      (dbi:disconnect conn))))
