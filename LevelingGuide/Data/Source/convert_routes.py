#!/usr/bin/env python3
"""Convert licensed Polestar leveling DATA into SobiLevel Forever's schema.

Original guide text and factual records: Copyright (c) 2026 The Polestar authors
and the credited data contributors. GPL-3.0-only; see Data/Licenses.
This converter and the modifications it makes: SobiLevel Forever, 2026,
GPL-3.0-only. No original Polestar runtime is needed or shipped.

Usage: python Data/Source/convert_routes.py [path/to/Data]
The preferred editable inputs are polestar-leveling.json and map-frames.json.
The original .guide files are also supplied for provenance and comparison.
"""
from __future__ import annotations
import collections
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from audit_routes import apply as apply_route_audit
from coordinate_targets import apply as apply_coordinate_targets

COMMIT = "e978e136279cf075eff34718f3ad5fd3dacba623"
REPO = "https://github.com/fitzforge/polestar"
KNOWN_CONDITIONS = {"onquest", "complete", "turnedin", "group", "level", "money", "skill", "has", "dungeon"}
KNOWN_VERBS = {"accept", "turnin", "collect", "goto", "kill", "getfp", "fly", "sethome", "vendor", "train", "buy", "complete", "interact", "use", "level", "note", "talk", "die"}
RACES = {"Alliance": ["Human", "Dwarf", "Gnome", "NightElf", "Skyborne"], "Horde": ["Orc", "Troll", "Tauren", "Scourge", "Skyborne"]}


def dump_lua(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError("nonfinite Lua value")
        return str(value)
    if isinstance(value, str):
        # JSON's ordinary string escapes are also Lua 5.1 escapes. Do not emit
        # JSON \u escapes: retain the Unicode bytes and escape controls only.
        s = value.replace("\\", "\\\\").replace('"', '\\"')
        s = s.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
        for i in range(32):
            if chr(i) in s:
                s = s.replace(chr(i), "\\%03d" % i)
        return '"' + s + '"'
    if isinstance(value, list):
        return "{" + ", ".join(dump_lua(x) for x in value) + "}"
    if isinstance(value, dict):
        parts = []
        for key, item in value.items():
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(key)) and key not in {"end", "repeat", "until", "local", "function", "if", "then", "else", "true", "false", "nil", "in", "for", "while", "do", "not", "and", "or", "break", "return"}:
                token = str(key)
            else:
                token = "[" + dump_lua(key) + "]"
            parts.append(token + " = " + dump_lua(item))
        return "{" + ", ".join(parts) + "}"
    raise TypeError(type(value))


def main(data_dir):
    source_dir = data_dir / "Source"
    guides = json.loads((source_dir / "polestar-leveling.json").read_text(encoding="utf8"))
    frames = json.loads((source_dir / "map-frames.json").read_text(encoding="utf8"))
    assert len(guides) == 65 and all(g.get("category") == "Leveling" for g in guides)
    global_names = {}
    for g in guides:
        global_names.update(g.get("names", {}))
        for s in g["steps"]:
            for a in s["goals"]:
                for key, name_key in (("quest", "title"), ("npc", "npcName"), ("object", "objName"), ("item", "itemName")):
                    if key in a and name_key in a:
                        global_names.setdefault(f"{key}:{a[key]}", a[name_key])
    unresolved = collections.Counter()
    changes = []
    unsupported = []
    source_goals = sum(len(s["goals"]) for g in guides for s in g["steps"])

    def resolver(guide):
        names = global_names | guide.get("names", {})
        written = guide.get("written", {})

        def resolve(text):
            if text is None:
                return None
            text = written.get(str(text), str(text))

            def sub(m):
                token = m.group(1)
                if token in names:
                    return str(names[token])
                unresolved[token] += 1
                typ, number = token.split(":", 1)
                return f"{typ.capitalize()} #{number}"
            return re.sub(r"\{([a-z]+:[0-9]+)\}", sub, text)
        return resolve

    def merge_filter(*sources):
        result = {}
        for key in ("races", "classes"):
            lists = [x[key] for x in sources if x and key in x]
            if lists:
                values = list(lists[0])
                for others in lists[1:]:
                    values = [x for x in values if x in others]
                result[key] = values
        return result

    def position(action):
        if not all(key in action for key in ("map", "x", "y")):
            return {}
        x, y = action["x"] / 100, action["y"] / 100
        # Some source points are valid just beyond their map border. Preserve
        # them in the source; never create an out-of-bounds native waypoint.
        out = {"uiMapID": action["map"], "x": round(x, 8), "y": round(y, 8), "coordFrame": "era" if action.get("f") == "e" else "live"}
        if action.get("f") == "e":
            b = frames.get(str(action["map"]))
            if not b:
                raise ValueError(f"Missing era frame {action['map']}")
            out.update(continentID=b["c"], worldX=round(b["top"] + (b["bottom"] - b["top"]) * y, 7), worldY=round(b["left"] + (b["right"] - b["left"]) * x, 7))
        if "z" in action:
            out["worldZ"] = action["z"]
        if "r" in action:
            out["radius"] = action["r"]
        return out

    def action_row(guide, block, action, block_index, goal_index, resolve):
        typ = action["t"]
        if typ not in KNOWN_VERBS:
            raise ValueError(f"Unsupported goal {typ}")
        only = merge_filter({"races": guide["races"]} if guide.get("races") else {}, block.get("only"), action.get("only"))
        if any(not values for values in only.values()):
            changes.append({"kind": "impossible-filter", "guide": guide["id"], "block": block_index, "goal": goal_index})
            return None
        quest_title = resolve(action.get("title"))
        block_title = resolve(block.get("title")) or guide["zoneName"]
        target = resolve(action.get("target") or action.get("npcName") or action.get("objName"))
        item = resolve(action.get("itemName"))
        location = resolve(action.get("location"))
        act_text = resolve(action.get("text"))
        count = action.get("count", 1)
        notes = []
        if block.get("note"):
            notes.append(resolve(block["note"]))
        if action.get("note"):
            n = resolve(action["note"])
            if n not in notes:
                notes.append(n)
        row = {"id": f"b{block_index:04d}g{goal_index:02d}", "blockID": block_index, "sourceBlock": block_index, "sourceGoal": goal_index, "blockTitle": block_title, "sourceKind": typ}
        row.update(only)
        row.update(position(action))
        if block.get("when"):
            row["conditions"] = copy.deepcopy(block["when"])
            for predicate in row["conditions"]:
                if predicate["k"] not in KNOWN_CONDITIONS:
                    unsupported.append({"guide": guide["id"], "block": block_index, "condition": predicate})
        for source, dest in (("quest", "questID"), ("oi", "objectiveIndex"), ("npc", "npcID"), ("npcName", "npcName"), ("object", "objectID"), ("objName", "objectName"), ("item", "itemID"), ("itemName", "itemName"), ("minLevel", "minLevel"), ("count", "count"), ("optional", "optional"), ("pre", "requiresAny"), ("preAll", "requiresAll"), ("closedBy", "closedBy"), ("preTitles", "prerequisiteTitles"), ("group", "group"), ("escort", "escort"), ("location", "location"), ("node", "nodeID"), ("startItem", "startItemID"), ("startItemName", "startItemName"), ("profLine", "professionID"), ("profRank", "professionRank"), ("profName", "professionName"), ("skillLine", "skillLineID"), ("skill", "skillName"), ("rank", "skillRank")):
            if source in action:
                row[dest] = copy.deepcopy(action[source])
        if quest_title:
            row["questTitle"] = quest_title
        if typ in ("accept", "turnin"):
            row["kind"] = typ
            row["text"] = ("Accept: " if typ == "accept" else "Turn in: ") + (quest_title or f"Quest #{action['quest']}")
            if target:
                notes.insert(0, "Talk to " + target + "." if action.get("npc") else "Interact with " + target + ".")
            if typ == "accept" and item:
                notes.insert(0, "Use " + item + " to start this quest.")
        elif typ in ("kill", "collect", "complete", "interact", "use", "talk") and action.get("quest"):
            row["kind"] = "complete"
            if typ == "kill":
                row["text"] = act_text or f"Kill {target or 'the quest target'} ×{count}"
            elif typ == "collect":
                row["text"] = f"Collect {item or 'the quest item'} ×{count}"
                if action.get("from"):
                    notes.insert(0, "From " + resolve(action["from"]) + ".")
                elif action.get("fromNpcs"):
                    notes.insert(0, "Sources: " + ", ".join(resolve(n["npcName"]) for n in action["fromNpcs"] if n.get("npcName")) + ".")
            elif typ == "talk":
                row["text"] = "Talk to " + (target or "the quest NPC")
            elif typ == "interact":
                row["text"] = "Interact with " + (target or "the quest object")
            elif typ == "use":
                row["text"] = "Use " + (item or "the quest item")
            else:
                row["text"] = "Complete: " + (quest_title or f"Quest #{action['quest']}")
                if action.get("objs"):
                    descriptions = []
                    for objective in action["objs"]:
                        description = resolve(objective.get("text", ""))
                        if description:
                            descriptions.append(description + (f" ×{objective['count']}" if objective.get("count", 1) > 1 else ""))
                    if descriptions:
                        notes.insert(0, "; ".join(descriptions) + ".")
            if quest_title and typ != "complete":
                row["text"] += " — " + quest_title
        elif typ == "goto":
            row["kind"] = "goto"
            row["text"] = "Go to " + (act_text or block_title)
        elif typ == "die":
            # Do not carry an intentional-death shortcut into an unqualified
            # new guide. This preserves the next destination via normal travel.
            row["kind"] = "goto"
            row["text"] = "Travel to " + (location or guide["zoneName"])
            row["blockTitle"] = row["text"]
            row["safeTravelReplacement"] = True
            notes = ["Walk to this destination by the normal roads. The source route's intentional-death shortcut is replaced with ordinary travel."]
            changes.append({"kind": "safe-travel", "guide": guide["id"], "block": block_index, "goal": goal_index, "destination": location})
        elif typ == "level":
            row["kind"] = "level"
            row["level"] = action["level"]
            row["levelFraction"] = action.get("frac", 0)
            row["text"] = f"Reach level {action['level']}" + (f" + {round(action['frac'] * 100)}% XP" if action.get("frac") else "")
        elif typ in ("fly", "getfp"):
            row["kind"] = "flight"
            row["mode"] = "fly" if typ == "fly" else "learn"
            row["text"] = ("Fly to " if typ == "fly" else "Learn the flight path at ") + (location or block_title)
            row["manual"] = True
        elif typ == "sethome":
            row["kind"] = "hearth"
            row["mode"] = "bind"
            row["text"] = "Set your Hearthstone to " + (location or block_title)
            row["manual"] = True
        elif typ == "train":
            row["kind"] = "train"
            row["text"] = "Train " + ("your class abilities" if action.get("class") else resolve(action.get("skill") or "available abilities"))
            row["manual"] = True
        elif typ in ("vendor", "buy"):
            row["kind"] = "vendor"
            row["mode"] = "buy" if typ == "buy" else "supplies"
            row["text"] = (f"Buy {item or 'supplies'} ×{count}" if typ == "buy" else "Sell unwanted items, repair and restock")
            row["manual"] = True
        else:
            row["kind"] = "note"
            row["manual"] = True
            if typ == "kill":
                row["text"] = act_text or f"Kill {target or 'the target'} ×{count}"
            elif typ == "collect":
                row["text"] = f"Collect {item or 'the item'} ×{count}"
            elif typ == "use":
                row["text"] = "Use " + (item or "the item")
            elif typ == "talk":
                row["text"] = "Talk to " + (target or "the NPC")
            elif typ == "interact":
                row["text"] = "Interact with " + (target or "the object")
            elif typ == "note":
                row["text"] = act_text or block_title
            else:
                raise ValueError(f"Unexpected fallback {typ}")
        if notes:
            row["detail"] = "\n\n".join(notes)
        return row

    routes = []
    for guide in guides:
        resolve = resolver(guide)
        route = {"id": guide["id"], "title": resolve(guide["title"]), "faction": guide["faction"], "startLevel": guide["minLevel"], "endLevel": guide["maxLevel"], "zone": guide["zone"], "zoneName": guide["zoneName"], "source": "Polestar", "sourceCommit": COMMIT, "steps": []}
        if guide.get("races"):
            route["races"] = guide["races"]
        if guide.get("next"):
            assert isinstance(guide["next"], str)
            route["next"] = guide["next"]
        labels = {block["label"]: i for i, block in enumerate(guide["steps"], 1) if block.get("label")}
        deferred = collections.defaultdict(list)
        for bi, block in enumerate(guide["steps"], 1):
            for unsupported_key in ("skipto", "nextWhen"):
                if unsupported_key in block:
                    raise ValueError(f"Unsupported control flow {unsupported_key}")
            for gi, action in enumerate(block["goals"], 1):
                row = action_row(guide, block, action, bi, gi, resolve)
                if row is None:
                    continue
                if block.get("along"):
                    stop = labels.get(block["along"])
                    assert stop and stop > bi, "invalid deferred objective"
                    original = copy.deepcopy(row)
                    original["blockID"] = stop
                    original["deferredFromBlock"] = bi
                    deferred[stop].append(original)
                    reminder = {"id": row["id"] + "-reminder", "blockID": bi, "sourceBlock": bi, "sourceGoal": gi, "blockTitle": row["blockTitle"], "kind": "note", "sourceKind": "along-reminder", "text": "While travelling: " + row["text"], "detail": "Work on this objective as you travel. Its completion checkpoint appears before " + resolve(guide["steps"][stop - 1].get("title", "the later stop")) + "." + ("\n\n" + row["detail"] if row.get("detail") else ""), "manual": True, "deferredToBlock": stop}
                    for k in ("races", "classes", "conditions", "optional", "questID", "questTitle"):
                        if k in row:
                            reminder[k] = row[k]
                    route["steps"].append(reminder)
                    changes.append({"kind": "deferred-objective", "guide": guide["id"], "block": bi, "goal": gi, "checkpoint": stop})
                else:
                    route["steps"].append(row)
        # Insert deferred goals at the named stop, before any hand-in there.
        if deferred:
            revised = []
            inserted = set()
            for row in route["steps"]:
                bi = row["blockID"]
                if bi in deferred and bi not in inserted:
                    revised.extend(deferred[bi])
                    inserted.add(bi)
                revised.append(row)
            assert inserted == set(deferred), "missing deferred stop"
            route["steps"] = revised
        for i, row in enumerate(route["steps"], 1):
            row["index"] = i
        route["stepCount"] = len(route["steps"])
        routes.append(route)

    audit = apply_route_audit(routes, source_dir, frames)
    coordinate_report = apply_coordinate_targets(routes, source_dir, frames)
    (source_dir / "coordinate-audit.json").write_text(json.dumps(coordinate_report, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    (source_dir / "route-audit.json").write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    assert not unsupported, f"Unsupported conditions: {unsupported}"
    by_id = {r["id"]: r for r in routes}
    assert len(by_id) == len(routes)
    starts = {}
    chains = []
    for faction, races in RACES.items():
        starts[faction] = {}
        for race in races:
            candidates = [r for r in routes if r["faction"] == faction and r.get("races") == [race] and r["startLevel"] == 1]
            assert len(candidates) == 1, (faction, race, len(candidates))
            start = candidates[0]
            starts[faction][race] = start["id"]
            chain = []
            current = start
            while True:
                assert current["id"] not in chain, "cycle in chain"
                assert current["faction"] == faction, "cross-faction link"
                chain.append(current["id"])
                if not current.get("next"):
                    assert current["endLevel"] == 60, "chain stops before 60"
                    assert any(s["kind"] == "level" and s.get("level") == 60 for s in current["steps"]), "no explicit level-60 goal"
                    break
                assert current["next"] in by_id, "missing chapter"
                current = by_id[current["next"]]
            chains.append({"faction": faction, "race": race, "chapters": len(chain), "steps": sum(len(by_id[x]["steps"]) for x in chain), "routeIDs": chain, "finishLevel": 60})
    all_steps = [s for r in routes for s in r["steps"]]
    stats = {"routeCount": len(routes), "sourceBlockCount": sum(len(g["steps"]) for g in guides), "sourceGoalCount": source_goals, "stepCount": len(all_steps), "uniqueQuestCount": len({s["questID"] for s in all_steps if s.get("questID")}), "questStepCount": sum(bool(s.get("questID")) for s in all_steps), "waypointCount": sum("uiMapID" in s for s in all_steps), "eraWaypointCount": sum(s.get("coordFrame") == "era" for s in all_steps), "raceStartCount": len(chains), "safeTravelReplacements": sum(c["kind"] == "safe-travel" for c in changes), "deferredObjectives": sum(c["kind"] == "deferred-objective" for c in changes)}
    provenance = {"project": "Polestar", "author": "The Polestar authors and credited contributors", "repository": REPO, "commit": COMMIT, "sourceVersion": "0.3.5", "retrieved": "2026-11-09", "license": "GPL-3.0-only", "validation": "Converted and structurally checked; not tested in the live WoW Forever client", **stats}
    order = [r["id"] for r in sorted(routes, key=lambda r: (r["faction"], r["startLevel"], 0 if r.get("races") else 1, r["id"]))]
    lines = ["-- SobiLevel Forever: normalized, attributed community leveling guide data.", "-- Original text/data: Copyright (c) 2026 The Polestar authors and credited contributors.", "-- Adaptation: SobiLevel Forever, 2026. GPL-3.0-only. See LICENSE_THIRD_PARTY.md.", "-- Generated by Data/Source/convert_routes.py; edit its supplied source inputs.", "local _, ns = ...", "ns.Data = ns.Data or {}", "local D = ns.Data", "D.routes = {}", "D.routeOrder = " + dump_lua(order), "D.starts = " + dump_lua(starts), "D.provenance = " + dump_lua(provenance), ""]
    for route in routes:
        metadata = {k: v for k, v in route.items() if k != "steps"}
        lines.append("D.routes[" + dump_lua(route["id"]) + "] = " + dump_lua(metadata)[:-1] + ", steps = {")
        lines.extend("    " + dump_lua(step) + "," for step in route["steps"])
        lines.append("}}\n")
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "Routes.lua").write_text("\n".join(lines) + "\n", encoding="utf8")
    report = {"provenance": provenance, "chains": chains, "kindCounts": dict(collections.Counter(s["kind"] for s in all_steps)), "conditionKinds": sorted({c["k"] for s in all_steps for c in s.get("conditions", [])}), "unresolvedTokens": dict(unresolved), "modifications": changes, "unverifiedInGame": True}
    (data_dir / "Source" / "validation.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    (data_dir / "Source" / "normalized-routes.json").write_text(json.dumps(routes, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf8")
    print(json.dumps({**stats, "unresolvedTokens": dict(unresolved), "outputBytes": (data_dir / "Routes.lua").stat().st_size, "conditions": report["conditionKinds"], "kindCounts": report["kindCounts"]}, indent=2))


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
