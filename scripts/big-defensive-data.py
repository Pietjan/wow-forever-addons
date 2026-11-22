#!/usr/bin/env python3
"""Write addons/GroupFrames/BigDefensiveData.lua: the spells that may be a
"big defensive", for GroupFrames to ask the game about at login.

    big-defensive-data.py [table dir]   default scratchpad/groupdebuffs

The directory holds the client's SkillLine.csv, SkillLineAbility.csv,
TraitDefinition.csv and SpellEffect.csv for the installed build:
https://wago.tools/db2/<Table>/csv?build=<version>

Which spells count as big defensives is the game's own judgement
(C_UnitAuras.AuraIsBigDefensive, which takes a spell ID); no client table
says so. So the list here is every candidate: every spell a class skill
line teaches (SkillLine.CategoryID 7), every talent (TraitDefinition), and
every spell those trigger (SpellEffect.EffectTriggerSpell), since the aura
is often a triggered spell. The addon keeps the ones the game names.
"""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "addons" / "GroupFrames" / "BigDefensiveData.lua"


def main():
    tables = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "scratchpad" / "groupdebuffs"

    def rows(name):
        with open(tables / f"{name}.csv", newline="", encoding="utf-8") as f:
            yield from csv.DictReader(f)

    class_lines = {r["ID"] for r in rows("SkillLine") if r.get("CategoryID") == "7"}
    spells = {int(r["Spell"]) for r in rows("SkillLineAbility") if r["SkillLine"] in class_lines}
    talents = {int(r["SpellID"]) for r in rows("TraitDefinition") if r["SpellID"] not in ("", "0")}
    base = spells | talents
    triggered = set()
    for r in rows("SpellEffect"):
        trigger = int(r["EffectTriggerSpell"] or 0)
        if trigger and int(r["SpellID"]) in base:
            triggered.add(trigger)
    ids = sorted(base | triggered)

    lines = [
        "-- Written by scripts/big-defensive-data.py; do not edit.",
        f"-- {len(ids)} candidates: class spells ({len(spells)}), talents ({len(talents)}) and what they trigger.",
        "local _, ns = ...",
        "ns.BIG_DEFENSIVE_CANDIDATES = {",
    ]
    for i in range(0, len(ids), 16):
        lines.append("\t" + ", ".join(str(x) for x in ids[i:i + 16]) + ",")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(ids)} spell IDs")


if __name__ == "__main__":
    main()
