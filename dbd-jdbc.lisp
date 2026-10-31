;;;; dbd-jdbc.lisp --- A cl-dbi driver backed by JDBC through cl-jdbc.
;;;;
;;;; Copyright (C) 2026  Anthony Green <anthony@atgreen.org>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; This makes every JDBC driver a cl-dbi backend.  Code written to the cl-dbi
;;;; API -- and the libraries built on it, Mito, sxql, cl-batis -- can talk to
;;;; any database with a JDBC driver through:
;;;;
;;;;   (dbi:connect :jdbc :url "jdbc:h2:mem:test")
;;;;
;;;; The driver jar is selected from the URL's subprotocol and fetched on first
;;;; use, exactly as with the native cl-jdbc API.  Force a particular driver
;;;; with :jdbc-driver (a keyword in cl-jdbc:*drivers*, or coordinates); pass
;;;; credentials with :username/:password and driver settings with :properties.

(defpackage #:dbd.jdbc
  (:use #:cl #:dbi.driver #:dbi.error)
  (:import-from #:openldk.interop #:java-call #:jstring #:lstring)
  (:export #:dbd-jdbc #:dbd-jdbc-connection #:dbd-jdbc-query
           #:<dbd-jdbc> #:<dbd-jdbc-connection> #:<dbd-jdbc-query>))

(in-package #:dbd.jdbc)

(defclass dbd-jdbc (dbi-driver) ())

(defclass dbd-jdbc-connection (dbi-connection)
  ((last-row-count :initform nil :accessor last-row-count)))

(defclass dbd-jdbc-query (dbi-query)
  ((result-set :initform nil :accessor query-result-set)))

(defmethod make-connection ((driver dbd-jdbc)
                            &key url database-name user username password
                              jdbc-driver properties)
  "Open a JDBC-backed cl-dbi connection.  URL (or DATABASE-NAME) is the JDBC URL,
e.g. \"jdbc:postgresql://localhost/app\".  USERNAME (or USER) and PASSWORD are the
credentials; JDBC-DRIVER forces a driver (see cl-jdbc:*drivers*) when the URL's
subprotocol is not enough; PROPERTIES are extra driver settings."
  (let ((url (or url database-name
                 (error 'dbi-error
                        :format-control
                        "dbd-jdbc needs a :url, e.g. (dbi:connect :jdbc :url \"jdbc:h2:mem:test\")"))))
    (make-instance 'dbd-jdbc-connection
                   :database-name url
                   :handle (cl-jdbc:connect url
                                            :user (or user username)
                                            :password password
                                            :driver jdbc-driver
                                            :properties properties))))

(defun connection-jdbc-object (conn)
  "The underlying java.sql.Connection behind a dbd-jdbc connection."
  (cl-jdbc::connection-object (connection-handle conn)))

(defmethod disconnect ((conn dbd-jdbc-connection))
  (cl-jdbc:close (connection-handle conn)))

(defmethod prepare ((conn dbd-jdbc-connection) (sql string) &key)
  "Prepare SQL as a real java.sql.PreparedStatement, so its ? parameters are
bound by the driver rather than spliced into the SQL text."
  (make-instance 'dbd-jdbc-query
                 :connection conn
                 :sql sql
                 :prepared (java-call "prepareStatement(Ljava/lang/String;)Ljava/sql/PreparedStatement;"
                                      (connection-jdbc-object conn) (jstring sql))))

(defmethod execute-using-connection ((conn dbd-jdbc-connection) (query dbd-jdbc-query) params)
  "Bind PARAMS and run QUERY.  A row-returning statement leaves its ResultSet
open for FETCH to drain; any other statement records its affected-row count."
  (let ((statement (query-prepared query)))
    (loop for value in params
          for index from 1
          do (cl-jdbc::bind-parameter statement index value))
    (if (eql 1 (java-call "execute()Z" statement))
        (let* ((result-set (java-call "getResultSet()Ljava/sql/ResultSet;" statement))
               (meta (java-call "getMetaData()Ljava/sql/ResultSetMetaData;" result-set))
               (count (java-call "getColumnCount()I" meta)))
          (setf (query-fields query)
                (loop for i from 1 to count
                      collect (lstring (java-call "getColumnLabel(I)Ljava/lang/String;" meta i)))
                (query-result-set query) result-set
                (query-row-count query) nil))
        (setf (query-result-set query) nil
              (query-fields query) nil
              (query-row-count query) (java-call "getUpdateCount()I" statement)
              (last-row-count conn) (query-row-count query)))
    query))

(defmethod fetch-using-connection ((conn dbd-jdbc-connection) (query dbd-jdbc-query))
  "The next row of QUERY's open ResultSet as a list of values in field order,
or NIL when the rows are exhausted (closing the ResultSet)."
  (declare (ignore conn))
  (let ((result-set (query-result-set query)))
    (when result-set
      (if (eql 1 (java-call "next()Z" result-set))
          (loop for i from 1 to (length (query-fields query))
                collect (cl-jdbc::jdbc-value->lisp
                         (java-call "getObject(I)Ljava/lang/Object;" result-set i)))
          (progn
            (ignore-errors (java-call "close()V" result-set))
            (setf (query-result-set query) nil)
            nil)))))

(defmethod row-count ((conn dbd-jdbc-connection))
  (last-row-count conn))

(defmethod free-query-resources ((query dbd-jdbc-query))
  (let ((result-set (query-result-set query)))
    (when result-set
      (ignore-errors (java-call "close()V" result-set))
      (setf (query-result-set query) nil)))
  (ignore-errors (java-call "close()V" (query-prepared query))))

(defmethod ping ((conn dbd-jdbc-connection))
  (not (eql 1 (java-call "isClosed()Z" (connection-jdbc-object conn)))))

;;; Transactions.  cl-dbi's begin/commit/rollback map onto JDBC's auto-commit
;;; switch: a transaction turns auto-commit off, and ending it turns it back on.

(defmethod begin-transaction ((conn dbd-jdbc-connection))
  (cl-jdbc:set-auto-commit (connection-handle conn) nil))

(defmethod commit ((conn dbd-jdbc-connection))
  (cl-jdbc:commit (connection-handle conn))
  (cl-jdbc:set-auto-commit (connection-handle conn) t))

(defmethod rollback ((conn dbd-jdbc-connection))
  (cl-jdbc:rollback (connection-handle conn))
  (cl-jdbc:set-auto-commit (connection-handle conn) t))
