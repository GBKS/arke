#!/usr/bin/env python3
"""Mechanical defaultValue: migration for one batch of files.

Applies ONLY safe, deterministic transforms; everything ambiguous is left
untouched and reported for a manual pass. Values are copied verbatim from the
catalogs (decision D3). Plural-variation keys, interpolated/hybrid keys, and
already-migrated sites are never touched.

Passes, in order:
  A. accessor keys: `String(localized: "key")` / `... , bundle: .module)`
     collapse to `L10n.<camelKey>`
  B. remaining `String(localized: "key", ...)` without defaultValue: insert
     `defaultValue:` right after the key, keep trailing args verbatim
  C. bare builder literals `Text("key")`, `Button("key", role:)` etc.:
     wrap in a localized String (or L10n accessor), keep trailing args

Usage: migrate_defaultvalue.py <path-prefix> [--module] [--accessors k1,k2,...]
  <path-prefix>  e.g. ArkeUI/Sources  (files under REPO/<prefix>)
  --module       package target: inserted lookups get `bundle: .module`
  --accessors    keys routed to L10n accessors (the L10n file must exist)

See Shared/Docs/Localization/Default_Value_Migration_Plan.md.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOGS = [REPO / "Shared/Localizable.xcstrings",
            REPO / "ArkeUI/Sources/ArkéUI/Localizable.xcstrings"]

SNAKE_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)+$")

# UI builders whose LocalizedStringKey argument has a StringProtocol overload.
BUILDERS = ("Text", "Button", "Label", "Toggle", "TextField", "Section",
            "navigationTitle", "help", "accessibilityLabel", "accessibilityHint",
            "confirmationDialog", "alert")


def swift_escape(value):
    return (value.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n").replace("\t", "\\t"))


def camel(key):
    head, *rest = key.split("_")
    return head + "".join(w.capitalize() for w in rest)


SPEC_RE = re.compile(r"%(\d+\$)?(?:lld|llu|ld|lu|d|u|@|f)")


def load_hybrids():
    """base ('key' from 'key %lld') -> (full catalog key, en value)."""
    hybrids = {}
    for path in CATALOGS:
        data = json.loads(path.read_text())
        for key, entry in data["strings"].items():
            if " %" not in key:
                continue
            base = key.split(" %")[0]
            if not SNAKE_RE.match(base):
                continue
            en = entry.get("localizations", {}).get("en", {})
            if "variations" in en:
                continue
            value = en.get("stringUnit", {}).get("value")
            if value:
                hybrids.setdefault(base, (key, value))
    return hybrids


def parse_interpolated_literal(text, start):
    """text[start] is the opening quote of a literal containing \\(...).
    Returns (end_index_after_closing_quote, [interpolation expr strings])
    or None if the literal is malformed / multiline."""
    i, exprs = start + 1, []
    while i < len(text):
        c = text[i]
        if c == "\n":
            return None
        if c == "\\" and text[i + 1] == "(":
            depth, j = 1, i + 2
            while j < len(text) and depth:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                return None
            exprs.append(text[i + 2:j - 1])
            i = j
            continue
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1, exprs
        i += 1
    return None


def migrate_hybrids(path, hybrids, module):
    """Pass D: `String(localized: "base \\(x)")` / `Text("base \\(x)")` ->
    explicit hybrid key + defaultValue carrying the interpolation, with the
    English text taken verbatim from the catalog value."""
    text = path.read_text()
    bundle = ", bundle: .module" if module else ""
    skipped, out, pos = [], [], 0
    lit_re = re.compile(r'"([a-z0-9]+(?:_[a-z0-9]+)+) (?=\\\()')
    while True:
        m = lit_re.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        base = m.group(1)
        parsed = parse_interpolated_literal(text, m.start())
        entry = hybrids.get(base)
        if not parsed or not entry:
            if entry:
                skipped.append((base, "unparseable interpolated literal"))
            out.append(text[pos:m.end()])
            pos = m.end()
            continue
        end, exprs = parsed
        key, value = entry
        spec_list = list(SPEC_RE.finditer(value))
        if len(spec_list) != len(exprs):
            skipped.append((base, f"{len(spec_list)} specifiers vs {len(exprs)} interpolations"))
            out.append(text[pos:end])
            pos = end
            continue
        # substitute i-th specifier (or its positional index) with the expr
        dv, last = [], 0
        for i, sm in enumerate(spec_list):
            idx = int(sm.group(1)[:-1]) - 1 if sm.group(1) else i
            dv.append(value[last:sm.start()].replace("\\", "\\\\").replace('"', '\\"'))
            dv.append(f"\\({exprs[idx]})")
            last = sm.end()
        dv.append(value[last:].replace("\\", "\\\\").replace('"', '\\"'))
        replacement = f'"{key}", defaultValue: "{"".join(dv)}"'

        before = text[max(0, m.start() - 60):m.start()]
        if re.search(r'String\(\s*localized:\s*$', before):
            out.append(text[pos:m.start()] + replacement)
            pos = end
        elif re.search(r'\bText\(\s*$', before):
            tail = text[end:end + 1]
            if tail == ")":
                out.append(text[pos:m.start()] +
                           f'String(localized: {replacement}{bundle})')
                pos = end
            else:
                skipped.append((base, "Text() with extra args — manual"))
                out.append(text[pos:end])
                pos = end
        else:
            skipped.append((base, "interpolated literal in unsupported position"))
            out.append(text[pos:end])
            pos = end
    new = "".join(out)
    if new != text:
        path.write_text(new)
    return new != text, skipped


def load_values():
    """key -> verbatim en value, for plain (non-plural) snake_case keys only."""
    values = {}
    for path in CATALOGS:
        data = json.loads(path.read_text())
        for key, entry in data["strings"].items():
            if not SNAKE_RE.match(key):
                continue
            en = entry.get("localizations", {}).get("en", {})
            if "variations" in en:  # plural keys: manual, stay catalog-managed
                continue
            value = en.get("stringUnit", {}).get("value")
            if value:
                values.setdefault(key, value)
    return values


def migrate_file(path, values, accessors, module):
    text = original = path.read_text()
    bundle = ", bundle: .module" if module else ""
    skipped = []

    def inline(key):
        return (f'String(localized: "{key}", '
                f'defaultValue: "{swift_escape(values[key])}"{bundle})')

    # Pass A: full lookup expressions for accessor keys -> L10n.<name>
    for key in accessors:
        text = re.sub(
            r'String\(localized:\s*"' + re.escape(key) +
            r'"(?:\s*,\s*bundle:\s*\.module)?\s*\)',
            f"L10n.{camel(key)}", text)

    # Pass B: insert defaultValue into remaining plain-key lookups.
    def add_default(m):
        key, tail = m.group(1), m.group(2)
        if key not in values:
            skipped.append((key, "String(localized:): no plain en value"))
            return m.group(0)
        return f'String(localized: "{key}", defaultValue: "{swift_escape(values[key])}"{tail}'

    text = re.sub(
        r'String\(localized:\s*"([a-z0-9]+(?:_[a-z0-9]+)+)"(\s*(?!,\s*defaultValue)[,)])',
        add_default, text)

    # Pass C: bare builder literals.
    def wrap_builder(m):
        name, key, sep = m.group(1), m.group(2), m.group(3)
        if key in accessors:
            return f"{name}(L10n.{camel(key)}{sep}"
        if key not in values:
            skipped.append((key, f"{name}(...): no plain en value"))
            return m.group(0)
        return f"{name}({inline(key)}{sep}"

    text = re.sub(
        r'\b(' + "|".join(BUILDERS) + r')\(\s*"([a-z0-9]+(?:_[a-z0-9]+)+)"\s*([,)])',
        wrap_builder, text)

    # Pass E: localized-string parameters of project components whose type was
    # changed from LocalizedStringKey to String during the migration
    # (DetailRow.title, LargeErrorView.title, CopyButton.help, row text: params).
    # Only fires on snake_case literals, which are always catalog keys here.
    def wrap_param(m):
        name, key = m.group(1), m.group(2)
        if key in accessors:
            return f"{name}: L10n.{camel(key)}"
        if key not in values:
            skipped.append((key, f"param {name}: no plain en value"))
            return m.group(0)
        return f"{name}: {inline(key)}"

    text = re.sub(
        r'\b(title|help|text|description):\s*"([a-z0-9]+(?:_[a-z0-9]+)+)"',
        wrap_param, text)

    # Cleanup: `Text("key", bundle: .module)` wraps keep the outer bundle arg,
    # which has no overload on Text(String, ...) — the lookup now carries the
    # bundle itself, so drop the stale outer argument.
    text = text.replace("bundle: .module), bundle: .module)", "bundle: .module))")
    text = re.sub(r"(L10n\.\w+), bundle: \.module\)", r"\1)", text)

    if text != original:
        path.write_text(text)
    return text != original, skipped


def main():
    args = sys.argv[1:]
    module = "--module" in args
    accessors = set()
    if "--accessors" in args:
        accessors = set(args[args.index("--accessors") + 1].split(","))
    prefix = args[0]

    values = load_values()
    hybrids = load_hybrids() if "--hybrids" in args else None
    changed, all_skipped = [], []
    for path in sorted((REPO / prefix).rglob("*.swift")):
        did, skipped = migrate_file(path, values, accessors, module)
        if hybrids:
            did_h, skipped_h = migrate_hybrids(path, hybrids, module)
            did, skipped = did or did_h, skipped + skipped_h
        if did:
            changed.append(str(path.relative_to(REPO)))
        all_skipped += [(str(path.relative_to(REPO)), k, why) for k, why in skipped]

    print(f"changed {len(changed)} files")
    if all_skipped:
        print("\nmanual pass needed:")
        for f, k, why in all_skipped:
            print(f"  {f}: {k} — {why}")


if __name__ == "__main__":
    main()
