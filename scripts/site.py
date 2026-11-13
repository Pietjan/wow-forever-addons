#!/usr/bin/env python3
"""Write docs/index.html: the addons, what each does, and a download link.

    site.py <owner/repo>

Everything comes from the repository itself: an addon's name, description and
version from its .toc, whether that version is released from the git tags
(<Addon>-v<version>, made by `make release/<addon>`), its picture from the
committed files in docs/mockups, and "needs extra files" from .gitignore.
The page is plain HTML with one stylesheet (docs/site.css), served by GitHub
Pages from docs/. Run it again after a release and commit the result.
"""
import html
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
OUT = ROOT / "docs" / "index.html"


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def toc_fields(path):
    fields = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("## ") and ":" in line:
            key, value = line[3:].split(":", 1)
            fields[key.strip()] = value.strip()
    return fields


def addons(repo):
    tags = set(git("tag", "--list").split())
    pictures = [Path(p) for p in git("ls-files", "docs/mockups").split()]
    ignored = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
    found = []
    for toc in sorted(ADDONS.glob("*/*.toc"), key=lambda p: p.stem.lower()):
        name = toc.stem
        if toc.parent.name != name:
            continue
        fields = toc_fields(toc)
        version = fields.get("Version", "")
        tag = f"{name}-v{version}"
        picture = next((p for p in pictures if p.name.startswith(name.lower() + "-")), None)
        found.append({
            "name": name,
            "notes": fields.get("Notes", ""),
            "version": version,
            "download": f"https://github.com/{repo}/releases/download/{tag}/{name}-{version}.zip" if tag in tags else None,
            "release": f"https://github.com/{repo}/releases/tag/{tag}" if tag in tags else None,
            "picture": picture.relative_to("docs").as_posix() if picture else None,
            "extra": any(line.strip().startswith(f"addons/{name}/") for line in ignored),
        })
    return found


def card(addon, repo):
    e = html.escape
    parts = ['<article class="addon">']
    if addon["picture"]:
        parts.append(f'<img src="{e(addon["picture"])}" alt="{e(addon["name"])} mock-up" loading="lazy">')
    parts.append(f'<h2>{e(addon["name"])} <span class="version">{e(addon["version"])}</span></h2>')
    parts.append(f'<p>{e(addon["notes"])}</p>')
    if addon["extra"]:
        parts.append(f'<p class="note">Needs files that are not in the download; see the '
                     f'<a href="https://github.com/{e(repo)}#readme">README</a>.</p>')
    if addon["download"]:
        parts.append(f'<p class="links"><a class="download" href="{e(addon["download"])}">Download {e(addon["version"])}</a> '
                     f'<a href="{e(addon["release"])}">Release notes</a></p>')
    else:
        parts.append('<p class="links note">This version is not released yet.</p>')
    parts.append("</article>")
    return "\n".join(parts)


def page(repo, found):
    e = html.escape
    cards = "\n".join(card(addon, repo) for addon in found)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WoW Forever addons</title>
<link rel="stylesheet" href="site.css">
</head>
<body>
<header>
<h1>WoW Forever addons</h1>
<p>{len(found)} small addons for World of Warcraft Forever, each on its own. Every download is one zip with one folder.</p>
<p><strong>To install:</strong> unzip into the game's <code>Interface/AddOns</code> folder, so that it holds a folder with the addon's name, then <code>/reload</code> or restart the game.</p>
</header>
<main>
{cards}
</main>
<footer>
<p>The pictures are mock-ups, not screenshots. Source, issues and older versions: <a href="https://github.com/{e(repo)}">github.com/{e(repo)}</a>.</p>
</footer>
</body>
</html>
"""


def main():
    if len(sys.argv) != 2 or "/" not in sys.argv[1]:
        sys.exit("usage: site.py <owner/repo>")
    repo = sys.argv[1]
    found = addons(repo)
    OUT.write_text(page(repo, found), encoding="utf-8")
    released = sum(1 for addon in found if addon["download"])
    print(f"{OUT.relative_to(ROOT)}: {len(found)} addons, {released} with a download")


if __name__ == "__main__":
    main()
