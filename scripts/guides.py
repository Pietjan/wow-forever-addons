#!/usr/bin/env python3
"""Fetch the leveling guides that ForeverGuide reads.

ForeverGuide has no guides of its own. It loads the guide files of
RestedXP Guides and WoW-Pro Leveling exactly as their authors publish
them. This script takes the WoW Forever leveling guides from both
projects' GitHub repositories and puts unmodified copies under
addons/ForeverGuide/Guides, with a guides.xml that lists them.

RestedXP: when the released RestedXP Guides addon is at hand (RXPGUIDES_DIR,
by default ../wow-addons/addons/RXPGuides next to this repository), its
guide files are used, because the released addon carries more guides
(levels 1-60) than the GitHub repository (1-22).

Dungeon guides are left out. Both guide sets are licensed for
non-commercial use (RestedXP: CC BY-NC-SA 4.0, WoW-Pro: CC BY-NC-ND 3.0);
the copies are for personal use and are kept out of git.

usage: guides.py            fetch both
       guides.py rxp        only RestedXP
       guides.py wowpro     only WoW-Pro
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "addons" / "ForeverGuide" / "Guides"
RXPGUIDES = Path(os.environ.get("RXPGUIDES_DIR") or ROOT.parent / "wow-addons" / "addons" / "RXPGuides")

SOURCES = {
    "rxp": {
        "title": "RestedXP Guides",
        "repo": "https://github.com/RestedXP/RXPGuides",
        "sparse": ["/Guides/forever/*.lua", "/Guides/GuideList-forever.xml", "/LICENSE"],
        "folder": "RXP",
    },
    "wowpro": {
        "title": "WoW-Pro Leveling",
        "repo": "https://github.com/Ludovicus-Maior/WoW-Pro-Guides",
        "sparse": ["/WoWPro_Leveling/Forever/", "/License.md"],
        "folder": "WoWPro",
    },
}


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def checkout(source, into):
    git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-checkout", source["repo"], str(into))
    git("sparse-checkout", "init", "--no-cone", cwd=into)
    git("sparse-checkout", "set", *source["sparse"], cwd=into)
    git("checkout", "-q", cwd=into)
    return git("rev-parse", "--short", "HEAD", cwd=into), git("log", "-1", "--format=%cs", cwd=into)


def scripts(xml):
    """The files a guide list loads, in order."""
    return re.findall(r'<Script\s+file="([^"]+)"', xml.read_text(errors="replace"))


def take_rxp(repo, dest):
    files = []
    for name in scripts(repo / "Guides" / "GuideList-forever.xml"):
        # Guides/forever/<file>.lua only: no dungeon guides, no hardcore
        # ("SurvivalGuide") guides, no import stub.
        match = re.fullmatch(r"Guides/forever/([^/]+\.lua)", name.replace("\\", "/"))
        if match and (repo / name).is_file():
            shutil.copyfile(repo / name, dest / match.group(1))
            files.append(match.group(1))
    shutil.copyfile(repo / "LICENSE", dest / "LICENSE")
    return files


def take_wowpro(repo, dest):
    files = []
    base = repo / "WoWPro_Leveling" / "Forever"
    for faction in ("Neutral", "Alliance", "Horde"):
        xml = base / faction / "Guides.xml"
        if not xml.is_file():
            continue
        (dest / faction).mkdir()
        for name in scripts(xml):
            if "dungeon" in name.lower() or not (base / faction / name).is_file():
                continue
            shutil.copyfile(base / faction / name, dest / faction / name)
            files.append(f"{faction}/{name}")
    shutil.copyfile(repo / "License.md", dest / "License.md")
    return files


def main():
    wanted = sys.argv[1:] or list(SOURCES)
    DEST.mkdir(parents=True, exist_ok=True)
    for key in wanted:
        source = SOURCES[key]
        dest = DEST / source["folder"]
        local = RXPGUIDES
        if key == "rxp" and (local / "Guides" / "GuideList-forever.xml").is_file():
            fresh = dest.with_name(dest.name + ".new")
            if fresh.exists():
                shutil.rmtree(fresh)
            fresh.mkdir()
            files = take_rxp(local, fresh)
            version = re.search(r"^## Version:\s*(\S+)", (local / "RXPGuides.toc").read_text(errors="replace"), re.M)
            origin = f"RXPGuides addon {version.group(1) if version else ''}".strip()
            if dest.exists():
                shutil.rmtree(dest)
            fresh.rename(dest)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                repo = Path(tmp) / "repo"
                commit, date = checkout(source, repo)
                if dest.exists():
                    shutil.rmtree(dest)
                dest.mkdir()
                files = (take_rxp if key == "rxp" else take_wowpro)(repo, dest)
            origin = f"{source['repo']} {commit} {date}"
        (dest / ".source").write_text(origin + "\n")
        (dest / "files.txt").write_text("".join(f"{name}\n" for name in files))
        print(f"{source['title']}: {len(files)} guide files ({origin})")

    lines = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">']
    for source in SOURCES.values():
        listing = DEST / source["folder"] / "files.txt"
        if listing.is_file():
            lines.append(f"\t<!-- {source['title']}: {source['repo']} -->")
            for name in listing.read_text().split("\n"):
                if name:
                    path = f"{source['folder']}/{name}".replace("/", "\\")
                    lines.append(f'\t<Script file="{path}"/>')
    lines.append("</Ui>")
    (DEST / "guides.xml").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
