;;;; tests/tests.lisp --- cl-jdbc test suite, run against an in-memory H2 database.
;;;;
;;;; Copyright (C) 2026  Anthony Green <anthony@atgreen.org>
;;;; SPDX-License-Identifier: MIT

(defpackage #:cl-jdbc/tests
  (:use #:cl #:fiveam)
  (:export #:cl-jdbc))

(in-package #:cl-jdbc/tests)

(def-suite cl-jdbc
  :description "Connecting, querying and transacting through the cl-jdbc API.")

(in-suite cl-jdbc)

(defvar *db-counter* 0)

(defmacro with-sample-db ((conn) &body body)
  "Bind CONN to a connection on a fresh, private in-memory H2 database holding a
USERS table of three rows, for the extent of BODY."
  `(jdbc:with-connection (,conn (format nil "jdbc:h2:mem:test~D" (incf *db-counter*)))
     (jdbc:execute ,conn "create table users (id int primary key, name varchar, age int, active boolean)")
     (jdbc:execute ,conn "insert into users values (?, ?, ?, ?)" 1 "Ada"   36 t)
     (jdbc:execute ,conn "insert into users values (?, ?, ?, ?)" 2 "Grace" 44 t)
     (jdbc:execute ,conn "insert into users values (?, ?, ?, ?)" 3 "Alan"  41 nil)
     ,@body))

(test query-returns-rows-and-columns
  "QUERY returns rows as alists plus the list of column labels."
  (with-sample-db (c)
    (multiple-value-bind (rows columns) (jdbc:query c "select id, name, age from users order by id")
      (is (equal '("ID" "NAME" "AGE") columns))
      (is (= 3 (length rows)))
      (is (= 1 (jdbc:row-value (first rows) "id")))
      (is (string= "Ada" (jdbc:row-value (first rows) "name")))
      (is (= 36 (jdbc:row-value (first rows) "age"))))))

(test parameters-are-bound
  "A ? parameter is bound and escaped by the driver, not spliced into the SQL."
  (with-sample-db (c)
    (let ((rows (jdbc:query c "select name from users where age > ? order by age" 40)))
      (is (equal '("Alan" "Grace")
                 (mapcar (lambda (row) (jdbc:row-value row "name")) rows))))
    ;; A value that would be dangerous spliced in is harmless as a parameter.
    (is (null (jdbc:query c "select * from users where name = ?" "'; drop table users; --")))
    (is (= 3 (jdbc:row-value (first (jdbc:query c "select count(*) c from users")) "c")))))

(test execute-returns-affected-count
  "EXECUTE returns the number of rows a statement changed."
  (with-sample-db (c)
    (is (= 1 (jdbc:execute c "update users set age = 37 where id = 1")))
    (is (= 2 (jdbc:execute c "delete from users where age > 40")))  ; Grace 44, Alan 41
    (is (= 1 (jdbc:row-value (first (jdbc:query c "select count(*) c from users")) "c")))))

(test null-round-trips
  "NULL comes back as NIL, and NIL binds as SQL NULL."
  (with-sample-db (c)
    (jdbc:execute c "insert into users values (?, ?, ?, ?)" 4 "Nemo" nil nil)
    (let ((row (first (jdbc:query c "select age, active from users where id = ?" 4))))
      (is (null (jdbc:row-value row "age")))
      (is (null (jdbc:row-value row "active"))))))

(test lisp-types-round-trip
  "Strings, integers, reals and booleans survive a round trip."
  (with-sample-db (c)
    (jdbc:execute c "create table t (s varchar, i bigint, d double, b boolean)")
    (jdbc:execute c "insert into t values (?, ?, ?, ?)" "hi" 9000000000 3.5d0 t)
    (let ((row (first (jdbc:query c "select * from t"))))
      (is (string= "hi" (jdbc:row-value row "s")))
      (is (= 9000000000 (jdbc:row-value row "i")))
      (is (= 3.5d0 (jdbc:row-value row "d")))
      (is (eq t (jdbc:row-value row "b"))))))

(test transaction-commits-on-success
  "WITH-TRANSACTION commits changes when the body returns normally."
  (with-sample-db (c)
    (jdbc:with-transaction (c)
      (jdbc:execute c "update users set age = age + 1"))
    (is (= 37 (jdbc:row-value (first (jdbc:query c "select age from users where id = 1")) "age")))
    (is (jdbc:auto-commit c))))         ; prior setting restored

(test transaction-rolls-back-on-error
  "WITH-TRANSACTION rolls back the body's changes when it unwinds."
  (with-sample-db (c)
    (ignore-errors
     (jdbc:with-transaction (c)
       (jdbc:execute c "update users set age = 999")
       (error "boom")))
    (is (= 36 (jdbc:row-value (first (jdbc:query c "select age from users where id = 1")) "age")))
    (is (jdbc:auto-commit c))))

(test url-selects-driver
  "A jdbc:<subprotocol>:... URL selects its driver with no :driver argument."
  (is (eq :h2 (jdbc::url-driver "jdbc:h2:mem:whatever")))
  (is (eq :postgresql (jdbc::url-driver "jdbc:postgresql://localhost/db")))
  (is (null (jdbc::url-driver "jdbc:unknowndb:whatever"))))
