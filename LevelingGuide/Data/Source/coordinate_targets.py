"""Build missing objective destinations from attributed factual QuestDB records.

Only data is decoded; no upstream addon code is loaded. Native/Era frames remain
distinct. A spawn cluster is an area, not proof of an exact or reachable NPC.
"""
import copy
import json
import math
from audit_routes import position


def field(row, index, default=None):
    return row[index-1] if len(row) >= index and row[index-1] is not None else default


def array(value):
    return value if isinstance(value, list) else [] if value is None else [value]


def spawns(row):
    result, i = [], 1
    while i + 2 < len(row):
        map_id, frame, count = row[i:i+3]
        i += 3
        for _ in range(int(count)):
            x, y, radius = row[i:i+3]
            i += 3
            result.append(dict(map=map_id, f="e" if frame == 0 else "l", x=x, y=y, r=radius))
    return result


def apply(routes, source_dir, frames):
    reference_path = source_dir / "coordinate-reference.json"
    if not reference_path.exists():
        return {}
    db = json.loads(reference_path.read_text(encoding="utf8"))
    corrections = json.loads((source_dir / "quest-corrections.json").read_text(encoding="utf8"))
    rules = json.loads((source_dir / "coordinate-rules.json").read_text(encoding="utf8"))
    report = dict(source=db["source"], destinations=[], noGeographicTarget=[], inventoryActions=[])
    for route in routes:
        for index, step in enumerate(route["steps"]):
            if step["kind"] not in ("complete", "turnin") or not step.get("questID"):
                continue
            # Supplement missing goals; do not rewrite the verified normal route.
            if step["kind"] != "complete" or "x" in step:
                continue
            qid = step["questID"]
            rule = rules.get(str(qid), {})
            record = db["quests"].get(str(qid))
            if not record:
                continue
            corrected = corrections.get(str(qid), {}).get("set", {}).get("objectives")
            objectives = []
            if corrected is not None:
                objectives = copy.deepcopy(corrected)
            else:
                raw, events = field(record, 12, []), field(record, 14, [])
                for j in range(0, len(raw), 3):
                    kind, oid = raw[j:j+2]
                    count = raw[j+2] if j+2 < len(raw) else None
                    obj = dict(type={1:"kill",2:"item",3:"object",4:"event"}[kind], id=oid, count=count)
                    if kind == 4:
                        obj["id"] = None
                        k = (oid-1)*4 if oid else -1
                        if k >= 0 and k+3 < len(events):
                            obj.update(map=events[k], f="e" if events[k+1] == 0 else "l", x=events[k+2], y=events[k+3])
                    objectives.append(obj)
            # The previous point is only used to choose among real spawn sites.
            anchors = [s for s in route["steps"][:index] if s.get("questID") == qid and "x" in s]
            anchor = anchors[-1] if anchors else None
            desired_map = anchor.get("uiMapID") if anchor else route.get("zone")
            def choose(points):
                if not points:
                    return None
                same_map = [p for p in points if p["map"] == desired_map]
                pool = same_map or points
                def score(point):
                    frame = "era" if point.get("f") == "e" else "live"
                    if anchor and anchor.get("uiMapID") == point["map"] and frame == anchor.get("coordFrame"):
                        return math.hypot(point["x"]/100-anchor["x"], point["y"]/100-anchor["y"])
                    return 0
                return min(pool, key=score)
            targets = []
            for oi, obj in enumerate(objectives, 1):
                target = dict(kind="complete", questID=qid, questTitle=step.get("questTitle"),
                    objectiveIndex=oi, blockTitle=step.get("blockTitle"), sourceKind=obj["type"])
                entity, candidates = None, []
                kind, oid = obj["type"], obj.get("id")
                if kind in ("kill", "talk", "object") and oid:
                    entity = db["objects" if kind == "object" else "npcs"].get(str(oid), [])
                    candidates = spawns(entity)
                    target["objectID" if kind == "object" else "npcID"] = oid
                elif kind == "item" and oid:
                    item = db["items"].get(str(oid), [])
                    entity = item
                    target["itemID"] = oid
                    n = int(field(item, 2, 0))
                    for j in range(n):
                        npc = db["npcs"].get(str(item[2+2*j]), [])
                        candidates.extend(spawns(npc))
                    k = 2 + 2*n
                    objects = int(item[k] or 0) if k < len(item) else 0
                    for j in range(objects):
                        record_obj = db["objects"].get(str(item[k+1+2*j]), [])
                        candidates.extend(spawns(record_obj))
                name = obj.get("text") or (field(entity,1) if entity else None)
                target["text"] = ({"kill":"Quest target: ","talk":"Talk to ","object":"Interact with ","item":"Collect "}.get(kind, "")
                    + (name or step.get("text", "Complete the event")))
                if obj.get("count"):
                    target["text"] += " x" + str(obj["count"])
                exact = position(obj, frames)
                selected = choose(candidates)
                recorded = next((t for t in step.get("objectiveTargets", []) if t.get("objectiveIndex") == oi and "x" in t), None)
                if not recorded:
                    recorded = next((t for t in route["steps"] if t.get("questID") == qid and t.get("objectiveIndex") == oi and "x" in t), None)
                point = exact or ({k:v for k,v in recorded.items() if k in ("uiMapID","x","y","coordFrame","continentID","worldX","worldY","worldZ")} if recorded else {}) or (position(selected,frames) if selected else {})
                if point:
                    target.update(point)
                    if exact:
                        target["navigationHint"] = "Recorded event/objective point. For an escort, stay with the NPC; do not run ahead to this marker."
                    else:
                        target["navigationHint"] = "Recorded spawn or collection area. Search nearby; this marker does not track a moving NPC."
                        target["approximate"] = True
                    targets.append(target)
                else:
                    # Preserve objective order even when it is an inventory action.
                    target["navigationHint"] = "No geographic point recorded for this objective. Follow the quest instructions; item combinations may be performed in your bags."
                    targets.append(target)
            if rule.get("inventoryOnly"):
                step["inventoryOnly"] = True
                step["text"] = rule["text"]
                for target in targets:
                    target["text"], target["inventoryOnly"] = rule["text"], True
                    target["navigationHint"] = "Item action: follow the instructions above. No travel marker is needed for the bag action."
                report["inventoryActions"].append(dict(route=route["id"],step=step["id"],quest=qid,evidence=rule["evidence"]))
            elif rule.get("selector"):
                selector = rule["selector"]
                candidates = [s for s in route["steps"][:index] if s.get("blockID") == step.get("blockID")
                    and "x" in s and all(s.get(k) == v for k,v in selector.items() if k != "contains")
                    and (not selector.get("contains") or selector["contains"] in s.get("text", ""))]
                if not candidates:
                    raise ValueError("Missing attributed guide anchor for " + str(qid))
                anchor = candidates[-1]
                for target in targets:
                    for key in ("uiMapID","x","y","coordFrame","continentID","worldX","worldY","worldZ"):
                        if key in anchor:
                            target[key] = anchor[key]
                    target["text"] = rule["text"]
                    target["areaOnly"] = rule.get("areaOnly", False)
                    target["navigationHint"] = ("Starting/task area only. Once here, carry out the event and stay with the NPC; this is not an escort's endpoint."
                        if rule.get("areaOnly") else "Destination recorded in this guide's preceding waypoint. Follow the quest/event instructions here.")
            if targets:
                step["objectiveTargets"] = targets
                if step.get("objectiveIndex"):
                    selected = next((t for t in targets if t["objectiveIndex"] == step["objectiveIndex"]), None)
                    if selected:
                        # Preserve the source action (feeding/using an item is
                        # not killing a mob just because a DB calls it "kill").
                        selected["text"] = step["text"]
                        for key in ("uiMapID","x","y","coordFrame","continentID","worldX","worldY","worldZ","navigationHint","approximate"):
                            if key in selected:
                                step[key] = selected[key]
                # Also make the targets available during a premature turn-in.
                for handin in route["steps"]:
                    if handin["kind"] == "turnin" and handin.get("questID") == qid:
                        handin["objectiveTargets"] = copy.deepcopy(targets)
                mapped = sum("x" in t for t in targets)
                row = dict(route=route["id"], step=step["id"], quest=qid, objectives=len(targets), mapped=mapped)
                if not rule.get("inventoryOnly"):
                    report["destinations" if mapped else "noGeographicTarget"].append(row)
    return report
