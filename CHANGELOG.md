# Changelog

All notable changes to cl-jdbc are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-31

First release. cl-jdbc is a native Common Lisp API for JDBC databases, running
on [OpenLDK](https://github.com/atgreen/openldk) — which transpiles the JDBC
drivers' Java bytecode to Common Lisp that SBCL compiles to native machine
code, so the driver runs in-process with no JVM. The JDBC API itself is part
of the JDK OpenLDK reads; a database *driver* jar is fetched from Maven Central
on first use and cached, selected automatically from the connection URL.

### Added

- A connection API driven by ordinary `jdbc:` URLs, with a registry of
  well-known drivers (H2, PostgreSQL, MySQL, MariaDB, SQLite, SQL Server,
  Oracle, Db2, Snowflake, Trino) so a URL alone usually selects and fetches the
  right driver; `register-driver` adds your own.
- Statements and queries with Lisp-native result handling and type mapping.
- `dbd-jdbc`: a [cl-dbi](https://github.com/fukamachi/cl-dbi) (DBI) driver that
  reaches any of those databases through its JDBC driver.

### Notes

- Requires a local OpenLDK checkout; see the README for setup.
- Live-database integration tests against PostgreSQL are opt-in (see
  `cl-jdbc/postgres-tests` and the README).
