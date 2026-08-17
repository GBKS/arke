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
    changed, all_skipped = [], []
    for path in sorted((REPO / prefix).rglob("*.swift")):
        did, skipped = migrate_file(path, values, accessors, module)
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
