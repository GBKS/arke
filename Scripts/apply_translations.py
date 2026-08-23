#!/usr/bin/env python3
"""Apply translations to the string catalogs.

Reads a JSON object {key: {"de": value, "zh-Hant": value, ...}} — any language
codes — from the file given as
argv[1] (or stdin). A value is a plain string, or {"one": ..., "other": ...}
for plural variations. Each key is written to every catalog that contains it,
with state "needs_review".

Keys marked shouldTranslate:false are skipped. Existing entries for the given
languages are overwritten (later batches / correction overlays win).
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOGS = ["Shared/Localizable.xcstrings", "ArkeUI/Sources/ArkéUI/Localizable.xcstrings",
            "ArkeMobile/InfoPlist.xcstrings", "ArkeDesktop/InfoPlist.xcstrings"]
UNITS: dict = {}
for _rel in CATALOGS:
    for _key in json.loads((REPO / _rel).read_text())["strings"]:
        UNITS.setdefault(_key, []).append(_rel)


def unit(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {
            form: {"stringUnit": {"state": "needs_review", "value": v}}
            for form, v in value.items()
        }}}
    return {"stringUnit": {"state": "needs_review", "value": value}}


def main():
    source = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else sys.stdin.read()
    translations = json.loads(source)

    catalogs = {}
    applied, skipped = 0, []
    for key, langs in translations.items():
        paths = UNITS.get(key)
        if not paths:
            skipped.append(key)
            continue
        for rel in paths:
            if rel not in catalogs:
                catalogs[rel] = json.loads((REPO / rel).read_text())
            entry = catalogs[rel]["strings"].get(key)
            if entry is None or entry.get("shouldTranslate") is False:
                continue
            loc = entry.setdefault("localizations", {})
            for lang, value in langs.items():
                loc[lang] = unit(value)
            applied += 1

    for rel, data in catalogs.items():
        (REPO / rel).write_text(
            json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    print(f"applied {applied} key-catalog writes across {len(catalogs)} catalogs")
    if skipped:
        print(f"skipped (not in unit index): {skipped}")


if __name__ == "__main__":
    main()
