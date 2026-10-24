#!/usr/bin/env python3
"""The apps' String Catalogs: keep them in step with the code, fill in German, check nothing is missing.

  scripts/strings.py sync            export every project's strings (xcodebuild -exportLocalizations) and update the
                                     catalogs: new keys are added, keys the code no longer uses are dropped,
                                     translations are kept; then prints what still lacks German
  scripts/strings.py fill FILE.json  German for keys, in every catalog that has the key:
                                     {"Log in": "Anmelden",
                                      "%lld people": {"en": {"one": "%lld person", "other": "%lld people"},
                                                      "de": {"one": "%lld Person", "other": "%lld Personen"}}}
  scripts/strings.py check           exit 1 if a key lacks German, or a German text's placeholders differ from the
                                     English ones (run before merging; `sync` first when the code changed)

Rules: ares-empire/docs/LANGUAGES.md; how the apps use the catalogs: CLAUDE.md → Languages.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECTS = ["Aresium/Aresium.xcodeproj", "Empire/Empire.xcodeproj", "Arestemis/Arestemis.xcodeproj",
            "Aresus/Aresus.xcodeproj", "Arestoteles/Arestoteles.xcodeproj"]
LANGUAGE = "de"
XLIFF = "{urn:oasis:names:tc:xliff:document:1.2}"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")


def catalogs() -> list[Path]:
    return sorted(p for p in ROOT.rglob("*.xcstrings") if "build" not in p.relative_to(ROOT).parts)


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def save(path: Path, catalog: dict) -> None:
    # Xcode's own layout (2-space JSON, " : " separators, sorted keys), so the IDE rewrites nothing.
    text = json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n")


def exported_keys(project: str) -> dict[Path, set[str]]:
    """Catalog path -> the keys the code uses, from Xcode's own export."""
    with tempfile.TemporaryDirectory() as out:
        run = subprocess.run(["xcodebuild", "-exportLocalizations", "-project", project, "-localizationPath", out,
                              "-exportLanguage", LANGUAGE], cwd=ROOT, capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(f"export of {project} failed:\n{run.stdout[-3000:]}\n{run.stderr[-3000:]}")
        tree = ET.parse(Path(out) / f"{LANGUAGE}.xcloc" / "Localized Contents" / f"{LANGUAGE}.xliff")
    found: dict[Path, set[str]] = {}
    base = (ROOT / project).parent
    for file in tree.getroot().iter(f"{XLIFF}file"):
        path = (base / file.get("original")).resolve()
        if not path.exists():          # InfoPlist.xcstrings: generated from Info.plist (app names only)
            continue
        ids = {unit.get("id").split("|==|")[0] for unit in file.iter(f"{XLIFF}trans-unit")}
        found.setdefault(path, set()).update(ids)
    return found


def translatable(key: str) -> bool:
    return re.search(r"[A-Za-z]", PLACEHOLDER.sub("", key)) is not None


def german(entry: dict) -> list[str] | None:
    """Every German text of an entry (one, or each plural form); None when missing."""
    de = entry.get("localizations", {}).get(LANGUAGE)
    if not de:
        return None
    if "stringUnit" in de:
        return [de["stringUnit"]["value"]]
    forms = de.get("variations", {}).get("plural", {})
    return [form["stringUnit"]["value"] for form in forms.values()] or None


def sync() -> None:
    wanted: dict[Path, set[str]] = {}
    for project in PROJECTS:
        print(f"exporting {project} …", file=sys.stderr)
        for path, keys in exported_keys(project).items():
            wanted.setdefault(path, set()).update(keys)
    for path in catalogs():
        catalog = load(path)
        keys = wanted.get(path.resolve(), set())
        old = catalog.get("strings", {})
        strings = {}
        for key in sorted(keys):
            entry = dict(old.get(key, {}))
            entry.pop("extractionState", None)
            if not translatable(key):
                entry = {"shouldTranslate": False}
            strings[key] = entry
        dropped = sorted(set(old) - keys)
        catalog["strings"] = strings
        save(path, catalog)
        print(f"{path.relative_to(ROOT)}: {len(strings)} keys" + (f", dropped {len(dropped)}: {dropped}" if dropped else ""))
    report(fail=False)


def fill(source: Path) -> None:
    given = json.loads(source.read_text())
    used = set()
    for path in catalogs():
        catalog = load(path)
        for key, entry in catalog["strings"].items():
            if key not in given:
                continue
            used.add(key)
            value = given[key]
            localizations = entry.setdefault("localizations", {})
            if isinstance(value, str):
                localizations[LANGUAGE] = {"stringUnit": {"state": "translated", "value": value}}
            else:
                for language, forms in value.items():
                    localizations[language] = {"variations": {"plural": {
                        form: {"stringUnit": {"state": "translated", "value": text}} for form, text in forms.items()}}}
        save(path, catalog)
    unused = sorted(set(given) - used)
    if unused:
        print(f"not in any catalog ({len(unused)}): {unused}")
    report(fail=False)


def report(fail: bool) -> None:
    problems = []
    for path in catalogs():
        for key, entry in load(path)["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            texts = german(entry)
            where = f"{path.relative_to(ROOT)}: {key!r}"
            if texts is None:
                problems.append(f"no German: {where}")
                continue
            english = sorted(PLACEHOLDER.findall(key))
            for text in texts:
                found = sorted(PLACEHOLDER.findall(text))
                # A plural form may leave out the count ("eine Person"); otherwise the placeholders must match.
                if found != english and not (len(texts) > 1 and set(found) <= set(english)):
                    problems.append(f"placeholders differ ({english} vs {found}): {where} -> {text!r}")
    for line in problems:
        print(line)
    print(f"{len(problems)} problem(s)")
    if fail and problems:
        sys.exit(1)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "sync":
        sync()
    elif command == "fill" and len(sys.argv) == 3:
        fill(Path(sys.argv[2]))
    elif command == "check":
        report(fail=True)
    else:
        sys.exit(__doc__)
