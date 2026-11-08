#!/usr/bin/env python3
"""Static checks for our own addons (the ones whose .toc names Pietjan as
author), or for the files given on the command line.

- Every Lua file must compile (luac -p).
- A name that is declared `local` somewhere in a file must not be read
  as a global anywhere in that file. That is what a local function used
  above its definition compiles to, and in the game it is a nil call on
  the first refresh. Found by reading luac's bytecode listing.
- Every file a .toc lists must exist.

Exit status is the number of problems, so `make` stops on any.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL_FUNCTION = re.compile(r"^\s*local\s+function\s+([A-Za-z_]\w*)")
LOCAL_NAMES = re.compile(r"^\s*local\s+([A-Za-z_][\w\s,]*?)\s*(?:=|$)")
GETGLOBAL = re.compile(r"^\s*\d+\s+\[(\d+)\]\s+GETGLOBAL\s+\S+\s+\S+\s*;\s*(\S+)")


def own_addons():
    for toc in sorted(ROOT.glob("addons/*/*.toc")):
        if re.search(r"^## Author:\s*Pietjan\s*$", toc.read_text(errors="replace"), re.M):
            yield toc.parent


def local_declarations(source):
    """name -> first line where it is declared local."""
    found = {}
    for number, line in enumerate(source.splitlines(), 1):
        match = LOCAL_FUNCTION.match(line)
        if match:
            found.setdefault(match.group(1), number)
            continue
        match = LOCAL_NAMES.match(line)
        if match and not line.lstrip().startswith("local function"):
            for name in match.group(1).split(","):
                name = name.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", name):
                    found.setdefault(name, number)
    return found


def check_lua(path):
    problems = []
    listing = subprocess.run(["luac", "-p", "-l", str(path)], capture_output=True, text=True)
    if listing.returncode != 0:
        problems.append(f"{path}: {listing.stderr.strip()}")
        return problems
    source = path.read_text(errors="replace")
    locals_ = local_declarations(source)
    seen = set()
    for line in listing.stdout.splitlines():
        match = GETGLOBAL.match(line)
        if not match:
            continue
        number, name = int(match.group(1)), match.group(2)
        if name in locals_ and (name, number) not in seen:
            seen.add((name, number))
            problems.append(
                f"{path}:{number}: '{name}' is read as a global here but declared local at line {locals_[name]}"
                " (used before its definition?)"
            )
    return problems


def check_toc(toc):
    problems = []
    for line in toc.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        listed = toc.parent / line.replace("\\", "/")
        if not listed.exists():
            problems.append(f"{toc}: lists {line}, which does not exist")
    return problems


def main(argv):
    problems = []
    if argv:
        paths = [Path(p) for p in argv]
    else:
        paths = list(own_addons())
    checked = 0
    for path in paths:
        files = [path] if path.is_file() else sorted(path.rglob("*.lua")) + sorted(path.glob("*.toc"))
        for file in files:
            if file.suffix == ".lua":
                problems.extend(check_lua(file))
                checked += 1
            elif file.suffix == ".toc":
                problems.extend(check_toc(file))
    for problem in problems:
        print(problem)
    print(f"{checked} Lua file(s) checked, {len(problems)} problem(s)")
    return min(len(problems), 125)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
