;;;; types.lisp --- Converting values between Lisp and java.sql.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-jdbc)

(defun bind-parameter (statement index value)
  "Bind VALUE to parameter INDEX (1-based) of a PreparedStatement.  Lisp values
map to JDBC setters, following the cl-postgres/Postmodern convention:
  T      -> boolean true
  NIL    -> boolean false
  :NULL  -> SQL NULL
  a string -> varchar, an integer -> bigint, a real -> double.
Anything else is passed through as a Java object (so a Java value obtained
elsewhere can be bound directly).  Note that NIL is false, not NULL: bind SQL
NULL with the keyword :NULL."
  (cond
    ((eq value :null)
     (java-call "setObject(ILjava/lang/Object;)V" statement index nil))
    ((eq value t)
     (java-call "setBoolean(IZ)V" statement index 1))
    ((null value)
     (java-call "setBoolean(IZ)V" statement index 0))
    ((stringp value)
     (java-call "setString(ILjava/lang/String;)V" statement index (jstring value)))
    ((integerp value)
     (java-call "setLong(IJ)V" statement index value))
    ((realp value)
     (java-call "setDouble(ID)V" statement index (coerce value 'double-float)))
    (t
     (java-call "setObject(ILjava/lang/Object;)V" statement index value))))

(defun jdbc-value->lisp (object)
  "A column value read from a ResultSet, as the closest Lisp value: NULL -> NIL,
a Java String -> a Lisp string, a Boolean -> T/NIL, a floating or decimal number
-> a double-float, any other number -> an integer.  Values with no natural Lisp
form (dates, timestamps, byte arrays) come back as their Java toString for now."
  (cond
    ((null object) nil)
    ((java-instance-p object "java.lang.String")     (lstring object))
    ((java-instance-p object "java.lang.Boolean")    (eql 1 (java-call "booleanValue()Z" object)))
    ((java-instance-p object "java.lang.Double")     (java-call "doubleValue()D" object))
    ((java-instance-p object "java.lang.Float")      (java-call "floatValue()F" object))
    ((java-instance-p object "java.math.BigDecimal") (java-call "doubleValue()D" object))
    ((java-instance-p object "java.lang.Number")     (java-call "longValue()J" object))
    (t (lstring (java-call "toString()Ljava/lang/String;" object)))))
