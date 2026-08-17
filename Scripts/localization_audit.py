#!/usr/bin/env python3
"""Localization audit for the defaultValue: migration.

Cross-references both .xcstrings catalogs against every Swift call site,
classifies keys, and emits per-feature work lists under Scripts/audit_output/.

See Shared/Docs/Localization/Default_Value_Migration_Plan.md (Phase 0).
Rerun after each migration batch to refresh the work lists.
"""

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOGS = {
    "Shared": REPO / "Shared/Localizable.xcstrings",
    "ArkeUI": REPO / "ArkeUI/Sources/ArkéUI/Localizable.xcstrings",
}
SOURCE_ROOTS = ["Shared", "ArkeMobile", "ArkeDesktop", "ArkeWidgets", "ArkeUI/Sources"]
OUT = REPO / "Scripts/audit_output"

SNAKE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)+")


def load_catalog(path):
    data = json.loads(path.read_text())
    keys = {}
    for key, entry in data["strings"].items():
        en = entry.get("localizations", {}).get("en", {})
        unit = en.get("stringUnit", {})
        variations = en.get("variations")
        # Plural keys carry English inside variations, not stringUnit.
        variation_values = []
        if variations:
            for vform in variations.get("plural", {}).values():
                variation_values.append(vform.get("stringUnit", {}).get("value") or "")
        keys[key] = {
            "value": unit.get("value") or "; ".join(v for v in variation_values if v),
            "has_plural": bool(variations),
            "should_translate": entry.get("shouldTranslate", True),
            "extraction_state": entry.get("extractionState", ""),
            "comment": entry.get("comment", ""),
        }
    return keys


def swift_files():
    for root in SOURCE_ROOTS:
        base = REPO / root
        for path in sorted(base.rglob("*.swift")):
            if "/build/" in str(path) or "/.build/" in str(path):
                continue
            yield path


def feature_of(path):
    """Group a file into a batch bucket: <Root>/<FeatureDir>."""
    rel = path.relative_to(REPO)
    parts = rel.parts
    root = "ArkeUI" if parts[0] == "ArkeUI" else parts[0]
    feature = "(root)"
    if "Views" in parts:
        i = parts.index("Views")
        feature = parts[i + 1] if i + 2 < len(parts) else "(views)"
    elif len(parts) > 2:
        feature = parts[1]
    return f"{root}/{feature}"


PLACEHOLDER = re.compile(r"%(\d+\$)?(lld|llu|ld|lu|d|u|@|f|\.\df)")
MARKER = "XPLACEHOLDERX"  # alphanumeric: survives re.escape untouched


def interpolation_regex(key):
    """Keys with format specifiers appear in code as interpolated literals:
    catalog '%lld addresses' <- code '"\\(count) addresses"'.
    Returns a regex matching the code-side literal (body only, no quotes)."""
    if not PLACEHOLDER.search(key):
        return None
    marked = re.escape(PLACEHOLDER.sub(MARKER, key))
    return marked.replace(MARKER, r'\\\((?:[^"\\]|\\.)*?\)')


def main():
    catalogs = {name: load_catalog(p) for name, p in CATALOGS.items()}
    all_keys = {}  # key -> merged info + which catalogs
    for name, keys in catalogs.items():
        for key, info in keys.items():
            all_keys.setdefault(key, {"catalogs": {}, **info})["catalogs"][name] = info

    files = {p: p.read_text() for p in swift_files()}

    # --- reference scan ---------------------------------------------------
    refs = defaultdict(list)  # key -> [(path, hits, with_defaultValue)]
    for key in all_keys:
        # Pure-placeholder keys ("%@", "%lld") and letterless symbol keys ("•",
        # "—") match any interpolation / any defaultValue containing the glyph —
        # pure scan noise. They're catalog config (D5), not migration targets.
        if not PLACEHOLDER.sub("", key).strip() or not re.search(r"[A-Za-z]", key):
            continue
        exact = f'"{key}"'
        interp = interpolation_regex(key)  # body regex or None
        interp_lit = re.compile('"' + interp + '"') if interp else None
        for path, text in files.items():
            hits = text.count(exact)
            if interp_lit:
                hits += len(interp_lit.findall(text))
            if not hits:
                continue
            with_dv = len(re.findall(
                r'String\(\s*localized:\s*' + re.escape(exact) + r'\s*,\s*defaultValue', text))
            if interp:
                # interpolated keys are migrated when the interpolation sits in
                # a defaultValue: (key side is then the bare hybrid key literal)
                with_dv += len(re.findall(r'defaultValue:\s*"' + interp + '"', text))
            refs[key].append((path, hits, with_dv))

    # --- classification ---------------------------------------------------
    rows = []
    for key, info in sorted(all_keys.items()):
        sites = refs.get(key, [])
        total = sum(h for _, h, _ in sites)
        migrated = sum(dv for _, _, dv in sites)
        values = {c: i["value"] for c, i in info["catalogs"].items()}
        drift = len(set(values.values())) > 1
        rows.append({
            "key": key,
            "catalogs": list(info["catalogs"]),
            "value": values.get("Shared") or values.get("ArkeUI") or "",
            "missing_en": not any(values.values()),
            "sites": total,
            "migrated_sites": migrated,
            "files": sorted({str(p.relative_to(REPO)) for p, _, _ in sites}),
            "multi_use": total >= 2,
            "has_plural": info["has_plural"],
            "should_translate": info["should_translate"],
            "stale_marked": info["extraction_state"] == "stale",
            "snake": bool(SNAKE_RE.match(key)),
            "value_drift": drift,
        })

    # --- hardcoded-English heuristic ---------------------------------------
    known_values = {r["value"] for r in rows if r["value"]}
    ui_call = re.compile(
        r'(?:Text|Button|Label|Toggle|TextField|ContentUnavailableView|Section'
        r'|navigationTitle|alert|confirmationDialog|help|accessibilityLabel'
        r'|StatusBadge\(text:)\(\s*"([^"\\]*)"')
    hardcoded = defaultdict(list)
    for path, text in files.items():
        preview_start = min((i for i in (text.find("#Preview"),
                                         text.find("PreviewProvider")) if i >= 0),
                            default=len(text))
        for m in ui_call.finditer(text):
            lit = m.group(1)
            if (" " in lit and lit[0].isupper()
                    and lit not in all_keys and lit not in known_values):
                line = text[:m.start()].count("\n") + 1
                tag = " (preview-only?)" if m.start() > preview_start else ""
                hardcoded[str(path.relative_to(REPO))].append((line, lit + tag))
    # String-literal assignments to message-ish vars, and interpolated alerts,
    # are caught separately (rough net):
    msg_re = re.compile(
        r'(?:errorMessage|message|title|subtitle|text)\s*=\s*"([A-Z][^"\\]*\s[^"\\]*)"')
    for path, text in files.items():
        for m in msg_re.finditer(text):
            lit = m.group(1)
            if lit not in known_values:
                line = text[:m.start()].count("\n") + 1
                hardcoded[str(path.relative_to(REPO))].append((line, lit))

    # --- outputs ------------------------------------------------------------
    OUT.mkdir(exist_ok=True)
    (OUT / "keys.json").write_text(json.dumps(rows, indent=1, ensure_ascii=False))

    def md_escape(s):
        return s.replace("|", "\\|").replace("\n", "\\n")

    # multi-use → L10n accessor candidates
    multi = [r for r in rows if r["sites"] >= 2 and r["snake"]]
    multi.sort(key=lambda r: -r["sites"])
    with open(OUT / "multiuse_keys.md", "w") as f:
        f.write("# Multi-use keys (L10n accessor candidates, D2)\n\n")
        f.write("| Key | Sites | Catalogs | English |\n|---|---|---|---|\n")
        for r in multi:
            f.write(f"| `{r['key']}` | {r['sites']} | {','.join(r['catalogs'])} "
                    f"| {md_escape(r['value']) or '**MISSING**'} |\n")

    # per-feature work lists
    by_feature = defaultdict(lambda: defaultdict(list))
    for r in rows:
        if r["sites"] == 0:
            continue
        remaining = r["sites"] - r["migrated_sites"]
        if remaining <= 0:
            continue
        for fp in r["files"]:
            by_feature[feature_of(REPO / fp)][fp].append(r)
    with open(OUT / "worklists.md", "w") as f:
        f.write("# Per-feature work lists (bare-key call sites remaining)\n\n")
        for feat in sorted(by_feature):
            n = sum(len(ks) for ks in by_feature[feat].values())
            f.write(f"\n## {feat} — {n} key-file pairs\n\n")
            for fp in sorted(by_feature[feat]):
                f.write(f"- **{fp}**\n")
                for r in sorted(by_feature[feat][fp], key=lambda r: r["key"]):
                    flags = "".join([
                        " ⚠️plural" if r["has_plural"] else "",
                        " ❌missing-en" if r["missing_en"] else "",
                        " 🔀drift" if r["value_drift"] else "",
                        " 🔁multi-use" if r["multi_use"] else "",
                    ])
                    f.write(f"  - `{r['key']}`{flags} → "
                            f"{md_escape(r['value']) or '(no value)'}\n")

    # problem lists
    with open(OUT / "problems.md", "w") as f:
        f.write("# Problem keys\n\n## Missing English value (referenced in code)\n\n")
        for r in rows:
            if r["missing_en"] and r["sites"] and r["snake"]:
                f.write(f"- `{r['key']}` — {r['sites']} site(s): "
                        f"{', '.join(r['files'])}\n")
        f.write("\n## Unreferenced keys (stale or dynamically constructed?)\n\n")
        for r in rows:
            if r["sites"] == 0:
                mark = " (already marked stale)" if r["stale_marked"] else ""
                f.write(f"- `{r['key']}`{mark}\n")
        f.write("\n## Shared/ArkéUI value drift\n\n")
        for r in rows:
            if r["value_drift"]:
                f.write(f"- `{r['key']}`: " + " vs ".join(
                    f"{c}=“{i['value']}”"
                    for c, i in all_keys[r["key"]]["catalogs"].items()) + "\n")

    with open(OUT / "hardcoded_english.md", "w") as f:
        f.write("# Hardcoded-English candidates (heuristic — triage manually)\n\n")
        for fp in sorted(hardcoded):
            f.write(f"- **{fp}**\n")
            for line, lit in hardcoded[fp]:
                f.write(f"  - L{line}: {md_escape(lit)}\n")

    # summary
    referenced = [r for r in rows if r["sites"]]
    fully_migrated = [r for r in referenced if r["migrated_sites"] >= r["sites"]]
    print(f"catalog keys: {len(rows)}  referenced: {len(referenced)}  "
          f"unreferenced: {len(rows) - len(referenced)}")
    print(f"total call sites: {sum(r['sites'] for r in rows)}  "
          f"already defaultValue: {sum(r['migrated_sites'] for r in rows)}")
    print(f"keys fully migrated: {len(fully_migrated)}  "
          f"multi-use (≥2 sites): {len(multi)}")
    print(f"missing-en referenced snake keys: "
          f"{sum(1 for r in rows if r['missing_en'] and r['sites'] and r['snake'])}")
    print(f"plural keys referenced: "
          f"{sum(1 for r in referenced if r['has_plural'])}")
    print(f"value drift Shared vs ArkéUI: "
          f"{sum(1 for r in rows if r['value_drift'])}")
    print(f"hardcoded-English candidates: "
          f"{sum(len(v) for v in hardcoded.values())} in {len(hardcoded)} files")
    print(f"\noutputs in {OUT.relative_to(REPO)}/")


if __name__ == "__main__":
    sys.exit(main())
