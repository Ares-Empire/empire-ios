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
                                     English ones, or a lookup in the code would keep the language the app started
                                     in (run before merging; `sync` first when the code changed)
  scripts/strings.py fix-lookups     rewrites `String(localized: "…", table: …, comment: …)` (Foundation's: the
                                     language the app started in) as a LocalizedStringResource in the app's language

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
        old = catalog.get("strings", {})
        # The export still lists keys no code uses; it marks them stale in the catalog.
        keys = {key for key in wanted.get(path.resolve(), set()) if old.get(key, {}).get("extractionState") != "stale"}
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


# Lookups that follow a language switch while the app runs (Shared/Language/AppLanguage.swift): a plain
# `String(localized: "…")` is the apps' own; a table or comment goes through a LocalizedStringResource in the app's
# language, which Xcode reads like Foundation's own call.
LOOKUP = "String(localized:"
RESOURCE = "LocalizedStringResource("
IN_APP_LANGUAGE = "locale: .appLanguage"
FIXED_LANGUAGE = re.compile(r"NSLocalizedString\(|AttributedString\(localized:|\.localizedString\(forKey:")


def swift_files() -> list[Path]:
    """The apps' code (tests left out: they also call Foundation's lookups on purpose)."""
    skipped = {"build", ".build", "DerivedData", ".venv"}
    return sorted(p for p in ROOT.rglob("*.swift")
                  if not skipped & set(p.relative_to(ROOT).parts) and not p.parent.name.endswith("Tests"))


def call_arguments(text: str, opening: int) -> tuple[int, list[tuple[int, int]]]:
    """For the call whose `(` is at `opening`: the index after its `)`, and each top-level argument's (start, end).
    String literals and their interpolations are skipped, so a `)` or `,` inside them does not count."""
    stack = [["code", 0]]           # code: [kind, bracket depth]; strings: [kind, 0]
    arguments, start, i = [], opening + 1, opening
    while i < len(text):
        kind, char = stack[-1][0], text[i]
        if kind == "code":
            if text.startswith('"""', i):
                stack.append(["block", 0])
                i += 3
                continue
            if char == '"':
                stack.append(["string", 0])
            elif char in "([{":
                stack[-1][1] += 1
            elif char in ")]}":
                stack[-1][1] -= 1
                if stack[-1][1] == 0:
                    if len(stack) == 1:
                        arguments.append((start, i))
                        return i + 1, arguments
                    stack.pop()                     # the end of an interpolation
            elif char == "," and len(stack) == 1 and stack[0][1] == 1:
                arguments.append((start, i))
                start = i + 1
            i += 1
        else:
            if char == "\\" and text.startswith("(", i + 1):
                stack.append(["code", 1])
                i += 2
            elif char == "\\":
                i += 2
            elif kind == "block" and text.startswith('"""', i):
                stack.pop()
                i += 3
            elif kind == "string" and char == '"':
                stack.pop()
                i += 1
            else:
                i += 1
    raise ValueError(f"unclosed call at {opening}")


def split_argument(argument: str) -> tuple[str | None, str]:
    """(label, value) of one argument's text, both stripped; no label for an unlabelled one."""
    match = re.match(r"\s*([A-Za-z_]+)\s*:(?!:)", argument)
    if not match:
        return None, argument.strip()
    return match.group(1), argument[match.end():].strip()


def lookups(text: str):
    """Each `String(localized:` call outside comments: (start, end, [(label, value)])."""
    for match in re.finditer(re.escape(LOOKUP), text):
        line_start = text.rfind("\n", 0, match.start()) + 1
        if "//" in text[line_start:match.start()]:
            continue
        end, spans = call_arguments(text, match.start() + len("String"))
        yield match.start(), end, [split_argument(text[a:b]) for a, b in spans]


def follows(arguments) -> bool:
    """Whether the lookup uses the language the app shows now."""
    if [label for label, _ in arguments] != ["localized"]:
        return False                                 # Foundation's: the language the app started in
    value = arguments[0][1]
    if value.startswith(RESOURCE):                   # a resource names its language, or keeps the start language
        _, inner = call_arguments(value, len(RESOURCE) - 1)
        return any(split_argument(value[a:b]) == ("locale", ".appLanguage") for a, b in inner)
    return True                                      # the apps' own String(localized:)


def lookup_problems() -> list[str]:
    problems = []
    for path in swift_files():
        text = path.read_text()
        where = lambda index: f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, index) + 1}"
        for start, _, arguments in lookups(text):
            if not follows(arguments):
                problems.append(f"lookup keeps the language the app started in (fix-lookups): {where(start)}")
        for match in FIXED_LANGUAGE.finditer(text):
            problems.append(f"lookup keeps the language the app started in: {where(match.start())}")
    return problems


def resource_call(arguments, column: int, limit: int = 120) -> str:
    """`String(localized: LocalizedStringResource(key, table:, locale: .appLanguage, comment:))`, wrapped under the
    resource's first argument where a line would pass the limit."""
    values = dict(arguments[1:])
    if values.get("bundle") not in (None, ".appLanguage"):
        raise ValueError("a bundle of its own")
    parts = [arguments[0][1]]
    if "table" in values:
        parts.append(f"table: {values['table']}")
    parts.append(IN_APP_LANGUAGE)
    if "comment" in values:
        parts.append(f"comment: {values['comment']}")
    head = f"{LOOKUP} {RESOURCE}"
    indent = " " * (column + len(head))
    lines = [head + parts[0]]
    for part in parts[1:]:
        width = len(lines[-1]) + (column if len(lines) == 1 else 0)
        if width + len(part) + 4 > limit:
            lines[-1] += ","
            lines.append(indent + part)
        else:
            lines[-1] += ", " + part
    return "\n".join(lines) + "))"


def fix_lookups() -> None:
    for path in swift_files():
        text = path.read_text()
        changes = []
        for start, end, arguments in lookups(text):
            if follows(arguments) or arguments[0][1].startswith(RESOURCE):
                continue
            column = start - (text.rfind("\n", 0, start) + 1)
            try:
                changes.append((start, end, resource_call(arguments, column)))
            except ValueError as error:
                print(f"left as it is ({error}): {path.relative_to(ROOT)}:{text.count(chr(10), 0, start) + 1}")
        for start, end, call in reversed(changes):
            text = text[:start] + call + text[end:]
        if changes:
            path.write_text(text)
            print(f"{path.relative_to(ROOT)}: {len(changes)} lookup(s)")


def report(fail: bool) -> None:
    problems = lookup_problems()
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
    elif command == "fix-lookups":
        fix_lookups()
    else:
        sys.exit(__doc__)
