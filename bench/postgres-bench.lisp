;;;; bench/postgres-bench.lisp --- cl-jdbc vs the native cl-postgres driver.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; A rough performance comparison of reaching PostgreSQL two ways: through its
;;;; JDBC driver under OpenLDK (cl-jdbc) and through the native Common Lisp
;;;; driver cl-postgres.  Both talk to the same server and run the same work --
;;;; row-by-row inserts, a repeated full-table scan, and repeated point queries.
;;;;
;;;; This is not in any ASDF system; load it directly, with a PostgreSQL running:
;;;;
;;;;   podman run -d --name cl-jdbc-pg \
;;;;     -e POSTGRES_USER=test -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=testdb \
;;;;     -p 55432:5432 postgres:17
;;;;
;;;;   JAVA_HOME=/path/to/jdk-25 sbcl --load bench/postgres-bench.lisp
;;;;
;;;; Connection defaults match that container; override with CL_JDBC_BENCH_PG_*
;;;; (HOST, PORT, DB, USER, PASSWORD).  Needs cl-postgres on the ASDF registry.
;;;;
;;;; Caveats, so the numbers aren't over-read: timings are warmup-sensitive
;;;; (OpenLDK transpiles and optimizes the driver lazily, so results warm up and
;;;; still show occasional multi-second compilation pauses), and they depend on
;;;; the OpenLDK build.  Treat them as directional.  The durable finding is that
;;;; a read-heavy scan is far cheaper with the native driver, because the cost
;;;; is the JDBC driver's own row decoding running as transpiled code, not
;;;; cl-jdbc's wrapper (GC, for instance, is under 1% of the scan).

(asdf:load-system "cl-jdbc")
(asdf:load-system "cl-postgres")

(defpackage #:cl-jdbc-bench
  (:use #:cl)
  (:export #:run))

(in-package #:cl-jdbc-bench)

(defun env (name default)
  (or (uiop:getenv name) default))

(defparameter *host*     (env "CL_JDBC_BENCH_PG_HOST" "localhost"))
(defparameter *port*     (parse-integer (env "CL_JDBC_BENCH_PG_PORT" "55432")))
(defparameter *db*       (env "CL_JDBC_BENCH_PG_DB" "testdb"))
(defparameter *user*     (env "CL_JDBC_BENCH_PG_USER" "test"))
(defparameter *password* (env "CL_JDBC_BENCH_PG_PASSWORD" "secret"))

(defparameter *rows* 2000
  "Rows in the benchmark table.")
(defparameter *scan-reps* 50
  "Full-table scans per scan trial.")
(defparameter *point-reps* 1000
  "Point queries per point-query trial.")
(defparameter *trials* 3
  "Timed trials per read phase (to expose variance).")

(defun jdbc-url ()
  (format nil "jdbc:postgresql://~A:~D/~A" *host* *port* *db*))

(defun row-name (i)
  (format nil "row-~D" i))

;;; Timing: wall-clock milliseconds, and the GC time inside the same window, so
;;; it is clear how little of a read phase is garbage collection.

(defun call-timed (thunk)
  (sb-ext:gc :full t)
  (let ((gc0 sb-ext:*gc-run-time*)
        (t0 (get-internal-real-time)))
    (funcall thunk)
    (flet ((ms (ticks) (/ (* 1000.0 ticks) internal-time-units-per-second)))
      (values (ms (- (get-internal-real-time) t0))
              (ms (- sb-ext:*gc-run-time* gc0))))))

(defun report-phase (label thunk &optional (trials 1))
  "Run THUNK TRIALS times, printing each trial's wall time and the worst GC time."
  (let ((walls '()) (max-gc 0.0))
    (dotimes (i trials)
      (multiple-value-bind (wall gc) (call-timed thunk)
        (push wall walls)
        (setf max-gc (max max-gc gc))))
    (setf walls (nreverse walls))
    (format t "  ~26A ~{~8,1F~^ ~} ms~:[~;   (gc <= ~,1F ms)~]~%"
            label walls (plusp max-gc) max-gc)
    (values (reduce #'min walls) max-gc)))

;;; cl-jdbc (PostgreSQL JDBC driver, transpiled by OpenLDK)

(defun run-jdbc ()
  (format t "~%cl-jdbc (PostgreSQL JDBC driver, transpiled by OpenLDK):~%")
  (jdbc:with-connection (c (jdbc-url) :user *user* :password *password*)
    (jdbc:execute c "drop table if exists bench")
    (jdbc:execute c "create table bench (id int primary key, name text, score double precision, flag boolean)")
    (report-phase (format nil "insert ~D (1 by 1)" *rows*)
                  (lambda ()
                    (jdbc:execute c "truncate bench")
                    (dotimes (i *rows*)
                      (jdbc:execute c "insert into bench values (?,?,?,?)"
                                    i (row-name i) (* i 1.5d0) (evenp i)))))
    (dotimes (w 5) (jdbc:query c "select id, name, score, flag from bench")) ; warmup the scan path
    (report-phase (format nil "scan x~D (~Dk rows)" *scan-reps* (round (* *rows* *scan-reps*) 1000))
                  (lambda () (dotimes (r *scan-reps*)
                               (jdbc:query c "select id, name, score, flag from bench")))
                  *trials*)
    (report-phase (format nil "point select x~D" *point-reps*)
                  (lambda () (dotimes (r *point-reps*)
                               (jdbc:query c "select id, name, score, flag from bench where id = ?"
                                           (mod r *rows*))))
                  *trials*)))

;;; cl-postgres (native Common Lisp wire-protocol driver)

(defun run-cl-postgres ()
  (format t "~%cl-postgres (native Common Lisp PostgreSQL driver):~%")
  (let ((conn (cl-postgres:open-database *db* *user* *password* *host* *port*)))
    (unwind-protect
         (progn
           (cl-postgres:exec-query conn "drop table if exists bench")
           (cl-postgres:exec-query conn "create table bench (id int primary key, name text, score double precision, flag boolean)")
           (cl-postgres:prepare-query conn "ins" "insert into bench values ($1,$2,$3,$4)")
           (cl-postgres:prepare-query conn "pt" "select id, name, score, flag from bench where id = $1")
           (report-phase (format nil "insert ~D (1 by 1)" *rows*)
                         (lambda ()
                           (cl-postgres:exec-query conn "truncate bench")
                           (dotimes (i *rows*)
                             (cl-postgres:exec-prepared conn "ins"
                                                        (list i (row-name i) (* i 1.5d0) (evenp i))))))
           (dotimes (w 5) (cl-postgres:exec-query conn "select id, name, score, flag from bench"
                                                  'cl-postgres:list-row-reader))
           (report-phase (format nil "scan x~D (~Dk rows)" *scan-reps* (round (* *rows* *scan-reps*) 1000))
                         (lambda () (dotimes (r *scan-reps*)
                                      (cl-postgres:exec-query conn "select id, name, score, flag from bench"
                                                              'cl-postgres:list-row-reader)))
                         *trials*)
           (report-phase (format nil "point select x~D" *point-reps*)
                         (lambda () (dotimes (r *point-reps*)
                                      (cl-postgres:exec-prepared conn "pt" (list (mod r *rows*))
                                                                 'cl-postgres:list-row-reader)))
                         *trials*))
      (cl-postgres:close-database conn))))

(defun run ()
  "Run both drivers against the PostgreSQL named by the *HOST* etc. parameters."
  (format t "~%Benchmarking against postgres at ~A:~D/~A (~D rows)~%"
          *host* *port* *db* *rows*)
  (handler-case
      (progn (run-jdbc) (run-cl-postgres) (format t "~%Done.~%"))
    (error (e)
      (format t "~%Benchmark aborted (is PostgreSQL running?): ~A~%" e)))
  (finish-output))

(run)
