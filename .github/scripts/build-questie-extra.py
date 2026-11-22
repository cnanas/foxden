#!/usr/bin/env python3
"""Builds Foxden/Data/QuestieExtra.lua: dungeon entrances and trash drops, precomputed from
QuestieDB's WoW Forever data (Questie team, GPLv3), so Foxden doesn't need the QuestieDB addon
for them. When QuestieDB is installed, Foxden still reads it live instead.

  python3 tools/build-questie-extra.py

Trash drops follow Core/Trash.lua: items dropped only by NPCs of one dungeon (so world drops are
left out), not by its bosses (that's boss loot), and not quest items."""
import re, sys, urllib.request
from pathlib import Path

RAW = "https://raw.githubusercontent.com/Questie/QuestieDB/master/"
ROOT = Path(__file__).resolve().parent.parent
import os
# the addon's folder: Foxden/ here, the repository root in the public copy (ADDON_DIR=. there)
ADDON = Path(os.environ["ADDON_DIR"]).resolve() if os.environ.get("ADDON_DIR") else ROOT / "Foxden"

def get(path):
    with urllib.request.urlopen(RAW + path, timeout=180) as r:
        return r.read().decode("utf-8")

# ---- a small reader for Lua data tables (literals only) ------------------------------------------
class Faction:
    def __init__(self, horde, alliance): self.horde, self.alliance = horde, alliance
class P:
    def __init__(self, s): self.s, self.i = s, 0
    def ws(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n": self.i += 1
            elif s.startswith("--", self.i):
                if s.startswith("--[[", self.i): self.i = s.index("]]", self.i) + 2
                else:
                    j = s.find("\n", self.i); self.i = len(s) if j < 0 else j
            else: break
    def val(self):
        self.ws(); s = self.s; c = s[self.i]
        if c == "{": return self.table()
        if c == "(":  # (isHorde and X or Y): a faction-dependent value, kept as both
            m = re.compile(r"\(\s*isHorde\s+and\s+").match(s, self.i)
            if not m: raise ValueError("unexpected expression at %d" % self.i)
            self.i = m.end(); horde = self.val(); self.ws()
            closed = s[self.i] == ")"  # (isHorde and X) or Y   as well as   (isHorde and X or Y)
            if closed: self.i += 1; self.ws()
            if not s.startswith("or", self.i): raise ValueError("expected 'or' at %d" % self.i)
            self.i += 2; alliance = self.val(); self.ws()
            if not closed: self.i += 1  # )
            return Faction(horde, alliance)
        if c in "'\"": return self.string(c)
        if s.startswith("nil", self.i): self.i += 3; return None
        if s.startswith("true", self.i): self.i += 4; return True
        if s.startswith("false", self.i): self.i += 5; return False
        m = re.compile(r"-?(0x[0-9a-fA-F]+|\d+\.?\d*(e-?\d+)?)").match(s, self.i)
        if m:
            self.i = m.end(); t = m.group(0)
            return int(t, 16) if "0x" in t else (float(t) if any(ch in t for ch in ".e") else int(t))
        raise ValueError("unexpected %r at %d" % (s[self.i:self.i + 30], self.i))
    def string(self, q):
        s = self.s; self.i += 1; out = []
        while s[self.i] != q:
            if s[self.i] == "\\": out.append(s[self.i + 1]); self.i += 2
            else: out.append(s[self.i]); self.i += 1
        self.i += 1
        return "".join(out)
    def table(self):
        s = self.s; self.i += 1; arr, obj = [], {}
        while True:
            self.ws()
            if s[self.i] == "}": self.i += 1; break
            if s[self.i] == "[":
                self.i += 1; k = self.val(); self.ws(); self.i += 1  # ]
                self.ws(); self.i += 1  # =
                obj[k] = self.val()
            else:
                m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(s, self.i)
                if m: self.i = m.end(); obj[m.group(1)] = self.val()
                else: arr.append(self.val())
            self.ws()
            if s[self.i] in ",;": self.i += 1
        if obj and arr:
            for n, v in enumerate(arr, 1): obj.setdefault(n, v)
            return obj
        return obj if obj else arr

def table_after(text, marker):
    i = text.index(marker) + len(marker)
    p = P(text); p.i = text.index("{", i)
    return p.table()

# QuestieDB's names for a few dungeons -> Foxden's (Core/QuestSource.lua ENTRANCE_ALIAS, and the raids)
ALIAS = {"stockade": "stormwind-stockade", "stockades": "stormwind-stockade", "temple-of-atalhakkar": "sunken-temple",
         "sunken-temple-of-atalhakkar": "sunken-temple", "lower-blackrock-spire": "blackrock-spire",
         "upper-blackrock-spire": "blackrock-spire", "dire-maul-east": "dire-maul", "dire-maul-west": "dire-maul",
         "dire-maul-north": "dire-maul", "temple-of-ahnqiraj": "ahnqiraj-temple"}
def slug(name):  # ns.Slug, then Foxden's names
    s = re.sub(r"^the\s+", "", str(name).lower())
    s = re.sub(r"['’]", "", s)
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return ALIAS.get(s, s)

def lua(v):
    if v is None: return "nil"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(round(v, 2)) if isinstance(v, float) else str(v)
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list): return "{" + ",".join(lua(x) for x in v) + "}"
    return "{" + ",".join("[%s]=%s" % (k if isinstance(k, int) else lua(k), lua(x)) for k, x in v.items()) + "}"

def main():
    print("reading QuestieDB...", file=sys.stderr)
    dungeons = table_after(get("support/Forever/Zones/dungeons.lua"), "local dungeons =")
    # area -> uiMap: QuestieDB's base table, then Forever's overrides on top
    def lua_return(text, name):
        m = re.search(name + r"\s*=\s*\[\[return\s*(\{.*?\})\s*\]\]", text, re.S)
        return P(m.group(1)).table() if m else {}
    area_map = dict(lua_return(get("support/Zones/areaIdToUiMapId.lua"), r"ZoneDB\.private\.areaIdToUiMapId"))
    area_map.update(lua_return(get("support/Forever/Zones/areaIdToUiMapId.lua"), r"ZoneDB\.private\.areaIdToUiMapIdOverride"))
    area_map = {k: v for k, v in area_map.items() if v}
    npcs = P(re.search(r"\[\[return\s*(\{.*\})\s*\]\]", get("data/Forever/foreverNpcDB.lua"), re.S).group(1)).table()
    items = P(re.search(r"\[\[return\s*(\{.*\})\s*\]\]", get("data/Forever/foreverItemDB.lua"), re.S).group(1)).table()

    # entrances: { name, slug, uiMapID, x, y } (Core/QuestSource.lua maps a few names to Foxden's)
    entrances = []
    area_slug = {}
    for area, d in dungeons.items():
        if not isinstance(d, (list, dict)): continue
        get_ = (lambda k: d[k - 1] if isinstance(d, list) and len(d) >= k else (d.get(k) if isinstance(d, dict) else None))
        name, alts, locs = get_(1), get_(2) or [], get_(4) or []
        if not isinstance(name, str): continue
        s = slug(name)
        area_slug[area] = s
        for a in (alts if isinstance(alts, list) else []): area_slug[a] = s
        for loc in (locs if isinstance(locs, list) else []):
            # a faction-dependent entrance becomes one per faction ("H" / "A")
            for one, fac in ([(loc.horde, "H"), (loc.alliance, "A")] if isinstance(loc, Faction) else [(loc, None)]):
                if isinstance(one, list) and len(one) >= 3 and area_map.get(one[0]):
                    entrances.append([name, s, area_map[one[0]], one[1], one[2]] + ([fac] if fac else []))

    # boss names per dungeon (Foxden's list), to leave boss loot out
    dsrc = (ADDON / "Data/Dungeons.lua").read_text()
    bosses = {}
    for m in re.finditer(r'^  \[\d+\] = \{ name = "([^"]+)"(.*)$', dsrc, re.M):
        bosses[slug(m.group(1))] = set(re.findall(r'name = "([^"]+)"', m.group(2)))

    def field(row, k):
        if isinstance(row, list): return row[k - 1] if len(row) >= k else None
        return row.get(k) if isinstance(row, dict) else None
    npc_slug, npc_name = {}, {}
    for nid, row in npcs.items():
        z = field(row, 9)
        if z in area_slug: npc_slug[nid] = area_slug[z]; npc_name[nid] = field(row, 1)
    trash = {}
    for iid, row in items.items():
        drops = field(row, 2)
        if not isinstance(drops, list) or not drops: continue
        sl = None; only = True
        for n in drops:
            s2 = npc_slug.get(n)
            if not s2 or (sl and s2 != sl): only = False; break
            sl = s2
        if not (only and sl) or field(row, 12) == 12: continue
        names = []
        for n in drops:
            nm = npc_name.get(n)
            if nm and nm not in names: names.append(nm)
        if any(nm in bosses.get(sl, set()) for nm in names): continue
        trash.setdefault(sl, []).append([iid, names])
    for sl in trash: trash[sl].sort(key=lambda e: e[0])

    out = ("-- Dungeon entrances and trash drops, precomputed from QuestieDB's WoW Forever data (Questie team,\n"
           "-- GPLv3, https://github.com/Questie/QuestieDB; see THIRD-PARTY-NOTICES.md), so Foxden doesn't need the\n"
           "-- QuestieDB addon for them. Generated by tools/build-questie-extra.py: don't edit by hand.\n"
           "local _, ns = ...\n"
           "-- { { name, slug, uiMapID, x, y (0-100) }, ... }\n"
           "ns.BuiltinEntrances = " + lua(entrances) + "\n"
           "-- [dungeon slug] = { { itemID, { mob name, ... } }, ... }\n"
           "ns.BuiltinTrash = " + lua(trash) + "\n")
    (ADDON / "Data/QuestieExtra.lua").write_text(out)
    print("QuestieExtra.lua: %d entrances, trash for %d dungeons (%d items), %d KB"
          % (len(entrances), len(trash), sum(len(v) for v in trash.values()), len(out) // 1024))

if __name__ == "__main__":
    main()
