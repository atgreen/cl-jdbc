# cl-jdbc

A native Common Lisp API for [JDBC](https://docs.oracle.com/en/java/javase/25/docs/api/java.sql/java/sql/package-summary.html)
databases, running on [OpenLDK](https://github.com/atgreen/openldk).

JDBC is Java's database API, and almost every database ships a JDBC driver:
PostgreSQL, MySQL, MariaDB, SQLite, Oracle, SQL Server, DB2, Snowflake, Trino,
H2, and dozens more. With OpenLDK those drivers run inside SBCL in the same
process and heap as your Lisp code — no JVM subprocess, no sockets, no
serialization. `cl-jdbc` wraps it in an idiomatic Lisp API: you connect with a
URL and query with Lisp data, and never see a Java method descriptor.

```lisp
(ql:quickload :cl-jdbc)   ; or (asdf:load-system "cl-jdbc")

(jdbc:with-connection (c "jdbc:h2:mem:demo")
  (jdbc:execute c "create table users (id int primary key, name varchar, age int)")
  (jdbc:execute c "insert into users values (?, ?, ?)" 1 "Ada"   36)
  (jdbc:execute c "insert into users values (?, ?, ?)" 2 "Grace" 44)

  (dolist (row (jdbc:query c "select name, age from users where age > ? order by age" 30))
    (format t "~A is ~A~%" (jdbc:row-value row "name") (jdbc:row-value row "age"))))
;; Ada is 36
;; Grace is 44
```

The database above is in-memory H2; point the URL at any database and the right
driver is fetched and loaded for you (see [Drivers](#drivers)).

## Two ways to use it

- **The native API** (`jdbc:` package) — the examples below. Small, direct, and
  self-describing: `connect`, `query`, `execute`, `with-transaction`.
- **A [cl-dbi](https://github.com/fukamachi/cl-dbi) driver** (`dbd-jdbc`) —
  JDBC as a backend for Common Lisp's standard database interface, so code
  written to cl-dbi (and the libraries on top of it, like Mito and sxql) can
  reach any JDBC database. See [As a cl-dbi driver](#as-a-cl-dbi-driver).

## Requirements

- SBCL on Linux
- OpenLDK, loadable as the ASDF system `openldk/interop`
- A JDK 25 (OpenLDK reads its classes), with `JAVA_HOME` set
- Network access on first use, to fetch driver jars from Maven Central into
  OpenLDK's cache (`~/.cache/openldk/`); offline afterwards

## Drivers

The JDBC API itself (`java.sql.*`) is part of the JDK, so it needs no jar. A
database *driver* does: its jar carries the code that speaks the wire protocol.
`cl-jdbc` keeps a registry of well-known drivers, so a connection URL alone is
usually enough — the matching jar is downloaded from Maven Central the first
time and cached by OpenLDK.

| Keyword        | URL looks like                       | Maven artifact                      |
|----------------|--------------------------------------|-------------------------------------|
| `:h2`          | `jdbc:h2:mem:demo`                   | `com.h2database:h2`                 |
| `:postgresql`  | `jdbc:postgresql://host/db`          | `org.postgresql:postgresql`         |
| `:mysql`       | `jdbc:mysql://host/db`               | `com.mysql:mysql-connector-j`       |
| `:mariadb`     | `jdbc:mariadb://host/db`             | `org.mariadb.jdbc:mariadb-java-client` |
| `:sqlite` †    | `jdbc:sqlite:/path/to.db`            | `org.xerial:sqlite-jdbc`            |
| `:sqlserver`   | `jdbc:sqlserver://host;database=db`  | `com.microsoft.sqlserver:mssql-jdbc` |
| `:oracle`      | `jdbc:oracle:thin:@host:1521/svc`    | `com.oracle.database.jdbc:ojdbc11`  |
| `:db2`         | `jdbc:db2://host/db`                 | `com.ibm.db2:jcc`                   |
| `:snowflake`   | `jdbc:snowflake://acct.snowflakecomputing.com` | `net.snowflake:snowflake-jdbc` |
| `:trino`       | `jdbc:trino://host:8080`             | `io.trino:trino-jdbc`               |

cl-jdbc works with **pure-Java (type-4) JDBC drivers**, which is almost all of
them — including every other driver in the table above. A driver that bundles a
**native library** is the exception: `† :sqlite` (xerial `sqlite-jdbc`) ships a
JNI `.so` it loads at connect time, and that does not work under OpenLDK yet
(you get `No native library found …`). See [Status](#status).

The driver is chosen from the URL's subprotocol (the token between the first two
colons). Override it with `:driver`, teach `cl-jdbc` a new one with
`register-driver`, or point `:driver` at Maven coordinates directly:

```lisp
(jdbc:register-driver :clickhouse "com.clickhouse:clickhouse-jdbc:0.7.1"
                      "com.clickhouse.jdbc.ClickHouseDriver")

(jdbc:connect "jdbc:custom://..."
              :driver '("com.example:its-driver:1.0" "com.example.Driver"))
```

## API

### Connecting

- `(connect url &key user password driver properties)` — open a connection.
  The driver is chosen from `url` unless `driver` overrides it (a keyword in
  `*drivers*`, `(coordinates class)`, or a driver-class string already on the
  classpath). `properties` is an alist or plist of driver-specific settings.
  Close it with `close`.
- `(with-connection (var url &rest options) &body body)` — open a connection for
  the body, then close it. `options` are `connect`'s keywords.
- `(close connection)` — close a connection.

### Running SQL

- `(query connection sql &rest parameters)` — run a `SELECT` (binding
  `parameters` to its `?` placeholders), returning `(values rows columns)`:
  `rows` is a list of rows, each an alist of `(column-label . value)`; `columns`
  is the list of column-label strings.
- `(execute connection sql &rest parameters)` — run an `INSERT`/`UPDATE`/
  `DELETE`/DDL statement, returning the number of rows affected.
- `(row-value row column)` — the value of `column` in a row, matched
  case-insensitively (SQL folds the case of unquoted identifiers, so a column
  written `name` often comes back labelled `NAME`).

Every statement goes through a `PreparedStatement`, so parameters are bound and
escaped by the driver rather than spliced into the SQL.

### Transactions

- `(with-transaction (connection) &body body)` — run `body` as one transaction:
  auto-commit is turned off, `body`'s changes are committed if it returns
  normally and rolled back if it unwinds, and the prior auto-commit setting is
  restored.
- `(commit connection)` / `(rollback connection)` — commit or roll back the
  current transaction explicitly.
- `(auto-commit connection)` / `(set-auto-commit connection on)` — read or set
  whether each statement commits by itself.

### Values

Parameters map from Lisp to JDBC following the cl-postgres/Postmodern
convention: `t` → boolean true, `nil` → boolean **false**, `:null` → SQL
`NULL`, a string → varchar, an integer → bigint, a real → double; any other
value is passed through as a Java object. Note that `nil` is false, not NULL —
bind SQL `NULL` with the keyword `:null`.

Results map back: `NULL` → `nil`, strings → strings, booleans → `t`/`nil`,
floating and decimal numbers → `double-float`, other numbers → integers.
(Reading is therefore slightly asymmetric: both SQL `NULL` and boolean false
read back as `nil`, as they do in cl-postgres.) Values with no natural Lisp
form (dates, timestamps, byte arrays) come back as their Java `toString` for
now.

## As a cl-dbi driver

`dbd-jdbc` makes JDBC a backend for [cl-dbi](https://github.com/fukamachi/cl-dbi),
the de-facto standard database-independent interface for Common Lisp. Load
`dbd-jdbc` and connect with driver `:jdbc`:

```lisp
(asdf:load-system "dbd-jdbc")

(let ((conn (dbi:connect :jdbc :url "jdbc:postgresql://localhost/app"
                               :username "me" :password "secret")))
  (dbi:do-sql conn "create table t (id int primary key, name varchar)")
  (dbi:do-sql conn "insert into t values (?, ?)" (list 1 "one"))
  (let ((query (dbi:execute (dbi:prepare conn "select * from t where id = ?") (list 1))))
    (dbi:fetch-all query)))   ; => ((:|ID| 1 :|NAME| "one"))
```

Because cl-dbi is the common substrate, this also brings JDBC databases to the
libraries built on it — the [Mito](https://github.com/fukamachi/mito) ORM, the
[sxql](https://github.com/fukamachi/sxql) query builder, and more. Pass
credentials with `:username`/`:password`, extra driver settings with
`:properties`, and force a driver with `:jdbc-driver` when the URL's subprotocol
is not enough.

## Status

Early. Connecting, parameterized queries and updates, result sets with Lisp
type conversion, transactions, the driver registry with on-demand jar download,
and the `dbd-jdbc` cl-dbi driver all work and are covered by tests
(`asdf:test-system "cl-jdbc"` and `asdf:test-system "dbd-jdbc"`, which run
against an in-memory H2 database). Prepared-statement reuse, batch execution,
richer temporal and binary type mapping, generated-key retrieval, metadata
introspection, and connection pooling are not wrapped yet. Drivers that load a
native JNI library — notably SQLite's xerial `sqlite-jdbc` — do not work under
OpenLDK yet; use a pure-Java (type-4) driver.

## Author

Anthony Green <green@moxielogic.com>

## License

MIT. See the headers in each source file.
