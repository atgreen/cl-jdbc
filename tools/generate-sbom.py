#!/usr/bin/env python3
"""Generate a CycloneDX SBOM for cl-jdbc.

cl-jdbc is a Common Lisp library, but its real runtime dependencies are Java
artifacts: the OpenLDK runtime that executes the drivers' bytecode, and the
JDBC driver jars it fetches from Maven Central on demand.  cl-jdbc loads no
driver unless a connection asks for it, so the drivers are *optional*
components here; the one hard dependency is OpenLDK.

The known drivers and their Maven coordinates live in runtime.lisp (*drivers*);
this script reads them from there so the SBOM cannot drift from what the code
actually offers.  Driver licenses are declared from a small table keyed by
Maven group:artifact (the SPDX expressions were confirmed for the pinned
versions).  Transitive dependencies of the drivers are not enumerated.

Usage: generate-sbom.py --version <cl-jdbc-version> [--output FILE]

Output is CycloneDX 1.5 JSON.  Run with python3 -I so an attacker-planted
module beside an input file cannot be imported.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
RUNTIME_LISP = REPO / "runtime.lisp"

# A Maven coordinate is group:artifact:version -- exactly two colons and no
# whitespace.  Driver-class strings (e.g. "org.h2.Driver") have no colons, so
# this matches coordinates and nothing else in *drivers*.
COORD_RE = re.compile(r'"([^":\s]+:[^":\s]+:[^":\s]+)"')

# Declared licenses keyed by "group:artifact".  "expression" is an SPDX license
# expression; "name" is a free-text name for licenses with no SPDX id.
DRIVER_LICENSES = {
    "com.h2database:h2": {"expression": "EPL-1.0 OR MPL-2.0"},
    "org.postgresql:postgresql": {"id": "BSD-2-Clause"},
    "com.mysql:mysql-connector-j": {"expression": "GPL-2.0-only WITH Universal-FOSS-exception-1.0"},
    "org.mariadb.jdbc:mariadb-java-client": {"id": "LGPL-2.1-or-later"},
    "org.xerial:sqlite-jdbc": {"id": "Apache-2.0"},
    "com.microsoft.sqlserver:mssql-jdbc": {"id": "MIT"},
    "com.oracle.database.jdbc:ojdbc11": {"name": "Oracle Free Use Terms and Conditions"},
    "com.ibm.db2:jcc": {"name": "IBM International Program License Agreement"},
    "net.snowflake:snowflake-jdbc": {"id": "Apache-2.0"},
    "io.trino:trino-jdbc": {"id": "Apache-2.0"},
}


def read_drivers():
    """Return [(group, artifact, version), ...] parsed from runtime.lisp."""
    text = RUNTIME_LISP.read_text(encoding="utf-8")
    m = re.search(r"\*drivers\*(.*?)^\s*\"Known JDBC drivers", text, re.DOTALL | re.MULTILINE)
    region = m.group(1) if m else text
    coords = COORD_RE.findall(region)
    if not coords:
        sys.exit("could not find any Maven coordinates in *drivers* in runtime.lisp")
    drivers = []
    for coord in coords:
        group, artifact, version = coord.split(":")
        drivers.append((group, artifact, version))
    return drivers


def license_entry(group, artifact):
    spec = DRIVER_LICENSES.get(f"{group}:{artifact}")
    if spec is None:
        return None
    if "expression" in spec:
        return [{"expression": spec["expression"]}]
    if "id" in spec:
        return [{"license": {"id": spec["id"]}}]
    return [{"license": {"name": spec["name"]}}]


def build_sbom(cl_jdbc_version, drivers):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    root_ref = f"pkg:github/atgreen/cl-jdbc@v{cl_jdbc_version}"
    openldk_ref = "pkg:github/atgreen/openldk"

    root_component = {
        "type": "library",
        "bom-ref": root_ref,
        "name": "cl-jdbc",
        "version": cl_jdbc_version,
        "description": "A native Common Lisp API for JDBC databases, running on OpenLDK.",
        "licenses": [{"license": {"id": "MIT"}}],
        "purl": root_ref,
        "externalReferences": [
            {"type": "vcs", "url": "https://github.com/atgreen/cl-jdbc"}
        ],
    }

    openldk_component = {
        "type": "framework",
        "bom-ref": openldk_ref,
        "name": "openldk",
        "description": "A JVM that transpiles Java bytecode to Common Lisp.",
        "scope": "required",
        "licenses": [{"expression": "GPL-3.0-or-later WITH Classpath-exception-2.0"}],
        "purl": openldk_ref,
        "externalReferences": [
            {"type": "vcs", "url": "https://github.com/atgreen/openldk"}
        ],
    }

    driver_components = []
    for group, artifact, version in drivers:
        purl = f"pkg:maven/{group}/{artifact}@{version}"
        component = {
            "type": "library",
            "bom-ref": purl,
            "group": group,
            "name": artifact,
            "version": version,
            # Drivers are fetched from Maven only when a connection needs one.
            "scope": "optional",
            "purl": purl,
        }
        licenses = license_entry(group, artifact)
        if licenses is not None:
            component["licenses"] = licenses
        driver_components.append(component)

    # cl-jdbc requires OpenLDK; the driver jars are optional and resolved on
    # demand, so they are not edges in the required-dependency graph.
    dependencies = [
        {"ref": root_ref, "dependsOn": [openldk_ref]},
        {"ref": openldk_ref, "dependsOn": []},
    ]

    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": now,
            "tools": [{"name": "cl-jdbc generate-sbom.py"}],
            "component": root_component,
        },
        "components": [openldk_component] + driver_components,
        "dependencies": dependencies,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate a CycloneDX SBOM for cl-jdbc.")
    parser.add_argument("--version", required=True, help="the cl-jdbc version being released")
    parser.add_argument("--output", help="write to this file instead of stdout")
    args = parser.parse_args()

    drivers = read_drivers()
    sbom = build_sbom(args.version, drivers)
    text = json.dumps(sbom, indent=2) + "\n"

    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
