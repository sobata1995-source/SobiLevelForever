# SobiLevel route data contract

`Data/Routes.lua` receives `local _, ns = ...` from WoW. It supplies:

- `ns.Data.routes[id]`: chapter metadata and flat `steps`.
- `ns.Data.routeOrder`: all 65 chapter IDs, ordered by faction and intended level.
- `ns.Data.starts[faction][raceToken]`: the ten starting routes.
- `ns.Data.provenance`: source commit, license and structural counts.

## Chapter

`id`, `title`, `faction`, `startLevel`, `endLevel`, `zone` (UI map ID),
`zoneName`, optional `races`, optional `next` (a single chapter ID), `stepCount`,
and `steps`. Level ranges are source metadata, not a requirement to discard the
earlier/later source quests. Every start's `next` chain reaches an explicit
level-60 goal. Common faction chapters are shared, not duplicated per race.

## Action

`id` is stable within a chapter. `index` is its 1-based display position.
`blockID`, `sourceBlock`, `sourceGoal` and `sourceKind` preserve the source origin.
`blockTitle` is the source section, `text` is the action, and `detail` carries
source tips and action-specific instructions. `questTitle` is an English fallback
for APIs that can display the localized quest title.

`kind` is one of `accept`, `turnin`, `complete`, `goto`, `level`, `flight`,
`hearth`, `train`, `vendor`, or `note`. `complete` from kill, collect, interact or
item-use data always has `questID` and `objectiveIndex`; a whole-quest completion
has `questID` and no objective index. A manual item-use/collect/talk advisory is a
`note` with its exact `sourceKind`, related item/object/NPC fields and `manual=true`.

Other fields, when present:

- `questID`, `objectiveIndex`, `itemID`, `itemName`, `count`, `startItemID`,
  `startItemName`, `npcID`, `npcName`, `objectID`, `objectName`.
- `minLevel`; `requiresAny` (at least one listed quest rewarded), `requiresAll`
  (every listed quest rewarded); `closedBy` (any listed quest active or rewarded
  closes this acceptance); `prerequisiteTitles` contains English fallback names.
- `professionID`, `professionRank`, `professionName` are quest profession gates.
- `races` and `classes` are positive inclusion lists; source filters are already
  intersected. Race tokens: Human, Dwarf, Gnome, NightElf, Orc, Troll, Tauren,
  Scourge, Skyborne. Class tokens are uppercase WoW tokens.
- `level` plus `levelFraction` represents level + XP/XPMax, e.g. 5 and .48 means
  level 5 with at least 48% progress, not level 5 alone.
- `optional`, `group` (metadata describing the suggested group), `escort`.
- `flight` has `mode='learn'` or `'fly'`, `location`, and possibly `nodeID`.
  `hearth` has `mode='bind'` and means set bind location, not use Hearthstone.
  `vendor` has `mode='buy'` or `'supplies'`.

## Conditions

`conditions` is an array of AND predicates. Evaluate the source block's entry
conditions once and keep that choice while executing its actions. Re-evaluating
`onquest` after the block turns a quest in can incorrectly hide its subsequent
accept action. Do not turn an unknown predicate into a silently true condition.

| `k` | Other fields | Meaning |
| --- | --- | --- |
| `onquest` | `q` array | Any listed quest is in the log. |
| `complete` | `q` number | Quest is active and ready to turn in. |
| `turnedin` | `q` number | Quest has been rewarded. |
| `group` | `q` number | User elected to do that group quest; not current party status. |
| `dungeon` | `map`, `name` | User opted into that dungeon; not current location. |
| `level` | `op`, `n`, optional `frac` | Compare level + XP/XPMax with n + frac. |
| `money` | `op`, `n` | Compare money in copper. |
| `skill` | `skillLine`, `name`, `n` | Known skill rank is at least n. |
| `has` | `item`, `n` | Bags contain at least n of the item. |

`neg=true` reverses a predicate. This snapshot uses `<` and `>=` level operators.
The original route used persistent per-quest group choices; a documented global
solo/group choice is a simplified runtime policy. It must apply consistently to
both positive and negated group conditions. There are no `skipto`, `nextWhen`,
conditional chapter links or unsupported predicate kinds in these 65 chapters.

## Coordinates

All `x` and `y` values are normalized **0–1**, and `uiMapID` is the source UI map
ID used by Forever. For `coordFrame='live'`, use x/y directly. For
`coordFrame='era'`, the same zone's old map bounds differ from current bounds:
the row additionally includes `continentID`, `worldX`, and `worldY`. Ask
`C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(worldX,worldY), uiMapID)`
for the current normalized point. Check the returned map ID and valid position.
If conversion is unavailable, show a manual/unavailable destination instead of
placing a pin at the old percentages. `worldZ`, if present, is informational;
it does not make a straight arrow understand floors, doors or caves.

Era world axes are `worldX = top + (bottom-top)*y` and
`worldY = left + (right-left)*x`, using the supplied old frame's bounds. The
converter computes them. It does not copy any original navigation engine.

## Deliberate adaptations

Six source `along` blocks contain seven objectives. An early manual reminder is
followed by the completion goal before the original labelled stop. These rows
have `deferredToBlock` / `deferredFromBlock`. Four `die` goals are ordinary travel
with `safeTravelReplacement=true`; their instructions no longer ask for death.
Eight source rows with contradictory race filters are absent from the runtime,
and retained in the original input. See validation.json for each modification.
