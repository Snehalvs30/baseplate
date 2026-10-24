#!/usr/bin/env python3
"""Checks the ArgoCD Application files, the way ArgoCD will read them.

- apps/ and disabled/ contain only .yaml files (ArgoCD silently skips anything else,
  such as "tenant.yaml " with a trailing space)
- every Application has a unique name and a destination namespace
- Helm chart sources are pinned to an exact version (not empty, "*", or "latest")
- sources in this repository point at a folder that exists
- with --remote-charts DIR: writes each Helm chart source's values to DIR and prints
  "repoURL chart version valuesfile" lines, so the caller can render each chart with
  our values (which checks them against the chart's own schema, if it has one)
"""
import os
import re
import sys

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THIS_REPO = "github.com/snehalvs30/baseplate"
FOLDERS = ["platform/bootstrap/apps", "platform/bootstrap/disabled"]
VERSION = re.compile(r"^v?\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$")

errors = []


def error(message):
    errors.append(message)


def applications():
    files = [os.path.join(REPO_ROOT, "platform/bootstrap/root-application.yaml")]
    for folder in FOLDERS:
        path = os.path.join(REPO_ROOT, folder)
        for name in sorted(os.listdir(path)):
            if name.startswith("."):
                continue
            if not name.endswith(".yaml"):
                error(f"{folder}/{name!r}: not a .yaml file, so ArgoCD would skip it")
                continue
            files.append(os.path.join(path, name))
    for file in files:
        with open(file) as handle:
            for document in yaml.safe_load_all(handle):
                if document:
                    yield os.path.relpath(file, REPO_ROOT), document


def main():
    remote_dir = None
    if len(sys.argv) == 3 and sys.argv[1] == "--remote-charts":
        remote_dir = sys.argv[2]
        os.makedirs(remote_dir, exist_ok=True)

    names = {}
    remote = []
    for file, app in applications():
        if app.get("kind") != "Application":
            error(f"{file}: expected kind Application, found {app.get('kind')}")
            continue
        name = app.get("metadata", {}).get("name", "")
        if name in names:
            error(f"{file}: Application name {name!r} is also used in {names[name]}")
        names[name] = file

        spec = app.get("spec", {})
        if not spec.get("destination", {}).get("namespace"):
            error(f"{file}: no destination namespace")

        source = spec.get("source", {})
        revision = str(source.get("targetRevision", "")).strip()
        if source.get("chart"):
            if not VERSION.match(revision):
                error(f"{file}: chart {source['chart']!r} must be pinned to an exact version, found {revision!r}")
            elif remote_dir is not None:
                values = source.get("helm", {}).get("valuesObject", {}) or {}
                values_file = os.path.join(remote_dir, f"{name}.yaml")
                with open(values_file, "w") as handle:
                    yaml.safe_dump(values, handle)
                remote.append(f"{source['repoURL']} {source['chart']} {revision} {values_file}")
        elif source.get("path") is not None:
            repo = source.get("repoURL", "").lower().removesuffix(".git")
            if repo.endswith(THIS_REPO) and not os.path.isdir(os.path.join(REPO_ROOT, source["path"])):
                error(f"{file}: source path {source['path']!r} doesn't exist in this repository")
        else:
            error(f"{file}: source has neither a chart nor a path")

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        sys.exit(1)
    if remote_dir is not None:
        print("\n".join(remote))
    else:
        print(f"OK: {len(names)} Applications checked")


if __name__ == "__main__":
    main()
