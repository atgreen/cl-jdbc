;;;; package.lisp --- Package definition for cl-jdbc.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(defpackage #:cl-jdbc
  (:use #:cl)
  (:nicknames #:jdbc)
  (:shadow #:close)
  (:import-from #:openldk.interop
                #:start-runtime
                #:maven-jar
                #:java-new #:java-call #:java-static #:java-static-field #:java-load
                #:jstring #:lstring #:make-java-array-of
                #:java-instance-p #:with-foreign-errors)
  (:export
   ;; runtime
   #:start #:*drivers* #:register-driver #:ensure-driver
   ;; connecting
   #:connect #:with-connection #:connection #:connection-p #:connection-url
   ;; closing (generic over connections)
   #:close
   ;; statements
   #:query #:execute #:row-value
   ;; transactions
   #:commit #:rollback #:with-transaction #:auto-commit #:set-auto-commit))
