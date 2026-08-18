#!/usr/bin/env python3
"""List translation-guard offenders: empty translated values and format-
specifier mismatches vs English. Mirrors LocalizationCatalogTests'
noEmptyTranslations / specifierParity checks, but prints the offending keys
(the simulator test only reports pass/fail per catalog)."""

import json
import re

CATALOGS = ["Shared/Localizable.xcstrings", "ArkeUI/Sources/ArkéUI/Localizable.xcstrings",
            "ArkeMobile/InfoPlist.xcstrings", "ArkeDesktop/InfoPlist.xcstrings"]
SPEC = re.compile(r"%(\d+\$)?(lld|llu|ld|lu|d|u|@|f)")


def specifiers(value):
    out, nxt = {}, 0
    for m in SPEC.finditer(value):
        idx = int(m.group(1)[:-1]) - 1 if m.group(1) else nxt
        out[idx] = m.group(2)
        nxt = idx + 1
    return out


def values_by_language(entry):
    langs = {}
    for lang, loc in entry.get("localizations", {}).items():
        vals = []
        if "stringUnit" in loc:
            vals.append(loc["stringUnit"].get("value", ""))
        for form in loc.get("variations", {}).get("plural", {}).values():
            vals.append(form.get("stringUnit", {}).get("value", ""))
        # substitution tokens hide an argument from the plain value
        if lang == "en":
            for sub in loc.get("substitutions", {}).values():
                vals.append(f"%{sub['argNum']}${sub['formatSpecifier']}")
        langs[lang] = vals
    return langs


def main():
    issues = 0
    for path in CATALOGS:
        strings = json.load(open(path))["strings"]
        name = path.split("/")[0]
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False:
                continue
            langs = values_by_language(entry)
            for lang, vals in langs.items():
                if "" in vals:
                    print(f"EMPTY  {name} {key!r} [{lang}]")
                    issues += 1
            reference = {}
            for v in langs.get("en", []):
                reference.update(specifiers(v))
            if not langs.get("en"):
                continue
            for lang, vals in langs.items():
                if lang == "en":
                    continue
                for v in vals:
                    for idx, t in specifiers(v).items():
                        if reference.get(idx) != t:
                            print(f"PARITY {name} {key!r} [{lang}] arg{idx+1}: "
                                  f"{t} vs en {reference.get(idx)} in {v!r}")
                            issues += 1
    print(f"\n{issues} issue(s)")


if __name__ == "__main__":
    main()
