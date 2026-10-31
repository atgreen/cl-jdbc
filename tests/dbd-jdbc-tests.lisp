;;;; tests/dbd-jdbc-tests.lisp --- dbd-jdbc exercised through the cl-dbi API.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(defpackage #:dbd-jdbc/tests
  (:use #:cl #:fiveam)
  (:export #:dbd-jdbc))

(in-package #:dbd-jdbc/tests)

(def-suite dbd-jdbc
  :description "The JDBC cl-dbi driver, driven entirely through the dbi: API.")

(in-suite dbd-jdbc)

(defvar *db-counter* 0)

(defmacro with-dbi ((conn) &body body)
  "Bind CONN to a cl-dbi connection (driver :jdbc) on a fresh in-memory H2
database holding a table T of two rows, for BODY."
  `(let ((,conn (dbi:connect :jdbc :url (format nil "jdbc:h2:mem:dbi~D" (incf *db-counter*)))))
     (unwind-protect
          (progn
            (dbi:do-sql ,conn "create table t (id int primary key, name varchar, score double)")
            (dbi:do-sql ,conn "insert into t values (?, ?, ?)" (list 1 "one" 1.5d0))
            (dbi:do-sql ,conn "insert into t values (?, ?, ?)" (list 2 "two" 2.5d0))
            ,@body)
       (dbi:disconnect ,conn))))

(defun scalar (conn sql &rest params)
  "The first column of the first row of SQL, run on CONN."
  (let ((row (first (dbi:fetch-all (dbi:execute (dbi:prepare conn sql) params) :format :values))))
    (first row)))

(test driver-is-found
  "DBI:CONNECT :JDBC loads and finds the dbd-jdbc driver."
  (with-dbi (c)
    (is (typep c 'dbd.jdbc:dbd-jdbc-connection))))

(test do-sql-returns-affected-count
  "DO-SQL returns the number of rows a statement changed."
  (with-dbi (c)
    (is (= 1 (dbi:do-sql c "update t set score = 9 where id = 1")))
    (is (= 2 (dbi:do-sql c "update t set score = score + 1")))))

(test fetch-all-returns-plists
  "FETCH-ALL returns each row as a plist keyed by column name."
  (with-dbi (c)
    (let ((rows (dbi:fetch-all (dbi:execute (dbi:prepare c "select id, name from t order by id")))))
      (is (= 2 (length rows)))
      (is (= 1 (getf (first rows) :id)))
      (is (string= "one" (getf (first rows) :name)))
      (is (string= "two" (getf (second rows) :name))))))

(test parameters-are-bound
  "A ? parameter is bound by the driver, so a query selects the right rows."
  (with-dbi (c)
    (let ((row (first (dbi:fetch-all (dbi:execute (dbi:prepare c "select name from t where id = ?")
                                                  (list 2))))))
      (is (string= "two" (getf row :name))))
    (is (= 2 (scalar c "select count(*) from t")))))

(test fetch-pulls-one-row-at-a-time
  "FETCH returns rows one at a time and NIL when the result set is drained."
  (with-dbi (c)
    (let ((query (dbi:execute (dbi:prepare c "select id from t order by id"))))
      (is (= 1 (getf (dbi:fetch query) :id)))
      (is (= 2 (getf (dbi:fetch query) :id)))
      (is (null (dbi:fetch query))))))

(test transaction-commits-on-success
  "DBI:WITH-TRANSACTION commits the body's changes when it returns normally."
  (with-dbi (c)
    (dbi:with-transaction c
      (dbi:do-sql c "update t set score = 7 where id = 1"))
    (is (= 7 (scalar c "select score from t where id = 1")))))

(test transaction-rolls-back-on-error
  "DBI:WITH-TRANSACTION rolls the body's changes back when it unwinds."
  (with-dbi (c)
    (ignore-errors
     (dbi:with-transaction c
       (dbi:do-sql c "update t set score = 0")
       (error "boom")))
    (is (= 1.5d0 (scalar c "select score from t where id = 1")))))
