#!/usr/bin/env python3
"""Audit a Release archive or simulator .app using release-resources.json."""

import argparse
import fnmatch
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).with_name("release-resources.json")


def matches(path, pattern):
    """Match at any bundle depth, including Xcode's flattened resource names."""
    parts = path.parts
    return any(fnmatch.fnmatchcase("/".join(parts[index:]), pattern)
               for index in range(len(parts)))


def audit(app, bundle, manifest):
    spec = manifest["apps"][app]
    problems = []
    classified = {}
    forbidden = list(spec["forbidden_patterns"])
    for entry in manifest["shared_classifications"] + spec["classifications"]:
        source = entry["source"]
        if source in classified:
            problems.append(f"duplicate classification: {source}")
        classified[source] = entry
        if entry["classification"] not in {"release", "debug_only", "unused"}:
            problems.append(f"unknown classification: {source}")
        if not entry["reason"].strip():
            problems.append(f"classification needs a reason: {source}")
        if not (ROOT / source).is_file():
            problems.append(f"classified source missing: {source}")
        if entry["classification"] in {"debug_only", "unused"}:
            forbidden.append(Path(source).name)

    # An added fixture needs an explicit decision even if the build excludes it.
    for folder in spec["sample_roots"]:
        source_root = ROOT / folder
        if not source_root.is_dir():
            problems.append(f"sample folder missing: {folder}")
        for source in sorted(source_root.rglob("*")):
            if source.is_file() and source.relative_to(ROOT).as_posix() not in classified:
                problems.append(f"unclassified sample: {source.relative_to(ROOT)}")
                forbidden.append(source.name)

    if not bundle.is_dir() or bundle.suffix != ".app":
        return problems + [f"not an app bundle directory: {bundle}"]

    for file in sorted(bundle.rglob("*")):
        if file.is_file():
            relative = file.relative_to(bundle)
            if any(matches(relative, pattern) for pattern in forbidden):
                problems.append(f"forbidden: {relative.as_posix()}")

    for target in spec["bundles"]:
        target_root = bundle / target["path"]
        if not target_root.is_dir():
            problems.append(f"required bundle missing: {target['path']}")
        required = list(target["required"])
        if target["shared_required"]:
            required += manifest["shared_required"]
        for entry in required:
            for name in entry["paths"]:
                resource = target_root / name
                if not resource.is_file() or resource.stat().st_size == 0:
                    relative = resource.relative_to(bundle).as_posix()
                    problems.append(f"required missing or empty: {relative} ({entry['reason']})")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True)
    parser.add_argument("--bundle", required=True, type=Path)
    args = parser.parse_args()
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if manifest["version"] != 1:
            raise ValueError("unsupported manifest version")
        if args.app not in manifest["apps"]:
            parser.error("unknown app; choose " + ", ".join(manifest["apps"]))
        problems = audit(args.app, args.bundle, manifest)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"{args.app}: release resource audit failed: {error}", file=sys.stderr)
        return 1
    if problems:
        print(f"{args.app}: release resource audit FAILED", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"{args.app}: release resource audit passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
