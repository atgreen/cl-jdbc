# cl-jdbc

A native Common Lisp API for [JDBC](https://docs.oracle.com/en/java/javase/25/docs/api/java.sql/java/sql/package-summary.html)
databases, running on [OpenLDK](https://github.com/atgreen/openldk).

JDBC is Java's database API, and almost every database ships a JDBC driver:
PostgreSQL, MySQL, MariaDB, SQLite, Oracle, SQL Server, DB2, Snowflake, Trino,
H2, and dozens more. OpenLDK transpiles those drivers' Java bytecode to Lisp
code that SBCL compiles and runs natively, in the same process and heap as your
own code, rather than running them on a separate JVM reached over a socket.
`cl-jdbc` wraps the JDBC API in a Lisp one: you connect with a URL and work with
Lisp values.

```lisp
(asdf:load-system "cl-jdbc")

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

- **The native API** (`jdbc:` package), shown in the examples below:
  `connect`, `query`, `execute`, `with-transaction`.
- **A [cl-dbi](https://github.com/fukamachi/cl-dbi) driver** (`dbd-jdbc`): JDBC
  as a backend for Common Lisp's standard database interface, so code written to
  cl-dbi (and the libraries on top of it, like Mito and sxql) can reach any JDBC
  database. See [As a cl-dbi driver](#as-a-cl-dbi-driver).

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
usually enough; the matching jar is downloaded from Maven Central the first time
and cached by OpenLDK.

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

cl-jdbc works with pure-Java (type-4) JDBC drivers, which covers every other
driver in the table above. SQLite's xerial `sqlite-jdbc` (`†`) is the exception:
it bundles a JNI native library (`.so`) that it loads at connect time, and that
does not work under OpenLDK yet (you get `No native library found`). See
[Status](#status).

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
value is passed through as a Java object. Note that `nil` is false, not NULL:
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
    (dbi:fetch-all query)))   ; => ((:|id| 1 :|name| "one"))
```

cl-dbi interns the plist keys from the column labels the database returns, so
their case follows the database (PostgreSQL lowercases, as above; H2 uppercases).
Because cl-dbi is the common substrate, libraries built on it, such as the
[Mito](https://github.com/fukamachi/mito) ORM and the
[sxql](https://github.com/fukamachi/sxql) query builder, reach JDBC databases
through it too. Pass credentials with `:username`/`:password`, extra driver
settings with `:properties`, and force a driver with `:jdbc-driver` when the
URL's subprotocol is not enough.

## Status

Early. Connecting, parameterized queries and updates, result sets with Lisp
type conversion, transactions, the driver registry with on-demand jar download,
and the `dbd-jdbc` cl-dbi driver all work and are covered by tests.
`asdf:test-system "cl-jdbc"` and `asdf:test-system "dbd-jdbc"` run against an
in-memory H2 database; `asdf:test-system "cl-jdbc/postgres-tests"` runs the same
against a live PostgreSQL, skipping when none is reachable (see
`tests/postgres-tests.lisp` for the container command). Not yet wrapped:
prepared-statement reuse, batch execution, richer temporal and binary type
mapping, generated-key retrieval, metadata introspection, and connection
pooling. Drivers that load a native JNI library, such as SQLite's xerial
`sqlite-jdbc`, do not work under OpenLDK yet; use a pure-Java (type-4) driver.

## Author

Anthony Green <green@moxielogic.com>

## License

cl-jdbc is distributed under the MIT license; see the headers in each source
file.

It runs on [OpenLDK](https://github.com/atgreen/openldk), which is distributed
under the GNU General Public License, version 3 or later, with the Classpath
exception (`GPL-3.0-or-later WITH Classpath-exception-2.0`). The JDBC drivers
you load at runtime are each under their own licenses.
