#!/usr/bin/env python3
"""Copy a docgen section file, dropping everything before its first level-1 heading.

Usage: strip_preamble.py <input.md> <output.md>

Text above the first line matching "# " is author preamble (editor notes, to-dos) and
never reaches the document. Lines inside fenced code blocks are ignored when looking for
the heading. A file with no level-1 heading is an error.
"""
import os
import re
import sys

FENCE = re.compile(r"^\s*(```|~~~)")
H1 = re.compile(r"^# \S")


class NoHeading(Exception):
    pass


def strip(lines, name):
    """Return lines from the first level-1 heading on; raise NoHeading if there is none."""
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence and H1.match(line):
            out = lines[i:]
            if out and not out[-1].endswith("\n"):
                out = out[:-1] + [out[-1] + "\n"]
            return out
    raise NoHeading(
        "docgen: %s has no level-1 heading ('# Title'); every section file needs one" % name)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    src, dst = argv[1], argv[2]
    with open(src, encoding="utf-8") as f:
        lines = f.readlines()
    try:
        out = strip(lines, src)
    except NoHeading as e:
        sys.stderr.write(str(e) + "\n")
        return 1
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        f.writelines(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
