#!/usr/bin/env python3
"""Write addons/GroupDebuffs/Data.lua: the debuff slots a group fills, the
classes that fill each, and every spell ID that carries a debuff's name.

    group-debuffs-data.py [table dir]   default scratchpad/groupdebuffs

The directory holds the client's SpellName.csv, SkillLineAbility.csv,
CreatureFamily.csv and TraitDefinition.csv for the installed build: https://wago.tools/db2/<Table>/csv?build=<version>

All IDs with the exact name are taken, so every rank is covered. That also
takes in creature versions of the spell, which only makes the list longer.
The icon comes from the lowest ID that a skill line teaches (a player's
rank 1), or the lowest ID of all for debuffs no skill line lists, such as
the ones a hunter's pet applies.

The catalogue was read off build 1.60.1.70938: every aura that a class
spell, a talent or a spell those trigger puts on an enemy (SpellEffect),
kept when the spell's own text (Spell) says it helps the whole group or
weakens the enemy. Left out because the text says "from the caster" or
"you deal", so only the caster gains: Fire Vulnerability, Shadow Weaving,
Winter's Chill, Improved Shadow Bolt, Stormstrike, Hemorrhage. Curse of
Shadow is no class spell in this game; Curse of the Elements covers all
magic.
"""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "addons" / "GroupDebuffs" / "Data.lua"

# (shown by default, [(class token, debuff name[, requirement]), ...]). A
# requirement is {"pet": family} for a hunter pet's debuff, which only
# counts while a pet of that family is in the group, or {"talent": name}
# for one that takes a talent, which counts for a player who has it (or
# whose talents are not known yet). An entry may end in {"each": class}:
# a player of that class can keep up only one of the entries so marked, so
# only as many of them show as there are such players. One entry is one
# slot in the row: debuffs that do the same job share a slot, which shows
# when any of its classes is in the group and lights up for whichever of
# them is on the target. On by default: what a group generally keeps on a
# boss. Off: situational, tied to a talent or a pet family, or the same
# effect as one that is on. Which debuffs push each other off a target is
# the server's doing and not in the client: the shared slots follow Classic
# (Sunder Armor and Expose Armor exclude each other, as do the demoralizing
# effects, while Faerie Fire and Curse of Recklessness stack with both).
CATALOGUE = [
    (True, [("WARRIOR", "Sunder Armor"), ("ROGUE", "Expose Armor")]),  # armor, one or the other
    (True, [("WARRIOR", "Demoralizing Shout"), ("DRUID", "Demoralizing Roar"), ("HUNTER", "Demoralizing Screech", {"pet": "Carrion Bird"})]),  # melee attack power
    (True, [("WARRIOR", "Thunder Clap")]),
    (True, [("DRUID", "Faerie Fire")]),
    (True, [("HUNTER", "Scorpid Sting"), ("DRUID", "Insect Swarm", {"talent": "Insect Swarm"})]),  # chance to hit
    (True, [("HUNTER", "Hunter's Mark")]),
    (True, [("HUNTER", "Dust Cloud", {"pet": "Tallstrider"})]),
    # One curse per warlock, likewise.
    (True, [("WARLOCK", "Curse of the Elements")], {"each": "WARLOCK"}),
    (True, [("WARLOCK", "Curse of Recklessness")], {"each": "WARLOCK"}),
    (False, [("WARLOCK", "Curse of Weakness")], {"each": "WARLOCK"}),
    (False, [("WARLOCK", "Curse of Tongues")], {"each": "WARLOCK"}),
    # A paladin keeps up one judgement: as many of these show as there are
    # paladins, the first ones that are switched on.
    (True, [("PALADIN", "Judgement of Wisdom")], {"each": "PALADIN"}),
    (True, [("PALADIN", "Judgement of Light")], {"each": "PALADIN"}),
    (True, [("PALADIN", "Judgement of the Crusader")], {"each": "PALADIN"}),
    (True, [("PRIEST", "Vampiric Embrace", {"talent": "Vampiric Embrace"})]),
    (False, [("PRIEST", "Vampiric Touch")]),
    (False, [("PRIEST", "Hex of Weakness")]),
]


def quote(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    tables = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "scratchpad/groupdebuffs"
    for name in ("SpellName.csv", "SkillLineAbility.csv", "CreatureFamily.csv", "TraitDefinition.csv"):
        if not (tables / name).exists():
            sys.exit(f"{tables / name}: not found; fetch https://wago.tools/db2/{name[:-4]}/csv?build=<version>")
    by_name = {}
    with open(tables / "SpellName.csv", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            by_name.setdefault(row["Name_lang"], []).append(int(row["ID"]))
    with open(tables / "SkillLineAbility.csv", newline="", encoding="utf-8") as handle:
        taught = {int(row["Spell"]) for row in csv.DictReader(handle)}
    with open(tables / "CreatureFamily.csv", newline="", encoding="utf-8") as handle:
        families = {row["Name_lang"]: int(row["ID"]) for row in csv.DictReader(handle)}
    with open(tables / "TraitDefinition.csv", newline="", encoding="utf-8") as handle:
        trait_spells = {int(row["SpellID"]) for row in csv.DictReader(handle) if row["SpellID"] not in ("", "0")}

    out = [
        "-- Generated by scripts/group-debuffs-data.py from the client's SpellName",
        "-- table. Do not edit: change the catalogue in the script and run it again.",
        "local _, ns = ...",
        "",
        "ns.DEBUFFS = {",
    ]
    missing = []
    slots = 0
    for on, members, *options in CATALOGUE:
        each = options[0].get("each") if options else None
        sources, ids = [], set()
        for klass, name, *rest in members:
            needs = rest[0] if rest else {}
            found = sorted(by_name.get(name, []))
            pet, talent = needs.get("pet"), needs.get("talent")
            # The talent as the talent tree names it (what an inspection
            # gives) and every rank a skill line teaches (what you know).
            tree = sorted(spell for spell in by_name.get(talent, []) if spell in trait_spells) if talent else []
            ranks = sorted(spell for spell in by_name.get(talent, []) if spell in taught) if talent else []
            if not found or (pet and pet not in families) or (talent and not tree):
                missing.append(name)
                continue
            icon = next((spell for spell in found if spell in taught), found[0])
            extra = ""
            if pet:
                extra += f', pet = {families[pet]}, petName = "{quote(pet)}"'
            if talent:
                extra += (f', talentName = "{quote(talent)}", talents = {{ {", ".join(map(str, tree))} }}, '
                          f'talentRanks = {{ {", ".join(map(str, ranks or tree))} }}')
            sources.append(f'{{ class = "{klass}", name = "{quote(name)}", icon = {icon}{extra} }}')
            ids.update(found)
        if not sources:
            continue
        slots += 1
        title = quote(" / ".join(member[1] for member in members if member[1] in by_name))
        out.append(
            f'\t{{ name = "{title}", on = {"true" if on else "false"}, {f'each = "{each}", ' if each else ""}'
            f'sources = {{ {", ".join(sources)} }}, ids = {{ {", ".join(map(str, sorted(ids)))} }} }},'
        )
    out += ["}", ""]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out))
    print(f"{OUT}: {slots} slots")
    for name in missing:
        print(f"  not in the game's tables, left out: {name}")
    return len(missing)


if __name__ == "__main__":
    sys.exit(main())
