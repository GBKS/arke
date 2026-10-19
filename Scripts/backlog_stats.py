#!/usr/bin/env python3
"""Backlog hygiene at a glance for Docs/Open_Follow_Ups.md.

Prints open-item counts per top-level section, then flags the three things
the backlog rules (CLAUDE.md, DECIDED 2026-10-19) say should not be there:
ticked lines still in the open file, entries longer than the size cap, and
`file:line` citations. Exit status is 0 regardless; this is a report, not a
gate. Run from the repo root:

    python3 Scripts/backlog_stats.py [--max-lines N] [--quiet]
"""

import argparse
import re
import sys
from collections import OrderedDict
from pathlib import Path

BACKLOG = Path("Docs/Open_Follow_Ups.md")
DEFAULT_MAX_LINES = 7  # title line + about six lines of body
FILE_LINE = re.compile(r"`[A-Za-z0-9_+./-]+\.swift:\d")


def parse(lines):
    """Yield (section, start_index, block_lines) for every `- [ ]` / `- [x]` item.

    A block is the item line plus every following indented, non-empty line.
    """
    section = "(preamble)"
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("## "):
            section = line[3:].strip()
        if line.startswith("- ["):
            j = i + 1
            while j < len(lines) and lines[j].strip() and lines[j][0] in " \t":
                j += 1
            yield section, i, lines[i:j]
            i = j
            continue
        i += 1


def title(block):
    first = block[0]
    m = re.search(r"\*\*(.+?)\*\*", first)
    # A bold title that wraps onto the next line has no closing ** here.
    text = m.group(1) if m else first[6:].lstrip("*")
    return text.strip()[:70]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--max-lines", type=int, default=DEFAULT_MAX_LINES,
                    help=f"entry size cap in lines (default {DEFAULT_MAX_LINES})")
    ap.add_argument("--quiet", action="store_true", help="counts only, no flags")
    args = ap.parse_args()

    if not BACKLOG.exists():
        sys.exit(f"{BACKLOG} not found; run from the repo root")
    lines = BACKLOG.read_text(encoding="utf-8").split("\n")

    counts = OrderedDict()
    ticked, oversize, file_line = [], [], []
    for section, start, block in parse(lines):
        is_open = block[0].startswith("- [ ]")
        if is_open:
            counts[section] = counts.get(section, 0) + 1
        else:
            ticked.append((start + 1, title(block)))
        if is_open and len(block) > args.max_lines:
            oversize.append((start + 1, len(block), title(block)))
        if is_open and any(FILE_LINE.search(l) for l in block):
            file_line.append((start + 1, title(block)))

    total = sum(counts.values())
    print(f"{BACKLOG}: {len(lines)} lines, {total} open items\n")
    width = max(len(s) for s in counts) if counts else 10
    for section, n in counts.items():
        print(f"  {n:4d}  {section:<{width}}")
    print()

    if args.quiet:
        return

    def flag(name, rows, fmt):
        print(f"{name}: {len(rows)}")
        for row in rows:
            print("  " + fmt(*row))
        print()

    flag("Ticked lines still in the open file (move to the Done log)",
         ticked, lambda ln, t: f"L{ln}: {t}")
    flag(f"Entries over {args.max_lines} lines (evidence belongs in a plan doc)",
         sorted(oversize, key=lambda r: -r[1]),
         lambda ln, n, t: f"L{ln} ({n} lines): {t}")
    flag("Entries citing file:line (cite symbols instead)",
         file_line, lambda ln, t: f"L{ln}: {t}")


if __name__ == "__main__":
    main()
