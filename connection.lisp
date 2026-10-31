;;;; connection.lisp --- Opening, closing, and transacting on connections.
;;;;
;;;; Copyright (C) 2026  Anthony Green <anthony@atgreen.org>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-jdbc)

(defstruct (connection (:constructor %make-connection))
  "An open java.sql.Connection and the URL it was opened on."
  object
  url)

(defun make-properties (user password properties)
  "A java.util.Properties from USER, PASSWORD, and PROPERTIES (an alist or plist
of string/keyword names to values), each coerced to a string.  Returns an empty
Properties when all are NIL."
  (let ((props (java-new "java.util.Properties" "()")))
    (flet ((put (key value)
             (when (and key value)
               (java-call "setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;"
                          props (jstring (string key)) (jstring (princ-to-string value))))))
      (put "user" user)
      (put "password" password)
      (loop for rest = properties then (cdr rest)
            while rest
            for head = (car rest)
            do (if (consp head)
                   (put (car head) (cdr head))         ; alist: (name . value)
                   (progn (put head (cadr rest))       ; plist: name value
                          (setf rest (cdr rest))))))
    props))

(defun connect (url &key user password driver properties)
  "Open a connection to the database at the JDBC URL.  The driver is chosen from
URL's subprotocol (jdbc:h2:..., jdbc:postgresql:...) unless DRIVER overrides it;
DRIVER is a keyword in *DRIVERS*, Maven coordinates with a class as (COORDINATES
CLASS), or a driver-class string already on the classpath.  USER and PASSWORD,
and PROPERTIES (an alist or plist of driver-specific settings), are passed to the
driver.  Close the result with CLOSE, or use WITH-CONNECTION."
  (start)
  (let ((driver (or driver (url-driver url))))
    (when driver (ensure-driver driver)))
  (with-foreign-errors ("JDBC")
    (%make-connection
     :object (java-static "java.sql.DriverManager"
                          "getConnection(Ljava/lang/String;Ljava/util/Properties;)Ljava/sql/Connection;"
                          (jstring url)
                          (make-properties user password properties))
     :url url)))

(defmethod close ((connection connection))
  (with-foreign-errors ("JDBC")
    (java-call "close()V" (connection-object connection)))
  (values))

(defmacro with-connection ((var url &rest options) &body body)
  "Bind VAR to a connection opened on URL for the extent of BODY, then close it.
OPTIONS are CONNECT's keywords (:user, :password, :driver, :properties)."
  `(let ((,var (connect ,url ,@options)))
     (unwind-protect (progn ,@body)
       (close ,var))))

;;; Transactions

(defun auto-commit (connection)
  "Whether CONNECTION commits each statement by itself (the JDBC default)."
  (eql 1 (java-call "getAutoCommit()Z" (connection-object connection))))

(defun set-auto-commit (connection on)
  "Turn CONNECTION's auto-commit ON (T) or off (NIL).  With it off, changes are
held until COMMIT or discarded by ROLLBACK."
  (java-call "setAutoCommit(Z)V" (connection-object connection) (if on 1 0))
  on)

(defun commit (connection)
  "Commit CONNECTION's current transaction."
  (with-foreign-errors ("JDBC")
    (java-call "commit()V" (connection-object connection)))
  connection)

(defun rollback (connection)
  "Roll back CONNECTION's current transaction, discarding its uncommitted changes."
  (with-foreign-errors ("JDBC")
    (java-call "rollback()V" (connection-object connection)))
  connection)

(defmacro with-transaction ((connection) &body body)
  "Run BODY as one transaction on CONNECTION: auto-commit is turned off for the
duration, BODY's changes are committed if it returns normally and rolled back if
it unwinds, and the connection's prior auto-commit setting is restored."
  (let ((conn (gensym "CONN")) (prior (gensym "PRIOR")) (done (gensym "DONE")))
    `(let* ((,conn ,connection)
            (,prior (auto-commit ,conn))
            (,done nil))
       (set-auto-commit ,conn nil)
       (unwind-protect
            (multiple-value-prog1 (progn ,@body)
              (commit ,conn)
              (setf ,done t))
         (unless ,done (ignore-errors (rollback ,conn)))
         (set-auto-commit ,conn ,prior)))))
