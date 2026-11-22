#!/usr/bin/env python3
"""Write addons/CombatScroll/Data.lua: for every spell a player or pet can
learn that does damage or heals, its school, whether it hits directly, and
how often it ticks if it does damage or healing over time. CombatScroll
uses this to tell which of your spells made a hit (the game does not say).

    combat-scroll-data.py [table dir]   default scratchpad/combatscroll

The directory holds the client's SpellMisc.csv, SpellEffect.csv,
SkillLineAbility.csv, TraitDefinition.csv, ItemEffect.csv,
ItemXItemEffect.csv and SpellItemEnchantment.csv for the installed build:
https://wago.tools/db2/<Table>/csv?build=<version>

Spells taken: everything a skill line teaches (class, pet, racial and
profession lines; the last have no damage effects and drop out) and every
talent spell. A spell's effects include those of the spells it triggers,
one level deep (Arcane Missiles' missiles, for one).

Read off SpellEffect (Effect, EffectAura, EffectAuraPeriod in ms) and
SpellMisc (SchoolMask, the row with DifficultyID 0):
- direct: school damage (2), health leech (9), heal (10), weapon damage
  (17, 31, 58, 121);
- over time: the auras periodic damage (3), periodic heal (8), periodic
  leech (53), periodic damage percent (89) and periodic dummy (226, the
  ticks of Blizzard and Flamestrike);
- what the ticks do (a heal tick only takes a spell whose ticks heal):
  periodic heal (8) heals, the other tick auras damage, and a periodic
  dummy damages when an effect of its spell aims at an enemy (ImplicitTarget
  6, 15, 16, 24: Blizzard, Consecration) and heals otherwise (Healing Rain,
  Blessed Recovery). A dummy beside a periodic energize (24) trades health
  for mana and is left out (Dark Sacrifice, 1277324: it took a heal's icon,
  2026-11-22);
- what the direct hits do, by the same split: heal (10) heals, the other
  direct effects damage; a triggered spell (64, or the periodic trigger of
  a channel) does what its own direct effects do;
- repeating direct hits: periodic trigger spell (23, 226 with a trigger)
  whose triggered spell hits directly, as Arcane Missiles: each missile is
  a direct hit, `every` seconds apart.

Damage shields (aura 15: "when struck, inflicts damage to the attacker")
get lists of their own, by school: the items whose equip spell
(ItemEffect TriggerType 1) is one, such as Sporid Cape, and the learnable
spells that are one (Thorns, Fire Shield).

Procs, for a hit of yours that no cast explains (Lightning Shield's
charges, Flametongue Weapon), by school; the damage spell itself is often a
server-side dummy, so the link from buff or enchant to the hit ends there:
- buffs: learnable spells with a proc trigger aura (42) whose triggered
  spell does damage or is only a dummy (3); the school is the triggered
  spell's, or the buff's when that one is physical. Buffs whose procs do
  something else (Aspects, Clearcasting, roots) drop out;
- weapon enchants (SpellItemEnchantment, read in game with
  C_Item.GetWeaponEnchantInfo): an enchant whose combat proc (1) or equip
  spell (3) does damage, in that spell's school (Frostbrand, poisons,
  Fiery Weapon); or one applied by a learnable spell (effect 54, 360)
  whose proc or equip spell is only a dummy, in the applying spell's school
  (Flametongue Weapon). Physical ones are left out.
"""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "addons" / "CombatScroll" / "Data.lua"

DIRECT_EFFECTS = {2, 9, 10, 17, 31, 58, 121}
DAMAGE_EFFECTS = DIRECT_EFFECTS - {10}  # less heal
TRIGGER_EFFECTS = {64}  # trigger spell
APPLY_AURA = 6
TICK_AURAS = {3, 8, 53, 89, 226}
PERIODIC_HEAL_AURA = 8
PERIODIC_DUMMY_AURA = 226
PERIODIC_ENERGIZE_AURA = 24
ENEMY_TARGETS = {"6", "15", "16", "24"}  # unit, source area, dest area, cone
TICK_DAMAGES, TICK_HEALS = 1, 2
HEAL_EFFECT = 10
TRIGGER_AURAS = {23, 226}
DAMAGE_SHIELD_AURA = 15
EQUIP = "1"  # ItemEffect.TriggerType
PROC_TRIGGER_AURA = 42
DUMMY = 3
DUMMY_AURA = 4
ENCHANT_EFFECTS = {"54", "360"}  # enchant item (permanent, temporary)
ENCHANT_PROC, ENCHANT_EQUIP = "1", "3"  # SpellItemEnchantment.Effect_N


def read(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main():
    tables = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "scratchpad/combatscroll"
    for name in ("SpellMisc.csv", "SpellEffect.csv", "SkillLineAbility.csv", "TraitDefinition.csv", "ItemEffect.csv", "ItemXItemEffect.csv", "SpellItemEnchantment.csv"):
        if not (tables / name).exists():
            sys.exit(f"{tables / name}: not found; fetch https://wago.tools/db2/{name[:-4]}/csv?build=<version>")

    school = {}
    for r in read(tables / "SpellMisc.csv"):
        if r["DifficultyID"] == "0":
            school[int(r["SpellID"])] = int(r["SchoolMask"])

    effects = {}
    shields = set()
    applies = {}  # enchant ID -> spells that put it on
    aims_at_enemy = set()
    for r in read(tables / "SpellEffect.csv"):
        if r["DifficultyID"] != "0":
            continue
        if r["Effect"] == str(APPLY_AURA) and r["EffectAura"] == str(DAMAGE_SHIELD_AURA):
            shields.add(int(r["SpellID"]))
        if r["ImplicitTarget_0"] in ENEMY_TARGETS or r["ImplicitTarget_1"] in ENEMY_TARGETS:
            aims_at_enemy.add(int(r["SpellID"]))
        effects.setdefault(int(r["SpellID"]), []).append(
            (int(r["Effect"]), int(r["EffectAura"]), int(r["EffectAuraPeriod"]), int(r["EffectTriggerSpell"]))
        )
        if r["Effect"] in ENCHANT_EFFECTS:
            applies.setdefault(int(r["EffectMiscValue_0"]), []).append(int(r["SpellID"]))

    learnable = {int(r["Spell"]) for r in read(tables / "SkillLineAbility.csv")}
    learnable |= {int(r["SpellID"]) for r in read(tables / "TraitDefinition.csv") if r["SpellID"] != "0"}

    def direct(spell):
        return any(e in DIRECT_EFFECTS for e, _, _, _ in effects.get(spell, []))

    def direct_kind(spell):
        kind = 0
        for e, _, _, _ in effects.get(spell, []):
            if e == HEAL_EFFECT:
                kind |= TICK_HEALS
            elif e in DIRECT_EFFECTS:
                kind |= TICK_DAMAGES
        return kind

    rows = {}
    for spell in sorted(learnable):
        hits, tick, every, kind, hit_kind = False, None, None, 0, 0
        trade = any(e == APPLY_AURA and a == PERIODIC_ENERGIZE_AURA for e, a, _, _ in effects.get(spell, []))
        for effect, aura, period, trigger in effects.get(spell, []):
            if effect in DIRECT_EFFECTS:
                hits = True
                hit_kind |= TICK_HEALS if effect == HEAL_EFFECT else TICK_DAMAGES
            elif effect in TRIGGER_EFFECTS and trigger and direct(trigger):
                hits = True
                hit_kind |= direct_kind(trigger)
            elif effect == APPLY_AURA and period > 0:
                if aura in TRIGGER_AURAS and trigger and direct(trigger):
                    every = period / 1000
                    hit_kind |= direct_kind(trigger)
                elif aura in TICK_AURAS:
                    if aura == PERIODIC_HEAL_AURA:
                        kind |= TICK_HEALS
                    elif aura != PERIODIC_DUMMY_AURA:
                        kind |= TICK_DAMAGES
                    elif spell in aims_at_enemy:
                        kind |= TICK_DAMAGES
                    elif trade:
                        continue
                    else:
                        kind |= TICK_HEALS
                    tick = period / 1000
        if not (hits or tick or every):
            continue
        rows[spell] = (school.get(spell, 0), 1 if hits else 0, tick or 0, every or 0, kind, hit_kind)

    item_effects = {int(r["ID"]): r for r in read(tables / "ItemEffect.csv")}
    shield_items = {}
    for r in read(tables / "ItemXItemEffect.csv"):
        effect = item_effects.get(int(r["ItemEffectID"]))
        if effect and effect["TriggerType"] == EQUIP and int(effect["SpellID"]) in shields:
            shield_items[int(r["ItemID"])] = school.get(int(effect["SpellID"]), 0)
    shield_spells = {spell: school.get(spell, 0) for spell in sorted(shields & learnable)}

    def damages(spell):
        return any(e in DAMAGE_EFFECTS for e, _, _, _ in effects.get(spell, []))

    def magic(mask):
        return mask not in (0, 1)

    def only_dummy(spell):
        effs = effects.get(spell, [])
        return bool(effs) and all(e == DUMMY or (e == APPLY_AURA and a == DUMMY_AURA) for e, a, _, _ in effs)

    proc_auras = {}
    for spell in sorted(learnable):
        for effect, aura, _, trigger in effects.get(spell, []):
            if effect == APPLY_AURA and aura == PROC_TRIGGER_AURA and trigger and (damages(trigger) or only_dummy(trigger)):
                mask = school.get(trigger, 0) if magic(school.get(trigger, 0)) else school.get(spell, 0)
                if magic(mask):
                    proc_auras[spell] = mask

    proc_enchants = {}
    for r in read(tables / "SpellItemEnchantment.csv"):
        enchant = int(r["ID"])
        for i in range(3):
            kind, spell = r[f"Effect_{i}"], int(r[f"EffectArg_{i}"])
            if kind not in (ENCHANT_PROC, ENCHANT_EQUIP) or not spell:
                continue
            if damages(spell) and magic(school.get(spell, 0)):
                proc_enchants[enchant] = school[spell]
            elif only_dummy(spell):
                masks = {school.get(a, 0) for a in applies.get(enchant, []) if a in learnable}
                masks = {m for m in masks if magic(m)}
                if len(masks) == 1:
                    proc_enchants[enchant] = masks.pop()

    def num(x):
        return f"{x:g}"

    lines = [
        "-- Generated by scripts/combat-scroll-data.py from the client tables; do not edit.",
        "-- [spellID] = { school mask, hits directly (1/0), seconds between ticks (0: none),",
        "--               seconds between repeated direct hits (0: none),",
        "--               what the ticks do (1 damage, 2 heal, 3 both, 0 no ticks),",
        "--               what the direct or repeated hits do (same numbers) }",
        "local _, ns = ...",
        "ns.spells = {",
    ]
    for spell, (mask, hits, tick, every, kind, hit_kind) in rows.items():
        lines.append(f"\t[{spell}] = {{ {mask}, {hits}, {num(tick)}, {num(every)}, {kind}, {hit_kind} }},")
    lines.append("}")
    lines.append("-- Damage shields: [itemID] / [spellID] = school mask")
    lines.append("ns.shieldItems = {")
    for item, mask in sorted(shield_items.items()):
        lines.append(f"\t[{item}] = {mask},")
    lines.append("}")
    lines.append("ns.shieldSpells = {")
    for spell, mask in shield_spells.items():
        lines.append(f"\t[{spell}] = {mask},")
    lines.append("}")
    lines.append("-- Procs: [buff spellID] / [enchantID] = school mask")
    lines.append("ns.procAuras = {")
    for spell, mask in proc_auras.items():
        lines.append(f"\t[{spell}] = {mask},")
    lines.append("}")
    lines.append("ns.procEnchants = {")
    for enchant, mask in sorted(proc_enchants.items()):
        lines.append(f"\t[{enchant}] = {mask},")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(rows)} spells, {len(shield_items)} damage shield items, {len(shield_spells)} damage shield spells, {len(proc_auras)} proc buffs, {len(proc_enchants)} proc enchants")


if __name__ == "__main__":
    main()
