"""Apply attributed factual corrections without changing saved step IDs/order.

Evidence: fitzforge/polestar cafeb253903d49c5d0e65fdc90bd4425d29d35c9,
forever-db/corrections/quests.json and data/guide-fixes.json.
Original contributor attribution and sources remain in the bundled JSON records.
GPL-3.0-only; source records may additionally credit CC-BY-4.0 data.
"""
import copy
import json
from collections import Counter

REVISION = "cafeb253903d49c5d0e65fdc90bd4425d29d35c9"
POSITION = ("uiMapID", "x", "y", "coordFrame", "continentID", "worldX", "worldY", "worldZ", "radius")


def position(record, frames):
    if not all(k in record for k in ("map", "x", "y")):
        return {}
    x, y = record["x"] / 100, record["y"] / 100
    if not (0 <= x <= 1 and 0 <= y <= 1):
        return {}
    result = dict(uiMapID=record["map"], x=x, y=y, coordFrame="era" if record.get("f") == "e" else "live")
    if result["coordFrame"] == "era":
        frame = frames.get(str(record["map"]))
        if not frame:
            return {}
        result.update(continentID=frame["c"], worldX=frame["top"]+(frame["bottom"]-frame["top"])*y,
                      worldY=frame["left"]+(frame["right"]-frame["left"])*x)
    return result


def apply(routes, source_dir, frames):
    corrections = json.loads((source_dir / "quest-corrections.json").read_text(encoding="utf8"))
    tips = json.loads((source_dir / "guide-corrections.json").read_text(encoding="utf8"))["fixes"]
    changes = []
    for route in routes:
        steps = route["steps"]
        for step in steps:
            quest_id = step.get("questID")
            if not quest_id:
                continue
            fields = corrections.get(str(quest_id), {}).get("set", {})
            if step["kind"] == "accept":
                for source, destination in (("preAny", "requiresAny"), ("preAll", "requiresAll")):
                    if source in fields and fields[source] != step.get(destination, []):
                        changes.append(dict(route=route["id"], step=step["id"], kind="prerequisites", field=destination,
                                            before=step.get(destination, []), after=fields[source]))
                        step[destination] = copy.deepcopy(fields[source])
            # Content tips are safe to add; route reorders need a separate migration.
            for tip in tips:
                anchor = tip.get("at", {})
                matches = (anchor.get("quest") == quest_id
                    and (not tip.get("faction") or tip["faction"] == route["faction"])
                    and (anchor.get("goal") == step["kind"] or (anchor.get("goal") == "objective" and step["kind"] == "complete"))
                    and (not anchor.get("objective") or anchor["objective"] == step.get("objectiveIndex")))
                # A class-scoped tip cannot be applied to an unrestricted step.
                if matches and tip.get("tip") and not tip.get("only"):
                    text = tip["tip"]
                    if text not in step.get("detail", ""):
                        step["detail"] = text + ("\n\n" + step["detail"] if step.get("detail") else "")
                        changes.append(dict(route=route["id"], step=step["id"], kind="sourced-tip", source=tip["id"]))
            objectives = fields.get("objectives")
            if objectives is None or step["kind"] not in ("complete", "turnin"):
                continue
            targets = []
            for index, objective in enumerate(objectives, 1):
                entity_key = {"kill": "npcID", "talk": "npcID", "item": "itemID", "object": "objectID"}.get(objective.get("type"))
                candidates = [s for s in steps if s.get("questID") == quest_id and s["kind"] == "complete"
                    and ((entity_key and objective.get("id") and s.get(entity_key) == objective["id"])
                         or (not entity_key and s.get("objectiveIndex") == index))]
                label = objective.get("text") or "Complete this quest objective."
                label = {"talk": "Talk to ", "kill": "Defeat ", "item": "Collect ", "object": "Interact with "}.get(objective.get("type"), "") + label
                target = dict(kind="complete", questID=quest_id, questTitle=step.get("questTitle"),
                    objectiveIndex=index, text=label,
                    sourceKind=objective.get("type"), blockTitle=step.get("blockTitle"))
                target["optional"] = "(Optional)" in objective.get("text", "")
                context = next((s for s in steps if s.get("questID") == quest_id and s["kind"] == "complete"), step)
                if context.get("detail"):
                    target["detail"] = context["detail"]
                if step.get("questTitle") == "The Great Outdoors":
                    # Both objectives happen at this quest's own campfire.
                    for key in POSITION:
                        if key in context:
                            target[key] = context[key]
                    target["actionHint"] = "Type /sit beside the campfire and wait for the Boosted Rest buff. Then talk to the NPC to turn in the quest."
                    target["navigationHint"] = "Quest campfire. Stay seated here until Boosted Rest is granted."
                if objective.get("count"):
                    target["count"] = objective["count"]
                    target["text"] += " x" + str(objective["count"])
                if entity_key and objective.get("id"):
                    target[entity_key] = objective["id"]
                if candidates:
                    candidate = candidates[0]
                    for key in POSITION + ("detail", "itemName", "npcName", "objectName"):
                        if key in candidate:
                            target[key] = candidate[key]
                exact = position(objective, frames)
                if exact:
                    for key in POSITION:
                        target.pop(key, None)
                    target.update(exact)
                targets.append(target)
            step["objectiveTargets"] = targets
            if step["kind"] == "complete" and step.get("objectiveIndex"):
                key = {"kill": "npcID", "talk": "npcID", "collect": "itemID", "interact": "objectID"}.get(step.get("sourceKind"))
                matched = [t for t in targets if key and step.get(key) and t.get(key) == step[key]]
                if len(matched) == 1:
                    target = matched[0]
                    if step["objectiveIndex"] != target["objectiveIndex"]:
                        changes.append(dict(route=route["id"], step=step["id"], kind="objective-index", before=step["objectiveIndex"], after=target["objectiveIndex"]))
                    step["objectiveIndex"] = target["objectiveIndex"]
                    step["text"] = target["text"]
                    if target.get("count"):
                        step["count"] = target["count"]
                current = next((t for t in targets if t["objectiveIndex"] == step["objectiveIndex"]), None)
                if current and current.get("x") is not None:
                    old = {k: step[k] for k in POSITION if k in step}
                    new = {k: current[k] for k in POSITION if k in current}
                    if old != new:
                        for key in POSITION:
                            step.pop(key, None)
                        step.update(new)
                        changes.append(dict(route=route["id"], step=step["id"], kind="objective-position"))
            elif step["kind"] == "complete":
                changes.append(dict(route=route["id"], step=step["id"], kind="whole-quest-targets", targets=len(targets)))
    # Every row is audited, including rows with no new corrections.
    unresolved = []
    for route in routes:
        for step in route["steps"]:
            if step.get("questID") and not step.get("questTitle"):
                raise ValueError("Missing quest title: " + route["id"] + "/" + step["id"])
            if "x" in step and not (0 <= step["x"] <= 1 and 0 <= step["y"] <= 1):
                raise ValueError("Out-of-bounds destination")
            if step["kind"] in ("accept", "complete", "turnin") and "x" not in step:
                unresolved.append(dict(route=route["id"], step=step["id"], quest=step.get("questID"),
                    kind=step["kind"], itemStart=bool(step["kind"] == "accept" and (step.get("itemID") or step.get("startItemID"))),
                    hasObjectiveTargets=any("x" in t for t in step.get("objectiveTargets", []))))
    return dict(evidenceCommit=REVISION, routeCount=len(routes), stepCount=sum(len(r["steps"]) for r in routes),
                changes=changes, changeCounts=dict(Counter(c["kind"] for c in changes)),
                stepsWithoutDirectCoordinates=unresolved, livePlaythroughVerified=False)
