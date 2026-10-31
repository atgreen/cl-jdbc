;;;; runtime.lisp --- Bootstrapping OpenLDK and putting JDBC drivers on the classpath.
;;;;
;;;; Copyright (C) 2026  Anthony Green <anthony@atgreen.org>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; The JDBC API itself (java.sql.*) is part of the JDK OpenLDK reads, so it
;;;; needs no jar.  A database *driver* does: its jar carries the classes that
;;;; speak the wire protocol, and loading its Driver class registers it with
;;;; java.sql.DriverManager.  cl-jdbc keeps a registry of well-known drivers so
;;;; a connection URL alone is usually enough -- the matching jar is fetched
;;;; from Maven Central on first use and cached by OpenLDK.

(in-package #:cl-jdbc)

(defparameter *drivers*
  ;; KEYWORD                 MAVEN COORDINATES                             DRIVER CLASS
  '((:h2         "com.h2database:h2:2.3.232"                       "org.h2.Driver")
    (:postgresql "org.postgresql:postgresql:42.7.4"               "org.postgresql.Driver")
    (:mysql      "com.mysql:mysql-connector-j:9.1.0"              "com.mysql.cj.jdbc.Driver")
    (:mariadb    "org.mariadb.jdbc:mariadb-java-client:3.5.1"     "org.mariadb.jdbc.Driver")
    (:sqlite     "org.xerial:sqlite-jdbc:3.47.1.0"                "org.sqlite.JDBC")
    (:sqlserver  "com.microsoft.sqlserver:mssql-jdbc:12.8.1.jre11" "com.microsoft.sqlserver.jdbc.SQLServerDriver")
    (:oracle     "com.oracle.database.jdbc:ojdbc11:23.6.0.24.10"  "oracle.jdbc.OracleDriver")
    (:db2        "com.ibm.db2:jcc:12.1.0.0"                       "com.ibm.db2.jcc.DB2Driver")
    (:snowflake  "net.snowflake:snowflake-jdbc:3.20.0"            "net.snowflake.client.jdbc.SnowflakeDriver")
    (:trino      "io.trino:trino-jdbc:465"                        "io.trino.jdbc.TrinoDriver"))
  "Known JDBC drivers as (KEYWORD MAVEN-COORDINATES DRIVER-CLASS).  The keyword
also names the URL subprotocol, so a jdbc:<keyword>:... URL selects a driver by
itself.  Add your own with REGISTER-DRIVER, or pass coordinates to ENSURE-DRIVER
directly.")

(defun register-driver (keyword coordinates class)
  "Teach cl-jdbc a JDBC driver: KEYWORD names it (and its URL subprotocol),
COORDINATES are its Maven coordinates (a \"group:artifact:version\" string, or
NIL if the jar is already on the classpath), and CLASS is its driver class name."
  (setf *drivers* (cons (list keyword coordinates class)
                        (remove keyword *drivers* :key #'first)))
  keyword)

(defvar *started* nil
  "True once START has brought the OpenLDK runtime up.")

(defvar *loaded-drivers* '()
  "Driver classes already loaded (and so registered with DriverManager).")

(defun start (&key extra-jars)
  "Start the OpenLDK Java runtime, with EXTRA-JARS (a list of jar pathnames or
namestrings) on the classpath.  Idempotent: calling it again only adds
EXTRA-JARS.  Driver jars are added on demand by CONNECT/ENSURE-DRIVER, so most
code never calls START itself."
  (if *started*
      (when extra-jars (start-runtime :classpath extra-jars))
      (progn
        (start-runtime :classpath extra-jars)
        (setf *started* t)))
  t)

(defun driver-spec (driver)
  "Resolve DRIVER to (values COORDINATES CLASS).  DRIVER is a keyword in
*DRIVERS*, a list (COORDINATES CLASS), or a bare driver-class string (whose jar
is assumed already on the classpath)."
  (etypecase driver
    (keyword
     (let ((row (or (assoc driver *drivers*)
                    (error "Unknown JDBC driver ~S; known: ~{~S~^ ~}"
                           driver (mapcar #'first *drivers*)))))
       (values (second row) (third row))))
    (cons   (values (first driver) (second driver)))
    (string (values nil driver))))

(defun ensure-driver (driver)
  "Make DRIVER (see DRIVER-SPEC) ready: fetch and classpath its jar if it names
Maven coordinates, then load its class so it registers with DriverManager.
Idempotent per class.  Returns the driver class name."
  (start)
  (multiple-value-bind (coordinates class) (driver-spec driver)
    (unless (member class *loaded-drivers* :test #'equal)
      (when coordinates
        (start-runtime :classpath (list (maven-jar coordinates))))
      (when class
        (java-load class)              ; its static initializer registers the driver
        (push class *loaded-drivers*)))
    class))

(defun url-driver (url)
  "The driver keyword a JDBC URL selects by its subprotocol -- the token
between the first two colons of \"jdbc:<subprotocol>:...\" -- or NIL if no known
driver matches it."
  (let* ((rest (and (> (length url) 5)
                    (string-equal "jdbc:" url :end2 5)
                    (subseq url 5)))
         (colon (and rest (position #\: rest)))
         (subprotocol (and colon (subseq rest 0 colon)))
         (keyword (and subprotocol (intern (string-upcase subprotocol) :keyword))))
    (and keyword (assoc keyword *drivers*) keyword)))

;;; CLOSE is a generic function over cl-jdbc's wrapper objects, each with its
;;; own method.  (Only connections are wrapped today; statements and result
;;; sets are opened and closed within QUERY/EXECUTE.)

(defgeneric close (object)
  (:documentation "Release the JDBC resource OBJECT, e.g. a connection."))
