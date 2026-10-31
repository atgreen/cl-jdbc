;;;; statement.lisp --- Running SQL and reading result sets.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-jdbc)

(defun prepare-statement (connection sql parameters)
  "A java.sql.PreparedStatement for SQL on CONNECTION, with PARAMETERS bound to
its ? placeholders in order.  Every statement goes through a PreparedStatement,
so parameters are escaped by the driver rather than spliced into the SQL."
  (let ((statement (java-call "prepareStatement(Ljava/lang/String;)Ljava/sql/PreparedStatement;"
                              (connection-object connection) (jstring sql))))
    (loop for value in parameters
          for index from 1
          do (bind-parameter statement index value))
    statement))

(defun read-result-set (result-set)
  "Drain a java.sql.ResultSet into (values ROWS COLUMNS): ROWS a list of rows,
each an alist of (column-label . value) in column order, and COLUMNS the list of
column-label strings.  Values are converted with JDBC-VALUE->LISP."
  (let* ((meta (java-call "getMetaData()Ljava/sql/ResultSetMetaData;" result-set))
         (count (java-call "getColumnCount()I" meta))
         (labels (loop for i from 1 to count
                       collect (lstring (java-call "getColumnLabel(I)Ljava/lang/String;" meta i)))))
    (values
     (loop while (eql 1 (java-call "next()Z" result-set))
           collect (loop for label in labels
                         for i from 1
                         collect (cons label
                                       (jdbc-value->lisp
                                        (java-call "getObject(I)Ljava/lang/Object;" result-set i)))))
     labels)))

(defun query (connection sql &rest parameters)
  "Run SQL that returns rows (a SELECT) on CONNECTION, binding PARAMETERS to its
? placeholders.  Returns (values ROWS COLUMNS): ROWS a list of rows, each an
alist of (column-label . value); COLUMNS the column-label strings.  Read a value
out of a row with ROW-VALUE, or with ASSOC.  For example:
  (query c \"select name, age from users where age > ?\" 21)"
  (start)
  (with-foreign-errors ("JDBC")
    (let ((statement (prepare-statement connection sql parameters)))
      (unwind-protect
           (read-result-set (java-call "executeQuery()Ljava/sql/ResultSet;" statement))
        (java-call "close()V" statement)))))

(defun execute (connection sql &rest parameters)
  "Run SQL that changes data or schema (INSERT, UPDATE, DELETE, DDL) on
CONNECTION, binding PARAMETERS to its ? placeholders.  Returns the number of
rows affected (0 for statements that affect none, such as DDL)."
  (start)
  (with-foreign-errors ("JDBC")
    (let ((statement (prepare-statement connection sql parameters)))
      (unwind-protect
           (java-call "executeUpdate()I" statement)
        (java-call "close()V" statement)))))

(defun row-value (row column)
  "The value of COLUMN (a column-label string) in ROW, an alist as QUERY
returns, or NIL if the row has no such column.  The match is case-insensitive,
since SQL folds the case of unquoted identifiers (and so a column written
\"name\" often comes back labelled \"NAME\")."
  (cdr (assoc (string column) row :test #'string-equal)))
